#!/usr/bin/perl
# d0426 step 2: the machine-wide gate queue. One lock per machine and user, shared by every checkout, worktree and
# repository, so two gates never run at once (each one adds to a macOS kernel leak and starves the other).
#   gatequeue.pl [--dir D] [--mode M] [--checkout C] -- <command> [args...]   wait for the lock, run the command under it
#   gatequeue.pl [--dir D] --list                                               who runs the gate, who waits
#   gatequeue.pl --print-dir                                                    the lock folder
# The lock is an exclusive flock on the open handle of <dir>/lock, held by this process while the command runs in a
# child (exec closes the handle: perl marks it close-on-exec), so the kernel frees it however this process ends.
# There is no lock file to clean. The holder writes who it is into the lock file only after it holds the lock, and a
# reader reads it only while the lock is held (its own try fails) and only believes a live pid.
# ZN_GATE_WAIT seconds (default 1800, at most a day; 0: fail at once), ZN_GATE_QUEUE_DIR the folder (specs), ZN_GATE_STILL
# the seconds between "still waiting" lines (default 60). Empty means unset.
# Exit codes: the command's (128+n for a signal); 75 not started (another gate held the machine: run it again);
# 123 the process that started this one is gone (the bounded runner's rule: while waiting it never runs the command,
# while holding it stops the command); 1 refused (a bad folder, waiting on its own ancestor); 2 usage.
use strict;
use warnings;
use Fcntl qw(:flock O_RDWR O_CREAT);
use POSIX qw(strftime WNOHANG);

my ( $DEFAULT_WAIT, $MAX_WAIT, $NOT_STARTED, $GONE ) = ( 1800, 86400, 75, 123 );
$SIG{CHLD} = 'DEFAULT';
my $STARTER = getppid();

sub default_dir { return ( $^O eq 'darwin' ? '/private/tmp' : '/tmp' ) . "/pickman-gate-queue-$<"; }

sub die_usage { print STDERR "gate: $_[0]\n"; exit 2; }

