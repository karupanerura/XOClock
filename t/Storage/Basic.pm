package t::Storage::Basic;
use strict;
use warnings;
use utf8;

use Test::More;

use XOClock::Storage::Memory;

sub run_test {
    my $class = shift;
    my $q     = shift;
    my $cb    = shift;
    isa_ok $q => 'XOClock::Storage', 'base class is XOClock::Storage';

    my @test;

    ## push
    push @test => sub {
        my $next = shift;
        my $called = 0;
        $q->push(
            %{ create_dummy_data(0) },
            cb => sub {
                pass 'call ok';
                size_is_valid($q => 1, $next);
                fail 'duplicate called.' if $called++;
            }
        );
    };

    ## push_multi
    push @test => sub {
        my $next = shift;
        my $called = 0;
        $q->push_multi(
            works => [map { create_dummy_data($_) } 1 .. 99],
            cb => sub {
                pass 'call ok';
                size_is_valid($q => 100, $next);
                fail 'duplicate called.' if $called++;
            }
        );
    };

    ## dump
    push @test => sub {
        my $next = shift;
        my $called = 0;
        $q->dump(
            cb => sub {
                my $works = shift;
                is scalar(@$works),    100, 'get data size is valid.';
                foreach my $i (0 .. 99) {
                    is $works->[$i]{epoch}, $i, 'get data is valid.';
                }
                size_is_valid($q => 100, $next);
                fail 'duplicate called.' if $called++;
            }
        );
    };

    ## shift
    push @test => sub {
        my $next = shift;
        my $called = 0;
        $q->shift(
            time => 0,
            cb   => sub {
                my $work = shift;
                is $work->{epoch}, 0, 'get data is valid.';
                size_is_valid($q => 99, $next);
                fail 'duplicate called.' if $called++;
            }
        );
    };

    ## shift_multi
    push @test => sub {
        my $next = shift;
        my $called = 0;
        $q->shift_multi(
            time => 9,
            cb => sub {
                my $works = shift;
                is scalar(@$works),    9, 'get data size is valid.';
                foreach my $i (0 .. 8) {
                    is $works->[$i]{epoch}, $i + 1, 'get data is valid.';
                }
                size_is_valid($q => 90, $next);
                fail 'duplicate called.' if $called++;
            }
        );
    };

    ## shift_all
    push @test => sub {
        my $next = shift;
        my $called = 0;
        $q->shift_all(
            cb => sub {
                my $works = shift;
                is scalar(@$works),    90, 'get data size is valid.';
                foreach my $i (0 .. 89) {
                    is $works->[$i]{epoch}, $i + 10, 'get data is valid.';
                }
                size_is_valid($q => 0, $next);
                fail 'duplicate called.' if $called++;
            }
        );
    };

    ## on_finish
    push @test => sub {
        my $next = shift;
        $cb->() if $cb;
        done_testing;
        $next->() if $next;
    };

    run_flatten(@test);
}

## size
sub size_is_valid {
    my($q, $wanted, $cb) = @_;

    my $called = 0;
    $q->size(
        cb => sub {
            my $size = shift;
            is $size, $wanted, 'size is valid.';
            $cb->() if $cb;
            fail 'duplicate called.' if $called++;
        }
    );
}

sub create_dummy_data {
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
