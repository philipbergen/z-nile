#!/usr/bin/perl
# The bounded runner (c0191): `./zn run [--time S] [--cpu S] [--] <command> [args...]` runs one command so that it
# cannot outlive its limits, its caller or its parent. See z-nile/skills/zz-test/SKILL.md, "Bounded commands".
#   --time S  wall-clock limit in seconds (default 60, at most 3600)
#   --cpu S   CPU-time limit per process in seconds (`ulimit -t`, inherited by every child; default: --time). It only ever
#             lowers the limit the caller already has: a caller under a lower one keeps it (a limit cannot be raised again)
# The command runs in a process group of its own. A watchdog in that group waits on a pipe only this process holds
# open, so if this process dies, however it died, the watchdog stops the group. On the wall-clock limit, on INT, TERM
# or HUP, or when the process that started the runner is gone, the group gets TERM, and KILL two seconds later; when the
# command ends, whatever is left in the group is killed. Exit status: the command's (128+n for a signal); 124 wall-clock limit; 125 CPU limit; 123 the process that started the runner is gone;
# 2 refused usage.
# Every process of the command carries ZN_BOUNDED_DEADLINE (epoch seconds) for `./zn reap`.
use strict;
use warnings;
use Config;
use Cwd qw(abs_path);
use File::Basename qw(dirname);
use POSIX ':sys_wait_h';

my ( $DEFAULT_TIME, $MAX_TIME, $GRACE ) = ( 60, 3600, 2 );
my $LIB = dirname( abs_path($0) );    # z-nile/lib: cpu.sh, the one place a CPU limit is lowered
$SIG{CHLD} = 'DEFAULT';               # an ignored SIGCHLD (inherited) would make every waitpid fail

sub usage {
    print STDERR "bounded: $_[0]\nusage: ./zn run [--time S] [--cpu S] [--report FILE] [--] <command> [args...]"
      . " (S: whole seconds, --time 1..$MAX_TIME, default $DEFAULT_TIME)\n";
    exit 2;
}

-d $LIB && -f "$LIB/cpu.sh"
  or do { print STDERR "bounded: $LIB/cpu.sh is missing: bounded.pl needs it beside it (the one place a CPU limit is lowered)\n"; exit 2 };
my ( $time, $cpu, $report );
while ( @ARGV && $ARGV[0] =~ /^-/ ) {
    my $o = shift @ARGV;
    last if $o eq '--';
    if ( $o eq '--report' ) {
        my $path = shift @ARGV;
        usage("--report needs a path") unless defined $path && $path ne '';
        usage("--report given twice")  if defined $report;
        $report = $path;
        next;
    }
    usage("unknown option $o") unless $o eq '--time' || $o eq '--cpu';
    my $v = shift @ARGV;
    usage("$o needs a whole number of seconds") unless defined $v && $v =~ /^[0-9]+$/;
    if ( $o eq '--time' ) {
        usage("--time must be 1..$MAX_TIME seconds (got $v)") unless $v >= 1 && $v <= $MAX_TIME;
        usage("--time given twice") if defined $time;
        $time = $v;
    }
    else {
        usage("--cpu must be 1..$MAX_TIME seconds (got $v)") unless $v >= 1 && $v <= $MAX_TIME;
        usage("--cpu given twice") if defined $cpu;
        $cpu = $v;
    }
}
usage("no command given") unless @ARGV;
$time //= $DEFAULT_TIME;
$cpu  //= $time;

# a limit already in force can only be lowered: the effective one is the smaller, and it is said when it is the caller's
chomp( my $inherited = `sh -c 'ulimit -t'` );
my $effective = $cpu;
if ( $inherited =~ /^[0-9]+\z/ && $inherited < $cpu ) {
    $effective = $inherited;
    print STDERR "bounded: the caller's CPU limit of $inherited s is lower than --cpu $cpu: it stays\n";
}

