#!perl -w
use strict;
use warnings;
use utf8;

use AnyEvent;
use XOClock::Storage::DBI;
use t::Storage::Basic;

my $cv = AnyEvent->condvar;
my $q  = XOClock::Storage::DBI->new(
    dsn      => 'DBI:SQLite:dbname=:memory:',
    username => '',
    password => ''
);
my $create_table = <<'EOD';
CREATE TABLE queue (
    id                INTEGER            NOT NULL PRIMARY KEY,
    worker            TEXT BINARY        NOT NULL,
    args              TEXT BINARY        NOT NULL,
    epoch             INTEGER UNSIGNED   NOT NULL,
    enable            INTEGER UNSIGNED   NOT NULL DEFAULT 1
);
EOD

$q->dbh->exec($create_table, sub {
    t::Storage::Basic->run_test($q => sub {
        $cv->broadcast;
    });
});

# asynchronously do sth. else here
$cv->wait;
