package MemcachedPP::Web;

use strict;
use warnings;

use Mojolicious 0.9999;
use Mojolicious::Lite;

use URI::Escape;
use Cache::Memcached;
$Cache::Memcached::HAVE_ZLIB = 0;

our $VERSION = '0.86';

app->home->parse( $ENV{WEBDEMO_HOME} );
app->renderer->root( app->home->rel_dir('templates') );
app->static->root( app->home->rel_dir('public') );
app->renderer->default_handler('ep');

get  '/'         => \&list_items => 'list';
get  '/list'     => \&list_items => 'list';
get  '/get/:key' => \&get_item   => 'get';
get  '/set/'     =>              => 'set';
get  '/set/:key' => \&get_item   => 'set';
post '/set'      => \&set_item   => 'list';
post '/del'      => \&del_items  => 'list';
get  '/del/:key' => \&del_item   => 'list';

sub list_items {
    my $c = shift;
    my $page_limit = 20;
    my @items;
    my $cachedump_str = "cachedump 1 $page_limit";
    my $stats = app->memd->stats([ $cachedump_str, 'items' ])
        ->{hosts}{$ENV{WEBDEMO_MEMCACHED}};
    my $stats_cachedump = $stats->{$cachedump_str};
    my $stats_items = $stats->{items};
    my $now = time();

    foreach my $line (split /^/, $stats_cachedump) {
        if (
            my ($key, $length, $exptime) = 
                ($line =~
                    m/^ITEM\s(\p{IsGraph}+)\s+\[\s*(\d{1,11})\s+b\;\s+(\d{1,11})\s+s\s*\]\s*$/gm)
        ) {
            my $ttl = ($exptime > 0) ? int($exptime - $now) : 0;
            my $value = substr(app->memd->get($key), 0, 128);
            push @items, [ uri_escape($key), $key, $length, $ttl, $value ];
        }
    }

    $c->stash(items => \@items);
    $c->render;
}

sub del_items
{
    my $c = shift;
    my $params = $c->req->body_params->to_hash;

    foreach my $key (keys %$params) {
        app->memd->delete($key) if ('on' eq $params->{$key});
    }

    list_items($c);
}

sub del_item
{
    my $c = shift;

    app->memd->delete( $c->param('key') );
    list_items($c);
}

sub get_item
{
    my $c = shift;
    my $item_key = $c->param('key');
    my $item_value = app->memd->get( $item_key );
    $c->render_not_found unless defined $item_value;

    $c->stash(item =>
        [ uri_escape($item_key), $item_key, length($item_value), $item_value ]
    );
    $c->render;
}

sub set_item
{
    my $c = shift;
    my $params = $c->req->body_params->to_hash;
    my $warnings = $c->stash('warnings');

    if (defined $params->{key} && ($params->{key} =~ m/[^\/\.\*]+/)) {
        $params->{key}     = substr($params->{key},   0, 250);
        $params->{value}   = substr($params->{value}, 0, 1048576); # 1 Mb
        $params->{exptime} = int($params->{exptime} || 0);
        app->memd->set($params->{key}, $params->{value}, $params->{exptime})
            or push @$warnings, "Set operation has failed";
    } else {
        push @$warnings, "Illegal key specified";
    }

    list_items($c);
}

app->plugins->add_hook(
    before_dispatch => sub {
        my ($self, $c) = @_;

        $c->stash(template_class => __PACKAGE__);

        $c->stash(warnings => []);
    }
);

(ref app)->attr('memd');
app->memd(
    new Cache::Memcached {
        servers            => [ $ENV{WEBDEMO_MEMCACHED} ],
        compress_threshold => 0,
    }
);

app->start;
__END__