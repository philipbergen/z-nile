#!/usr/bin/env bash
# The prep's mutation check: in the prototype clone $1 (a clone under $TMPDIR with the prototype applied), apply each
# mutant to fence.SWEEPER (a literal text replaced, refused unless it occurs exactly once), read the change back, run
# the acceptance spec, print the failing cases and their messages, and restore the prototype.
# Run: ./zn run --time 600 -- bash mutants.sh <clone>   (about 3 minutes)
set -u
P=$1; F=$P/z-nile/tests/lib/fence.luau; cp "$F" "$F.proto"
mutate() { # mutate <name> <literal> <replacement>
  local name=$1 out
  cp "$F.proto" "$F"
  FROM=$2 TO=$3 perl -0pi -e 'my ($f, $t) = @ENV{qw(FROM TO)}; my $n = () = /\Q$f\E/g; die "matches $n times\n" unless $n == 1; s/\Q$f\E/$t/' "$F" \
    || { echo "== $name: not applied"; return; }
  grep -qF -- "$3" "$F" || { echo "== $name: read-back failed"; return; }
  out=$(cd "$P/z-nile" && lune run tests/run -- .tracker/issues/c0225/acceptance/sweep-settle.spec.luau 2>&1)
  echo "== $name: $(grep -E '^[0-9]+ passed' <<<"$out")"
  grep -E '^FAIL' <<<"$out" | sed 's/^/   /'
  grep -E 'expected|does not say' <<<"$out" | sed 's/^.*spec:/     spec:/' | sort | uniq -c | head -8
}
mutate "M1 ends on the first empty scan" '++$quiet >= 5' '++$quiet >= 1'
mutate "M2 ends on the fourth empty scan" '++$quiet >= 5' '++$quiet >= 4'
mutate "M3 ends on the sixth empty scan" '++$quiet >= 5' '++$quiet >= 6'
mutate "M4 a stopping scan does not restart the count" '"$quiet = 0; kill' '"kill'
mutate "M5 no pause between empty scans" '"select(undef, undef, undef, 0.05); next }"' '"next }"'
mutate "M6 the seam takes any number in an entry" '/^([1-9]\\d*)(?:@([1-9]\\d*))?$/;' '/(\\d+)(?:@(\\d+))?/;'
mutate "M7 the seam ignores @n" '$from{0 + $1} = 0 + ($2 // 1)' '$from{0 + $1} = 1'
mutate "M8 hidden pids are candidates from the first scan" 'if ($later{$_} <= $scan)' 'if (1)'
mutate "M9 a 10 ms pause after an empty scan" '"select(undef, undef, undef, 0.05); next }"' '"select(undef, undef, undef, 0.01); next }"'
# M10 (the limit of 50 counts every scan) is only seen by check.sh's real run (AC9): see mutants-result.txt
cp "$F.proto" "$F"; rm -f "$F.proto"
