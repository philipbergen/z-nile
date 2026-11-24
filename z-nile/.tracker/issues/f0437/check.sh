#!/usr/bin/env bash
# Acceptance checks for f0437. SEQUESTERED: never edit during execution.
# One `check "ACn: ..."` per Checked acceptance criterion, in the same order as the issue doc.
HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd -P)" # physical: tests/run strips the physical cwd
source "$(git -C "$HERE" rev-parse --show-toplevel)/z-nile/lib/ac.sh" # cds to the item's project home
# sequestered specs: here before `./zn done`, promoted to its project's tests/acceptance/f0437 after it
A="$HERE/acceptance"
[[ -d $A ]] || A="$PWD/tests/acceptance/f0437"

# Work outside `check` is limited to running a spec through `tests/run` (which AC_LIST=1 list mode refuses),
# `./zn members` and other cheap reads; everything else goes inside `check`.
# check "AC1: <statement>" lune run tests/run -- "$A/<name>.spec.luau"
check "AC1: the Go tests of z-nile/go pass" bash -c 'source lib/goenv.sh && cd go && go test -count=1 ./...'
check "AC2: ./zn app, the page, live.js and its data layer pass their specs" lune run tests/run -- tests/tooling/app-cli.spec.luau tests/tooling/app-copy.spec.luau
check "AC3: slice 1: the markdown renderer (hostile corpus, strict DOM check, computed contrast, steps) and the engine facts (whole sections, template comments)" lune run tests/run -- tests/tooling/app-md.spec.luau tests/tooling/approval-facts.spec.luau
# one-time real-work proof, never promoted: real waiting tickets through the engine, the Go reader and the renderer
check "AC3: slice 1: on the real tracker, the characters of each contract part on disk equal the characters the page receives (whole chain)" bash tests/chain/walk-chain.sh

check "AC4: slice 2: the units index and id links" lune run tests/run -- tests/tooling/units-facts.spec.luau tests/tooling/units-write.spec.luau
check "AC4: slice 2: the page: id links (the renderer and the frozen real tickets against the frozen real index), the detail view, routing and fetching" lune run tests/run -- tests/tooling/app-links.spec.luau tests/tooling/app-md.spec.luau tests/tooling/app-cli.spec.luau
# one-time real-work proof, never promoted: the real tracker's units index through the engine, the Go reader and the page's code
check "AC4: slice 2: on the real tracker, every id of the waiting tickets is a link or a marked unknown, counted, c0261 resolves to its stub, and no word changes (whole chain)" bash tests/chain/units-chain.sh

finish
