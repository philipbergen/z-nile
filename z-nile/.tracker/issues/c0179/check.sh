#!/usr/bin/env bash
# Acceptance checks for c0179. This is the design's check file: it is written with the design on branch c0179-build (the design is
# still a draft), and a design review judges it before the ticket merges.
# One `check "ACn: ..."` per Checked acceptance criterion, in the same order as the issue doc.
#
# A criterion that cannot be measured on this host FAILS with `not measurable on <host>: run on macOS`: z-nile/lib/ac.sh has no
# skip state (its one other outcome, exit 75, means "the gate did not start" and is printed with that wrong meaning), so a failure
# is the only honest one. The ticket can therefore be finished only on a Mac. The parts that can be checked anywhere run
# everywhere (AC1's other-host half, AC3's CPU comparison).
HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd -P)" # physical: tests/run strips the physical cwd
source "$(git -C "$HERE" rev-parse --show-toplevel)/z-nile/lib/ac.sh" # cds to the item's project home
# sequestered specs: here before `./zn done`, promoted to its project's tests/acceptance/c0179 after it
A="$HERE/acceptance"
[[ -d $A ]] || A="$PWD/tests/acceptance/c0179"

# Work outside `check` is limited to running a spec through `tests/run` (which AC_LIST=1 list mode refuses),
# `./zn members` and other cheap reads; everything else goes inside `check`.
METER="scripts/fsevents-meter.sh"
GOMOD="$PWD/go"
BASE=f7c7a35bb                         # origin/main when this branch started: the "before" of every comparison
W="$PWD/.cache/c0179-check.$$"         # a name only (each check runs in its own subshell); AC5's check, the last, removes the folder
EXPECTED="$HERE/expected-pass.txt"     # the tests that passed at $BASE (package, name), generated once from `go test -json` there
EXPECTED_SKIP="$HERE/expected-skip.txt" # the tests that were skipped at $BASE

# The Go tests make their own fixture repositories and run git as a user would; this file's git fence (ac.sh: GIT_CONFIG_*, a hooks
# path, a protocol allow-list, an ssh stub) would change what they test (TestInitRunsNoGlobalHooks fails under it). They touch only their
# private TMPDIR, and the gate's own go stage runs them unfenced, so every GIT_* variable is dropped for them.
nogit() { local v a=(); for v in $(env | sed -n 's/^\(GIT_[A-Za-z0-9_]*\)=.*/\1/p'); do a+=(-u "$v"); done; env ${a[@]+"${a[@]}"} "$@"; }

not_measurable() { echo "not measurable on $(uname -s): run on macOS"; return 1; }

# --- AC1 ---------------------------------------------------------------------------------------------------------------------
# macOS half: a real-FSEvents proof that stays here (it builds the Swift helper on first use and depends on what FSEvents
# delivers; the meter's arguments, refusals and output are specced in tests/tooling/fsevents-meter.spec.luau).
ac1_real_meter() {
  [[ "$(uname -s)" == Darwin ]] || { not_measurable; return 1; }
  local d out n
  mkdir -p "$PWD/.cache" && d="$(mktemp -d "$PWD/.cache/c0179-XXXXXX")" || return 1
  out="$($METER --no-idle --limit 120 --root "$d" -- bash -c 'for i in $(seq 1 3000); do : > "$1/f$i"; done; sleep 1' _ "$d")" || { rm -rf "$d"; echo "$out"; return 1; }
  rm -rf "$d"
  n="$(printf '%s\n' "$out" | awk -F'\t' '$1 == "events" { print $2 }')"
  echo "events: $n"
  [[ -n $n && $n -ge 3000 && $n -le 20000 ]]
}
# other-host half: on a host that is not macOS the meter prints `meter: not available` and exits 0 (the host is named by the
# meter's test seam, so this runs everywhere).
ac1_other_host() {
  local out rc
  out="$(FSEVENTS_METER_UNAME=Linux $METER --root . -- true 2>&1)"; rc=$?
  echo "$out"
  [[ $rc -eq 0 && $out == *"meter: not available"* ]]
}
check "AC1: the real meter counts at least 3,000 events (and under 20,000) for 3,000 files written under its root, on macOS" ac1_real_meter
check "AC1: on another host it prints 'meter: not available' and exits 0" ac1_other_host

