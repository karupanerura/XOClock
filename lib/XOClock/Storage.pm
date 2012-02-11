package XOClock::Storage;
use strict;
use warnings;
use utf8;

sub new   { require Carp; Carp::croak 'this is abstruct method' }
sub push  { require Carp; Carp::croak 'this is abstruct method' }
sub shift { require Carp; Carp::croak 'this is abstruct method' }
sub copy  { require Carp; Carp::croak 'this is abstruct method' }

1;
