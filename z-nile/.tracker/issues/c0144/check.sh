#!/usr/bin/env bash
# Acceptance checks for c0144. SEQUESTERED: never edit during execution.
# One `check "ACn: ..."` per Checked acceptance criterion, in the same order as the issue doc.
HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd -P)" # physical: tests/run strips the physical cwd
source "$(git -C "$HERE" rev-parse --show-toplevel)/z-nile/lib/ac.sh" # cds to the item's project home
# sequestered specs: here before `./zn done`, promoted to its project's tests/acceptance/c0144 after it
A="$HERE/acceptance"
[[ -d $A ]] || A="$PWD/tests/acceptance/c0144"

# Work outside `check` is limited to running a spec through `tests/run` (which AC_LIST=1 list mode refuses),
# `./zn members` and other cheap reads; everything else goes inside `check`.
check "AC1: the pure rules: rich and colored only on a terminal or when forced, NO_COLOR, TERM=dumb, the width, fit, wrap, columns, bars, links" \
  lune run tests/run -- "$A/term.spec.luau"
check "AC2: piped output is plain and unchanged by the color options; on a terminal or with --color=always it is the rich look, fits the width and keeps every fact; check, refusals, usage and zz-rules" \
  lune run tests/run -- "$A/look.spec.luau"
# AC3 (here only, never a gate rule after done: lesson zz-test/promoted-specs-pin-rules-not-sets): piped, every command
# with a look prints byte for byte what the engine at the merge-base with origin's main printed. The base is read from
# origin itself (git ls-remote), never a local ref the branch can move (lesson zz-review/sequestration-reference-not-a-ref);
# once c0144 has landed the base holds it, and the comparison is of the engine with itself, which it says.
plain_matches_base() {
  set -o pipefail
  local tip base out=.cache/c0144-base
  tip=$(git ls-remote origin refs/heads/main | awk '{print $1}') && [[ -n $tip ]] ||
    { echo "cannot read origin's main (git ls-remote origin)"; return 1; }
  git cat-file -e "$tip^{commit}" 2>/dev/null || { echo "origin's main $tip is not here: git fetch origin"; return 1; }
  base=$(git merge-base "$tip" HEAD) || { echo "no merge-base with origin's main"; return 1; }
  if git cat-file -e "$base:z-nile/engine/term.luau" 2>/dev/null; then
    echo "the base $base already holds c0144: comparing the engine with itself"
  fi
  rm -rf "$out" && mkdir -p "$out" || return 1
  (cd "$ZN_ROOT" && git archive "$base" zn z-nile/engine z-nile/lib) | tar -x -C "$out" ||
    { echo "cannot unpack the base's tooling from $base"; return 1; }
  [[ -f $out/zn && -f $out/z-nile/engine/main.luau ]] || { echo "the base's tooling is incomplete in $out"; return 1; }
  C0144_BASE="$(cd "$out" && pwd -P)" lune run tests/run -- "$A/plain-base.luau"
}
check "AC3: piped, every command prints byte for byte what the engine before c0144 printed" plain_matches_base
check "AC4: the specs that read ./zn's output still pass" \
  lune run tests/run -- tests/acceptance/c0082/cli.spec.luau tests/acceptance/c0111/metrics-lessons.spec.luau \
  tests/acceptance/c0111/lessons-cli.spec.luau tests/acceptance/c0045/workstreams.spec.luau \
  tests/acceptance/c0120/freeze.spec.luau tests/acceptance/c0120/homes.spec.luau \
  tests/acceptance/c0119/capture-cli.spec.luau tests/acceptance/c0084/spend-command.spec.luau \
  tests/acceptance/c0084/metrics-phases.spec.luau tests/acceptance/c0120/promote-home.spec.luau \
  tests/acceptance/c0053/commands-sync.spec.luau

finish
