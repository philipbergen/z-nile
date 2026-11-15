#!/usr/bin/env bash
# Acceptance checks for f0339. SEQUESTERED: never edit during execution.
# One `check "ACn: ..."` per Checked acceptance criterion, in the same order as the issue doc.
HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd -P)" # physical: tests/run strips the physical cwd
source "$(git -C "$HERE" rev-parse --show-toplevel)/z-nile/lib/ac.sh" # cds to the item's project home
# sequestered specs: here before `./zn done`, promoted to its project's tests/acceptance/f0339 after it
A="$HERE/acceptance"
[[ -d $A ]] || A="$PWD/tests/acceptance/f0339"

# Work outside `check` is limited to running a spec through `tests/run` (which AC_LIST=1 list mode refuses),
# `./zn members` and other cheap reads; everything else goes inside `check`.

check "AC1: explainer.check refuses every way a page breaks the shape (contract, sections, diagrams, Touched modules, choices, fetches), and only y or yes approves" \
  lune run tests/run -- "$A/explainer.spec.luau"
check "AC2: ./zn explain prints the page and the contract hash; ./zn approve refuses a missing, uncommitted or broken page before it opens anything, opens a good one, asks y/n, records only on y, and nothing when the contract changed while it was open" \
  lune run tests/run -- "$A/approve-page.spec.luau"
check "AC3: the template is a page of the shape; the usage text, z-design, zz-rules, zz-review and the README say who writes the page and what approve does with it" \
  lune run tests/run -- "$A/docs.spec.luau"
check "AC4: f0339's own explainer page passes ./zn explain f0339" \
  "$(git -C "$HERE" rev-parse --show-toplevel)/zn" explain f0339

finish