my ( $dir, $mode, $checkout, $list, $print ) = ( undef, 'unknown', undef, 0, 0 );
my @cmd;
while (@ARGV) {
    my $a = shift @ARGV;
    if    ( $a eq '--dir' )      { $dir      = shift @ARGV // die_usage('--dir needs a folder'); }
    elsif ( $a eq '--mode' )     { $mode     = shift @ARGV // die_usage('--mode needs a value'); }
    elsif ( $a eq '--checkout' ) { $checkout = shift @ARGV // die_usage('--checkout needs a path'); }
    elsif ( $a eq '--list' )      { $list  = 1; }
    elsif ( $a eq '--print-dir' ) { $print = 1; }
    elsif ( $a eq '--' )         { @cmd = @ARGV; @ARGV = (); }
    else                         { die_usage("unknown argument $a"); }
}
$dir = $ENV{ZN_GATE_QUEUE_DIR} if !defined $dir && defined $ENV{ZN_GATE_QUEUE_DIR} && $ENV{ZN_GATE_QUEUE_DIR} ne '';
$dir = default_dir() if !defined $dir || $dir eq '';
if ($print) { print "$dir\n"; exit 0; }
die_usage('no command (usage: gatequeue.pl [--dir D] [--mode M] [--checkout C] -- command...)') if !$list && !@cmd;
$checkout //= `pwd -P 2>/dev/null` // '';
chomp $checkout;

# The folder: a plain folder of this user, mode 0700, never a symlink.
sub prepare {
    for my $d ( $dir, "$dir/waiting" ) {
        if ( -l $d || ( -e $d && !-d $d ) ) { print STDERR "gate: $d is not a plain folder; refusing to queue\n"; exit 1; }
        if ( !-d $d ) {
            mkdir $d, 0700 or ( -d $d ) or do { print STDERR "gate: cannot make $d: $!\n"; exit 1; };
        }
        if ( ( stat $d )[4] != $< ) { print STDERR "gate: $d belongs to another user; refusing to queue\n"; exit 1; }
        chmod 0700, $d;
    }
}
prepare();

sub open_file {
    my ($path) = @_;
    sysopen( my $fh, $path, O_RDWR | O_CREAT, 0600 ) or do { print STDERR "gate: cannot open $path: $!\n"; exit 1; };
    return $fh;
}

sub when { return strftime( '%Y-%m-%d %H:%M:%S %Z', localtime( $_[0] ) ); }

sub describe {    # ("pid P, checkout C, mode M, since T", P) from one description line, or ('', 0) when it is not believable
    my ($line) = @_;
    return ( '', 0 ) unless defined $line;
    chomp $line;
    my %f = map { /^(\w+)=(.*)$/ ? ( $1, $2 ) : () } split /\t/, $line;
    return ( '', 0 ) unless defined $f{pid} && $f{pid} =~ /^\d+$/ && kill( 0, $f{pid} );    # never believed on EPERM
    return ( "pid $f{pid}, checkout " . ( $f{checkout} // '?' ) . ', mode ' . ( $f{mode} // '?' ) . ', since ' . when( $f{since} // 0 ), $f{pid} );
}

sub holder_info {    # (text, pid): called only while the lock is held by someone else
    my $fh = open_file("$dir/lock");
    seek( $fh, 0, 0 );
    my ( $d, $pid ) = describe( scalar <$fh> );
    return $d eq '' ? ( 'holder unknown (it has not written who it is yet)', 0 ) : ( $d, $pid );
}

sub waiters {    # the live waiters: a waiter file is flocked by its waiter, so one we can lock is a dead waiter's
    my @out;
    opendir( my $dh, "$dir/waiting" ) or return @out;
    for my $n ( sort grep { /^\d+$/ } readdir $dh ) {
        my $path = "$dir/waiting/$n";
        open( my $fh, '<', $path ) or next;
        if ( flock( $fh, LOCK_EX | LOCK_NB ) ) { unlink $path; next; }    # its waiter checks the file is still there
        my ($d) = describe( scalar <$fh> );
        push @out, $d if $d ne '';
    }
    return @out;
}

if ($list) {
    my $fh = open_file("$dir/lock");
    if ( flock( $fh, LOCK_EX | LOCK_NB ) ) { print "no gate is running\n"; exit 0; }
    seek( $fh, 0, 0 );
    my ($d) = describe( scalar <$fh> );
    print 'running: ', ( $d eq '' ? 'holder unknown' : $d ), "\n";
    print "waiting: $_\n" for waiters();
    exit 0;
}

sub is_ancestor {    # is $_[0] one of this process's ancestors? (at most 64 steps up)
    my ($want) = @_;
    return 1 if defined $ENV{ZN_GATE_HOLDER_PID} && $ENV{ZN_GATE_HOLDER_PID} eq $want;    # the holder tells its command
    my $p = $$;
    for ( 1 .. 64 ) {
        my $up = `ps -o ppid= -p $p 2>/dev/null`;
        return 0 unless defined $up && $up =~ /^\s*(\d+)\s*$/;
        $p = $1;
        return 0 if $p <= 1;
        return 1 if $p == $want;
    }
    return 0;
}

sub starter_gone { return getppid() != $STARTER; }

my $wait = $DEFAULT_WAIT;
$wait = $ENV{ZN_GATE_WAIT} if defined $ENV{ZN_GATE_WAIT} && $ENV{ZN_GATE_WAIT} =~ /^\d+$/;
$wait = $MAX_WAIT if $wait > $MAX_WAIT;
my $still = 60;
$still = $ENV{ZN_GATE_STILL} if defined $ENV{ZN_GATE_STILL} && $ENV{ZN_GATE_STILL} =~ /^[1-9]\d*$/;
print STDERR "gate: queue folder overridden: $dir\n" if $dir ne default_dir();

my ( $child, $wpath ) = ( 0, undef );
for my $sig (qw(INT TERM HUP)) {    # before the fork: a signal in between is never lost
    $SIG{$sig} = sub {
        if ($child) { kill $sig, $child; return; }
        unlink $wpath if defined $wpath;
        exit( 128 + ( $sig eq 'INT' ? 2 : $sig eq 'HUP' ? 1 : 15 ) );
    };
}

my $lock = open_file("$dir/lock");
my $mine = join( "\t", "pid=$$", "checkout=$checkout", "mode=$mode", "since=" . time ) . "\n";
if ( !flock( $lock, LOCK_EX | LOCK_NB ) ) {
    my ( $who, $holder ) = holder_info();
    if ( $holder && is_ancestor($holder) ) {
        print STDERR "gate: not started: the gate holding the machine ($who) is an ancestor of this one, so waiting would never end (a gate run by a gate must have ZN_MEASURED set)\n";
        exit 1;
    }
    if ( $wait == 0 ) {
        print STDERR "gate: not started: another gate holds this machine ($who); ZN_GATE_WAIT=0 means do not wait; run it again when it ends (./zn gate-queue shows who runs and who waits)\n";
        exit $NOT_STARTED;
    }
    print STDERR "gate: waiting for another gate on this machine: $who\n";
    $wpath = "$dir/waiting/$$";
    my $wfh;
    for ( 1 .. 3 ) {    # a lister may remove a file it finds unlocked between our create and our lock: make it again
        $wfh = open_file($wpath);
        flock( $wfh, LOCK_EX );
        my @a = stat $wfh;
        my @b = stat $wpath;
        last if @b && $a[1] == $b[1];
    }
    truncate( $wfh, 0 );
    syswrite( $wfh, $mine );
    my ( $t0, $last ) = ( time, time );
    my $got = 0;
    for ( 1 .. $MAX_WAIT + 1 ) {    # one-second slices: the parent and the bound are looked at between them
        if ( starter_gone() ) { unlink $wpath; print STDERR "gate: not started: the process that started it is gone\n"; exit $GONE; }
        my $left = $wait - ( time - $t0 );
        last if $left <= 0;
        $got = eval {
            local $SIG{ALRM} = sub { die "slice\n" };
            alarm 1;
            my $ok = flock( $lock, LOCK_EX );
            alarm 0;
            $ok;
        };
        alarm 0;
        last if $got;
        if ( time - $last >= $still ) {
            $last = time;
            my ($w) = holder_info();
            print STDERR 'gate: still waiting ' . ( time - $t0 ) . " s ($w)\n";
        }
    }
    unlink $wpath;
    if ( !$got ) {
        my ($now) = holder_info();
        print STDERR 'gate: not started: gave up after ' . ( time - $t0 ) . " s waiting for another gate on this machine ($now); ZN_GATE_WAIT=$wait; run it again when it ends (./zn gate-queue shows who runs and who waits)\n";
        exit $NOT_STARTED;
    }
    print STDERR 'gate: proceeding after waiting ' . ( time - $t0 ) . " s\n";
}
truncate( $lock, 0 );
syswrite( $lock, $mine );

$ENV{ZN_GATE_HOLDER_PID} = $$;    # the command (and what it starts) can tell it is inside the holder
my $pid = fork;
die "gate: fork: $!\n" unless defined $pid;
if ( $pid == 0 ) { exec { $cmd[0] } @cmd or do { print STDERR "gate: cannot run $cmd[0]: $!\n"; exit 127; }; }
$child = $pid;
my $r = 0;
for ( 1 .. 100_000_000 ) {    # every fifth of a second: the command's end, or the starter's death (stop the command)
    $r = waitpid( $pid, WNOHANG );
    last if $r == $pid || $r < 0;
    if ( starter_gone() ) {
        kill 'TERM', $pid;
        for ( 1 .. 50 ) {    # ten seconds to end, then KILL
            $r = waitpid( $pid, WNOHANG );
            last if $r == $pid || $r < 0;
            select( undef, undef, undef, 0.2 );
        }
        if ( $r != $pid ) { kill 'KILL', $pid; waitpid( $pid, 0 ); }
        print STDERR "gate: the process that started it is gone: the command was stopped\n";
        exit $GONE;
    }
    select( undef, undef, undef, 0.2 );
}
my $st = $?;
exit( $st & 127 ? 128 + ( $st & 127 ) : $st >> 8 );
