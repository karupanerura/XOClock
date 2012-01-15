package XOClock::Admin::Server;
use strict;
use warnings;
use utf8;

use AnyEvent;
use AnyEvent::JSONRPC::Lite::Server;
use Scalar::Util qw/weaken/;
use Log::Minimal;
use Data::Validator 0.04;
use 5.10.0;

use Class::Accessor::Lite 0.04 (
    ro  => [
        qw/host port/,
    ],
    rw  => [
        qw/server jsonrpc/,
    ],
);

sub new {
    state $rule = Data::Validator->new(
        host   => +{ isa => 'Str' },
        port   => +{ isa => 'Int' },
        server => +{ isa => 'XOClock::Server' },
    )->with(qw/Method/);
    my($class, $arg) = $rule->validate(@_);

    bless(+{ %$arg } => $class)->init;
}

sub init {
    my $self = shift;

    return $self;
}

sub run {
    my $self = shift;

    $self->jsonrpc( $self->create_jsonrpc_server(host => $self->host, port => $self->port) );
}

sub create_jsonrpc_server {
    state $rule = Data::Validator->new(
        host     => +{ isa => 'Str' },
        port     => +{ isa => 'Str' },
    )->with(qw/Method/);
    my($self, $arg) = $rule->validate(@_);

    infof('create admin JSONRPC Server. listen: %s:%d', $arg->{host}, $arg->{port});
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
    my %callback;
    foreach my $name (qw/server_status num_workers num_queues running_workers/) {
        $callback{$name} = sub {
            my ($res_cv, $arg) = @_;

            $res_cv->result($self->$name($arg));
        };
    }

    return %callback;
}

sub server_status {
    my $self = shift;

    return +{
        num_workers     => $self->num_workers,
        num_queues      => $self->num_queues,
        running_workers => $self->running_workers,
        server_queue    => $self->server_queue,
    };
}

sub num_workers {
    my $self = shift;

    return $self->server->{pm} ? $self->server->pm->num_workers : 0;
}

sub num_queues {
    my $self = shift;

    return $self->server->{pm} ? $self->server->pm->num_queues : 0;
}

sub running_workers { shift->server->running_workers }
sub server_queue    { shift->server->queue }

1;
