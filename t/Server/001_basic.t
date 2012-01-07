#!perl -w
use strict;
use warnings;
use utf8;

use Test::More;
use Test::SharedFork;
use Test::TCP;

use t::TestUtil qw/test_server_config/;
use t::TestUtil::Worker::Mock;

use AnyEvent;
use XOClock::Server;
use XOClock::Client;
use Time::Piece 1.20;

my $args = +{
    hoge => 'fuga'
};

my $server = Test::TCP->new(
    code => sub {
        my $port = shift;

        my $cv = AnyEvent->condvar;
        local $t::TestUtil::Worker::Mock::Callback = sub {
            my($self, $receved) = @_;

            pass('called worker.');
            is_deeply $receved, $args, 'args ok.';
        };
        my $app  = XOClock::Server->new( test_server_config($port) )->run;
        $cv->recv;
    }
);

wait_port($server->port);
my $client = XOClock::Client->new(
    host => '127.0.0.1',
    port => $server->port,
);
my $res = $client->enqueue(
    name      => 'Mock',
    datetime  => (Time::Piece->gmtime + 1)->strftime('%Y-%m-%d %H:%M:%S'),
    args      => $args,
)->recv;
is $res, 'ok', 'enqueue success.';

sleep 2;
$server->stop;
undef $server;

done_testing;
