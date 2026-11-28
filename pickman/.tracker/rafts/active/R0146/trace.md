# Trace: R0146

Commit: 39632e37984d5881ee905ff82d6198d7bb97bf01

## Claims

| claim | design | test | code |
|---|---|---|---|
| c0196:P1: Pin f0147's HUD pick counter (Hud.picksBox under the score) clear of f0158's danger ring dots on f0158's screens, in a unit case of its own, once both have landed: neither issue's executor may edit the other's sequestered or promoted spec, and f0147's design review 003 probe found no overlap on f0158's 15 screens | pickman/.tracker/issues/active/c0196/c0196.md:19, pickman/.tracker/issues/active/c0196/c0196.md:22-23, pickman/.tracker/issues/active/c0196/c0196.md:31-35 | pickman/tests/unit/Hud/picks-ring.spec.luau:104-121 | none |
| c0196:S1: A unit case in `pickman/tests/unit/Hud` (or beside f0158's ring unit specs): on each of f0158's sample screens and insets, desktop and touch, `Hud.picksBox(Touch.blocks(l).score)` meets no dot of the ring at its full extent (every sector lit). | pickman/.tracker/issues/active/c0196/c0196.md:26, pickman/.tracker/issues/active/c0196/c0196.md:32-34 | pickman/tests/unit/Hud/picks-ring.spec.luau:104-121 | none |
| c0196:S2: Recorded by f0147's design review 004 F4: the instruction lived only in f0147.md; this chore carries it whatever order f0147 and f0158 land in. | pickman/.tracker/issues/active/c0196/c0196.md:27, pickman/.tracker/issues/active/c0196/c0196.md:7 | pickman/.tracker/issues/active/c0196/check.sh:12 (provenance note, not a standalone runtime criterion; f0147 and f0158 are in done/ and AC1 runs the standalone spec) | none |
| c0196:AC1: `tests/unit/Hud/picks-ring.spec.luau` | pickman/.tracker/issues/active/c0196/c0196.md:48, pickman/.tracker/issues/active/c0196/c0196.md:34 | pickman/.tracker/issues/active/c0196/check.sh:12, pickman/tests/unit/Hud/picks-ring.spec.luau:104-121 | none |
| c0196:AC2: None. | pickman/.tracker/issues/active/c0196/c0196.md:50-51 (vacuous: no Judged criteria) | pickman/.tracker/issues/active/c0196/check.sh:12 (vacuous: no Judged criteria) | none |
| c0196:AC3: None. | pickman/.tracker/issues/active/c0196/c0196.md:53-54 (vacuous: no Observed criteria) | pickman/.tracker/issues/active/c0196/check.sh:12 (vacuous: no Observed criteria) | none |

## Source files

| file | claims |
|---|---|
