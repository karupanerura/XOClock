package XOClock::Storage::Memory;
use strict;
use warnings;
use utf8;

use parent qw/XOClock::Storage/;

use 5.10.0;
use Data::Validator;
use sort '_mergesort';

use Class::Accessor::Lite (
    rw  => [qw/queue/],
);

sub new {
    my $class = CORE::shift;

    bless +{
        queue => []
    } => $class;
}

sub push {
    my $self = CORE::shift;
    my $arg  = $self->work_validate(@_);

    my $pos = $self->get_insert_pos(epoch => $arg->{epoch});
    splice(@{ $self->queue }, $pos, 0, $arg);
}

sub push_multi {
    my $self = CORE::shift;

    foreach my $work (@_) {
        CORE::push @{ $self->queue } => $self->work_validate($work);
    }
    $self->queue([ sort { $a->{epoch} <=> $b->{epoch} } @{ $self->queue } ]);
}

sub get_insert_pos {
    state $rule = Data::Validator->new(
        epoch  => +{ isa => 'Int' },
    )->with(qw/Method/);
    my($self, $arg) = $rule->validate(@_);

    my($head, $tail) = (0, $#{ $self->queue });
    return 0 if $tail == -1;

    my $last_pos;
    while ($head <= $tail) {
        my $pos = $head + int(($tail - $head) / 2);
        $last_pos = $pos;

        my $epoch = $self->queue->[$pos]{epoch};
        if ($epoch > $arg->{epoch}) {
            $tail = $pos - 1;
        }
        elsif ($epoch < $arg->{epoch}) {
            $head = $pos + 1;
        }
        else {## $epoch == $arg->{epoch}
            last;
        }
    }

    return ($self->queue->[$last_pos]{epoch} < $arg->{epoch}) ?
        $last_pos + 1:
        $last_pos;
}

sub shift {
    state $rule = Data::Validator->new(
        time => +{ isa => 'Int', default => sub { time } },
    )->with(qw/Method/);
    my($self, $arg) = $rule->validate(@_);

    if (@{ $self->queue } and ($arg->{time} >= $self->queue->[0]{epoch})) {
        return CORE::shift @{ $self->queue };
    }
}

sub shift_multi {
    state $rule = Data::Validator->new(
        time => +{ isa => 'Int', default => sub { time } },
    )->with(qw/Method/);
    my($self, $arg) = $rule->validate(@_);

    my @works;
    while (@{ $self->queue } and ($arg->{time} >= $self->queue->[0]{epoch})) {
        CORE::push @works => CORE::shift @{ $self->queue };
    }

    return \@works;
}

sub shift_all {
    my $self = CORE::shift;

    my @works = @{ $self->queue };
    $self->queue([]);

    return \@works;
}

sub copy {
    state $rule = Data::Validator->new(
        to => +{ isa => 'XOClock::Storage' },
    )->with(qw/Method/);
    my($self, $arg) = $rule->validate(@_);

    my @works = @{ $self->shift_all };
    $arg->{to}->push_multi(@works);
}

1;
