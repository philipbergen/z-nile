#!/usr/bin/env bash
# E2: does the sweeper (Perl file $1) leave a detached, exec-looping leftover running? $2 sweeps, each in a fresh jail
# with the runner's profile (writes only under $3), the sweep narrowed to the looper through the seam. $4 (default
# 0.2) is how long the swept command waits after starting the looper; $5 = file makes the looper re-exec a script
# file ($0, as c0168 review 002's looper did) instead of `perl -e`.
# Prints one line per sweep that left the looper alive, then a total. The looper stops by itself after 20 s.
set -u
SW=$1; N=$2; DIR=$(cd "$3" && pwd -P); WAIT=${4:-0.2}; MODE=${5:-e}; OUT=$$
P="(version 1)(allow default)(deny network-outbound (remote ip))(allow network-outbound (remote ip \"localhost:*\"))"
P+="(deny file-write* (subpath \"/\"))(allow file-write* (subpath \"/dev\"))(allow file-write* (subpath \"$DIR\"))"
P+="(deny signal (with no-log))(allow signal (target same-sandbox))"
LOOP='use Time::HiRes qw(time); exec $^X, "-e", $ARGV[0], @ARGV if time < $ARGV[1]; exit'
printf '%s\n' 'use Time::HiRes qw(time); exec $^X, $0, @ARGV if time < $ARGV[0]; exit' > "$DIR/looper.pl"
if [[ $MODE == file ]]; then RUN="exec \$^X, \"$DIR/looper.pl\", time + 20"; else RUN='exec $^X, "-e", $ARGV[1], $ARGV[1], time + 20'; fi
START='perl -e '"'"'exit if fork; setpgrp(0, 0); exit if fork; open my $f, ">", $ARGV[0] or die; print $f "$$\n"; close $f;
open STDOUT, ">", "/dev/null"; open STDERR, ">&STDOUT"; use Time::HiRes qw(time); '"$RUN"''"'"' "$1" "$2"; sleep '"$WAIT"
left=0
for i in $(seq 1 "$N"); do
  only="$DIR/only-$$-$i"; : > "$only"
  err=$(sandbox-exec -p "$P" env PICKMAN_TEST_JAIL=sandbox-exec PICKMAN_SWEEP_ONLY="$only" \
    perl -e "$(cat "$SW")" "$OUT" sh -c "$START" _ "$only" "$LOOP" 2>&1)
  pid=$(cat "$only"); echo "said: ${err:-nothing}" >> "$DIR/said-$$.log"
  sleep 0.1
  if kill -0 "$pid" 2>/dev/null; then left=$((left + 1)); echo "sweep $i: looper $pid left running; sweeper said: ${err:-nothing}"; kill -KILL "$pid"; fi
  rm -f "$only"
done
echo "left running: $left of $N (wait $WAIT, mode $MODE)"
