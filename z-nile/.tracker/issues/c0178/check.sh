#!/usr/bin/env bash
# Acceptance checks for c0178 (redesign of 2026-11-24). SEQUESTERED once the design is reviewed: never edit during execution.
# One `check "ACn: ..."` per Checked acceptance criterion, in the order of the issue document.
#
# Every number below is derived in the document (Acceptance criteria, "Where the numbers come from"). A criterion that cannot be
# measured on this host FAILS with `not measurable on <host>: run on macOS`: z-nile/lib/ac.sh has no skip state, and its other
# outcome (exit 75) means "the gate did not start", so a failure is the only honest outcome. The criteria that run anywhere
# (AC1, AC4) run everywhere.
HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd -P)" # physical: tests/run strips the physical cwd
source "$(git -C "$HERE" rev-parse --show-toplevel)/z-nile/lib/ac.sh" # cds to the item's project home
# sequestered specs: here before `./zn done`, promoted to its project's tests/acceptance/c0178 after it
A="$HERE/acceptance"
[[ -d $A ]] || A="$PWD/tests/acceptance/c0178"

# Work outside `check` is limited to running a spec through `tests/run` (which AC_LIST=1 list mode refuses),
# `./zn members` and other cheap reads; everything else goes inside `check`.
METER="scripts/fsevents-meter.sh"
BASE=5e8f5eaa4               # origin/main when this design was measured: the "before" of AC3's comparison
W="$PWD/.cache/c0178-check"  # this file's work folder (a name only; each check makes and removes what it uses)
# AC2's limits: the steady-state (second) run of each heavy spec file, measured with the simulation (E5) times 1.15
LIGHT_MAX=59100   # tests/tooling/light-path.spec.luau: today 225,599, the simulation 51,305
MODELS_MAX=50100  # tests/tooling/models-dispatch.spec.luau: today 112,318, the simulation 43,500
LAND_MAX=39200    # tests/acceptance/f0399/land.spec.luau: today 81,361, the simulation 34,024
# AC3's limit: one full fast-tier z-nile suite (99.9% of a full gate's events, c0179 AC5), derived in the document
SUITE_MAX=990000  # today 1,927,831 under z-nile/.cache in one full gate
# AC6's limit: light-path's run on the per-run volume (creates only, no removals: E7 measured 23,744)
LIGHT_VOLUME_MAX=27400

not_measurable() { echo "not measurable on $(uname -s): run on macOS"; return 1; }
events_of() { awk -F'\t' '$1 == "events" { print $2; exit }'; }
status_of() { awk -F'\t' '$1 == "status" { print $2; exit }'; }
kzone() { zprint 2>/dev/null | awk '$1 == "data.kalloc.1024" { print $7 }'; }
mounts() { mount; hdiutil info 2>&1; }

# One spec file from this home, under the meter over the home's .cache, twice: the first run leaves the spec's fixtures (or
# removes an earlier run's), the second is the steady state a gate sees, and the one whose events count. Prints
# "<events> <passed> <failed>" of the second run.
steady() { # <spec> [env...]
  local spec=$1 out1 out2 rc
  shift
  out1="$("$ZN_ROOT/zn" run --time 900 -- env "$@" lune run tests/run -- "$spec" 2>&1)" || { printf '%s\n' "$out1" | tail -20; return 1; }
  out2="$("$ZN_ROOT/zn" run --time 900 -- $METER --no-idle --limit 850 --root "$PWD/.cache" -- env "$@" lune run tests/run -- "$spec" 2>&1)"
  rc=$?
  [[ $rc == 0 && "$(printf '%s\n' "$out2" | status_of)" == 0 ]] || { printf '%s\n' "$out2" | tail -20; return 1; }
  printf '%s %s %s\n' "$(printf '%s\n' "$out2" | events_of)" \
    "$(printf '%s\n' "$out2" | sed -n 's/^\([0-9]*\) passed, \([0-9]*\) failed.*/\1/p' | tail -1)" \
    "$(printf '%s\n' "$out2" | sed -n 's/^\([0-9]*\) passed, \([0-9]*\) failed.*/\2/p' | tail -1)"
}

# --- AC1: the template and the clone (slice 1), on every host ---------------------------------------------------------------
check "AC1: trackerfix.new clones this run's packed template (a copy where cloning is refused) into a fixture that holds what a build holds, no file of it names the template, the rewrite list is exactly the template's path-naming files, a template is never shared across runs or kept after a tooling change, and a changed template refuses the next clone" \
  lune run tests/run -- "$A/template.spec.luau"