# --- AC2 and AC4 share one metered run of the two Go packages ------------------------------------------------------------------
# The build is warmed first (`go test -run '^$'`), so the compile's own files are not in the count. The run is `go test -json`
# with a private TMPDIR, metered with four roots: that TMPDIR (the criterion's number) and, to catch fixtures moved out of it to an
# uncounted place, the home's .cache, /private/tmp and the home folder. The private TMPDIR is a fresh folder in the system temp folder,
# the one place of this file outside .cache: the Go tests assume a TMPDIR that lies under no git repository (several of them test
# exactly that), so it cannot sit inside the checkout; it is removed before the run's findings are written. The findings go to
# $W/gorun, one `key<TAB>value` line each, for AC2 and AC4.
go_metered_run() {
  [[ -s $W/gorun ]] && return 0
  [[ "$(uname -s)" == Darwin ]] || { not_measurable; return 1; }
  local pt mounts_before mounts_after out left procs
  mkdir -p "$W" && pt="$(mktemp -d "${TMPDIR:-/tmp}/c0179-go.XXXXXX")" || return 1
  (cd "$GOMOD" && "$ZN_ROOT/zn" run --time 1200 -- go test -run '^$' ./internal/host ./cmd/zn) > "$W/warm.log" 2>&1 || { cat "$W/warm.log"; return 1; }
  mounts_before="$(mount; hdiutil info 2>&1)"
  out="$(nogit "$ZN_ROOT/zn" run --time 3000 -- $METER --no-idle --limit 2400 --root "$pt" --root "$PWD/.cache" --root /private/tmp --root "$HOME" -- \
    env TMPDIR="$pt" bash -c "cd '$GOMOD' && go test -count=1 -json ./internal/host ./cmd/zn > '$W/test.json'" 2>&1)"
  mounts_after="$(mount; hdiutil info 2>&1)"
  left="$(find "$pt" -maxdepth 1 -name 'zn-*template*' 2>/dev/null | wc -l | tr -d ' ')"
  procs="$(pgrep -f "$pt" 2>/dev/null | wc -l | tr -d ' ')"
  rm -rf "$pt"
  {
    printf '%s\n' "$out" | awk -F'\t' '$1 == "events" { n++; print "events" n "\t" $2 } $1 == "status" { print "status\t" $2 } $1 == "wall-seconds" { print "wall\t" $3 }'
    echo "load	$(uptime | sed 's/.*averages*: *//; s/[ ,].*//')"
    [[ "$mounts_before" == "$mounts_after" ]] && echo "mounts	same" || echo "mounts	CHANGED"
    echo "leftover-templates	$left"
    echo "processes-using-tmpdir	$procs"
  } > "$W/gorun"
  cat "$W/gorun"
}
gorun_get() { awk -F'\t' -v k="$1" '$1 == k { print $2 }' "$W/gorun"; }
# the sets of passed and skipped tests of the run, as "package name" lines
tests_of() { # <action>
  grep "\"Action\":\"$1\"" "$W/test.json" | grep '"Test":' | sed -E 's/.*"Package":"([^"]*)","Test":"([^"]*)".*/\1 \2/' | LC_ALL=C sort -u
}
ac2_events() {
  go_metered_run || return 1
  local tmpd cache outside st lost newskip bad=0
  tmpd="$(gorun_get events1)"; cache="$(gorun_get events2)"; outside=$(( $(gorun_get events3) + $(gorun_get events4) )); st="$(gorun_get status)"
  echo "events under the run's TMPDIR: $tmpd (limit 60000; 197458 at the baseline); under the home's .cache: $cache; under /private/tmp and the home folder together: $outside (limit 15000); go test status: $st; load $(gorun_get load)"
  # every guard is evaluated and reported, so a failing number never hides a failing guard
  [[ $st == 0 && -n $tmpd && $tmpd -le 60000 ]] || { echo "FAIL: the events under TMPDIR are above 60000, or go test failed"; bad=1; }
  # fixtures moved out of TMPDIR to an uncounted place: .cache may hold only a few hundred events (the files of this check)
  [[ $cache -le 1000 && $outside -le 15000 ]] || { echo "FAIL: events outside the run's TMPDIR"; bad=1; }
  # fewer events from fewer or skipped tests: every test that passed at the base passes, and none that ran there is skipped now
  lost="$(LC_ALL=C comm -23 "$EXPECTED" <(tests_of pass))"
  [[ -z $lost ]] || { echo "FAIL: tests that passed at $BASE and did not pass now:"; printf '%s\n' "$lost" | head -20; bad=1; }
  newskip="$(LC_ALL=C comm -13 "$EXPECTED_SKIP" <(tests_of skip))"
  [[ -z $newskip ]] || { echo "FAIL: tests skipped now and not at $BASE:"; printf '%s\n' "$newskip" | head -20; bad=1; }
  echo "passed tests: $(tests_of pass | wc -l | tr -d ' ') (the base's $(wc -l < "$EXPECTED" | tr -d ' ') all among them unless listed above)"
  [[ $bad == 0 ]]
}

