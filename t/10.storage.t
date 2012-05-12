use Test::More tests => 16;
use File::Temp qw(tempdir tempfile);
use MemcachedPP::Storage;
use MemcachedPP::Storage::SQLite;

diag( "Testing MemcachedPP::Storage" );

my $memory = MemcachedPP::Storage->new();
isa_ok($memory, 'MemcachedPP::Storage');
storage_ok($memory);

diag( "Testing MemcachedPP::Storage::SQLite" );

my $tempdir = tempdir('memcachedppXXXX', TMPDIR => 1, CLEANUP => 1);
my (undef, $db_file) = tempfile(DIR =>$tempdir);

my $sqlite = MemcachedPP::Storage::SQLite->new(dbfile => $db_file);
isa_ok($sqlite, 'MemcachedPP::Storage::SQLite');
storage_ok($sqlite);


sub storage_ok
{
    my $storage = shift;

    my $data1 = 'data1';
    my $data2 = '____data2___';
    ok(
        $storage->set('key1', 0, 0, \$data1) &&
        $storage->set('key2', 0, 0, \$data2)
    );
    
    is_deeply($storage->get( [qw/key1 key2/] ), {
        key1 => [0, length($data1), $data1],
        key2 => [0, length($data2), $data2],
    } );

    my $cachedump = $storage->stats_cachedump(1, 100);

    is_deeply($cachedump, {
        key1 => [ length($data1), 0 ],
        key2 => [ length($data2), 0 ],
    } );

    ok(2 == $storage->stats_items_number);

    ok( $storage->delete('key1') );

    ok(1 == $storage->stats_items_number);

    my $data_long = '0' x 4096;
    $storage->set('key2', 0, 0, \$data_long);

    is_deeply($storage->get( [qw/key1 key2/] ), {
        key2 => [0, 4096, $data_long],
    } );
}
