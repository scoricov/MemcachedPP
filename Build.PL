use strict;
use warnings;
use Module::Build;

my $builder = Module::Build->new(
    module_name         => 'MemcachedPP',
    license             => 'perl',
    dist_author         => 'Alexey Skorikov <alexey@skorikov.name>',
    dist_version_from   => 'lib/MemcachedPP.pm',
    dist_abstract       => 'README',
    requires => {
        'Log::Dispatch'       => 2.26,
        'Cache::Memcached'    => 1.29,
        'Mojolicious'         => 0.9999,
        'AnyEvent'            => 5.27,
        'EV'                  => 3.9,
        'DBI'                 => 1.61,
        'DBD::SQLite'         => 1.29,
        'Test::More'          => 0,
        'Test::Pod'           => 1.14,
        'File::Temp'          => 0,
        'version'             => 0,
    },
    add_to_cleanup      => [ 'MemcachedPP-*' ],
);

$builder->create_build_script();
