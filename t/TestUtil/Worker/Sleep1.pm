package t::TestUtil::Worker::Sleep1;
use strict;
use warnings;
use utf8;

use parent qw/XOClock::Worker/;

sub run {
    my($class, $args) = @_;

    sleep 1;
}

1;
