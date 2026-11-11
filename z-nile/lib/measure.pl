# The one clock for a process group (the Python port starts here).
# wall is seconds from znmeasure::now at the start until write; cpu is the user and system time of
# every child this process has waited for (times(), which on Unix includes their descendants).
# A report that cannot be written is skipped. The command's exit is never this module's.
package znmeasure;
use strict;
use warnings;

my $hires = eval { require Time::HiRes; 1 };

sub now {
    return $hires ? Time::HiRes::time() : time();
}

# One line, `wall=<seconds> cpu=<seconds>`, three decimal places. Nothing on failure.
sub write {
    my ( $path, $t0 ) = @_;
    return unless defined $path && $path ne '' && defined $t0 && $t0 ne '';
    my $wall = now() - $t0;
    $wall = 0 if $wall < 0;
    my ( $cu, $cs ) = ( times() )[ 2, 3 ];
    open my $fh, '>', $path or return;
    printf {$fh} "wall=%.3f cpu=%.3f\n", $wall, $cu + $cs;
    close $fh;
}

1;
