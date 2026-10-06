#!/usr/bin/env bash
# Acceptance checks for f0013. SEQUESTERED: never edit during execution.
# One `check "ACn: ..."` per Checked acceptance criterion, in the same order as the issue doc.
HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd -P)" # physical: tests/run strips the physical cwd
source "$(git -C "$HERE" rev-parse --show-toplevel)/scripts/lib/ac.sh" # cds to the repo root
# sequestered specs: here before `tracker.sh done`, promoted to tests/acceptance/f0013 after it
A="$HERE/acceptance"
[[ -d $A ]] || A="$PWD/tests/acceptance/f0013"

check "AC1: session lifecycle: join, leave, independence, config" lune run tests/run -- "$A/lifecycle.spec.luau"
check "AC2: intents are validated and rate-limited, applied in order" lune run tests/run -- "$A/intents.spec.luau"
check "AC3: sessions follow the sim tick semantics and are deterministic" lune run tests/run -- "$A/tick.spec.luau"
check "AC4: snapshot schema v1 and jumpTick" lune run tests/run -- "$A/snapshot.spec.luau"
check "AC5: the server clock gives 30 Hz at any frame rate, capped" lune run tests/run -- "$A/clock.spec.luau"
check "AC6: 50 players x 60 s steps in under 4 s" lune run tests/run -- "$A/bench.spec.luau"
check "AC7: the place: no auto characters, the Ready/Intent/Snapshot remotes, Main boots Sessions, sessions start on Ready" lune run tests/run -- "$A/place.spec.luau"

finish