my $origppid = getppid();    # the process that started this one: its death stops the command too
my $deadline = time + $time;
require "$LIB/measure.pl";
# `./zn run` records itself when nothing else is already measuring this process (the gate sets ZN_MEASURED).
if ( $ENV{ZN_RUN_RECORD} && !$ENV{ZN_MEASURED} && !defined $report ) {
    my $dir = $ENV{TMPDIR} // '/tmp';
    $report = "$dir/zn-run-$$.txt";
}
my $t0 = znmeasure::now();
pipe( my $r, my $w ) or die "bounded: pipe: $!\n";
my $pid = fork;
die "bounded: fork: $!\n" unless defined $pid;
if ( $pid == 0 ) {
    setpgrp( 0, 0 );
    my $wd = fork;
    die "bounded: fork: $!\n" unless defined $wd;
    if ( $wd == 0 ) {

        # the watchdog: a member of the command's group, ignoring the signals forwarded to it; it waits for end of
        # file on the pipe (this process is gone), or for the deadline plus the grace plus one (this process is stuck)
        close $w;
        $SIG{$_} = 'IGNORE' for qw(INT TERM HUP);
        open STDIN,  '<', '/dev/null';
        open STDOUT, '>', '/dev/null';
        open STDERR, '>', '/dev/null';
        my $left = $deadline + $GRACE + 1 - time;
        $left = 0 if $left < 0;
        my $rin = '';
        vec( $rin, fileno($r), 1 ) = 1;
        select( my $rout = $rin, undef, undef, $left );
        kill 'TERM', -getpgrp();
        select( undef, undef, undef, $GRACE );
        kill 'KILL', -getpgrp();
        exit 0;
    }

    # the command holds neither end of the pipe, so it can't keep the watchdog waiting
    close $r;
    close $w;
    $ENV{ZN_BOUNDED_DEADLINE} = $deadline;
    exec { 'sh' } 'sh', '-c', '. "$1" && zn_lower_cpu "$2" || exit 126; shift 2; exec "$@"', 'sh', "$LIB/cpu.sh", $cpu, @ARGV
      or die "bounded: exec: $!\n";
}
close $r;
setpgrp( $pid, $pid );    # also set by the child: whichever runs first wins, so neither races the other

# The wait: the command's end, the wall-clock limit, a signal to this runner, or the death of the runner's own parent
# (the shell or session that started it) - whichever comes first. Polled every fifth of a second rather than blocked
# in waitpid, because a parent's death sends no signal.
my ( $timedout, $signalled, $orphaned ) = ( 0, 0, 0 );
my ( $stopping, $killed ) = ( 0, 0 );
my $stop = sub { $stopping ||= time; kill 'TERM', -$pid };
for my $s (qw(INT TERM HUP)) {
    $SIG{$s} = sub {
        $signalled = $s eq 'INT' ? 2 : $s eq 'HUP' ? 1 : 15;
        $stop->();
    };
}
my $got;
while (1) {
    $got = waitpid( $pid, WNOHANG );
    last if $got == $pid || $got == -1;
    if ( !$stopping ) {
        if ( time >= $deadline ) { $timedout = 1; $stop->() }
        elsif ( getppid() != $origppid ) { $orphaned = 1; $stop->() }
    }
    if ( $stopping && !$killed && time - $stopping >= $GRACE ) { kill 'KILL', -$pid; $killed = 1 }
    select( undef, undef, undef, 0.2 );
}
my $st = $?;
my ( $cu, $cs ) = ( times )[ 2, 3 ];
znmeasure::write( $report, $t0 );
if ( $ENV{ZN_RUN_RECORD} && !$ENV{ZN_MEASURED} && defined $report && ( $ENV{ZN_TOP} // '' ) ne '' ) {
    system( 'lune', 'run', 'z-nile/record', '--', '--phase', 'other', '--report', $report, '--subject', 'run' );
}

# whatever is left in the group, the watchdog included
kill 'KILL', -$pid;
my $code = $st & 127 ? 128 + ( $st & 127 ) : $st >> 8;
if ($signalled) { exit 128 + $signalled }
if ($orphaned) {
    print STDERR "bounded: the process that started it is gone: stopped: $ARGV[0]\n";
    exit 123;
}
if ($timedout) {
    print STDERR "bounded: stopped at the wall-clock limit (--time $time s): $ARGV[0]\n";
    exit 124;
}

# CPU limit: the kernel's SIGXCPU ends the process (status 128+24), and the Rokit shim turns that into a plain exit 1, so a
# command is said to have been stopped by the limit only when it ended in one of those two ways having used 90% or more
# of the allowance; any other status is the command's own, with a note when it came close (`times` sums the CPU of every
# child, while the limit is per process)
my ( @names, @nums, %signo ) = ( split( ' ', $Config{sig_name} ), split( ' ', $Config{sig_num} ) );
@signo{@names} = @nums;
my $xcpu = 128 + ( $signo{XCPU} // 24 );
if ( $code != 0 && $cu + $cs >= 0.9 * $effective ) {
    if ( $code == 1 || $code == $xcpu ) {
        printf STDERR "bounded: stopped at the CPU limit (--cpu %d s, used %.1f s): %s\n", $effective, $cu + $cs, $ARGV[0];
        exit 125;
    }
    printf STDERR "bounded: note: the command and its children used %.1f s of CPU (limit %d s per process)\n", $cu + $cs, $effective;
}
exit $code;
