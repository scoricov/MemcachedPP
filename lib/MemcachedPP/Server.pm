package MemcachedPP::Server;

use strict;
use warnings;

use Socket qw(IPPROTO_TCP TCP_NODELAY);

use EV;
use AnyEvent;
use AnyEvent::Handle;
use AnyEvent::Socket;

use MemcachedPP::Log;

our $VERSION = '0.86';


sub new {
    my($class, @args) = @_;

    my $self = bless {
        no_delay  => 0,
        timeout   => 3600,
        keepalive => 1,
        @args,
    }, $class;

    ref $self->{storage} or
        die "Invalid or unspecified storage\n";

    return $self;
}

sub storage { shift->{storage} }

sub start_listen {
    my $self = shift;
    my @listen = @{$self->{listen} || [ ($self->{host} || '') . ":$self->{port}" ]};
    for my $listen (@listen) {
        push @{$self->{listen_guards}}, $self->_create_tcp_server($listen);
    }
}

sub register_service {
    my $self = shift;
    DEBUG "Registering service";

    $self->start_listen;

    $self->{exit_guard} = AE::cv {
        delete $self->{listen_guards};
    };
    $self->{exit_guard}->begin;
}

sub run {
    my $self = shift;
    $self->register_service;

    my $w; $w = AE::signal QUIT => sub { $self->{exit_guard}->end; undef $w };
    $self->{exit_guard}->recv;

    DEBUG "Shutting down";
}

sub _create_tcp_server {
    my ( $self, $listen ) = @_;

    my($host, $port, $is_tcp);
    if ($listen =~ /:\d+$/) {
        ($host, $port) = split /:/, $listen;
        $host = undef if $host eq '';
        $is_tcp = 1;
    } else {
        $host = "unix/";
        $port = $listen;
    }

    DEBUG "Starting to listen to $listen";

    return tcp_server $host, $port, sub { $self->_accept_handler($is_tcp, @_); }
}

sub _accept_handler {
    my ( $self, $is_tcp, $sock, $peer_host, $peer_port ) = @_;

    INFO "Accepted connection from $peer_host:$peer_port";

    return unless $sock;
    $self->{exit_guard}->begin;

    if ( $is_tcp && $self->{no_delay} ) {
        setsockopt($sock, IPPROTO_TCP, TCP_NODELAY, 1)
            or die "setsockopt(TCP_NODELAY) failed:$!";
    }

    my $handle = AnyEvent::Handle->new(
        fh        => $sock,
        timeout   => $self->{timeout},
        rtimeout  => $self->{timeout},
        wtimeout  => $self->{timeout},
        keepalive => $self->{keepalive},
    );
    my $ret = AE::cv;

    my $cleanup = sub {
        DEBUG "Closing connection";
        my $err = $_[2];
        $handle->destroy;
        if ($err) {
            ERROR "Connection error: $err";
            $ret->send($err);
        }
    };

    $handle->on_error($cleanup);
    $handle->on_eof($cleanup);
    $handle->on_timeout($cleanup);

    $handle->push_read(line => $self->_read_commands );
}

sub _read_commands
{
    my $self = shift;

    my $read_commands;
    $read_commands = sub {
        my ($handle, $cmd) = @_;

        DEBUG "Client> $cmd";

        if (
            my ($key, $flag, $ttl, $length) = 
                ($cmd =~ m/^set ([\p{IsWord}\/|:-]{1,250}) (\d{1,5}) (\d{1,11}) (\d{1,16})( noreply)?\s*$/)
        ) {
            $handle->push_read(chunk => $length, sub {
                my $data = $_[1];
                $self->storage->set($key, $flag, $ttl, \$data ) ?
                    $handle->push_write("STORED\r\n") :
                    $handle->push_write("NOT_STORED\r\n");
            } );
        }

        elsif (
            my ($keys_line) =
                ($cmd =~ m/^get (([\p{IsWord}\/|:-]{1,250})(\*([\p{IsWord}\/|:-]{1,250})){0,127})\s*$/)
        ) {
            my @keys = split /\*/, $keys_line, 128;
            my $items = $self->storage->get(\@keys);

            if ($items) {
                while (my ($item_key, $item) = each %$items) {
                    $handle->push_write("VALUE $item_key $item->[0] $item->[1]\r\n");
                    $handle->push_write("$item->[2]\r\n");
                }
                $handle->push_write("END\r\n");
            } else {
                $handle->push_write("ERROR\r\n");
            }
        }

        elsif (
            my ($delkey) = 
                ($cmd =~ m/^delete ([\p{IsWord}\/|:-]{1,250})(\s(\d{1,11}))?(\s(noreply))?\s*$/)
        ) {
            $self->storage->delete($delkey) ?
                $handle->push_write("DELETED\r\n") :
                $handle->push_write("NOT_FOUND\r\n");
        }

        elsif ($cmd =~ m/^stats items\s*$/) {
            my $number = $self->storage->stats_items_number;
            $handle->push_write("STAT items:1:number $number\r\n");
            $handle->push_write("END\r\n");
        }

        elsif (
            my ($slab, $limit) =
                ($cmd =~ m/^stats cachedump (\d{1,6}) (\d{1,6})\s*$/)
        ) {
            my $cachedump = $self->storage->stats_cachedump($slab, $limit);

            if ($cachedump) {
                while (my ($item_key, $item) = each %$cachedump) {
                    $handle->push_write("ITEM $item_key [$item->[0] b; $item->[1] s]\r\n");
                }
                $handle->push_write("END\r\n");
            } else {
                $handle->push_write("ERROR\r\n");
            }
        }

        elsif ($cmd =~ m/^version\s*$/) {
            $handle->push_write("VERSION $VERSION\r\n");
        }

        elsif ($cmd =~ m/^quit\s*$/) {
            $handle->destroy;
        }

        elsif ($cmd =~ m/\P{IsCntrl}/) {
            $handle->push_write("CLIENT_ERROR bad command line\r\n");
        }

        $handle->push_read(line => $read_commands);
    };

    return $read_commands;
}

1;
__END__