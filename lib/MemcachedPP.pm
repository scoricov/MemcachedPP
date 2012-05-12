package MemcachedPP;

use strict;

use Getopt::Std;
use Fcntl qw(:DEFAULT :flock);
use POSIX qw(setsid setuid setpgid);
use Log::Dispatch;

use MemcachedPP::Log;
use MemcachedPP::Server;

use constant FORK_WAIT => 2;
use constant FORK_MAX_ATTEMPTS => 10;

our $VERSION = '0.86';


sub daemonize
{
    my ($class, $pid_file, $uid, $gid) = @_;

    print "Starting memcachedpp... ";

    if (my $old_pid = $class->get_pid($pid_file)) {
        kill(0, $old_pid) and
            die "The daemon is already running with PID $old_pid";
    }

    sysopen(PIDFILE, $pid_file, O_RDWR|O_CREAT) or
        die "Can't open PID file $pid_file: $!";
    flock(PIDFILE, LOCK_EX | LOCK_NB) or
        die "PID file $pid_file is already locked";
    sysseek PIDFILE, 0, 0 and truncate PIDFILE, 0 or
        die "PID file $pid_file is not writable: $!";

    my $attempt = 0;
    my $pid;

    while (not defined ($pid = fork())) {
        die "Too many failed fork attempts: $!\n"
            if ++$attempt > FORK_MAX_ATTEMPTS;
        warn "Fork failed: $!\n";
        sleep FORK_WAIT;
    }

    if ($pid)
    {
        syswrite PIDFILE, "$pid\n", length("$pid\n") and close(PIDFILE)
            or die "Can't write PID file $pid_file: $!";

        print "Success (PID=$pid)\n";
        exit 1;
    }

    umask 0;
    POSIX::setsid()                 or die "Can't start a new session: $!";
    $uid and POSIX::setuid($uid)    || die "Can't set UID: $!";
    $gid and POSIX::setpgid($gid)   || die "Can't set GID: $!";
    open STDIN,  q{<}, '/dev/null'  or die "Can't read /dev/null: $!";
    open STDOUT, q{+>&STDIN}        or die "Can't write to STDIN: $!";
    open STDERR, q{+>&STDIN}        or die "Can't write to STDIN: $!";
    $0 = 'memcachedpp';

    1;
}

sub get_pid
{
    my ($class, $pid_file) = @_;

    (-r $pid_file) or return 0;
    open(PIDFILE, '<', $pid_file) or return 0;
    my $pid = <PIDFILE>;
    close(PIDFILE);
    $pid or return 0;

    return int($pid);
}

sub start {
    my ($class, %opts) = @_;
    %opts or getopts('l:f:p:u:g:dhKT:L:DS', \%opts);

    $opts{h}                 && $class->print_usage;
    my $pid_file = $opts{p} || 'memcachedpp.pid';

    if ($opts{S}) {
        $class->stop_daemon($pid_file);
        exit;
    }

    my $listen    = $opts{l} || $class->print_usage;
    my $db_file   = $opts{f};
    my $daemonize = $opts{d};
    my $log_level = $opts{D} ? 'debug' : 'warning';

    my $logger = MemcachedPP::Log::set_logger( Log::Dispatch->new );

    if ($daemonize && ( my $log_file = $opts{L} ) )
    {
        require Log::Dispatch::File;
        $logger->add( Log::Dispatch::File->new
            ( name      => 'logfile',
              min_level => $log_level,
              filename  => $log_file,
              mode      => '>>',
              newline   => 1,
            )
        );
    } else
    {
        require Log::Dispatch::Screen;
        $logger->add( Log::Dispatch::Screen->new
            ( name      => 'screen',
              min_level => $log_level,
              newline   => 1,
            )
        );
    }

    local $SIG{__WARN__} = sub { WARN $_[0] };
    local $SIG{__DIE__} = sub { CRITICAL $_[0] };

    my $storage;

    if ($db_file) {
        require MemcachedPP::Storage::SQLite;
        $storage = MemcachedPP::Storage::SQLite->new(dbfile => $db_file);
    } else {
        require MemcachedPP::Storage;
        $storage = MemcachedPP::Storage->new;
    }

    my %args = (
        listen    => [ $listen ],
        storage   => $storage,
        keepalive => $opts{K},
    );
    $args{timeout} = $opts{T} if defined $opts{T};

    my $server = MemcachedPP::Server->new(%args);

    if ($daemonize) {
        my ($uid, $guid) = ($opts{u}, $opts{g});
        $class->daemonize($pid_file, $uid, $guid);
    }

    $server->run;
}

sub stop_daemon
{
    my ($class, $pid_file) = @_;

    print "Stopping memcachedpp... ";

    my $pid = $class->get_pid($pid_file) or die
        "The daemon is probably not running. Failed to read PID file $pid_file";

    if ( kill(0, $pid) ) {
        kill(15, $pid) or kill(9, $pid) or die "Failed to kill the process $pid";
    } else {
        print "Failed to locate the process with PID $pid. " .
              "Probably it is not running. Removing PID file... ";
    }

    unlink $pid_file or die "Failed to remove PID file $pid_file";
    print "Success\n";
    1;
}

sub print_usage
{
    print <<EOF_USAGE;
Usage:

  Start:
    $0 -l <host:port> [-K] [-T <timeout>] [-f <db_file>] [-d [-p <pid_file>] [-u <UID>] [-g <GID>] ] [-L <log_file>] [-D]

  Stop:
    $0 -S [-p <pid_file>]

EOF_USAGE
    exit;
}

1;
__END__


=head1 NAME

MemcachedPP - pure Perl lightweight implementation of Memcached


=head1 VERSION

This document describes MemcachedPP version 0.86


=head1 SYNOPSIS

    use MemcachedPP;
    use MemcachedPP::Storage;

    my $server = MemcachedPP::Server->new(
        host    => '127.0.0.1',
        port    => 9191,
        storage => MemcachedPP::Storage->new(),
    );

    $server->run;


=head1 INTERFACE

Example 1:

./memcachedpp -l 127.0.0.1:9191 -T 60 -f sqlite.db -d -p memdpp.pid -D -L memdpp.log

Meaning:
* run memcachedpp as daemon write PID to memdpp.pid
* listen to 127.0.0.1:9191 for incomming connections,
  disconnect after 60 seconds of idling or transport delay;
* setup SQLite storage within database file of sqlite.db
* write logs to memdpp.log, set log level to DEBUG

Example 2:

./memcachedpp -l somesocket -D

Meaning:
* run memcachedpp in foreground mode
* listen to UNIX socket 'somesocket' for incomming connections;
* setup storage in memory
* write logs to screen, set log level to DEBUG

Example 3:

./memcachedpp -S -p memdpp.pid

Meaning:
* read memcachedpp PID from file memdpp.pid;
* stop memcachedpp daemon;


=head1 DEPENDENCIES

Log::Dispatch - for comprehensive logging
Cache::Memcached - to talk to MemcachedPP service
Mojolicious - to produce web interface
AnyEvent, EV - for asynchronous server
DBI, DBD::SQLite - for storage


=head1 AUTHOR

Alexey Skorikov  C<< <alexey@skorikov.name> >>


=head1 LICENCE AND COPYRIGHT

Copyright (c) 2010, Alexey Skorikov C<< <alexey@skorikov.name> >>. All rights reserved.

This module is free software; you can redistribute it and/or
modify it under the same terms as Perl itself. See L<perlartistic>.
