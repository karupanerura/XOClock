package XOClock::Admin::Client;
use 5.010_001;
use strict;
use warnings;
use utf8;

our $VERSION = '0.01';

use AnyEvent::JSONRPC::Lite::Client;
use Data::Validator;

use Class::Accessor::Lite (
    ro => [qw/host port/],
    rw => [qw/jsonrpc/]
);

sub new {
    state $rule = Data::Validator->new(
        host              => +{ isa => 'Str' },
        port              => +{ isa => 'Int' },
    )->with(qw/Method/);
    my($class, $arg) = $rule->validate(@_);

    bless(+{ %$arg } => $class)->init;
}

sub init {
    my $self = shift;

    $self->jsonrpc(
        AnyEvent::JSONRPC::Lite::Client->new(
            host => $self->host,
            port => $self->port,
        )
    );

    return $self;
}

sub request {
    state $rule = Data::Validator->new(
        name => +{ isa => 'Str' },
        args => +{ isa => 'HashRef', optional => 1 },
    )->with(qw/Method/);
    my($self, $arg) = $rule->validate(@_);

    $self->jsonrpc->call($arg->{name} => exists($arg->{args}) ? $arg->{args} : ());
}

# shortcut
sub server_status   { shift->request(name => 'server_status')   }
sub num_workers     { shift->request(name => 'num_workers')     }
sub num_queues      { shift->request(name => 'num_queues')      }
sub running_workers { shift->request(name => 'running_workers') }
sub server_queue    { shift->request(name => 'server_queue')    }

1;
__END__

=head1 NAME

XOClock::Client - Perl extention to do something

=head1 VERSION

This document describes XOClock::Client version 0.01.

=head1 SYNOPSIS

    use XOClock::Client;

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
