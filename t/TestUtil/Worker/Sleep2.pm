package t::TestUtil::Worker::Sleep2;
use strict;
use warnings;
use utf8;

use parent qw/XOClock::Worker/;

sub run {
    my($class, $args) = @_;

    sleep 2;
}

1;
