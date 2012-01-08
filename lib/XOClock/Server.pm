package XOClock::Server;
use 5.010_001;
use strict;
use warnings;
use utf8;

use AnyEvent;
use AnyEvent::JSONRPC::Lite::Server;
use Scalar::Util qw/weaken/;
use Time::Piece 1.20 ();
use Parallel::ForkManager;
use Log::Minimal;
use Data::Validator 0.04;
use Class::Load;

our $VERSION = '0.01';

use Class::Accessor::Lite 0.04 (
    ro  => [
        qw/host port/,
        qw/max_workers registered_worker interval/,# from config
    ],
    rw  => [
        qw/jsonrpc checker/,
        qw/queue worker/,
        qw/process_queue running_worker process_cb/
    ],
);

sub new {
    state $rule = Data::Validator->new(
        host              => +{ isa => 'Str' },
        port              => +{ isa => 'Int' },
        max_workers       => +{ isa => 'Int' },
        registered_worker => +{ isa => 'HashRef[Str]' },
        interval          => +{ isa => 'Int' },
    )->with(qw/Method/);
    my($class, $arg) = $rule->validate(@_);

    bless(+{ %$arg } => $class)->init;
}

sub init {
    my $self = shift;

    $self->worker(+{});
    $self->running_worker(+{});
    $self->process_cb(+{});

    $self->queue([]);
    $self->process_queue([]);

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
        my $tp = do {
            local $ENV{TZ} = exists($arg->{time_zone}) ? $arg->{time_zone} : undef;

            my $proto = $ENV{TZ} ? Time::Piece->localtime : 'Time::Piece';
            $proto->strptime($arg->{datetime}, '%Y-%m-%d %H:%M:%S');
        };
        if ($tp->epoch >= time) {
            push @{ $self->queue } => +{
                worker => $worker,
                args   => $arg->{args},
                epoch  => $tp->epoch,
            };
            $self->queue([ sort { $a->{epoch} <=> $b->{epoch} } @{ $self->queue } ]);

            # enqueue success
            return 1;
        }
        else {
            warnf(
                q{Cannot enqueue. already past '%s'. (Worker:'%s', time_zone '%s')},
                $arg->{datetime}, $arg->{name},
                exists($arg->{time_zone}) ? $arg->{time_zone} : 'GMT'
            );

            # enqueue failed
            return;
        }
    }
    else {
        warnf(q{Worker '%s' is not registered.}, $arg->{name});

        # enqueue failed
        return;
    }
}

sub dequeue {
    state $rule = Data::Validator->new(
        time => +{ isa => 'Int', default => sub { time } },
    )->with(qw/Method/);
    my($self, $arg) = $rule->validate(@_);

    my $count = 0;
    if (@{ $self->queue } and ($arg->{time} >= $self->queue->[0]{epoch})) {
        while (my $work = shift @{ $self->queue }) {
            if ($arg->{time} < $work->{epoch}) {
                unshift @{ $self->queue } => $work;
                last;
            }
            $self->start_worker($work);
            $count++;
        }
    }

    return $count;
}

sub start_worker {
    state $rule = Data::Validator->new(
        worker => +{ isa => 'XOClock::Worker' },
        args   => +{ isa => 'HashRef'         },
        epoch  => +{ isa => 'Int'             },
    )->with(qw/Method/);
    my($self, $work) = $rule->validate(@_);

    $self->run_on_child(
        name  => $work->{worker}->name,
        code  => sub { $work->{worker}->run($work->{args}) },
        retry => $work->{worker}->retry_count,
    );
}

sub get_worker {
    state $rule = Data::Validator->new(
        name => +{ isa => 'Str' },
    )->with(qw/Method Sequenced/);
    my($self, $arg) = $rule->validate(@_);

    $self->worker->{$arg->{name}} ||= sub {
        my $class = $self->registered_worker->{$arg->{name}};
        if ( Class::Load::try_load_class($class) ) {
            infof(q{Worker load success. class: %s, name: %s}, $class, $arg->{name});
            return $class->new(name => $arg->{name});
        }
        else {
            critf(q{Worker load failed. class: %s, name: %s}, $class, $arg->{name});
            return;
        }
    }->() if exists($self->registered_worker->{$arg->{name}});
}

sub pm {
    my $self = shift;

    $self->{pm} ||= Parallel::ForkManager->new($self->max_workers);
}

sub in_child { shift->pm->{in_child} }
sub pm_processes_count { scalar keys %{ shift->pm->{processes} } }
sub pm_is_working_max {
    my $self = shift;

    $self->pm_processes_count >= $self->max_workers;
}
sub pm_nothing_children {
    my $self = shift;

    $self->pm_processes_count == 0;
}

sub run_on_child {
    state $rule = Data::Validator->new(
        name  => +{ isa => 'Str'     },
        code  => +{ isa => 'CodeRef' },
        retry => +{ isa => 'Int', default => 0 }
    )->with(qw/Method/);
    my($self, $arg) = $rule->validate(@_);

    if ($self->pm_is_working_max) {## child working max
        $self->process_enqueue($arg);
        return;
    }
    else {## create child process
        weaken($self);
        if (my $pid = $self->pm->start) {
            # parent
            infof(q{start worker name:'%s', pid:'%d'}, $arg->{name}, $pid);
            $self->process_cb->{$pid} = sub {
                my ($pid, $status) = @_;

                infof(q{finish worker name:'%s', pid:'%d', status:'%d'}, $arg->{name}, $pid, $status);

                delete $self->running_worker->{$arg->{name}}{$pid};
                delete $self->process_cb->{$pid};
                delete $self->pm->{processes}{$pid};

                unless ($status == 0) {## retry
                    if ($arg->{retry}) {
                        my $next_retry = $arg->{retry} - 1;

                        warnf('retry queue. can retry %d more times.', $next_retry);
                        $self->process_enqueue(+{
                            %$arg,
                            retry => $next_retry,
                        });
                    }
                    else {
                        warnf(q{job failed. name:'%s', pid:'%d', status:'%d'}, $arg->{name}, $pid, $status);
                    }
                }

                ## dequeue
                $self->process_dequeue;
            };
            $self->running_worker->{$arg->{name}}{$pid} = AnyEvent->child(
                pid => $pid,
                cb  => $self->process_cb->{$pid},
            );

            return $pid;
        }
        else {
            # child
            $arg->{code}->($self, );
            $self->pm->finish;
        }
    }
}

sub process_enqueue {
    my($self, $arg) = @_;

    warnf(q{child process working max. push to queue '%s'. queue size = %d}, $arg->{name}, scalar(@{ $self->process_queue }));
    push @{ $self->process_queue } => $arg;
}

sub process_dequeue {
    my $self = shift;

    until ($self->pm_is_working_max) {
        last unless @{ $self->process_queue };
        ## dequeue
        $self->run_on_child(shift @{ $self->process_queue });
    }
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
}

sub close_jsonrpc {
    my $self = shift;

    infof('close jsonrpc.');
    $self->jsonrpc(undef);
}

sub wait_all_workers {
    my $self = shift;

    return unless $self->{pm};

    infof('wait all workers.');
    $self->_wait_all_workers;
}

sub _wait_all_workers {
    my $self = shift;

    $self->wait_all_children;
    if (@{ $self->process_queue }) {
        $self->process_dequeue;
        $self->_wait_all_workers;
    }
}

sub wait_all_children {
    my $self = shift;

    until ($self->pm_nothing_children) {
        my $pid = $self->pm->wait_one_child;
        if (my $cb = $self->process_cb->{$pid}) {
            $cb->($pid, 0);
        }
    }
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