# --- AC2: the three heavy spec files, steady state, on macOS ----------------------------------------------------------------------
ac2_heavy() {
  [[ "$(uname -s)" == Darwin ]] || { not_measurable; return 1; }
  local spec max min line ev passed failed bad=0
  echo "load: $(sysctl -n vm.loadavg 2>/dev/null)"
  for line in "tests/tooling/light-path.spec.luau $LIGHT_MAX 23" "tests/tooling/models-dispatch.spec.luau $MODELS_MAX 22" \
    "tests/acceptance/f0399/land.spec.luau $LAND_MAX 18"; do
    read -r spec max min <<< "$line"
    read -r ev passed failed <<< "$(steady "$spec")" || { echo "FAIL: $spec did not run"; bad=1; continue; }
    echo "$spec: $ev events (limit $max), $passed passed, $failed failed (at least $min passed at $BASE)"
    [[ -n $ev && $ev -le $max && $failed == 0 && ${passed:-0} -ge $min ]] || bad=1
  done
  [[ $bad == 0 ]]
}
check "AC2: the steady-state run of light-path, models-dispatch and f0399/land makes at most 59,100, 50,100 and 39,200 file events under the home's .cache (225,599, 112,318 and 81,361 today), no case failing and at least as many passing as at the base" ac2_heavy

# --- AC3: one full fast-tier suite, base against head, interleaved (opt-in: it runs four suites) -----------------------------------
# The base is a clone of the repository at $BASE under this file's work folder (its own home, .cache, lock and jail); its origin is
# pointed at a missing folder, so nothing it runs can reach the real repository. Each round runs base then head, each suite under the
# meter over its own home's .cache, with its CPU-seconds (children included), the kernel zone before and after, and its results file.
suite() { # <home> <results file> [env...] -> "<events> <cpu-seconds> <kzone delta> <status>"
  local home=$1 res=$2 k0 k1 out
  shift 2
  k0="$(kzone)"
  out="$(cd "$home" && "$ZN_ROOT/zn" run --time 3500 -- perl -e 'my $p = fork(); if (!$p) { exec @ARGV or exit 127 } waitpid($p, 0); my $s = $? >> 8; my @t = times; printf STDERR "cpu-seconds\t%.1f\n", $t[2] + $t[3]; exit $s' \
    "$ZN_ROOT/$METER" --no-idle --limit 3400 --root "$home/.cache" -- env PICKMAN_RESULTS="$res" "$@" lune run tests/run 2>&1)"
  k1="$(kzone)"
  printf '%s %s %s %s\n' "$(printf '%s\n' "$out" | events_of)" "$(printf '%s\n' "$out" | awk -F'\t' '$1 == "cpu-seconds" { print $2 }')" \
    "$((k1 - k0))" "$(printf '%s\n' "$out" | status_of)"
}
passed_cases() { # <results json> -> sorted "file :: case" lines that passed
  perl -MJSON::PP -e 'local $/; my $d = decode_json(<STDIN>); for my $f (@{$d->{files}}) { for my $c (@{$f->{cases}}) { print "$f->{file} :: $c->{name}\n" if $c->{ok} } }' < "$1" | LC_ALL=C sort -u
}
ac3_suite() {
  [[ "$(uname -s)" == Darwin ]] || { not_measurable; return 1; }
  if [[ ${C0178_FULL:-} != 1 ]]; then
    echo "not measured: this runs four full suites (about 40 minutes); set C0178_FULL=1 (the lead runs it once, at the merge)"
    return 1
  fi
  local b="$W/base" r ev cpu kz st bad=0 hcpu=() bcpu=() hk=() bk=() hev=""
  rm -rf "$W" && mkdir -p "$W" || return 1
  git clone -q --no-hardlinks "$ZN_ROOT" "$b" && git -C "$b" checkout -q "$BASE" && git -C "$b" remote set-url origin "$W/no-origin" &&
    mkdir -p "$b/z-nile/.cache" || return 1
  for r in 1 2; do
    read -r ev cpu kz st <<< "$(suite "$b/z-nile" "$b/z-nile/.cache/c0178-results-$r.json")"
    echo "round $r base: $ev events, $cpu CPU-seconds, kernel zone $kz, status $st"; bcpu+=("$cpu"); bk+=("$kz")
    cp "$b/z-nile/.cache/c0178-results-$r.json" "$W/base-$r.json" 2>/dev/null
    read -r ev cpu kz st <<< "$(suite "$PWD" "$PWD/.cache/c0178-results-$r.json" PICKMAN_FIXTURE_VOLUME=1)"
    echo "round $r head: $ev events, $cpu CPU-seconds, kernel zone $kz, status $st"; hcpu+=("$cpu"); hk+=("$kz")
    mv "$PWD/.cache/c0178-results-$r.json" "$W/head-$r.json" 2>/dev/null
    [[ $st == 0 ]] || { echo "FAIL: the head suite failed in round $r"; bad=1; }
    hev="$hev $ev"
  done
  for ev in $hev; do [[ -n $ev && $ev -le $SUITE_MAX ]] || { echo "FAIL: $ev events above $SUITE_MAX"; bad=1; }; done
  # no test lost: every case that passed at the base (in either round) passes at head (in both)
  local lost
  lost="$(LC_ALL=C comm -23 <(cat <(passed_cases "$W/base-1.json") <(passed_cases "$W/base-2.json") | LC_ALL=C sort -u) \
    <(LC_ALL=C comm -12 <(passed_cases "$W/head-1.json") <(passed_cases "$W/head-2.json")))"
  [[ -z $lost ]] || { echo "FAIL: cases that passed at $BASE and not at head:"; printf '%s\n' "$lost" | head -20; bad=1; }
  # not slower: the head's CPU-seconds are not above the base's (the larger of each side's two rounds against the smaller)
  perl -e 'my ($b1,$b2,$h1,$h2) = @ARGV; my $b = $b1 < $b2 ? $b1 : $b2; my $h = $h1 > $h2 ? $h1 : $h2; printf "CPU: head %.1f against base %.1f\n", $h, $b; exit($h <= $b ? 0 : 1)' \
    "${bcpu[0]}" "${bcpu[1]}" "${hcpu[0]}" "${hcpu[1]}" || { echo "FAIL: the head suite costs more CPU than the base's"; bad=1; }
  # the kernel zone: the head's rise per suite no more than the base's plus the noise other sessions make (4,580, c0179 E6)
  perl -e 'my ($b1,$b2,$h1,$h2) = @ARGV; my $b = ($b1 + $b2) / 2; my $h = ($h1 + $h2) / 2; printf "kernel zone per suite: head %.0f, base %.0f\n", $h, $b; exit($h <= $b + 4580 ? 0 : 1)' \
    "${bk[0]}" "${bk[1]}" "${hk[0]}" "${hk[1]}" || { echo "FAIL: the kernel zone rose more per suite at head"; bad=1; }
  rm -rf "$W"
  [[ $bad == 0 ]]
}
check "AC3: one full fast-tier z-nile suite (the head's asking for a volume) makes at most 990,000 file events under its home's .cache (1,927,831 today), every case that passed at the base passes, it costs no more CPU-seconds than the base's, and its kernel-zone rise is no more than the base's plus 4,580 (two interleaved rounds; C0178_FULL=1)" ac3_suite

