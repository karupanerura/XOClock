package XOClock::Util;
use strict;
use warnings;
use utf8;

use 5.10.0;

use parent qw/Exporter/;
our @EXPORT_OK = qw/parse_datetime/;

use Data::Validator 0.04;
use Time::Local;
use Log::Minimal;

sub parse_datetime {
    state $rule = Data::Validator->new(
        str       => +{ isa => 'Str' },
        time_zone => +{ isa => 'Str', default => 'GMT' },
    );
    my $arg = $rule->validate(@_);

    if ($arg->{str} =~ /^(\d{4})-(\d{2})-(\d{2}) (\d{2}):(\d{2}):(\d{2})$/) {
        my $e;
        my $epoch = do {
            local $@;
            my $epoch = eval {
                local $ENV{TZ} = $arg->{time_zone};
                Time::Local::timelocal($6, $5, $4, $3, $2 - 1, $1 - 1900);
            };
            $e = $@ if $@;
            $epoch;
        };
        if ($e) {
            warnf(q{cannnot parse string. error = '%s'}, $e);
            return;
        }

        return $epoch;
    }
    else {
        warnf('required format like "XXXX-XX-XX XX:XX:XX" text.');
        return;
    }
}


1;
