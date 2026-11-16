#!/usr/bin/env bash
# E4: what an unseamed sweep of a clean run costs (every pid 2..99999, nothing left), for the sweeper texts given, in
# the launcher form, each run $N times in a fresh jail with the runner's signal rules. Prints wall seconds per run
# (median, max) and the CPU the sweeper used (user+sys, summed over the runs).
# Run: ./zn run --time 300 -- experiments/E4-sweep-cost.sh 20 <old.pl> <new.pl>
set -u
N=$1; shift
P="(version 1)(allow default)(deny signal (with no-log))(allow signal (target same-sandbox))"
for SW in "$@"; do
  perl -MTime::HiRes=time -e '
    my ($n, $p, $sw) = @ARGV; open my $h, "<", $sw or die; local $/; my $code = <$h>; my @w;
    my ($u0, $s0) = (times)[2, 3];
    for (1 .. $n) { my $t = time; system("sandbox-exec", "-p", $p, "perl", "-e", $code, "-", "sh", "-c", "exit 0") == 0 or die "sweep failed: $?"; push @w, time - $t }
    my ($u1, $s1) = (times)[2, 3]; @w = sort { $a <=> $b } @w;
    printf "%s: wall median %.3f s, max %.3f s; cpu %.3f s per run\n", $sw, $w[$#w / 2], $w[-1], ($u1 - $u0 + $s1 - $s0) / $n;
  ' "$N" "$P" "$SW"
done
