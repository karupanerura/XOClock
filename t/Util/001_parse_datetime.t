use strict;
use warnings;
use utf8;

use Test::More;
use t::TestUtil qw/ignore_logminimal/;

use XOClock::Util qw/parse_datetime/;

subtest 'check epoch' => sub {
    is parse_datetime(
        str    => '1970-01-01 00:00:00',
    ), 0, 'Parse GMT string.';

    is parse_datetime(
        str       => '1970-01-01 09:00:00',
        time_zone => 'Asia/Tokyo',
    ), 0, 'Parse Asia/Tokyo string.';

    is parse_datetime(
        str       => '1970-01-01 09:00:00',
        time_zone => 'JST-9',
    ), 0, 'Parse JST-9 string.';
};

ignore_logminimal {
    subtest 'check failer case' => sub {
        is parse_datetime(
            str => '1970-01-01 00:00:0000',
        ), undef, 'not valid format';

        is parse_datetime(
            str       => '0000-00-00 00:00:00',
            time_zone => 'JST-9',
        ), undef, 'not valid time';

        is parse_datetime(
            str       => '1970-01-01 09:00:00',
            time_zone => 'HogeHoge',
        ), 60 * 60 * 9, 'uning GMT if not valid time_zone';
    };
};

done_testing;
