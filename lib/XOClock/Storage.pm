package XOClock::Storage;
use strict;
use warnings;
use utf8;

use 5.10.0;
use Data::Validator;

sub new         { require Carp; Carp::croak 'this is abstruct method' }
sub push        { require Carp; Carp::croak 'this is abstruct method' }
sub push_multi  { require Carp; Carp::croak 'this is abstruct method' }
sub shift       { require Carp; Carp::croak 'this is abstruct method' }
sub shift_multi { require Carp; Carp::croak 'this is abstruct method' }
sub shift_all   { require Carp; Carp::croak 'this is abstruct method' }

sub copy {
    state $rule = Data::Validator->new(
        to => +{ isa => 'XOClock::Storage' },
    )->with(qw/Method/);
    my($self, $arg) = $rule->validate(@_);

    my @works = @{ $self->shift_all };
    $arg->{to}->push_multi(@works);
}

sub work_validate {
    state $rule = Data::Validator->new(
        worker => +{ isa => 'HashRef' },
        args   => +{ isa => 'HashRef' },
        epoch  => +{ isa => 'Int'     },
    );
    CORE::shift; ## trush
    $rule->validate(@_);
}

1;
