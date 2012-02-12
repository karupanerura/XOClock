package t::TestUtil;
use strict;
use warnings;
use utf8;

use parent qw/Exporter/;
our @EXPORT_OK = qw/test_server_config ignore_logminimal create_dummy_work run_flatten/;
use Log::Minimal ();

sub ignore_logminimal (&) {## no critic
    my $code = shift;

    local $Log::Minimal::PRINT = sub {};
    $code->();
}

sub test_server_config {
    my $port = shift;

    return (
        host        => '127.0.0.1',
        port        => $port,
        max_workers => 2,
        interval    => 1,
        registered_worker => +{
            'Sleep1' => 't::TestUtil::Worker::Sleep1',
            'Sleep2' => 't::TestUtil::Worker::Sleep2',
            'Sleep3' => 't::TestUtil::Worker::Sleep3',
            'Mock'   => 't::TestUtil::Worker::Mock',
        },
        storage        => 'XOClock::Storage::Memory',
        storage_option => +{},
    );
}

sub create_dummy_work {
    my $epoch = shift;

    +{
        worker => +{},
        args   => +{},
        epoch  => $epoch,
    }
}

sub run_flatten {
    my $code = pop;
    while (my $next = pop) {
        my $cb = $code;
        $code = sub { $next->($cb) };
    }
    $code->();
}

1;
