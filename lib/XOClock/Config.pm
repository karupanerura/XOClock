package XOClock::Config;
use 5.010_001;
use strict;
use warnings;
use utf8;

our $VERSION = '0.01';

use Class::Accessor::Lite (
    ro  => [qw/max_workers/],
    rw  => [qw/worker marged_config/],
);
use Data::Validator;
use YAML::Syck ();
use Log::Minimal;
use File::Zglob ();

sub load {
    state $rule = Data::Validator->new(
        file => +{ isa => 'Str' },
        type => +{ isa => 'Str', default => 'main' }
    )->with(qw/Method/);
    my($class, $arg) = $rule->validate(@_);
    my $config = $class->_load($arg);

    return $class->new(
        validated => 1,
        config    => $config,
    );
}

sub _load {
    state $rule = Data::Validator->new(
        file => +{ isa => 'Str' },
        type => +{ isa => 'Str' },
    )->with(qw/Method/);
    my($class, $arg) = $rule->validate(@_);

    return do {
        local $YAML::Syck::ImplicitUnicode = 1;
        infof(q{load config from '%s'.}, $arg->{file});
        $class->config_validate(
            config => scalar(YAML::Syck::LoadFile($arg->{file})),
            file   => $arg->{file},
            type   => $arg->{type},
        )
    };
}

sub new {
    state $rule = Data::Validator->new(
        config => +{ isa => 'HashRef' },
        type   => +{ isa => 'Str' },
        file   => +{ isa => 'Str' },
        validated => +{ isa => 'Bool', default => 0, xor => [qw/type file/] }
    )->with(qw/Method/);
    my($class, $arg) = $rule->validate(@_);
    my $config = $arg->{validated} ?
        $arg->{config}:
        $class->config_validate($arg);

    bless(+{ %$config } => $class)->init;
}

sub init {
    my $self = shift;
    state $child_rule = Data::Validator->new($self->child_config_rule);

    $self->marged_config(+{});
    if (exists $self->{config_file}) {
        $self->load_child_config(@{ delete $self->{config_file} });
    }

    return $self;
}

sub load_child_config {
    my $self = shift;

    foreach my $file (map { File::Zglob::zglob($_) } @_) {
        unless (exists $self->marged_config->{$file}) {
            my $config = $self->_load(file => $file, type => 'child');
            $self->marged_config->{$file} = $config;
            $self->merge($config);
        }
    }
}

sub merge {
    my($self, $config) = @_;

    foreach my $key (keys %$config) {
        given ($key) {
            when ('worker') {
                $self->merge_worker($config->{worker});
            }
            when ('config_file') {
                $self->load_child_config(@{ $config->{config_file} });
            }
            default {
                require Carp;
                Carp::croak "Unknown config: $key";
            }
        }
    }
}

sub merge_worker {
    my($self, $worker) = @_;

    foreach my $name (keys %$worker) {
        if ( exists $self->worker->{$name} ) {
            require Carp;
            Carp::croak "duplicate worker: $name";
        }
    }

    $self->worker(
        +{
            %{ $self->worker },
            %$worker,
        }
    );
}

sub config_validate {
    state $rule = Data::Validator->new(
        config => +{ isa => 'HashRef' },
        type   => +{ isa => 'Str' },
        file   => +{ isa => 'Str' },
    )->with(qw/Method/);
    my($class, $arg) = $rule->validate(@_);

    my $config_rule;
    given ($arg->{type}) {
        when ('main') {
            state $_config_rule = Data::Validator->new($class->config_rule)->with(qw/NoThrow/);
            $config_rule = $_config_rule;
        }
        when ('child') {
            state $_config_rule = Data::Validator->new($class->child_config_rule)->with(qw/NoThrow/);
            $config_rule = $_config_rule;
        }
        default {
            require Carp;
            Carp::croak "Unknown type: $arg->{type}";
        }
    }

    my $config = $config_rule->validate($arg->{config});
    if ($config_rule->has_errors) {
        my $errors = $config_rule->clear_errors;

        critf('config file validate failed. file: "%s"', $arg->{file});
        foreach my $e (@$errors) {
            critf(q{Error name: '%s', type: '%s', message: '%s'.}, $e->{name}, $e->{type}, $e->{message});
        }

        require Carp;
        Carp::croak 'config file validate failed.';
    }

    return $config;
}

sub common_rule {
    return (
     worker      => +{ isa => 'HashRef[Str]' },
     config_file => +{ isa => 'ArrayRef[Str]', optional => 1 },
    )
}

sub config_rule {
    my $class = shift;

    return (
        max_workers => +{ isa => 'Int' },
        $class->common_rule,
    );
}

sub child_config_rule {
    my $class = shift;

    return (
        $class->common_rule,
    );
}

1;
__END__

=head1 NAME

XOClock::Config - Perl extention to do something

=head1 VERSION

This document describes XOClock::Config version 0.01.

=head1 SYNOPSIS

    use XOClock::Config;

    my $config = XOClock::Config->load(file => "xoclock.yaml");

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
