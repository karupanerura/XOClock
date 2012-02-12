package XOClock::Server;
use 5.010_001;
use strict;
use warnings;
use utf8;

use AnyEvent;
use AnyEvent::JSONRPC::Lite::Server;
use Scalar::Util qw/weaken/;
use AnyEvent::ForkManager;
use Log::Minimal;
use Data::Validator 0.04;
use Class::Load;
use XOClock::Util ();
use Time::HiRes;

our $VERSION = '0.01';

use Class::Accessor::Lite 0.04 (
    ro  => [
        qw/host port/,
        qw/max_workers registered_worker storage storage_option interval/,# from config
    ],
    rw  => [
        qw/jsonrpc checker/,
        qw/queue worker/,
        qw/running_workers/,
    ],
);

sub new {
    state $rule = Data::Validator->new(
        host              => +{ isa => 'Str' },
        port              => +{ isa => 'Int' },
        max_workers       => +{ isa => 'Int' },
        registered_worker => +{ isa => 'HashRef[Str]' },
        storage           => +{ isa => 'Str', },
        storage_option    => +{ isa => 'HashRef' },
        interval          => +{ isa => 'Int' },
    )->with(qw/Method/);
    my($class, $arg) = $rule->validate(@_);

    bless(+{ %$arg } => $class)->init;
}

sub init {
    my $self = shift;

    $self->worker(+{});
    $self->queue( $self->create_queue );
    $self->running_workers(+{});

    return $self;
}

sub run {
    state $rule = Data::Validator->new(
        create_jsonrpc_server => +{ isa => 'Bool', default => 1 },
        create_checker        => +{ isa => 'Bool', default => 1 },
    )->with(qw/Method/);
    my($self, $arg) = $rule->validate(@_);
    weaken($self);

    if ($arg->{create_jsonrpc_server}) {
        $self->jsonrpc(
            $self->create_jsonrpc_server(
                host => $self->host,
                port => $self->port,
            )
        );
    }

    if ($arg->{create_checker}) {
        $self->checker(
            AnyEvent->timer(
                interval => $self->interval,
                cb       => sub {
                    my $started_job_count = $self->dequeue;
                    infof('job started %d process.', $started_job_count) if $started_job_count;
                }
            )
        );
    }

    return $self;
}

sub enqueue {
    state $rule = Data::Validator->new(
        name      => +{ isa => 'Str' },
        datetime  => +{ isa => 'Str' },
        time_zone => +{ isa => 'Str', optional => 1 },
        args      => +{ isa => 'HashRef' },
    )->with(qw/Method NoThrow/);
    my($self, $arg) = $rule->validate(@_);

    if ($rule->has_errors) {
        my $errors = $rule->clear_errors;
        warnf('enqueue failed.');
        foreach my $e (@$errors) {
            warnf(q{Error name: '%s', type: '%s', message: '%s'.}, $e->{name}, $e->{type}, $e->{message});
        }

        # enqueue failed
        return;
    }
    elsif ( my $worker = $self->get_worker($arg->{name}) ) {
        return $self->_enqueue(
            worker   => $worker,
            datetime => $arg->{datetime},
            exists($arg->{time_zone}) ? (time_zone => $arg->{time_zone}) : (),
            args     => $arg->{args},
        );
    }
    else {
        warnf(q{Worker '%s' is not registered.}, $arg->{name});

        # enqueue failed
        return;
    }
}

sub _enqueue {
    state $rule = Data::Validator->new(
        worker    => +{ isa => 'HashRef[Str]' },
        datetime  => +{ isa => 'Str' },
        time_zone => +{ isa => 'Str', optional => 1 },
        args      => +{ isa => 'HashRef' },
    )->with(qw/Method/);
    my($self, $arg) = $rule->validate(@_);

    my $tp = XOClock::Util::strptime(
        str    => $arg->{datetime},
        format => '%Y-%m-%d %H:%M:%S',
        exists($arg->{time_zone}) ? (time_zone => $arg->{time_zone}) : ()
    );
    if ($tp->epoch >= time) {
        $self->queue->push(
            worker => $arg->{worker},
            args   => $arg->{args},
            epoch  => $tp->epoch,
        );

        # enqueue success
        return 1;
    }
    else {
        warnf(
            q{Cannot enqueue. already past '%s'. (Worker:'%s', time_zone '%s')},
            $arg->{datetime}, $arg->{worker}{name},
            exists($arg->{time_zone}) ? $arg->{time_zone} : 'GMT'
        );

        # enqueue failed
        return;
    }
}

