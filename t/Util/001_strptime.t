use strict;
use warnings;
use utf8;

use Test::More;
use Time::Piece 1.20;

use XOClock::Util qw/strptime/;

subtest 'check epoch' => sub {
    is strptime(
        str    => '1970-01-01 00:00:00',
        format => '%Y-%m-%d %H:%M:%S',
    )->epoch, 0, 'Parse GMT string.';

    is strptime(
        str       => '1970-01-01 09:00:00',
        time_zone => 'JST',
        format    => '%Y-%m-%d %H:%M:%S',
    )->epoch, 0, 'Parse JST string.';
};

subtest 'check object' => sub {
    subtest '1970-01-01 00:00:00 (GMT)' => sub {
        my $tp = strptime(
            str    => '1970-01-01 00:00:00',
            format => '%Y-%m-%d %H:%M:%S',
        );
        is $tp->year,  1970, 'year';
        is $tp->mon,   1,    'mon';
        is $tp->mday,  1,    'mday';
        is $tp->hour,  0,    'hour';
        is $tp->min,   0,    'min';
        is $tp->sec,   0,    'sec';

        is $tp->tzoffset, 0, 'tzoffset';
    };
    subtest '1970-01-01 09:00:00 (JST)' => sub {
        my $tp = strptime(
            str       => '1970-01-01 09:00:00',
            time_zone => 'JST',
            format    => '%Y-%m-%d %H:%M:%S',
        );
        is $tp->year,  1970, 'year';
        is $tp->mon,   1,    'mon';
        is $tp->mday,  1,    'mday';
        is $tp->hour,  9,    'hour';
        is $tp->min,   0,    'min';
        is $tp->sec,   0,    'sec';

        is $tp->tzoffset, 60 * 60 * 9, 'tzoffset';
    };
};

done_testing;
