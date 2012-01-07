#!perl
use strict;
use warnings;
BEGIN {
    unshift @INC, 'inc';

    # author requires, or bundled modules
    my @devmods = qw(
        inc::Module::Install             1.00
        Module::Install::AuthorTests     0.002
        Module::Install::Repository      0.06
        Test::Requires                   0.06
    );
    my @not_available;
    while(my($mod, $ver) = splice @devmods, 0, 2) {
        eval qq{use $mod $ver (); 1} or push @not_available, $mod;
    }
    if(@not_available) {
        print qq{# The following modules are not available.\n};
        print qq{# `perl $0 | cpanm` will install them:\n};
        print $_, "\n" for @not_available;
        exit 1;
     }
}
use inc::Module::Install;

all_from 'lib/XOClock.pm';

requires 'Getopt::Long' => '2.37';
requires 'Class::Accessor::Lite' => '0.04';
requires 'Time::Piece' => '1.20';
requires 'Parallel::ForkManager';
requires 'Log::Minimal';
requires 'AnyEvent';
requires 'AnyEvent::JSONRPC::Lite';
requires 'Scalar::Util';
requires 'Data::Validator';
requires 'IO::Handle';
requires 'YAML::Syck';

test_requires 'Test::More'     => '0.88';
test_requires 'Test::Requires' => '0.06';

auto_set_repository;

tests_recursive;
author_tests 'xt';

install_script 'xoclockd';

clean_files qw(
    XOClock-*
    *.stackdump
    cover_db *.gcov *.gcda *.gcno
    nytprof
    *.out
);

WriteAll(check_nmake => 0);
