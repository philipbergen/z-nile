#!/usr/bin/env bash
# Acceptance checks for c0137. SEQUESTERED: never edit during execution.
# One `check "ACn: ..."` per Checked acceptance criterion, in the same order as the issue doc.
HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd -P)" # physical: tests/run strips the physical cwd
source "$(git -C "$HERE" rev-parse --show-toplevel)/z-nile/lib/ac.sh" # cds to the item's project home
# sequestered specs: here before `./zn done`, promoted to its project's tests/acceptance/c0137 after it
A="$HERE/acceptance"
[[ -d $A ]] || A="$PWD/tests/acceptance/c0137"

# The script of a whole `check "<label>…" bash -c '…'` criterion in a finished check.sh: from the first `bash -c '`
# after the label's line to the first line ending in `'` (design review 002 F1: a fixed line is only reachable when
# every statement before it in its criterion passes; review 003 F1: a check.sh AC, run at c0137's check and done only,
# so the three criteria's text pins never become gate rules).
criterion() {
  awk -v lab="check \"$2" -v q="'" '
    index($0, lab) == 1 { s = 1 }
    s && !o { p = index($0, "bash -c " q); if (!p) next; o = 1; $0 = substr($0, p + 9) }
    o { if (substr($0, length($0)) == q) { print substr($0, 1, length($0) - 1); found = 1; exit } print }
    END { if (!found) exit 1 }' "$1"
}
# each criterion runs from the home as ./zn check runs it, and passes silently
whole_criteria() {
  local spec file label script out bad=0
  for spec in issues/done/c0044/check.sh:AC9: issues/done/c0067/check.sh:AC10: rafts/done/R0025/check.sh:RC1:; do
    file=".tracker/${spec%%:*}"; label="${spec#*:}"
    script=$(criterion "$file" "$label") || { echo "$file: no bash -c criterion $label"; bad=1; continue; }
    if ! out=$(bash -c "$script" 2>&1) || [[ -n $out ]]; then echo "$file ${label%:}: ${out:-exit non-zero}"; bad=1; fi
  done
  return $bad
}

# Work outside `check` is limited to running a spec through `tests/run` (which AC_LIST=1 list mode refuses),
# `./zn members` and other cheap reads; everything else goes inside `check`.
check "AC1: no finished check reads .claude from z-nile/, and each rewritten scan goes red on a phrase in either skills folder" \
  lune run tests/run -- "$A/scans.spec.luau"
check "AC2: c0120's finished-file and c0115's absence specs still pass" \
  lune run tests/run -- tests/acceptance/c0120/finished.spec.luau tests/acceptance/c0115/absence.spec.luau

check "AC3: the three criteria the four lines sit in (c0044 AC9, c0067 AC10, R0025 RC1) pass whole from the home" \
  whole_criteria
finish
