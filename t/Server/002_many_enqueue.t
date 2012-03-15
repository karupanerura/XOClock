#!perl -w
use strict;
use warnings;
use utf8;

use Test::More tests => 300;
use Test::SharedFork;
use Test::TCP;

use t::TestUtil qw/test_server_config ignore_logminimal/;
use t::TestUtil::Worker::Mock;

use AnyEvent;
use XOClock::Server;
use XOClock::Client;
use POSIX ();

my $args = +{
    hoge => 'fuga'
};

ignore_logminimal {
    test_tcp(
        client => sub {
            my ($port, $server_pid) = @_;
            wait_port($port);

            my $client = XOClock::Client->new(
                host => '127.0.0.1',
                port => $port,
            );
            foreach (1 .. 100) {
                my $res = $client->enqueue(
                    name      => 'Mock',
                    datetime  => POSIX::strftime('%Y-%m-%d %H:%M:%S', gmtime(time + 1)),
                    args      => $args,
                )->recv;
                is $res, 'ok', 'enqueue success.';
            }

            1 until (waitpid($server_pid, 0) == $server_pid);
        },
        server => sub {
            my $port = shift;

            my $cv = AnyEvent->condvar;
            local $t::TestUtil::Worker::Mock::Callback = sub {
                my($self, $receved) = @_;

                pass('called worker.');
                is_deeply $receved, $args, 'args ok.';
            };
            my $app = XOClock::Server->new( test_server_config($port) )->run;
            my $w; $w = AnyEvent->timer(
                after => 2,
                cb    => sub {
                    $w = AnyEvent->idle(
                        cb => sub {
                            if ($app->pm->num_workers == 0 and $app->pm->num_queues == 0) {
                                $cv->send;
                                undef $w;
                            }
                        }
                   );
                }
            );
            $cv->recv;
            exit(0);
        },
    );
};
