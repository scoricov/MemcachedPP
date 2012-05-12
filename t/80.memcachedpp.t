use Test::More tests => 205;
use File::Temp qw(tempdir tempfile);
use Cache::Memcached;

diag( "Testing MemcachedPP" );

my $tempdir = tempdir('memcachedppXXXX', TMPDIR => 1, CLEANUP => 1);
my (undef, $socket)   = tempfile(DIR =>$tempdir);
my (undef, $pid_file) = tempfile(DIR =>$tempdir);
my (undef, $log_file) = tempfile(DIR =>$tempdir);
my (undef, $db_file) = tempfile(DIR =>$tempdir);


my $pid;

if ($pid = fork())
{
    local $SIG{__DIE__} = sub { kill 'TERM', $pid; };

    sleep(2); # wait for daemon

    ok(-S $socket);
    ok(-f $pid_file);
    ok(-f $log_file);
    ok(-f $db_file);

    my @memd;
    push @memd,
        Cache::Memcached->new({
            servers   => [ $socket ],
            compress_threshold => 0,
        })
    for(1..100);

    my $i = 0;
    srand(time ^ $$);
    for (@memd) {
        $i++;
        my $data = 'Data' . $i . 'X' x int(rand(4096));
        ok( $_->set('somekey' . $i, $data) );
    }

    $i = 0;
    for (@memd) {
        $i++;
        my $value = $_->get('somekey' . $i);
        ok($value =~ /Data${\$i}/);
    }

    require MemcachedPP;
    my $stop = MemcachedPP->stop_daemon($pid_file);
    ok($stop);

    exit 0;
}

require MemcachedPP;
MemcachedPP->start(
    'd' => 1,
    'l' => $socket,
    'f' => $db_file,
    'p' => $pid_file,
    'L' => $log_file,
);
