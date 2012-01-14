package t::TestUtil::Worker::Failed;
use strict;
use warnings;
use utf8;

use parent qw/XOClock::Worker/;

sub run {
    my($class, $args) = @_;

    die;
}

1;
