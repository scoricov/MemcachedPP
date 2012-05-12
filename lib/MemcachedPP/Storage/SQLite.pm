package MemcachedPP::Storage::SQLite;

use strict;
use warnings;

use base qw(MemcachedPP::Storage);
use DBI qw(:sql_types);
require DBD::SQLite;

sub new
{
    my ($class, %args) = @_;
    $args{dbfile} ||= 'sqlite.db';

    my $self = bless \%args, ref $class || $class;
    $self->connect;

    return $self;
}

sub connect
{
    my $self = shift;

    my $dbh = DBI->connect(
        'dbi:SQLite:dbname=' . $self->{dbfile}, '', '',
        { RaiseError => 0, AutoCommit => 1 }
    )
        or die "Failed to connect to SQLite database within file '" .
            $self->{dbfile} . "': @!\n";

    $dbh->do( q{
        CREATE TABLE IF NOT EXISTS memcachedpp(
            id      VARCHAR(250) PRIMARY KEY ASC NOT NULL,
            exptime INTEGER,
            value   BLOB
        );
    } );

    $dbh->do( q{ DELETE FROM memcachedpp; } ) if $self->{reset};

    return $self->{dbh} = $dbh;
}

sub get
{
    my ($self, $keys) = @_;
    return 0 unless @$keys;
    my $items = {};

    my $sth = $self->{dbh}->prepare("
        SELECT id, exptime, value FROM memcachedpp WHERE
        id in (?" . ',?' x $#$keys . ") AND
        ( exptime = 0 OR exptime > strftime('%s','now') );
    ") or die @!;
    $sth->execute(@$keys);

    while (my $row = $sth->fetchrow_arrayref) {
        $items->{$row->[0]} = [ $row->[1], length($row->[2]), $row->[2] ];
    }

    return $items;
}

sub _set
{
    my ($self, $key, $exptime, $value) = @_;

    $self->delete($key);

    my $sth = $self->{dbh}->prepare( q{
        INSERT INTO memcachedpp (id, exptime, value) VALUES (?, ?, ?);
    } );
    $sth->bind_param(1, $key, SQL_VARCHAR);
    $sth->bind_param(2, $exptime, SQL_INTEGER);
    $sth->bind_param(3, $$value, SQL_BLOB);
    $sth->execute();

    return 1;
}

sub delete
{
    my ($self, $key) = @_;
    my $deleted = $self->{dbh}->do( q{
        DELETE FROM memcachedpp WHERE id = ?;
    }, undef, $key);

    return int $deleted;
}

sub cleanup
{
    my $self = shift;
    my $deleted = $self->{dbh}->do( q{
        DELETE FROM memcachedpp WHERE
        exptime != 0 AND exptime <= strftime('%s','now');
    } );

    return int $deleted;
}

sub stats_cachedump
{
    my ($self, $slab, $limit) = @_;
    my $items = {};
    return $items if ($limit <= 0);

    $self->cleanup;

    my $sth = $self->{dbh}->prepare( q{
        SELECT id, exptime, length(value) FROM memcachedpp WHERE
        exptime = 0 OR exptime > strftime('%s','now')
        LIMIT ?;
    } );
    $sth->execute($limit);

    while (my $row = $sth->fetchrow_arrayref) {
        $items->{$row->[0]} = [ int $row->[2], int $row->[1] ];
    }

    return $items;
}

sub stats_items_number
{
    my $self = shift;

    my $sth = $self->{dbh}->prepare( q{
        SELECT COUNT(id) FROM memcachedpp WHERE
        exptime = 0 OR exptime > strftime('%s','now');
    } );
    $sth->execute();

    return int $sth->fetchrow_arrayref->[0];
}

1;
__END__