sub dequeue {
    state $rule = Data::Validator->new(
        time => +{ isa => 'Int', default => sub { time } },
    )->with(qw/Method/);
    my($self, $arg) = $rule->validate(@_);

    my $works = $self->queue->shift_multi($arg);
    my $count = scalar @$works;
    foreach my $work (@$works) {
        $self->start_worker($work);
    }

    return $count;
}

sub start_worker {
    state $rule = Data::Validator->new(
        worker => +{ isa => 'HashRef[Str]' },
        args   => +{ isa => 'HashRef'      },
        epoch  => +{ isa => 'Int'          },
    )->with(qw/Method/);
    my($self, $work) = $rule->validate(@_);

    $self->run_on_child(
        name  => $work->{worker}{name},
        code  => sub {
            my $class = $work->{worker}{class};
            if ( Class::Load::try_load_class($class) ) {
                infof(q{Worker load success. class: %s, name: %s}, $class, $work->{worker}{name});
                $class->run($work->{args});
            }
            else {
                critf(q{Worker load failed. class: %s, name: %s}, $class, $work->{worker}{name});
                return;
            }
        },
    );
}

sub get_worker {
    state $rule = Data::Validator->new(
        name => +{ isa => 'Str' },
    )->with(qw/Method Sequenced/);
    my($self, $arg) = $rule->validate(@_);

    $self->worker->{$arg->{name}} ||= +{
        class => $self->registered_worker->{$arg->{name}},
        name  => $arg->{name},
    } if exists($self->registered_worker->{$arg->{name}});
}

sub pm {
    my $self = shift;

    $self->{pm} ||=
        AnyEvent::ForkManager->new(
            max_workers => $self->max_workers,
            $self->create_pm_callback,
        );
}

sub create_pm_callback {
    my $self = shift;

    return (
        on_start => sub {
            my ($pm, $pid, $self, $arg) = @_;
            infof(q{start worker name:'%s', pid:'%d'}, $arg->{name}, $pid);
            $self->running_workers->{$arg->{name}}{$pid} = +{
                start_time => scalar Time::HiRes::gettimeofday
            };
        },
        on_finish => sub {
            my ($pm, $pid, $status, $self, $arg) = @_;
            my $worker_info = delete $self->running_workers->{$arg->{name}}{$pid};
            my $diff = Time::HiRes::gettimeofday - $worker_info->{start_time};
            infof(q{finish worker name:'%s', pid:'%d', status:'%d' running:%f[sec]}, $arg->{name}, $pid, $status, $diff);

            unless ($status == 0) {
                warnf(q{job failed. name:'%s', pid:'%d', status:'%d'}, $arg->{name}, $pid, $status);
            }
        },
        on_working_max => sub {
            my ($pm, $self, $arg) = @_;
            warnf(q{child process working max. queued '%s'.}, $arg->{name});
        },
        on_enqueue => sub {
            my ($pm, $self, $arg) = @_;
            infof(q{push to queue '%s'. queue size = %d}, $arg->{name}, $pm->num_queues);
        },
        on_dequeue => sub{
            my ($pm, $self, $arg) = @_;
            infof(q{shift queue '%s'. queue size = %d}, $arg->{name}, $pm->num_queues);
        }
    );
}

sub is_child { shift->pm->is_child }

sub run_on_child {
    state $rule = Data::Validator->new(
        name  => +{ isa => 'Str'     },
        code  => +{ isa => 'CodeRef' },
    )->with(qw/Method/);
    my($self, $arg) = $rule->validate(@_);

    $self->pm->start(
        cb => sub {
            my($pm, $self, $arg) = @_;

            # skip signal
            local $SIG{INT}  = sub {};
            local $SIG{TERM} = sub {};
            local $SIG{QUIT} = sub {};
            local $SIG{HUP}  = sub {};

            $arg->{code}->($self);
        },
        args => [$self, $arg],
    );
}

sub create_queue {
    my $self = shift;

    infof('create storage class:"%s"', $self->storage);
    Class::Load::load_class( $self->storage );
    $self->storage->new($self->storage_option);
}