# --- AC3: CPU, not wall time, because wall time on a busy machine says nothing ---------------------------------------------------
# Test binaries of $BASE and of this checkout (go test -c), run interleaved base, head, base, head, base, head; the CPU-seconds
# (user plus system of the binary and every child it waited for) of the two packages are added, and the median head/base ratio
# must be at most 1.10. Writes only under .cache.
cpu_of() { # <dir> <binary>: CPU-seconds of the run
  (cd "$1" && nogit perl -e 'my $p = fork(); if (!$p) { open(STDOUT, ">", "/dev/null"); open(STDERR, ">&", \*STDOUT); exec @ARGV or exit 127 } waitpid($p, 0); my @t = times; printf "%.2f\n", $t[2] + $t[3]' "$2" -test.count=1)
}
ac3_cpu() {
  mkdir -p "$W/cpu/base" || return 1
  git -C "$ZN_ROOT" archive "$BASE" z-nile/go z-nile/engine z-nile/lib z-nile/vendor z-nile/templates z-nile/roots.luau z-nile/affected.luau | tar -x -C "$W/cpu/base" || return 1
  (cd "$W/cpu/base" && git init -q -b main . && git add -A && git -c user.name=t -c user.email=t@x.invalid commit -q -m base) > /dev/null 2>&1 || return 1
  local bg="$W/cpu/base/z-nile/go" pkg
  for pkg in host:internal/host zn:cmd/zn; do
    (cd "$bg" && "$ZN_ROOT/zn" run --time 1500 -- go test -c -o "$W/cpu/base-${pkg%%:*}.test" "./${pkg##*:}") > /dev/null 2>&1 || { echo "the base's ${pkg%%:*} test binary did not build"; return 1; }
    (cd "$GOMOD" && "$ZN_ROOT/zn" run --time 1500 -- go test -c -o "$W/cpu/head-${pkg%%:*}.test" "./${pkg##*:}") > /dev/null 2>&1 || { echo "this checkout's ${pkg%%:*} test binary did not build"; return 1; }
  done
  local r b h ratios=""
  for r in 1 2 3; do
    b=0; h=0
    for who in base head; do
      local total=0 c
      for pkg in host:internal/host zn:cmd/zn; do
        local dir="$GOMOD/${pkg##*:}"; [[ $who == base ]] && dir="$bg/${pkg##*:}"
        c="$(cpu_of "$dir" "$W/cpu/$who-${pkg%%:*}.test")" || { echo "$who ${pkg%%:*} test binary failed"; return 1; }
        awk -v c="$c" 'BEGIN { exit !(c + 0 > 1) }' || { echo "$who ${pkg%%:*}: no CPU time measured ('$c')"; return 1; }
        total="$(awk -v a="$total" -v b="$c" 'BEGIN { printf "%.2f", a + b }')"
      done
      [[ $who == base ]] && b=$total || h=$total
    done
    echo "round $r: base ${b}s CPU, head ${h}s CPU"
    ratios="$ratios $(awk -v a="$b" -v b="$h" 'BEGIN { printf "%.3f", b / a }')"
  done
  local median
  median="$(printf '%s\n' $ratios | sort -n | sed -n 2p)"
  echo "head/base CPU ratios:$ratios; median $median (limit 1.10)"
  [[ $median =~ ^[0-9]+\.[0-9]+$ ]] || { echo "no ratio measured"; return 1; }
  awk -v m="$median" 'BEGIN { exit !(m <= 1.10) }'
}

ac4_no_mounts() {
  go_metered_run || return 1
  echo "mounts $(gorun_get mounts); zn-*template* folders left in the run's TMPDIR: $(gorun_get leftover-templates); processes still using it: $(gorun_get processes-using-tmpdir)"
  [[ "$(gorun_get mounts)" == same && "$(gorun_get leftover-templates)" == 0 && "$(gorun_get processes-using-tmpdir)" == 0 ]]
}

# --- AC5: the file events of one full gate (the owner's own question), a baseline for the Lune fixtures ----------------------------
# It runs a FULL gate (long): only when C0179_AC5=1; the lead runs it under the meter and records the number in the Verification log. It
# has no limit: it records. It is the last check, so it also removes the work folder.
ac5_full_gate() {
  rm -rf "$W/test.json"
  [[ "$(uname -s)" == Darwin ]] || { rm -rf "$W"; not_measurable; return 1; }
  if [[ ${C0179_AC5:-} != 1 ]]; then
    rm -rf "$W"
    echo "not measured: a full gate takes long; set C0179_AC5=1 to run one under the meter (the lead records the number in the Verification log)"
    return 1
  fi
  local d out
  mkdir -p "$W/gate-tmp" && d="$W/gate-tmp"
  out="$("$ZN_ROOT/zn" run --time 3500 -- $METER --no-idle --limit 3400 --root "$PWD/.cache" --root "$d" -- env TMPDIR="$d" "$ZN_ROOT/z-nile/check.sh" --full 2>&1)"
  rm -rf "$W"
  printf '%s\n' "$out" | grep -E '^(events|fseventsd-cpu-seconds|wall-seconds|status)'
  [[ "$(printf '%s\n' "$out" | awk -F'\t' '$1 == "status" { print $2 }')" == 0 ]]
}

check "AC2: during go test of ./internal/host and ./cmd/zn the events under the run's TMPDIR are at most 60,000, with the same tests passing, none newly skipped, and nothing moved out of TMPDIR (NOT MET: about 71,300, see Open to the human)" ac2_events
check "AC3: the CPU-seconds of the two packages' test binaries at HEAD are at most 1.10 times the base's (median of three interleaved rounds)" ac3_cpu
check "AC4: the metered AC2 run leaves mount and hdiutil info unchanged, no zn-*template* folder in its TMPDIR and no process using it" ac4_no_mounts
check "AC5: the file events of one full gate are measured with the meter (home .cache and the gate's TMPDIR) and recorded: the baseline for the Lune fixtures" ac5_full_gate

finish
