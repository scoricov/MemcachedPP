use strict;
use warnings;
use ExtUtils::MakeMaker;

WriteMakefile(
    NAME                => 'MemcachedPP',
    AUTHOR              => 'Alexey Skorikov <alexey@skorikov.name>',
    VERSION_FROM        => 'lib/MemcachedPP.pm',
    ABSTRACT_FROM       => 'lib/MemcachedPP.pm',
    PL_FILES            => {},
    PREREQ_PM => {
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
    dist                => { COMPRESS => 'gzip -9f', SUFFIX => 'gz', },
    clean               => { FILES => 'MemcachedPP-*' },
);
