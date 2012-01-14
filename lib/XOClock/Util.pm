package XOClock::Util;
use strict;
use warnings;
use utf8;

use 5.10.0;

use parent qw/Exporter/;
our @EXPORT_OK = qw/strptime/;

use Data::Validator 0.04;
use Time::Piece 1.20;

sub strptime {
    state $rule = Data::Validator->new(
        str       => +{ isa => 'Str' },
        time_zone => +{ isa => 'Str', optional => 1 },
        format    => +{ isa => 'Str' },
    );
    my $arg = $rule->validate(@_);

    local $ENV{TZ} = exists($arg->{time_zone}) ? $arg->{time_zone} : undef;

    my $proto = Time::Piece->strptime($arg->{str}, $arg->{format});
    $proto = Time::Piece->localtime( $proto ) if $ENV{TZ};

    return $proto;
}

1;
