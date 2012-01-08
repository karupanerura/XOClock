package XOClock;
use 5.010_001;
use strict;
use warnings;
use utf8;

our $VERSION = '0.01';

use Getopt::Long ();
use XOClock::Server;
use AnyEvent;
use Class::Accessor::Lite 0.04 (
    ro => [qw/host port logfile config_file/],
    rw => [qw/config/],
);
use Log::Minimal;
use IO::Handle;
use YAML::Syck ();

sub getopt_spec {
    return(
        'host=s',
        'port=i',
        'logfile=s',
        'config_file=s',
        'version',
        'help',
    );
}

sub getopt_parser {
    return Getopt::Long::Parser->new(
        config => [qw(
            no_ignore_case
            bundling
            no_auto_abbrev
        )],
    );
}

sub new {
    my $class = shift;
    local @ARGV = @_;

    my %opts;
    my $success = $class->getopt_parser->getoptions(
        \%opts,
        $class->getopt_spec());

    if(!$success) {
        $opts{help}++;
        $opts{getopt_failed}++;
    }

    $opts{argv} = \@ARGV;

    return bless \%opts, $class;
}

sub run {
    my $self = shift;

    if($self->{help}) {
        $self->do_help();
    }
    elsif($self->{version}) {
        $self->do_version();
    }
    else {
        $self->dispatch(@ARGV);
    }

    return;
}

sub load_config {
    my $self = shift;

    my $config = $self->config_file ? do {
        local $YAML::Syck::ImplicitUnicode = 1;
        infof(q{load config from '%s'.}, $self->config_file);
        YAML::Syck::LoadFile($self->config_file);
    } : +{};

    $self->config( $config );
}

sub logging {
    my $self = shift;
    my $cb   = shift;

    my $fh = $self->logfile ? do {
        open(my $fh, '>>', $self->logfile) or die $!;
        $fh->autoflush(1);
        $fh;
    } : do {# STDERR(default)
        my $fh = \*STDERR;
        $fh->autoflush(1);
        $fh;
    };

    ## logging
    $cb->($fh, @_);

    close($fh) if $self->logfile;
}

sub dispatch {
    my($self, @args) = @_;

    local $Log::Minimal::PRINT = sub {
        $self->logging(
            sub {
                my ($fh, $time, $type, $message, $trace, $raw_message) = @_;
                print {$fh} ("$time [$type][$$] $message at $trace\n");
            } => @_
        );
    };
    infof('running on pid: %d.', $$);
    $self->load_config;

    my $cv = AnyEvent->condvar;
    my $server = $self->create_server;

    my @signal_guard;
    foreach my $signal (qw/INT TERM QUIT/) {
        push @signal_guard => AnyEvent->signal(
            signal => $signal,
            cb     => sub {
                # graceful shutdown
                critf(q{signal '%s' trapped.}, $signal);
                warnf(q{graceful shutdown.});
                $server->finalize;
                $cv->send;
            },
        );
    }
    push @signal_guard => AnyEvent->signal(
        signal => 'HUP',
        cb     => sub {
            critf(q{signal '%s' trapped.}, 'HUP');
            warnf(q{graceful restart.});
            # TODO
            # graceful restart
            $self->reload;
            my $new_server = $self->create_server;

            # stop
            warnf(q{stop old server.});
            $server->stop_dequeue;

            warnf(q{enqueue target change to new server.});
            $server->jsonrpc->reg_cb( $new_server->create_callback );
            $new_server->jsonrpc($server->jsonrpc);
            $server->jsonrpc(undef);

            warnf(q{moving a queue from old server to new server.});
            foreach my $accessor (qw/queue process_queue/) {
                push @{ $new_server->$accessor } => @{ $server->$accessor };
                $server->$accessor([]);
            }
            $new_server->queue([ sort { $a->{epoch} <=> $b->{epoch} } @{ $new_server->queue } ]);

            warnf(q{old server finalize. wait all workers.});
            $server->wait_all_workers;
            $server = $new_server;
            warnf(q{stoped old server.});

            # start
            warnf(q{start new server.});
            $server->run(
                create_jsonrpc_server => 0,
            );
            $server->process_dequeue if ($server->process_queue);
        },
    );

    ## run server
    $server->run;

    ## start server
    infof('server start.');
    $cv->recv;
    infof('server shutdown.');

    return;
}

sub create_server {
    my $self = shift;

    return XOClock::Server->new(
        host              => $self->host                  || '0.0.0.0',
        port              => $self->port                  || 5312,
        max_workers       => $self->config->{max_workers} || 4,
        registered_worker => $self->config->{worker}      || +{},
        interval          => $self->config->{interval}    || 1,
    );
}

sub reload {
    my $self = shift;
    infof(q{reload config.});
    $self->load_config;
}

sub do_help {
    my($self) = @_;
    if($self->{getopt_failed}) {
        die $self->help_message();
    }
    else {
        print $self->help_message();
    }
}

sub appname {
    my($self) = @_;
    require File::Basename;
    return File::Basename::basename($0);
}

sub do_version {
    my($self) = @_;
    print $self->version_message();
}

sub help_message {
    my($self) = @_;
    require Pod::Usage;

    open my $fh, '>', \my $buffer;
    Pod::Usage::pod2usage(
        -message => $self->version_message(),
        -exitval => 'noexit',
        -output  => $fh,
        -input   => __FILE__,
    );
    close $fh;
    return $buffer;
}

sub version_message {
    my($self) = @_;

    require Config;
    return sprintf "%s\n" . "\t%s/%s\n" . "\tperl/%vd on %s\n",
        $self->appname(), ref($self), $VERSION,
        $^V, $Config::Config{archname};
}

1;
__END__

=head1 NAME

XOClock - Perl extention to do something

=head1 VERSION

This document describes XOClock version 0.01.

=head1 SYNOPSIS

    $ XOClock --help

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