# --- AC4: without the gate asking for a volume, a run makes none and says nothing of one, on every host ------------------------------
ac4_no_volume() {
  local before after out
  before="$(mount)"
  out="$("$ZN_ROOT/zn" run --time 300 -- env -u PICKMAN_FIXTURE_VOLUME lune run tests/run -- tests/tooling/board.spec.luau 2>&1)" || { printf '%s\n' "$out" | tail -20; return 1; }
  after="$(mount)"
  printf '%s\n' "$out" | tail -1
  [[ "$before" == "$after" ]] || { echo "FAIL: the mounts changed"; return 1; }
  ! printf '%s\n' "$out" | grep -q '^fixtures: volume'
}
check "AC4: a run the gate did not ask for a volume (every run off macOS, every run by hand) makes no volume, says nothing of one, and keeps its fixtures on the home's disk as today" ac4_no_volume

# --- AC5: the per-run volume's decisions (slice 3), on every host ---------------------------------------------------------------
check "AC5: only a fixture volume of this home whose owner is dead is detached at a start, never a live run's, another program's or a real disk's, and a run uses a volume only on macOS, as the outermost run, when the gate asked for one" \
  lune run tests/run -- "$A/volume.spec.luau"

# --- AC6: a gate-driven run on the per-run volume (slice 3), on macOS -------------------------------------------------------------
ac6_volume_run() {
  [[ "$(uname -s)" == Darwin ]] || { not_measurable; return 1; }
  local before after out ev res="$PWD/.cache/c0178-results.json" names_before names_after bad=0
  rm -f "$res"; mkdir -p "$PWD/.cache"
  before="$(mounts)"; names_before="$(ls -A "$PWD/.cache" | grep -v '^c0178-results\|^spec-durations.tsv$' | LC_ALL=C sort)"; touch "$W.stamp"
  out="$("$ZN_ROOT/zn" run --time 900 -- $METER --no-idle --limit 850 --root "$PWD/.cache" -- \
    env PICKMAN_FIXTURE_VOLUME=1 PICKMAN_RESULTS="$res" lune run tests/run -- tests/tooling/light-path.spec.luau 2>&1)"
  after="$(mounts)"; names_after="$(ls -A "$PWD/.cache" | grep -v '^c0178-results\|^spec-durations.tsv$' | LC_ALL=C sort)"
  ev="$(printf '%s\n' "$out" | events_of)"
  printf '%s\n' "$out" | grep -E '^fixtures: |passed, ' | tail -3
  echo "events: $ev (limit $LIGHT_VOLUME_MAX)"
  [[ "$(printf '%s\n' "$out" | status_of)" == 0 ]] || { echo "FAIL: the run failed"; bad=1; }
  printf '%s\n' "$out" | grep -q '^fixtures: volume ' || { echo "FAIL: the run did not say it used a volume"; bad=1; }
  [[ -n $ev && $ev -le $LIGHT_VOLUME_MAX ]] || { echo "FAIL: events above the limit"; bad=1; }
  [[ "$before" == "$after" ]] || { echo "FAIL: mount or hdiutil info changed"; bad=1; }
  [[ "$names_before" == "$names_after" ]] || { echo "FAIL: the home's .cache gained or lost entries: $(diff <(printf '%s\n' "$names_before") <(printf '%s\n' "$names_after") | tr '\n' ' ')"; bad=1; }
  [[ -s $res ]] || { echo "FAIL: the results file the orchestrator reads was not carried out of the volume"; bad=1; }
  [[ "$PWD/.cache/spec-durations.tsv" -nt "$W.stamp" ]] || { echo "FAIL: the run's durations were not carried out of the volume"; bad=1; }
  rm -f "$res" "$W.stamp"
  [[ $bad == 0 ]]
}
check "AC6: a run on the per-run volume makes at most 27,400 file events for light-path, says so, carries the results file and the durations out, and leaves mount, hdiutil info and the home's .cache as they were" ac6_volume_run

