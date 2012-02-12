package XOClock::Storage::DBI;
use strict;
use warnings;
use utf8;

use 5.10.0;
use Data::Validator;

use parent qw/XOClock::Storage/;

use DBI;
use JSON;
use AnyEvent::DBI;
use Class::Load;
use Class::Accessor::Lite (
    ro => [qw/json builder driver dbh table/]
);
use SQL::Maker;
SQL::Maker->load_plugin('InsertMulti');

sub new {
    state $rule = Data::Validator->new(
        dsn      => +{ isa => 'Str' },
        username => +{ isa => 'Str' },
        password => +{ isa => 'Str' },
        table    => +{ isa => 'Str', default => 'queue' },
        attr     => +{
            isa => 'HashRef',
            default => sub {
                +{
                    RaiseError          => 1,
                    PrintError          => 0,
                    ShowErrorStatement  => 1,
                    AutoInactiveDestroy => 1
                },
            }
        },
    )->with(qw/Method/);
    my($class, $arg) = $rule->validate(@_);

    my $json    = JSON->new->utf8(1);
    my $driver  = (DBI->parse_dsn($arg->{dsn}))[1];
    my $dbh     = AnyEvent::DBI->new($arg->{dsn}, $arg->{username}, $arg->{password}, %{ $arg->{attr} });
    my $builder = SQL::Maker->new(driver => $driver);
    bless +{
        json    => $json,
        builder => $builder,
        driver  => $driver,
        table   => $arg->{table},
        dbh     => $dbh,
    } => $class,
}

sub select_columns { [qw/id worker args epoch/] }

sub deflate_data {
    my $self = CORE::shift;
    my $arg  = $self->work_validate(@_);

    return +{
        worker => $self->json->encode($arg->{worker}),
        args   => $self->json->encode($arg->{args}),
        epoch  => $arg->{epoch},
    }, exists($arg->{cb}) ? $arg->{cb} : ();
}

sub inflate_data {
    my($self, $data) = @_;

    return +{
        %$data,
        worker => $self->json->decode($data->{worker}),
        args   => $self->json->decode($data->{args}),
    };
}

sub format_data {
    state $rule = Data::Validator->new(
        data => +{ isa => 'ArrayRef' }
    )->with(qw/Method Sequenced/);
    my($self, $arg) = $rule->validate(@_);

    my %data;
    foreach my $i (0 .. $#{ $self->select_columns }) {
        my $name     = $self->select_columns->[$i];
        $data{$name} = $arg->{data}[$i];
    }

    return $self->inflate_data(\%data);
}

sub push {
    my $self       = CORE::shift;
    my($data, $cb) = $self->deflate_data(@_);

    my($sql, @args) = $self->builder->insert(
        $self->table,
        $data,
    );
    $self->dbh->exec($sql, @args, sub {
        $cb->() if $cb;
    });
}

sub push_multi {
    my $self = shift;
    return $self->push_multi_mysql(@_) if lc($self->driver) eq 'mysql';

    state $rule = Data::Validator->new(
        works => +{ isa => 'ArrayRef' },
        cb    => +{ isa => 'CodeRef', optional => 1 },
    );
    my $arg = $rule->validate(@_);

    my $count = 0;
    my $max   = scalar @{ $arg->{works} };
    foreach my $work (@{ $arg->{works} }) {
        $self->push(
            %$work,
            cb => sub {
                if (++$count == $max) {
                    $arg->{cb}->() if exists $arg->{cb};
                }
            },
        );
    }
}

sub push_multi_mysql {
    state $rule = Data::Validator->new(
        works => +{ isa => 'ArrayRef' },
        cb    => +{ isa => 'CodeRef', optional => 1 },
    )->with(qw/Method/);
    my($self, $arg) = $rule->validate(@_);

    my @works;
    foreach my $work (@{ $arg->{works} }) {
        CORE::push @works => $self->deflate_data($work);
    }
    my($sql, @args) = $self->builder->insert_multi(
        $self->table,
        \@works,
    );
    $self->dbh->exec($sql, @args, sub {
        $arg->{cb}->() if exists $arg->{cb};
    });
}

