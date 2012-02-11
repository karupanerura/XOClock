package XOClock::Storage::Memory;
use strict;
use warnings;
use utf8;

use 5.10.0;
use Data::Validator;

use Class::Accessor::Lite (
    rw  => [qw/queue/],
);

sub new {
    my $class = shift;

    bless +{
        queue => []
    } => $class;
}

sub push {
    state $rule = Data::Validator->new(
        worker => 'HashRef',
        args   => 'HashRef',
        epoch  => 'Int',
    )->with(qw/Method/);
    my($self, $arg) = $rule->validate(@_);

    my $pos = $self->get_insert_pos(epoch => $arg->{epoch});
    splice(@{ $self->queue }, $pos, 0, $arg);
}

sub get_insert_pos {
    state $rule = Data::Validator->new(
        epoch  => 'Int',
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

sub copy {
    state $rule = Data::Validator->new(
        to => +{ isa => __PACKAGE__ },
    )->with(qw/Method/);
    my($self, $arg) = $rule->validate(@_);

    return unless @{ $self->queue };

    my $last_epoch = $self->queue->[-1]{epoch};
    while (my $work = $self->shift(time => $last_epoch)) {
        $arg->{to}->push($work)
    }
}

1;
