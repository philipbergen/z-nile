# Answers to design review 006: c0263

- F1: fixed: who.spec expects `merged  human:Cy (from git)`, as provenance.spec and the Design do (`grep -n merged who.spec.luau provenance.spec.luau`: both say `human:Cy`).
- F2: fixed: the derived rafter is the oldest life commit at which `raft:` became the current value and stayed so (`raftAt` read at the edge); a ready, a restamp and the move to `done/` keep the value and start nothing. The pure case's life now carries the D/A pair of the move, a ready and a restamp (Fay stays the rafter); a mutant taking the newest matching commit is killed; who.spec adds c0050 (raft, ready, done, no stored row: `rafted  human:Bob`, never Hal or Cy); E11 ran the rule on 8 real done items.
- F3: fixed: the publish validator takes published events only (`unblocked`, `confirmed`, `ranked`; `unblocked` alone in `active/`); publish.spec's create is a `confirmed` row and refuses an `approved`, `rafted` and `delivered` row; record.spec asserts no `rafted` row reaches main from a published append. Run on the prototype.
- F4: fixed: lifecycle.spec makes `done` fail (a promoted spec that fails), asserts no delivered row, no `done/` folder and a clean tree, then fixes the spec and `done` appends exactly one row per member. Run on the prototype.
- F5: fixed: dispatch.spec cuts PR #50 first, main gains the `ranked` row, the stale PR is refused, and PR #51 carries the united record (main's rows, then ours) and merges.
- F6: fixed: the board case compares event, actor, detail and source of every entry against a literal list.
- F7: fixed: the carried move refuses under `ZN_DISPATCH` (Behaviour 9) and approve.spec drives it after a real approval.
- F8: fixed: `./zn record` calls `refuseStale()` before it publishes (Behaviour 6); `c0081/publish-guard` and the 15 other promoted specs the reviewer named were rerun on the prototype: 141 passed, 6 failed, all six named under Overrides.
- F9: fixed: the stale cross-references are corrected (open question 2, `via=`, the `body` mention).
- F10: stated: `who` and the board both take `people` from one `git log --format=%ae` over the whole log.
- F11: fixed: the prep stop ends "then ./zn dispatch <id> again" (dispatch.spec asserts it); open question 1 is put to the user in the report with the decided sentence beside it.
