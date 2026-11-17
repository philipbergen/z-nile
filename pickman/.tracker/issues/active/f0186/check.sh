#!/usr/bin/env bash
# Acceptance checks for f0186. SEQUESTERED: never edit during execution.
# One `check "ACn: ..."` per Checked acceptance criterion, in the same order as the issue doc.
HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd -P)" # physical: tests/run strips the physical cwd
source "$(git -C "$HERE" rev-parse --show-toplevel)/z-nile/lib/ac.sh" # cds to the item's project home
# sequestered specs: here before `./zn done`, promoted to its project's tests/acceptance/f0186 after it
A="$HERE/acceptance"
[[ -d $A ]] || A="$PWD/tests/acceptance/f0186"

# Work outside `check` is limited to running a spec through `tests/run` (which AC_LIST=1 list mode refuses),
# `./zn members` and other cheap reads; everything else goes inside `check`.
check "AC1: a run counts the paid revives it used: each continue the offer takes counts one, nothing else does, a new run starts at none, and every game over carries the count (Session's events and frames too)" lune run tests/run -- "$A/count.spec.luau"
check "AC2: a hiscore entry records the run's revives: the submission, the stored row, the rows read back, the lobby's rows, the top-10 list and the best carry them; none, old rows and junk are nil; revives never rank, order or replace" lune run tests/run -- "$A/rows.spec.luau"
check "AC3: through the real adapters, Submits hands HiscoreStore the run's revives (also after a leave) and HiscoreStore writes them into every stored row and the run's list entry" lune run tests/run -- "$A/submit.spec.luau"
check "AC4: every board's rows end with REVIVES n after the level, REVIVES 0 for none (old rows included), the lives figure is not shown, and the viewer's best line shows its revives" lune run tests/run -- "$A/boards.spec.luau"
check "AC5: the game over shows REVIVES n (REVIVES 0 for none) in RevivesView, booted and shown each frame by the client's Main, with Flow's overlay unchanged" lune run tests/run -- "$A/gameover.spec.luau"
check "AC6: the price of a play shows as 5 R\$ struck through, on sale for 1 R\$: the lobby's buy lines and the test purchase screen for a play, as rich text; the other lobby lines and the continue's price as they were" lune run tests/run -- "$A/price.spec.luau"
check "AC7: game-design.md states the revives, the free game per game and the sale price (lives spent gone), architecture.md declares Flow -> Lobby, and pickman's paid-play records stay in its own stores" lune run tests/run -- "$A/docs.spec.luau"
check "AC8: Logic stays engine-free, every dependency is declared, and every feature has unit specs" lune run tests/run -- tests/meta/architecture.spec.luau

finish