# --- AC7: a killed run's volume is found and detached by the next run, and nothing else is (slice 3), on macOS ---------------------
descendant_runner() { # <pid>: the first descendant whose command is the spec runner
  ps -axo pid=,ppid=,command= | perl -e 'my $root = shift; my (%kids, %cmd); while (<STDIN>) { my ($p, $pp, $c) = /^\s*(\d+)\s+(\d+)\s+(.*)$/ or next; push @{$kids{$pp}}, $p; $cmd{$p} = $c }
    my @q = ($root); while (@q) { my $p = shift @q; for my $k (@{$kids{$p} || []}) { if ($cmd{$k} =~ /lune run tests.run /) { print "$k\n"; exit 0 } push @q, $k } } exit 1' "$1"
}
ac7_killed() {
  [[ "$(uname -s)" == Darwin ]] || { not_measurable; return 1; }
  local before after pid i dev decoy="" vol out bad=0
  before="$(mounts)"
  mkdir -p "$W/decoy" || return 1
  # a RAM disk that is not ours, mounted inside the home's .cache: the next run must leave it alone
  decoy="$(hdiutil attach -nomount ram://65536 | awk '{ print $1; exit }')" && newfs_apfs -v c0178-decoy "$decoy" > /dev/null &&
    vol="$(diskutil list | awk -v d="${decoy#/dev/}" '/^\/dev\/disk[0-9]+ \(synthesized\)/ { c = $1 } /Physical Store/ && $NF == d { sub("/dev/", "", c); print c "s1" }')" &&
    diskutil mount -mountOptions nobrowse -mountPoint "$W/decoy" "$vol" > /dev/null || { echo "could not make the decoy"; [[ -n $decoy ]] && hdiutil detach -force "$decoy" > /dev/null; return 1; }
  PICKMAN_FIXTURE_VOLUME=1 "$ZN_ROOT/zn" run --time 600 -- lune run tests/run -- tests/tooling/light-path.spec.luau > "$W/killed.log" 2>&1 &
  pid=$!
  for i in $(seq 1 600); do mount | grep -qF " $PWD/.cache (" && break; sleep 0.1; done
  sleep 5
  # kill -9 this run's top runner process alone (a descendant of the background job, never another checkout's run)
  kill -9 "$(descendant_runner "$pid")" 2> /dev/null; wait "$pid" 2> /dev/null
  mount | grep -qF " $PWD/.cache (" && echo "the killed run's volume is still mounted (expected)" || { echo "FAIL: the killed run never mounted its volume"; bad=1; }
  out="$("$ZN_ROOT/zn" run --time 300 -- env PICKMAN_FIXTURE_VOLUME=1 lune run tests/run -- tests/tooling/board.spec.luau 2>&1)" || { echo "FAIL: the next run failed"; bad=1; }
  printf '%s\n' "$out" | grep -E '^fixtures: ' | head -3
  mount | grep -qF " $W/decoy (" || { echo "FAIL: the decoy volume was detached"; bad=1; }
  hdiutil detach -force "$decoy" > /dev/null 2>&1
  rm -rf "$W"
  after="$(mounts)"
  [[ "$before" == "$after" ]] || { echo "FAIL: mount or hdiutil info differ from before the killed run"; bad=1; }
  [[ $bad == 0 ]]
}
check "AC7: a run killed with its volume mounted leaves it to the next run, which detaches it and no other volume, and mount and hdiutil info end as they began" ac7_killed

finish
