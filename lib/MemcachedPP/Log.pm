package MemcachedPP::Log;

use strict;
use POSIX qw(strftime);

our $LOGGER;
our %IMPORT_CALLED;


sub import
{
    my $class = shift;

    no strict qw(refs);

    my $caller_pkg = caller();

    return 1 if $IMPORT_CALLED{$caller_pkg}++;

    for(qw(DEBUG INFO NOTICE WARNING ERROR CRITICAL ALERT EMERGENCY)) {
        my $sub_name = $_;
        my $level    = lc($_);
        *{"$caller_pkg\::$sub_name"} = sub {
            my $message = strftime("[%d %b %Y %H:%M:%S]", localtime) .
                          " [$level] " . $_[0];
            $LOGGER ?
                $LOGGER->log(
                    level => $level,
                    message => $message
                ) :
                print STDOUT $message . "\n";
        };
    }
}

sub set_logger
{
    my $logger = shift;
    return $LOGGER = $logger if ((ref $logger) =~ /^Log::Dispatch/);
    return 0;
}

1;
__END__