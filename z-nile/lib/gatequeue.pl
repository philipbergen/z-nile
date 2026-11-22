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
# ZN_GATE_WAIT seconds (default 1800; 0: fail at once), ZN_GATE_QUEUE_DIR the folder (specs). Empty means unset.
use strict;
use warnings;
use Fcntl qw(:flock O_RDWR O_CREAT);
use POSIX qw(strftime);

my $DEFAULT_WAIT = 1800;

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

sub describe {    # "pid P, checkout C, mode M, since T" from one description line, or '' when it is not believable
    my ($line) = @_;
    return '' unless defined $line;
    chomp $line;
    my %f = map { /^(\w+)=(.*)$/ ? ( $1, $2 ) : () } split /\t/, $line;
    return '' unless defined $f{pid} && $f{pid} =~ /^\d+$/ && kill( 0, $f{pid} ) || ( $! == 1 && defined $f{pid} );
    return "pid $f{pid}, checkout " . ( $f{checkout} // '?' ) . ', mode ' . ( $f{mode} // '?' ) . ', since ' . when( $f{since} // 0 );
}

sub holder_text {    # called only while the lock is held by someone else
    my $fh = open_file("$dir/lock");
    seek( $fh, 0, 0 );
    my $line = <$fh>;
    my $d    = describe($line);
    return $d eq '' ? 'holder unknown (it has not written who it is yet)' : $d;
}

sub waiters {    # the live waiters: a waiter file is flocked by its waiter, so one we can lock is a dead waiter's
    my @out;
    opendir( my $dh, "$dir/waiting" ) or return @out;
    for my $n ( sort grep { /^\d+$/ } readdir $dh ) {
        my $path = "$dir/waiting/$n";
        open( my $fh, '<', $path ) or next;
        if ( flock( $fh, LOCK_EX | LOCK_NB ) ) { unlink $path; next; }
        my $line = <$fh>;
        my $d    = describe($line);
        push @out, $d if $d ne '';
    }
    return @out;
}

if ($list) {
    my $fh = open_file("$dir/lock");
    if ( flock( $fh, LOCK_EX | LOCK_NB ) ) { print "no gate is running\n"; exit 0; }
    seek( $fh, 0, 0 );
    my $d = describe( scalar <$fh> );
    print 'running: ', ( $d eq '' ? 'holder unknown' : $d ), "\n";
    print "waiting: $_\n" for waiters();
    exit 0;
}

my $wait = $DEFAULT_WAIT;
$wait = $ENV{ZN_GATE_WAIT} if defined $ENV{ZN_GATE_WAIT} && $ENV{ZN_GATE_WAIT} =~ /^\d+$/;

my $lock = open_file("$dir/lock");
my $mine = join( "\t", "pid=$$", "checkout=$checkout", "mode=$mode", "since=" . time ) . "\n";
if ( !flock( $lock, LOCK_EX | LOCK_NB ) ) {
    my $who = holder_text();
    if ( $wait == 0 ) {
        print STDERR "gate: not started: another gate holds this machine ($who); ZN_GATE_WAIT=0 means do not wait\n";
        exit 1;
    }
    print STDERR "gate: waiting for another gate on this machine: $who\n";
    my $wpath = "$dir/waiting/$$";
    my $wfh   = open_file($wpath);
    flock( $wfh, LOCK_EX );
    truncate( $wfh, 0 );
    syswrite( $wfh, $mine );
    my $t0  = time;
    my $got = eval {
        local $SIG{ALRM} = sub { die "timeout\n" };
        alarm $wait;
        my $ok = flock( $lock, LOCK_EX );
        alarm 0;
        $ok;
    };
    alarm 0;
    unlink $wpath;
    if ( !$got ) {
        my $now = holder_text();
        print STDERR "gate: not started: gave up after " . ( time - $t0 ) . " s waiting for another gate on this machine ($now); ZN_GATE_WAIT=$wait\n";
        exit 1;
    }
    print STDERR 'gate: proceeding after waiting ' . ( time - $t0 ) . " s\n";
}
truncate( $lock, 0 );
syswrite( $lock, $mine );

my $pid = fork;
die "gate: fork: $!\n" unless defined $pid;
if ( $pid == 0 ) { exec { $cmd[0] } @cmd or do { print STDERR "gate: cannot run $cmd[0]: $!\n"; exit 127; }; }
for my $s (qw(INT TERM HUP)) { $SIG{$s} = sub { kill $s, $pid }; }
my $r;
for ( 1 .. 1000000 ) {    # EINTR from a forwarded signal retries; the child's end leaves the loop
    $r = waitpid( $pid, 0 );
    last if $r == $pid;
}
my $st = $?;
exit( $st & 127 ? 128 + ( $st & 127 ) : $st >> 8 );
