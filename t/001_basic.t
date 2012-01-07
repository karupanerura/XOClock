#!perl -w
use strict;
use Test::More;

use XOClock;

# test XOClock here
my $app = XOClock->new('--version');

my $help = $app->help_message;
note $help;
ok $help, 'help_message';

ok $app->appname,         'appname';
ok $app->version_message, 'version_message';

my $v = do {
    open my $fh, '>', \my $buffer;
    local *STDOUT = $fh;
    $app->run(); # do version
    $buffer;
};
like $v, qr/perl/;

my $x = `$^X -Ilib script/xoclockd --version`;
like $x, qr/perl/, 'exec xoclockd --version';

done_testing;