sub create_jsonrpc_server {
    state $rule = Data::Validator->new(
        host     => +{ isa => 'Str' },
        port     => +{ isa => 'Str' },
    )->with(qw/Method/);
    my($self, $arg) = $rule->validate(@_);

    infof('create JSONRPC Server. listen: %s:%d', $arg->{host}, $arg->{port});
    my $server = AnyEvent::JSONRPC::Lite::Server->new(
        address => $arg->{host},
        port    => $arg->{port},
    );
    $server->reg_cb( $self->create_callback );

    return $server;
}

sub create_callback {
    my $self = shift;

    weaken($self);

    return (
        enqueue => sub {
            my ($res_cv, $arg) = @_;

            my $result = $self->enqueue($arg) ? 'ok' : 'ng';
            $res_cv->result($result);
        },
    );
}

sub graceful_shutdown {
    my $self = shift;

    warnf(q{graceful shutdown.});
    $self->finalize;
}

sub graceful_restart {
    state $rule = Data::Validator->new(
        new_config => +{ isa => 'HashRef' },
    )->with(qw/Method/);
    my($self, $arg) = $rule->validate(@_);
    my $class = Scalar::Util::blessed($self);

    warnf(q{graceful restart.});

    my $new = $class->new(%{ $arg->{new_config} });

    # stop
    warnf(q{stop old server.});
    $self->stop_dequeue;

    warnf(q{enqueue target change to new server.});
    $self->jsonrpc->reg_cb( $new->create_callback );
    $new->jsonrpc($self->jsonrpc);
    $self->jsonrpc(undef);

    warnf(q{moving a queue from old server to new server.});
    $self->queue->copy(to => $new->queue);
    if ($self->{pm}) {
        $new->pm->process_queue ( $self->pm->process_queue  );
        $new->pm->running_worker( $self->pm->running_worker );
        $new->pm->process_cb    ( $self->pm->process_cb     );
        $new->pm->wait_async    ( $self->pm->wait_async     );
        $new->running_workers   ( $self->running_workers    );
    }

    $_[0] = $self = $new;
    warnf(q{stoped old server.});

    # start
    warnf(q{start new server.});
    $self->run(
        create_jsonrpc_server => 0,
    );
    $self->pm->dequeue if ($self->{pm} and $self->pm->num_queues and ($self->pm->num_workers == 0));

    return $self;
}

sub finalize {
    my $self = shift;

    $self->stop_dequeue;
    $self->close_jsonrpc;
    $self->wait_all_workers;
}

sub stop_dequeue {
    my $self = shift;

    infof('stop dequeue.');
    $self->checker(undef);
    infof('stop dequeue ok.');
}

sub close_jsonrpc {
    my $self = shift;

    infof('close jsonrpc.');
    $self->jsonrpc(undef);
    infof('close jsonrpc ok.');
}

sub wait_all_workers {
    my $self = shift;

    return unless $self->{pm};

    infof('wait all workers.');
    $self->wait_all_children(
        cb => sub {
            my($pm) = @_;
            infof('wait all workers ok.');
        },
        blocking => 1
    );
}

sub wait_all_children {
    my $self = shift;

    $self->pm->wait_all_children(@_);
}

sub DESTOROY {
    my $self = shift;

    $self->finalize;
}

1;
__END__

=head1 NAME

XOClock::Server - Perl extention to do something

=head1 VERSION

This document describes XOClock::Server version 0.01.

=head1 SYNOPSIS

    use AnyEvent;
    use XOClock::Server;

    my $cv = AnyEvent->condvar;
    my $server = XOClock::Server->new(
        host        => '0.0.0.0',
        port        => 5312,
        max_workers => 2,
        interval    => 5,
        registered_worker => +{
            'FooWork' => 'ProjectFoo::Worker::XOClock::FooWork'
        },
    )->run;
    $cv->recv;

=head1 DESCRIPTION

# TODO

=head1 INTERFACE

=head2 Functions

=head3 C<< hello() >>

# TODO

=head1 DEPENDENCIES

Perl 5.8.1 or later.

=head1 BUGS

All complex software has bugs lurking in it, and this module is no
exception. If you find a bug please either email me, or add the bug
to cpan-RT.

=head1 SEE ALSO

L<perl>

=head1 AUTHOR

Kenta Sato E<lt>karupa@cpan.orgE<gt>

=head1 LICENSE AND COPYRIGHT

Copyright (c) 2012, Kenta Sato. All rights reserved.

This library is free software; you can redistribute it and/or modify
it under the same terms as Perl itself.

=cut
