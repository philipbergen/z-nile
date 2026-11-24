#!/usr/bin/env bash
# Acceptance checks for c0179. The design's check file (written with the design on branch c0179-build, F2 of the code review: the
# design is still a draft and a design review judges this file before the ticket merges).
# One `check "ACn: ..."` per Checked acceptance criterion, in the same order as the issue doc.
HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd -P)" # physical: tests/run strips the physical cwd
source "$(git -C "$HERE" rev-parse --show-toplevel)/z-nile/lib/ac.sh" # cds to the item's project home
# sequestered specs: here before `./zn done`, promoted to its project's tests/acceptance/c0179 after it
A="$HERE/acceptance"
[[ -d $A ]] || A="$PWD/tests/acceptance/c0179"

# Work outside `check` is limited to running a spec through `tests/run` (which AC_LIST=1 list mode refuses),
# `./zn members` and other cheap reads; everything else goes inside `check`.
# check "AC1: <statement>" lune run tests/run -- "$A/<name>.spec.luau"

METER="scripts/fsevents-meter.sh"
GOMOD="$PWD/go"

# AC1, macOS half: a real-FSEvents proof that stays here (it builds the Swift helper on first use and depends on what FSEvents
# delivers; the meter's arguments, refusals and output are specced in tests/tooling/fsevents-meter.spec.luau).
ac1_real_meter() {
  local d out n
  [[ "$(uname -s)" == Darwin ]] || { echo "not macOS: the other half of AC1 covers this host"; return 0; }
  d="$(mktemp -d "${TMPDIR:-/tmp}/c0179-ac1.XXXXXX")" || return 1
  out="$($METER --no-idle --limit 120 --root "$d" -- bash -c 'for i in $(seq 1 3000); do : > "$1/f$i"; done; sleep 1' _ "$d")" || { rm -rf "$d"; echo "$out"; return 1; }
  rm -rf "$d"
  n="$(printf '%s\n' "$out" | awk -F'\t' '$1 == "events" { print $2 }')"
  echo "events: $n"
  [[ -n $n && $n -ge 3000 && $n -le 20000 ]]
}
# AC1, other-host half: on a host that is not macOS the meter prints `meter: not available` and exits 0 (the host is named by the
# meter's test seam, so this runs everywhere).
ac1_other_host() {
  local out rc
  out="$(FSEVENTS_METER_UNAME=Linux $METER --root . -- true 2>&1)"; rc=$?
  echo "$out"
  [[ $rc -eq 0 && $out == *"meter: not available"* ]]
}
check "AC1: the real meter counts at least 3,000 events (and under 20,000) for 3,000 files written under its root, on macOS" ac1_real_meter
check "AC1: on another host it prints 'meter: not available' and exits 0" ac1_other_host

# AC2 and AC3 share one metered run of `go test -count=1 ./internal/host ./cmd/zn` (private TMPDIR as the root, so only that
# run's events count), kept in a file for the second check.
GORUN="${TMPDIR:-/tmp}/c0179-gorun.$$" # a name only; the last check removes the file
go_metered_run() {
  [[ -s $GORUN ]] && return 0
  [[ "$(uname -s)" == Darwin ]] || { echo "not macOS: no meter"; echo "skipped" > "$GORUN"; return 0; }
  local d load
  d="$(mktemp -d "${TMPDIR:-/tmp}/c0179-go.XXXXXX")" || return 1
  load="$(uptime | sed 's/.*averages*: *//; s/[ ,].*//')"
  { $METER --no-idle --limit 900 --root "$d" -- env TMPDIR="$d" bash -c "cd '$GOMOD' && go test -count=1 ./internal/host ./cmd/zn"; echo "load	$load"; } > "$GORUN" 2>&1
  rm -rf "$d"
}
ac2_events() {
  go_metered_run || return 1
  grep -q '^skipped' "$GORUN" && { echo "skipped (not macOS)"; return 0; }
  local n st
  n="$(awk -F'\t' '$1 == "events" { print $2 }' "$GORUN")"; st="$(awk -F'\t' '$1 == "status" { print $2 }' "$GORUN")"
  echo "events under TMPDIR: $n (limit 60000, baseline 197458); go test status: $st"
  [[ $st == 0 && -n $n && $n -le 60000 ]]
}
ac3_wall() {
  go_metered_run || return 1
  grep -q '^skipped' "$GORUN" && { echo "skipped (not macOS)"; return 0; }
  local w load
  w="$(awk -F'\t' '$1 == "wall-seconds" { print $3 }' "$GORUN")"; load="$(awk -F'\t' '$1 == "load" { print $2 }' "$GORUN")"
  echo "wall ${w}s against the 70 s baseline (limit 77 s), load $load"
  awk -v l="$load" 'BEGIN { exit !(l < 4) }' || { echo "not measured: machine busy"; return 0; }
  awk -v w="$w" 'BEGIN { exit !(w <= 77) }'
}
# AC4: the meter and the changed tests mount nothing: `mount` and `hdiutil info` are the same before and after a metered run.
ac4_no_mounts() {
  rm -f "$GORUN" # the last check: the run AC2 and AC3 shared is done with
  [[ "$(uname -s)" == Darwin ]] || { echo "not macOS (skipped)"; return 0; }
  local a b
  a="$(mount; hdiutil info 2>/dev/null)"
  $METER --no-idle --root . -- true > /dev/null || return 1
  b="$(mount; hdiutil info 2>/dev/null)"
  [[ "$a" == "$b" ]]
}
check "AC2: during go test of ./internal/host and ./cmd/zn the events under TMPDIR are at most 60,000 and the tests pass (NOT MET: about 71,000, see Open to the human)" ac2_events
check "AC3: the wall time of the same run is no worse than the 70 s baseline by more than 10% on an idle machine (load under 4), else 'not measured: machine busy'" ac3_wall
check "AC4: mount and hdiutil info are identical before and after a metered run" ac4_no_mounts

finish
