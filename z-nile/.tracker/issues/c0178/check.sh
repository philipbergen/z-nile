#!/usr/bin/env bash
# Acceptance checks for c0178, slice 1 (revised 2026-11-24 after design review 005). SEQUESTERED once the design review settles:
# never edit during execution. One `check "ACn: ..."` per Checked acceptance criterion, in the order of the issue document.
#
# Every number below is derived in the document ("Where the numbers come from"). A criterion, or the part of one, that cannot be
# measured on this host FAILS with `not measurable on <host>: run on macOS` (z-nile/lib/ac.sh has no skip state; exit 75 means "the
# gate did not start"). AC4 and AC5 run whole suites and fail with `not measured` unless C0178_FULL=1.
HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd -P)" # physical: tests/run strips the physical cwd
source "$(git -C "$HERE" rev-parse --show-toplevel)/z-nile/lib/ac.sh" # cds to the item's project home
# sequestered specs: here before `./zn done`, promoted to its project's tests/acceptance/c0178 after it
A="$HERE/acceptance"
[[ -d $A ]] || A="$PWD/tests/acceptance/c0178"
P="$HERE/probe" # check-only probes: never promoted (they stay in this folder)

# Work outside `check` is limited to running a spec through `tests/run` (which AC_LIST=1 list mode refuses),
# `./zn members` and other cheap reads; everything else goes inside `check`.
METER="$PWD/scripts/fsevents-meter.sh" # z-nile/scripts/fsevents-meter.sh (c0179), from this home
# Every spec run queues behind other gates on the machine (z-nile/lib/gatequeue.pl) for up to ZN_GATE_WAIT seconds, inside a
# `./zn run --time 3600` bound: the wait is capped at 1800 s so each run keeps at least 1800 s of its own.
export ZN_GATE_WAIT=$(( ${ZN_GATE_WAIT:-1800} > 1800 ? 1800 : ${ZN_GATE_WAIT:-1800} ))
BOUND=3600
# AC2: one run of the fifteen-fixture probe (E9): at most two template builds plus fifteen per-fixture budgets
TEMPLATE_BUILD_MAX=9000 # E9: two builds took 11,811 events (5,906 each) in the simulation
FIXTURE_MAX=400        # E9: 169 a fixture in the simulation; a copy is about 4,400 cold, a build 8,941
# AC3: the head's steady-state events at most this fraction of the base's, per heavy file (E5: 0.23, 0.39, 0.42)
HEAVY_RATIO_MAX=0.50
# AC4: one full fast-tier suite at head after a warm-up (an estimate: see the document; 1,927,831 in c0179's full gate)
SUITE_MAX=990000
CPU_MARGIN=1.04

not_measurable() { echo "not measurable on $(uname -s): run on macOS"; return 1; }
on_mac() { [[ "$(uname -s)" == Darwin ]]; }
events_of() { awk -F'\t' '$1 == "events" { print $2; exit }'; }
status_of() { awk -F'\t' '$1 == "status" { print $2; exit }'; }
kzone() { zprint 2> /dev/null | awk '$1 == "data.kalloc.1024" { print $7 }'; }

