package MemcachedPP::Storage;

use strict;
use warnings;

use AnyEvent;


sub new
{
    my $class = shift;

    return bless {
        cache => {},
    }, ref $class || $class;
}

sub get
{
    my ($self, $keys) = @_;
    return 0 unless @$keys;
    my $items = {};
    my $now = AnyEvent->now;

    foreach my $key (@$keys) {
        if (exists $self->{cache}{$key}) {
            my $item = $self->{cache}{$key};

            $items->{$key} = [ $item->[0], length($item->[1]), $item->[1] ]
                if (($item->[0] == 0) || ($now < $item->[0]));
        }
    }

    return $items;
}

sub set
{
    my ($self, $key, $flag, $exptime, $value) = @_;
    return 0 unless length($key);
    $exptime ||= 0;
    $value ||= '';
    $exptime += AnyEvent->now if ((2592000 > $exptime) && ($exptime > 0));
    $exptime ++ if ($exptime % 2);
    $self->_set($key, int $exptime, $value);
    return 1;
}

sub _set
{
    my ($self, $key, $exptime, $value) = @_;
    $self->{cache}{$key} = [ $exptime, $$value ];
    return 1;
}

sub delete
{
    my ($self, $key) = @_;
    return delete $self->{cache}{$key} ? 1 : 0;
}

sub cleanup
{
    my $self = shift;
    my $now = AnyEvent->now;

    for (keys %{ $self->{cache} }) {
        $self->delete($_) if (
            ( $self->{cache}{$_}->[0] > 0 ) &&
            ( $self->{cache}{$_}->[0] <= $now )
        );
    }

    return 1;
}

sub stats_cachedump
{
    my ($self, $slab, $limit) = @_;
    my $items = {};
    my $cnt = 0;

    return $items if ( ($limit <= 0) or !$self->stats_items_number );

    while (
        ($cnt < $limit) &&
        ( my ($key, $item) = each %{ $self->{cache} } )
    ) {
        $items->{$key} = [ length($item->[1]), $item->[0] ];
        $cnt++;
    }

    return $items;
}

sub stats_items_number
{
    my $self = shift;
    $self->cleanup;
    return scalar keys %{ $self->{cache} };
}

1;
__END__