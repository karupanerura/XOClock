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
    $arg->{cb}->(status => 'success') if exists $arg->{cb};
}

sub push_multi {
    state $rule = Data::Validator->new(
        works => +{ isa => 'ArrayRef' },
        cb    => +{ isa => 'CodeRef', optional => 1 },
    )->with(qw/Method/);
    my($self, $arg) = $rule->validate(@_);

    foreach my $work (@{ $arg->{works} }) {
        CORE::push @{ $self->queue } => $self->work_validate($work);
    }
    $self->queue([ sort { $a->{epoch} <=> $b->{epoch} } @{ $self->queue } ]);
    $arg->{cb}->(status => 'success') if exists $arg->{cb};
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
        cb   => +{ isa => 'CodeRef' },
    )->with(qw/Method/);
    my($self, $arg) = $rule->validate(@_);

    if (@{ $self->queue } and ($arg->{time} >= $self->queue->[0]{epoch})) {
        $arg->{cb}->(CORE::shift @{ $self->queue });
    }
}

sub shift_multi {
    state $rule = Data::Validator->new(
        time => +{ isa => 'Int', default => sub { time } },
        cb   => +{ isa => 'CodeRef' }
    )->with(qw/Method/);
    my($self, $arg) = $rule->validate(@_);

    my @works;
    while (@{ $self->queue } and ($arg->{time} >= $self->queue->[0]{epoch})) {
        CORE::push @works => CORE::shift @{ $self->queue };
    }

    $arg->{cb}->(\@works);
}

sub shift_all {
    state $rule = Data::Validator->new(
        cb   => +{ isa => 'CodeRef' }
    )->with(qw/Method/);
    my($self, $arg) = $rule->validate(@_);

    my @works = @{ $self->queue };
    $self->queue([]);

    $arg->{cb}->(\@works);
}

1;
