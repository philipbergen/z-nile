# Idea review 001

## Findings

- F1: The Problem and the Solution treat all four tickets as prepared, approved designs with sequestered specs, and that is false for c0368 and only partly true for the others. On origin/main, c0368 is `design: draft` with no `acceptance/` folder and no `approval.md`, so it has no sequestered specs and no prototype that could "go red in its own raft", and nothing can be "re-prepped" or "re-approved". Its actual overlap with c0369 is that both override the same three c0283 approve specs (`tests/acceptance/c0283/approve.spec.luau`, `tests/tooling/approve.spec.luau`, `tests/tooling/approve-publish.spec.luau`). c0267 and f0339 do have sequestered specs (c0267's `docs.spec.luau` pins `./zn approve <id> --publish`), but they have no `approval.md`. Only c0250 has both. So "the person has re-approved each changed design" can't be true for three of the four. As written, the Problem can't be judged true for c0368, and the Solution's done-condition can't be met for it.

## Verdict

revise
