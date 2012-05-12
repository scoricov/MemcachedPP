use Test::More tests => 25;
use Cache::Memcached;
use IO::Socket::INET;
use MemcachedPP::Server;
use MemcachedPP::Storage;

diag( "Testing MemcachedPP::Server $MemcachedPP::Server::VERSION" );

my @listen = ();
push @listen, '127.0.0.1:' . $_ for (9192..9212);

my $server = MemcachedPP::Server->new(
    listen  => \@listen,
    storage => MemcachedPP::Storage->new,
);

isa_ok($server, 'MemcachedPP::Server');

my $pid;

if ($pid = fork())
{
    local $SIG{__DIE__} = sub { kill 'TERM', $pid; };

    sleep(2); # wait for daemon

    ok(
        IO::Socket::INET->new(PeerAddr => $_, Timeout  => 1)
    ) for (@listen);

    my $memd = Cache::Memcached->new({
        servers   => \@listen,
        compress_threshold => 0,
    });

    $memd->set('expired_key', 'some data', 2);

    sleep(3);

    ok( !defined $memd->get('expired_key') );

    $memd->set('test_key', '0000000000', 0);

    my $cachedump_str = 'cachedump 1 100';
    my $stats = $memd->stats([ $cachedump_str, 'items' ])
        ->{hosts}{$listen[0]};

    ok($stats->{$cachedump_str} =~ m/^ITEM test_key\s+\[10\s+b\;\s+0\s+s\]/);
    ok($stats->{items} =~ m/^STAT\s+items\:\d+\:number\s+1/);

    kill 'TERM', $pid;
    exit 0;
}

$server->run;
