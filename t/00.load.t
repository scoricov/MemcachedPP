use Test::More tests => 6;

BEGIN {
use_ok( 'MemcachedPP::Log' );
use_ok( 'MemcachedPP::Server' );
use_ok( 'MemcachedPP::Storage' );
use_ok( 'MemcachedPP::Storage::SQLite' );
use_ok( 'MemcachedPP::Web' );
use_ok( 'MemcachedPP' );
}

diag( "Testing load" );
