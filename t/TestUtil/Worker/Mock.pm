package t::TestUtil::Worker::Mock;
use strict;
use warnings;
use utf8;

use parent qw/XOClock::Worker/;
our $Callback = sub { sleep 1 };

sub run {
    my($class, $args) = @_;

    $class->$Callback($args);
}

1;
