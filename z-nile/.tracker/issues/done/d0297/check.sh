#!/usr/bin/env bash
# Acceptance checks for d0297. SEQUESTERED: never edit during execution.
# One `check "ACn: ..."` per Checked acceptance criterion, in the same order as the issue doc.
HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd -P)" # physical: tests/run strips the physical cwd
source "$(git -C "$HERE" rev-parse --show-toplevel)/z-nile/lib/ac.sh" # cds to the item's project home
# sequestered specs: here before `./zn done`, promoted to its project's tests/acceptance/d0297 after it
A="$HERE/acceptance"
[[ -d $A ]] || A="$PWD/tests/acceptance/d0297"

# Work outside `check` is limited to running a spec through `tests/run` (which AC_LIST=1 list mode refuses),
# `./zn members` and other cheap reads; everything else goes inside `check`.
check "AC1: the selector never names a spec under a project root (an item's acceptance/ or proofs/, a raft's folder), whether the change adds it or the branch's current list names it, with or without a project; a promoted acceptance spec and a spec under tests/ are still selected; a change of only sequestered specs and tracker documents scopes to ALL; the caller's own list is the one way in, and it keeps the project filter and the home-relative form; the gate's scope never takes a caller's own list" lune run tests/run -- "$A/select.spec.luau"
check "AC2: lune run z-nile/affected prints no sequestered spec on a prep branch (committed or untracked, against origin/main or --base main, with --project as the gate calls it, or named on the command line) while a spec the branch adds under tests/ still prints; on a layer branch it prints the ticket's own sequestered specs only with --own-acceptance; the gate's own forms there (--project, with and without --base) print none either; no gate, hook or forwarder uses the flag, and in the engine it is used only in a selector call's argv in the file that writes results.txt (cmd.finish's, wherever it lives), at least once" lune run tests/run -- "$A/cli.spec.luau"
check "AC3: (the proof is pinned by hash, so a changed proof fails here) ./zn finish on a layer whose ticket has an acceptance spec records that spec and its case in the layer's results.txt, beside the unit spec the layer added" bash -c '[[ ! -d "$0/acceptance" ]] || { [[ $(git hash-object "$0/proofs/finish.spec.luau") == 6396778c2d2b07e28c82ca9a36beed82ff296754 ]] || { echo "proofs/finish.spec.luau changed since it was pinned" >&2; exit 1; }; lune run tests/run -- "$0/proofs/finish.spec.luau"; }' "$HERE"
check "AC4: zz-test says the selector never selects a sequestered spec and that ./zn finish alone passes --own-acceptance, and z-nile/affected.luau's usage block has a line for the flag" bash -c '
  set -e
  g() { grep -qF -e "$1" "$2" || { echo "missing in $2: $1" >&2; exit 1; }; }
  S="$ZN_ROOT/z-nile/skills/zz-test/SKILL.md"
  g "It never selects a sequestered spec" "$S"
  g "\`./zn finish\` alone passes \`--own-acceptance\`" "$S"
  # the usage block, not the parse code: a `--   ... --flag  -- what it does` line, as every usage line is
  grep -qE "^--[[:space:]]+\.\.\. --own-acceptance[[:space:]]+--[[:space:]]+[^[:space:]]" "$ZN_ROOT/z-nile/affected.luau" ||
    { echo "affected.luau has no usage line for --own-acceptance" >&2; exit 1; }
'

finish
