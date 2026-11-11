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

sub _field {
    my ($s) = @_;
    $s = '' unless defined $s;
    $s =~ s/[\t\r\n]/ /g;
    return $s;
}

# One append to <root>/.cache/measure.tsv. Nothing on failure. The line is already one row of fields.
sub append {
    my ( $root, $line ) = @_;
    return unless defined $root && $root ne '' && defined $line && $line ne '';
    $line =~ s/[\r\n]//g;
    my $dir = "$root/.cache";
    mkdir $dir, 0755;
    open my $fh, '>>', "$dir/measure.tsv" or return;
    print {$fh} $line, "\n";
    close $fh;
}

# Appends one buffer line for a command that just finished. Fields, in order: ms, kind, phase, subject,
# wall, cpu, ai, test, tokens, model, unmeasured, id, branch, head. id comes from ZN_MEASURE_ID or the
# focus file; branch and head come from the environment (a detached HEAD leaves branch empty).
sub buffer {
    my ( $root, $t0, $kind, $phase, $subject ) = @_;
    return unless defined $root && $root ne '' && defined $t0 && $t0 ne '';
    my $wall = now() - $t0;
    $wall = 0 if $wall < 0;
    my ( $cu, $cs ) = ( times() )[ 2, 3 ];
    my $ms = int( ( $hires ? Time::HiRes::time() : time() ) * 1000 );
    my $id = $ENV{ZN_MEASURE_ID} // '';
    if ( $id eq '' ) {
        my $focus = "$root/.cache/tracker-focus";
        if ( open my $ff, '<', $focus ) {
            my $line = <$ff>;
            close $ff;
            if ( defined $line && $line =~ /(\S+)/ ) { $id = $1; }
        }
    }
    my $branch = $ENV{ZN_MEASURE_BRANCH} // '';
    $branch = '' if $branch eq 'HEAD';
    my $head   = $ENV{ZN_MEASURE_HEAD} // '';
    my $test   = ( defined $phase && $phase eq 'test' ) ? sprintf( '%.3f', $wall ) : '';
    my $record = join(
        "\t",
        $ms,               _field($kind), _field($phase), _field($subject),
        sprintf( '%.3f', $wall ), sprintf( '%.3f', $cu + $cs ), '', $test, '', '', 'tokens,ai',
        _field($id), _field($branch), _field($head),
    );
    append( $root, $record );
}

1;
