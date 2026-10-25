#!/usr/bin/env bash
# Acceptance checks for c0096. SEQUESTERED: never edit during execution.
# One `check "ACn: ..."` per Checked acceptance criterion, in the same order as the issue doc.
HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd -P)" # physical: tests/run strips the physical cwd
source "$(git -C "$HERE" rev-parse --show-toplevel)/z-nile/lib/ac.sh" # cds to the repo root
# sequestered specs: here before `./zn done`, promoted to tests/acceptance/c0096 after it
A="$HERE/acceptance"
[[ -d $A ]] || A="$PWD/tests/acceptance/c0096"

# Work outside `check` is limited to running a spec through `tests/run` (which AC_LIST=1 list mode refuses),
# `./zn members` and other cheap reads; everything else goes inside `check`.
# AC1: the folder each check.sh requires for the jailed-case marker is the one its spec writes, before and after
# `./zn done` promotes the specs
marker_folders() {
  local id spec want have dir
  for pair in c0076:sweeper c0078:jail-signals; do
    id=${pair%%:*} spec=${pair#*:}
    dir=$(../zn find "$id") || return 1
    want=$(grep -oE '\.cache/[a-z0-9-]+/jailed-cases-ran' "$dir/check.sh" | head -1)
    want=${want%/jailed-cases-ran}
    [[ -f $dir/acceptance/$spec.spec.luau ]] && have=$dir/acceptance/$spec.spec.luau || have=tests/acceptance/$id/$spec.spec.luau
    grep -qF "/$want\`" "$have" || { echo "$have does not write under $want"; return 1; }
  done
}
check "AC1: each spec writes its jailed-case marker under the folder its check.sh requires" marker_folders

finish
