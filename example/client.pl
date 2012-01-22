use strict;
use warnings;
use utf8;

use XOClock::Client;
use Time::Piece 1.20 ();

my $worker = shift(@ARGV) or die "Usage: $0 WorkerName [after]";
my $after  = shift(@ARGV) || 1;
my $count  = shift(@ARGV) || 1;
my $sleep  = shift(@ARGV) || 0;

my $client = XOClock::Client->new(
    host => '127.0.0.1',
    port => 5312,
);
foreach (1 .. $count) {
    my $res = $client->enqueue(
        name      => $worker,
        datetime  => (Time::Piece->gmtime + $after)->strftime('%Y-%m-%d %H:%M:%S'),
        args      => +{},
    )->recv;
    warn "Response: $res";
    select undef, undef, undef, $sleep if $sleep;
}
