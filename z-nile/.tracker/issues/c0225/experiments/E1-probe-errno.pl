# E1: inside a jail with the runner's signal rules, what does kill 0 answer for a live process of the same sandbox
# that re-execs itself in a loop (no pause between execs), and how long does one full scan of pids 2..99999 take?
# Run: ./zn run --time 120 -- sandbox-exec -p '<profile>' perl E1-probe-errno.pl <samples>
use strict; use warnings; use Errno; use Time::HiRes qw(time sleep);
my $n = shift // 2000;
pipe(my $r, my $w) or die;
my $p = fork // die;
if ($p == 0) { # detach: a grandchild in its own session that re-execs itself while it is an orphan of launchd
  close $r; exit if fork; setpgrp(0, 0);
  print $w "$$\n"; close $w;
  open STDOUT, '>', '/dev/null'; open STDERR, '>&STDOUT';
  my $code = 'exec $^X, "-e", $ARGV[0], $ARGV[0] if getppid() == 1; exit';
  exec $^X, '-e', $code, $code;
}
close $w; my $pid = <$r>; chomp $pid; waitpid($p, 0);
my (%seen, $t0);
for (1 .. $n) { my $ok = kill(0, $pid); my $e = $ok ? 'answered' : $!{EPERM} ? 'EPERM' : $!{ESRCH} ? 'ESRCH' : "errno " . ($!+0);
  $seen{$e}++; sleep(0.0005 + rand(0.002)); }
printf "looper %d: %s\n", $pid, join(', ', map { "$_ $seen{$_}" } sort keys %seen);
$t0 = time; my $c = grep { kill(0, $_) } 2 .. 99999; printf "full scan: %.1f ms, %d answered\n", 1000 * (time - $t0), $c;
kill 'KILL', $pid; sleep 0.1; printf "looper after KILL answers: %d\n", kill(0, $pid) ? 1 : 0;
