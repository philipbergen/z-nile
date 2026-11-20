# Review 010: c0250 (design mode)
Inputs: prep worktree `prep-c0250-r2` at HEAD (`git diff 7e61b3451 HEAD -- z-nile/.tracker/issues/c0250`: `design-refute-009.md`, `c0250.md` E7 Result header, E7 (1) and (5), `experiments/mutants-r2.txt`, `experiments/prototype.patch`, `harvest.md`); prototype commit b806c8a4f (`git show b806c8a4f`, read only: `engine/dispatcher.luau` `nestedRaftOf`, `modelStep`, `oneStep`).

Round 8 of the back-and-forth. The scope is only the two answers to review 009. F1 holds. `nestedRaftOf(ctx, id)` is the one raft lookup, and both `modelStep` and `oneStep` call it before `dispatch.nestedStop(id, nestedRaft)`. The removed copies were the same expression, so behaviour is unchanged. The `oneStep` tail now reads "(nothing is blocked until your author runs it)", which agrees with Design 5: the nested step only stops, and its author blocks the item. The old words "the item is blocked, not this step" no longer appear in the design or the specs. The E7 Result header names tip b806c8a4f. `experiments/prototype.patch` equals `git diff bf939624c b806c8a4f -- . ':!z-nile/.tracker'` byte for byte after its header line, and that header names b806c8a4f. `origin/proto-c0250-r2` contains b806c8a4f. The two remaining mentions of 740fce2c0 are historical and correct (where `nestedStop` first appeared, and where the item-fallback mutant ran). F2 holds. E7 (5) now records the third lead mutant, with its counts (4 failed, 10 passed) and the cases that failed. `mutants-r2.txt` lists the four FAIL lines and says plainly that the run does not separate the c0020 case from the cascade. The harvest lines copy review 009's `Erred:` lines. One small new defect came in with the prototype edit.

### F1 [low] The new helper sits between `blocker`'s comment and `blocker`, so that comment now reads as part of `nestedRaftOf`'s
Where: prototype b806c8a4f `z-nile/engine/dispatcher.luau` about lines 319-332 (also in `experiments/prototype.patch`)
Evidence: the comment "-- c0250: the item that holds `id` blocked on origin/main: … Returns it and the id the human resolves." describes `blocker`. It is now followed by the new "-- c0250 (design review 009 F1): the raft a nested step's author blocks …" comment and `local function nestedRaftOf`. `blocker` comes only after that function's `end`. The first comment's "Returns it and the id the human resolves" does not match `nestedRaftOf`, which returns one value.
Critique: the executor ports this prototype, so it would copy the misplaced comment into the engine. This is cosmetic: no behaviour or contract changes.
Consequences: none.
Recommendation: when the build ports the patch, put `nestedRaftOf` (with its own comment) above `blocker`'s comment, or below `blocker`. Nothing in the design, the specs or the record needs to change. A note in the next prototype commit is enough.
Erred: z-design
Upstream: none

Verdict: approve