sub shift {
    state $rule = Data::Validator->new(
        time => +{ isa => 'Int', default => sub { time } },
        cb   => +{ isa => 'CodeRef' }
    )->with(qw/Method/);
    my($self, $arg) = $rule->validate(@_);

    my($sql, @args) = $self->builder->select(
        $self->table,
        $self->select_columns,
        +{
            epoch  => +{'<=' => $arg->{time}},
            enable => 1,
        },
        +{
            limit    => 1,
        },
    );
    $self->dbh->exec($sql, @args, sub {
        my(undef, $datas) = @_;
        my $work = $self->format_data($datas->[0]);

        my $id = delete $work->{id};
        $self->disable_works(
            id => [$id],
            cb => sub {
                $arg->{cb}->($work);
            }
        );
    });
}

sub shift_multi {
    state $rule = Data::Validator->new(
        time => +{ isa => 'Int', default => sub { time } },
        cb   => +{ isa => 'CodeRef' }
    )->with(qw/Method/);
    my($self, $arg) = $rule->validate(@_);

    my($sql, @args) = $self->builder->select(
        $self->table,
        $self->select_columns,
        +{
            epoch  => +{'<=' => $arg->{time}},
            enable => 1,
        },
    );
    $self->dbh->exec($sql, @args, sub {
        my(undef, $datas) = @_;

        my(@ids, @works);
        foreach my $data (@$datas) {
            my $work = $self->format_data($data);
            CORE::push @ids   => delete $work->{id};
            CORE::push @works => $work;
        }

        @works = sort { $a->{epoch} <=> $b->{epoch} } @works;
        $self->disable_works(
            id => \@ids,
            cb => sub {
                $arg->{cb}->(\@works);
            }
        );
    });
}

sub shift_all {
    state $rule = Data::Validator->new(
        cb   => +{ isa => 'CodeRef' }
    )->with(qw/Method/);
    my($self, $arg) = $rule->validate(@_);

    my($sql, @args) = $self->builder->select(
        $self->table,
        $self->select_columns,
        +{
            enable => 1,
        },
    );
    $self->dbh->exec($sql, @args, sub {
        my(undef, $datas) = @_;

        my(@ids, @works);
        foreach my $data (@$datas) {
            my $work = $self->format_data($data);
            CORE::push @ids   => delete $work->{id};
            CORE::push @works => $work;
        }

        @works = sort { $a->{epoch} <=> $b->{epoch} } @works;
        $self->disable_works(
            id => \@ids,
            cb => sub {
                $arg->{cb}->(\@works);
            }
        );
    });
}

sub dump {
    state $rule = Data::Validator->new(
        cb   => +{ isa => 'CodeRef' }
    )->with(qw/Method/);
    my($self, $arg) = $rule->validate(@_);

    my($sql, @args) = $self->builder->select(
        $self->table,
        $self->select_columns,
        +{
            enable => 1,
        },
    );
    $self->dbh->exec($sql, @args, sub {
        my(undef, $datas) = @_;

        my(@works);
        foreach my $data (@$datas) {
            my $work = $self->format_data($data);
            delete $work->{id};
            CORE::push @works => $work;
        }

        @works = sort { $a->{epoch} <=> $b->{epoch} } @works;
        $arg->{cb}->(\@works);
    });
}

sub size {
    state $rule = Data::Validator->new(
        cb   => +{ isa => 'CodeRef' }
    )->with(qw/Method/);
    my($self, $arg) = $rule->validate(@_);

    my $table = $self->table;
    $self->dbh->exec("SELECT count(*) FROM $table WHERE enable = 1;", sub {
        my(undef, $datas) = @_;
        my $count = $datas->[0][0];

        $arg->{cb}->($count);
    });
}

sub disable_works {
    state $rule = Data::Validator->new(
        id => +{ isa => 'ArrayRef' },
        cb => +{ isa => 'CodeRef', optional => 1 }
    )->with(qw/Method/);
    my($self, $arg) = $rule->validate(@_);

    my($sql, @args) = $self->builder->update(
        $self->table,
        +{ enable => 0 },
        +{
            id => $arg->{id},
        },
    );
    $self->dbh->exec($sql, @args, sub {
        $arg->{cb}->() if exists $arg->{cb};
    });
}

sub clean_disable_works {
    state $rule = Data::Validator->new(
        cb => +{ isa => 'CodeRef', optional => 1 }
    )->with(qw/Method/);
    my($self, $arg) = $rule->validate(@_);

    my($sql, @args) = $self->builder->delete(
        $self->table,
        +{ enable => 0 },
    );
    $self->dbh->exec($sql, @args, sub {
        $arg->{cb}->() if exists $arg->{cb};
    });
}

1;