# The base: `git merge-base HEAD origin/main` now, cloned into a fresh folder OUTSIDE the repository (never under a home's .cache,
# where the head's jailed specs can write), removed by the trap of the check's own subshell, and named by git only after it is
# shown to be its own top. Its origin names a missing folder, so nothing it runs can reach the real repository. Sets BASE_TOP.
make_base() {
  local sha hold top
  sha="$(git -C "$ZN_ROOT" merge-base HEAD origin/main)" || { echo "no merge base with origin/main"; return 1; }
  hold="$(mktemp -d "${TMPDIR:-/tmp}/c0178-base.XXXXXX")" || return 1
  hold="$(cd "$hold" && pwd -P)"
  trap 'rm -rf "'"$hold"'"' EXIT
  case "$hold/" in "$ZN_ROOT"/*) echo "refusing: $hold is inside the repository"; return 1 ;; esac
  git clone -q --no-hardlinks --no-checkout "$ZN_ROOT" "$hold/base" || return 1
  top="$(cd "$hold/base" && git rev-parse --show-toplevel)"
  [[ $top == "$hold/base" ]] || { echo "refusing: the base clone's top is $top, not $hold/base"; return 1; }
  git -C "$hold/base" checkout -q "$sha" && git -C "$hold/base" remote set-url origin "$hold/no-origin" || return 1
  mkdir -p "$hold/base/z-nile/.cache"
  BASE_TOP="$hold/base"
  echo "base $sha in $BASE_TOP"
}

# One spec run of <files> from the home <home>, bounded, results in <res> (a path under <home>/.cache). With METERED=1 the run is
# under the meter over <home>/.cache; prints "events <n>" and "status <s>" lines (events only on macOS).
spec_run() { # <home> <res> <files...>
  local home=$1 res=$2 out
  shift 2
  rm -f "$res"
  if [[ ${METERED:-} == 1 ]]; then
    out="$(cd "$home" && "$ZN_ROOT/zn" run --time $BOUND -- "$home/scripts/fsevents-meter.sh" --no-idle --limit $((BOUND - 60)) \
      --root "$home/.cache" -- env PICKMAN_RESULTS="$res" lune run tests/run -- "$@" 2>&1)"
    printf '%s\n' "$out" | awk -F'\t' '$1 == "events" { print "events " $2 } $1 == "status" { print "status " $2 }'
  else
    out="$(cd "$home" && "$ZN_ROOT/zn" run --time $BOUND -- env PICKMAN_RESULTS="$res" lune run tests/run -- "$@" 2>&1)"
    echo "status $?"
  fi
  printf '%s\n' "$out" | grep -E '^fixtures: ' || true
}
passed_cases() { # <results json> -> sorted "file :: case" lines that passed
  [[ -s $1 ]] || return 0
  perl -MJSON::PP -e 'local $/; my $d = decode_json(<STDIN>); for my $f (@{$d->{files}}) { for my $c (@{$f->{cases}}) { print "$f->{file} :: $c->{name}\n" if $c->{ok} } }' < "$1" | LC_ALL=C sort -u
}
# Every case that passed at the base passes at head; the base must have run (status 0) and passed something.
same_cases() { # <base json> <base status> <head json> <label>
  local lost n
  [[ $2 == 0 ]] || { echo "FAIL ($4): the base run did not pass (status $2): no comparison"; return 1; }
  n="$(passed_cases "$1" | wc -l | tr -d ' ')"
  [[ $n -gt 0 ]] || { echo "FAIL ($4): the base passed no case: no comparison"; return 1; }
  lost="$(LC_ALL=C comm -23 <(passed_cases "$1") <(passed_cases "$3"))"
  echo "$4: $n cases passed at the base; $(passed_cases "$3" | wc -l | tr -d ' ') at head"
  [[ -z $lost ]] || { echo "FAIL ($4): cases that passed at the base and not at head:"; printf '%s\n' "$lost" | head -20; return 1; }
}
# every spec file of a home (a glob pathspec; built with a variable so the path scan reads no literal glob)
SPEC_GLOB=":(glob)${SPEC_TOP:-tests}/**/*.spec.luau"
fixture_files() { # <home> <fast|slow>: the spec files that build a trackerfix or netfix fixture, in that tier, relative to <home>
  (cd "$1" && git grep -lE 'trackerfix\.new\(|netfix\.world\(' -- "$SPEC_GLOB" | LC_ALL=C sort) > "$1/.cache/c0178-fx.txt"
  cut -f2 "$1/tests/slow.tsv" | LC_ALL=C sort > "$1/.cache/c0178-slow.txt"
  if [[ $2 == slow ]]; then LC_ALL=C comm -12 "$1/.cache/c0178-fx.txt" "$1/.cache/c0178-slow.txt"; else LC_ALL=C comm -23 "$1/.cache/c0178-fx.txt" "$1/.cache/c0178-slow.txt"; fi
}

# One suite run from <home> under the meter over <home>/.cache: its CPU-seconds (children included) on a "cpu-seconds" line and the
# meter's lines. With <files> only those files (E12 runs it so on unchanged main); with none, the whole fast tier.
suite_cpu() { # <home> [files...]
  local home=$1
  shift
  (cd "$home" && "$ZN_ROOT/zn" run --time $BOUND -- perl -e 'my $p = fork(); if (!$p) { exec @ARGV or exit 127 } waitpid($p, 0); my $s = $? >> 8; my @t = times; printf STDERR "cpu-seconds\t%.1f\n", $t[2] + $t[3]; exit $s' \
    "$home/scripts/fsevents-meter.sh" --no-idle --limit $((BOUND - 60)) --root "$home/.cache" -- lune run tests/run ${1+--} "$@" 2>&1)
}

# --- AC1: the template and the clone, on every host ------------------------------------------------------------------------------
check "AC1: trackerfix.new clones this run's packed template (a copy where cloning is refused) into a fixture that holds what a build holds, no file of it names the template, the rewrite list is checked at every build and every clone before any push, templates are never shared across runs or kept after a tooling change, the sweep touches only its grammar, a template something wrote into refuses the next clone, and reserved names, linked sources and existing destinations are refused" \
  lune run tests/run -- "$A/template.spec.luau"

# --- AC2: what a fixture costs: the mechanism's number, on macOS ------------------------------------------------------------------
ac2_probe() {
  on_mac || { not_measurable; return 1; }
  local out ev max
  rm -rf "$PWD/.cache/fixture-templates" "$PWD"/.cache/c0178-probe-*
  out="$(METERED=1 spec_run "$PWD" "$PWD/.cache/c0178-probe.json" "$P/fixtures.spec.luau")"
  ev="$(printf '%s\n' "$out" | awk '$1 == "events" { print $2 }')"
  max=$((2 * TEMPLATE_BUILD_MAX + 15 * FIXTURE_MAX))
  echo "fifteen fixtures in one run: $ev events (limit $max = 2 x $TEMPLATE_BUILD_MAX + 15 x $FIXTURE_MAX); $(printf '%s\n' "$out" | grep '^status')"
  [[ "$(printf '%s\n' "$out" | awk '$1 == "status" { print $2 }')" == 0 && -n $ev && $ev -le $max ]]
}
check "AC2: in one run fifteen fixtures (ten with lessons, five without) make at most two template builds plus fifteen per-fixture budgets of file events (2 x 9,000 + 15 x 400 = 24,000; 134,146 today), on macOS" ac2_probe

# --- AC3: the three heavy files against the base measured here, and the copy line -------------------------------------------------
ac3_heavy() {
  local bad=0 spec b h line bst
  on_mac || { not_measurable; return 1; }
  make_base || return 1
  for spec in tests/tooling/light-path.spec.luau tests/tooling/models-dispatch.spec.luau tests/acceptance/f0399/land.spec.luau; do
    spec_run "$BASE_TOP/z-nile" "$BASE_TOP/z-nile/.cache/c0178-r.json" "$spec" > /dev/null # leaves the base's fixtures: the next is steady
    line="$(METERED=1 spec_run "$BASE_TOP/z-nile" "$BASE_TOP/z-nile/.cache/c0178-r.json" "$spec")"
    b="$(printf '%s\n' "$line" | awk '$1 == "events" { print $2 }')"; bst="$(printf '%s\n' "$line" | awk '$1 == "status" { print $2 }')"
    cp "$BASE_TOP/z-nile/.cache/c0178-r.json" "$BASE_TOP/c0178-base.json" 2> /dev/null
    spec_run "$PWD" "$PWD/.cache/c0178-r.json" "$spec" > /dev/null
    line="$(METERED=1 spec_run "$PWD" "$PWD/.cache/c0178-r.json" "$spec")"
    h="$(printf '%s\n' "$line" | awk '$1 == "events" { print $2 }')"
    echo "$spec: base $b, head $h events (steady state)"
    perl -e 'exit(($ARGV[0] > 0 && $ARGV[1] <= $ARGV[0] * $ARGV[2]) ? 0 : 1)' "${b:-0}" "${h:-999999999}" "$HEAVY_RATIO_MAX" || { echo "FAIL: head above $HEAVY_RATIO_MAX of the base"; bad=1; }
    same_cases "$BASE_TOP/c0178-base.json" "$bst" "$PWD/.cache/c0178-r.json" "$spec" || bad=1
  done
  # a run in which a fixture fell back to a copy on macOS says so once (the probe makes two fallbacks through the seam)
  line="$(spec_run "$PWD" "$PWD/.cache/c0178-r.json" "$P/copyline.spec.luau")"
  printf '%s\n' "$line"
  [[ "$(printf '%s\n' "$line" | grep -c '^fixtures: 2 fixture tree(s) were copied, not cloned')" == 1 && "$(printf '%s\n' "$line" | grep -c '^fixtures: ')" == 1 ]] ||
    { echo "FAIL: the copy line is not printed exactly once"; bad=1; }
  rm -f "$PWD/.cache/c0178-r.json"
  [[ $bad == 0 ]]
}
check "AC3: the steady-state run of light-path, models-dispatch and f0399/land at head makes at most half the base's file events (the base measured in this check), every case that passed at the base passing, and a run in which a fixture fell back to a copy on macOS says so in one line" ac3_heavy

# --- AC4: the fast tier: every case of the fixture spec files, and one full suite (opt-in) ------------------------------------------
ac4_fast() {
  if [[ ${C0178_FULL:-} != 1 ]]; then
    echo "not measured: this runs the fast fixture files twice and four full suites; set C0178_FULL=1 (the lead runs it once, at the merge)"
    return 1
  fi
  local bad=0 files st bk0 bk1 hk0 hk1 bcpu hcpu ev out
  make_base || return 1
  # every case of the fast-tier fixture spec files, case by case (each side lists its own files)
  files=($(fixture_files "$BASE_TOP/z-nile" fast)) # paths hold no spaces
  st="$(spec_run "$BASE_TOP/z-nile" "$BASE_TOP/z-nile/.cache/c0178-fast.json" "${files[@]}" | awk '$1 == "status" { print $2 }')"
  files=($(fixture_files "$PWD" fast)) # paths hold no spaces
  spec_run "$PWD" "$PWD/.cache/c0178-fast.json" "${files[@]}" > /dev/null
  same_cases "$BASE_TOP/z-nile/.cache/c0178-fast.json" "$st" "$PWD/.cache/c0178-fast.json" "fast fixture files" || bad=1
  on_mac || { not_measurable; return 1; }
  # one full fast suite each side: a warm-up round (unmeasured), then the counted round
  suite_cpu "$BASE_TOP/z-nile" > /dev/null
  bk0="$(kzone)"; out="$(suite_cpu "$BASE_TOP/z-nile")"; bk1="$(kzone)"
  bcpu="$(printf '%s\n' "$out" | awk -F'\t' '$1 == "cpu-seconds" { print $2 }')"
  suite_cpu "$PWD" > /dev/null
  hk0="$(kzone)"; out="$(suite_cpu "$PWD")"; hk1="$(kzone)"
  hcpu="$(printf '%s\n' "$out" | awk -F'\t' '$1 == "cpu-seconds" { print $2 }')"; ev="$(printf '%s\n' "$out" | events_of)"
  echo "full fast suite at head: $ev events (limit $SUITE_MAX, an estimate), $hcpu CPU-seconds against the base's $bcpu, kernel zone +$((hk1 - hk0)) against the base's +$((bk1 - bk0)); $(printf '%s\n' "$out" | status_of | sed 's/^/status /')"
  [[ "$(printf '%s\n' "$out" | status_of)" == 0 ]] || { echo "FAIL: the head suite failed"; bad=1; }
  [[ -n $ev && $ev -le $SUITE_MAX ]] || { echo "FAIL: above $SUITE_MAX: record the number in the Verification log and put it to the owner, as c0179 did for its AC2"; bad=1; }
  perl -e 'exit(($ARGV[0] > 0 && $ARGV[1] <= $ARGV[0] * $ARGV[2]) ? 0 : 1)' "${bcpu:-0}" "${hcpu:-999999}" "$CPU_MARGIN" || { echo "FAIL: CPU above $CPU_MARGIN x the base"; bad=1; }
  [[ $((hk1 - hk0)) -le $((bk1 - bk0 + 4580)) ]] || { echo "FAIL: the kernel zone rose more than the base's plus 4,580"; bad=1; }
  [[ $bad == 0 ]]
}
check "AC4: every case of the fast-tier fixture spec files that passes at the base passes at head, and one full fast suite at head after a warm-up makes at most 990,000 file events (an estimate), costs at most 1.04 times the base's CPU-seconds and raises the kernel zone at most the base's plus 4,580 (C0178_FULL=1)" ac4_fast

# --- AC5: the slow tier: every case of the slow fixture spec files and the slow guard proofs (opt-in) -------------------------------
ac5_slow() {
  if [[ ${C0178_FULL:-} != 1 ]]; then
    echo "not measured: this runs the slow fixture files and guard proofs twice; set C0178_FULL=1 (the lead runs it once, at the merge)"
    return 1
  fi
  local files st extra=(tests/acceptance/c0058/fence.spec.luau tests/acceptance/c0058/lock.spec.luau tests/acceptance/c0049/parallel-runner.spec.luau)
  make_base || return 1
  files=($(fixture_files "$BASE_TOP/z-nile" slow)) # paths hold no spaces
  st="$(spec_run "$BASE_TOP/z-nile" "$BASE_TOP/z-nile/.cache/c0178-slow.json" "${files[@]}" "${extra[@]}" | awk '$1 == "status" { print $2 }')"
  files=($(fixture_files "$PWD" slow)) # paths hold no spaces
  spec_run "$PWD" "$PWD/.cache/c0178-slow.json" "${files[@]}" "${extra[@]}" > /dev/null
  same_cases "$BASE_TOP/z-nile/.cache/c0178-slow.json" "$st" "$PWD/.cache/c0178-slow.json" "slow fixture files and guard proofs"
}
check "AC5: every case of the slow-tier fixture spec files and of c0058/fence, c0058/lock and c0049/parallel-runner that passes at the base passes at head (C0178_FULL=1)" ac5_slow

# --- AC6: the fast guard specs, by name, on every host ------------------------------------------------------------------------------
check "AC6: the fast guard specs repo-fence, fence-cache-entry, c0060/fixture, fixture-elsewhere and c0077/cache-paths pass" \
  lune run tests/run -- tests/tooling/repo-fence.spec.luau tests/tooling/fence-cache-entry.spec.luau tests/acceptance/c0060/fixture.spec.luau tests/tooling/fixture-elsewhere.spec.luau tests/acceptance/c0077/cache-paths.spec.luau

finish
