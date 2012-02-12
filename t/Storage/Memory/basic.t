#!perl -w
use strict;
use warnings;
use utf8;

use XOClock::Storage::Memory;
use t::Storage::Basic;

my $q = XOClock::Storage::Memory->new;
t::Storage::Basic->run_test($q);
