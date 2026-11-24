#!/usr/bin/env bash
# Acceptance checks for c0179. SEQUESTERED: never edit during execution.
# One `check "ACn: ..."` per Checked acceptance criterion, in the same order as the issue doc.
HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd -P)" # physical: tests/run strips the physical cwd
source "$(git -C "$HERE" rev-parse --show-toplevel)/z-nile/lib/ac.sh" # cds to the item's project home
# sequestered specs: here before `./zn done`, promoted to its project's tests/acceptance/c0179 after it
A="$HERE/acceptance"
[[ -d $A ]] || A="$PWD/tests/acceptance/c0179"

# Work outside `check` is limited to running a spec through `tests/run` (which AC_LIST=1 list mode refuses),
# `./zn members` and other cheap reads; everything else goes inside `check`.
# check "AC1: <statement>" lune run tests/run -- "$A/<name>.spec.luau"

# AC1 (c0179 slice 1, a real-work proof that stays here and is never promoted: it builds the Swift helper on first use and
# depends on what FSEvents delivers; the meter's argument handling, refusals and output are specced in tests/tooling/fsevents-meter.spec.luau).
ac1_real_meter() {
  local d out n
  [[ "$(uname -s)" == Darwin ]] || { echo "meter: not available on this host (skipped)"; return 0; }
  d="$(mktemp -d "${TMPDIR:-/tmp}/c0179-ac1.XXXXXX")" || return 1
  out="$(scripts/fsevents-meter.sh --no-idle --limit 120 --root "$d" -- bash -c 'for i in $(seq 1 3000); do : > "$1/f$i"; done; sleep 1' _ "$d")" || { rm -rf "$d"; echo "$out"; return 1; }
  rm -rf "$d"
  n="$(printf '%s\n' "$out" | awk -F'\t' '$1 == "events" { print $2 }')"
  echo "events: $n"
  [[ -n $n && $n -ge 3000 && $n -le 20000 ]]
}
check "AC1: the real meter counts at least 3,000 events (and under 20,000) for 3,000 files written under its root" ac1_real_meter

finish
