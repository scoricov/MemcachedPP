#!/usr/bin/env perl

use strict;
use warnings;

use Test::More tests => 25;
use FindBin;
use Test::Mojo;
require MemcachedPP::Web;

diag( "Testing MemcachedPP::Web $MemcachedPP::Web::VERSION" );

BEGIN {
    $ENV{WEBDEMO_HOME}      ||= "$FindBin::Bin/../";
    $ENV{WEBDEMO_MEMCACHED} ||= '127.0.0.1:9191';
    $ENV{MOJO_MODE}         ||= 'production';
}

my $pid;

if ($pid = fork())
{
    local $SIG{__DIE__} = sub { kill 'TERM', $pid; };

    sleep(2); # wait for backend

    my $t = Test::Mojo->new(app => 'MemcachedPP::Web');

    $t->get_ok('/')->status_is(200)->content_type_is('text/html')
        ->content_like(qr/MemcachedPP List/i);

    $t->get_ok('/list')->status_is(200)->content_type_is('text/html')
        ->content_like(qr/Empty/i);

    $t->get_ok('/set')->status_is(200)->content_type_is('text/html')
        ->content_like(qr/MemcachedPP Set/i);

    $t->post_form_ok('/set' =>
        {
            key     => 'key1',
            value   => 'Test string for key1',
            expires => 0,
        },
        {Expect => '100-continue'},
    );

    $t->get_ok('/get/key1')->status_is(200)->content_type_is('text/html')
        ->content_like(qr/MemcachedPP Get/i)
            ->content_like(qr/Test string for key1/i);

    $t->get_ok('/del/key1')->status_is(200)->content_type_is('text/html')
        ->content_like(qr/Empty/i);

    $t->get_ok('/foo')->status_is(404)
        ->content_like(qr/Not Found/);

    kill 'TERM', $pid;
    exit 0;
}

# setup backend

require MemcachedPP::Server;
require MemcachedPP::Storage;

my $server = MemcachedPP::Server->new(
    listen  => [ $ENV{WEBDEMO_MEMCACHED} ],
    storage => MemcachedPP::Storage->new,
);
$server->run;
