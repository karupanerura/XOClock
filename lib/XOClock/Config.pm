package XOClock::Config;
use 5.010_001;
use strict;
use warnings;
use utf8;

our $VERSION = '0.01';

use Class::Accessor::Lite (
    ro  => [qw/max_workers worker/],
);
use Data::Validator;
use YAML::Syck ();
use Log::Minimal;

sub config_rule {
    state $rule = Data::Validator->new(
        max_workers => +{ isa => 'Int' },
        worker      => +{ isa => 'HashRef[Str]' },
    );

    return $rule;
}

sub new {
    my $class  = shift;
    my $config = $class->config_rule->validate(@_);

    bless(+{ %$config } => $class)->init;
}

sub init {
    my $self = shift;

    return $self;
}

sub load {
    my $class  = shift;
    my $config = $class->_load(@_);

    $class->new($config);
}

sub _load {
    state $rule = Data::Validator->new(
        file => +{ isa => 'Str' }
    )->with(qw/Method/);
    my($class, $arg) = $rule->validate(@_);

    return do {
        local $YAML::Syck::ImplicitUnicode = 1;
        infof(q{load config from '%s'.}, $arg->{file});
        YAML::Syck::LoadFile($arg->{file});
    };
}

1;
__END__

=head1 NAME

XOClock::Config - Perl extention to do something

=head1 VERSION

This document describes XOClock::Config version 0.01.

=head1 SYNOPSIS

    use XOClock::Config;

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
