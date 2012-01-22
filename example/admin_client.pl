use strict;
use warnings;
use utf8;

use XOClock::Admin::Client;
use Time::Piece 1.20 ();
use Data::Dumper;

my $client = XOClock::Admin::Client->new(
    host => '127.0.0.1',
    port => 5313,
);
my $res = $client->server_status->recv;
warn Dumper $res;
