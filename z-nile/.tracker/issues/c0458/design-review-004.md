# Review 004: c0458 (design mode)
Inputs: prep worktree `prep-collapse-reviews-and-tighten-caps` at 77a09de34 with its uncommitted `z-nile/.tracker/issues/c0458/{c0458.md,check.sh,guesses.md,harvest.md,acceptance/{caps-modes,walk,docs}.spec.luau,experiments/prototype.patch,design-refute-003.md}`; `design-review-003.md`. Checks made: `experiments/prototype.patch` (366 lines) applied to a `git archive 1b78199b0` copy in `.cache/c0458-r4-proto`, its own repository, with the three specs copied into its `z-nile/tests/acceptance/c0458r4`. On that copy walk passes 5/5 and caps-modes 4/4. The mutant `RANK[word] > current` -> `RANK[word] >= 0` in `easy.raisedBy` (a raise at the ticket's own level counted) turns AC8 red. Also read: `z-nile/engine/main.luau:7255-7290` (`stop`'s raise path) and `:718-727` (`moveOnOrigin`), `z-nile/engine/publish.luau:30-33` (`Raise`), `:182-194` (`movedEdit`), `:427-478` (`raiseEdit`), `:560-607` (`validateMoves`), `z-nile/tests/tooling/light-publish.spec.luau:390-472`, `z-nile/engine/workread.luau:395-437`, `z-nile/engine/lightgit.luau:176-198`, and the z-design Risk paragraph. Every run went through `./zn run`.

Round 3 answers. The refute file disputes nothing, so there is no refutation to accept or re-raise.
- F1 is fixed in the documents. Item 10, G2 and the prototype's release text all say `stop` empties the raft and the unraised members are rafted again under a new id. That closes the stale-review, stale-trace and stale-layer problem. AC9's added `rafting` case passes on the prototype. The publish step the fix relies on is a new defect (F1 below).
- F2 is fixed. The Test plan names the `workread` IO case (`Level: c0011 risky` answers `release`, `Level: nonsense` answers `none`). The two rows point at it, and they say which half ran and which is reasoned.
- F3 is fixed. `raisedBy(reviews, levels)` counts a raise only above the ticket's level. AC8 pins own-level, below-level and above-level lines, and the mutant above turns AC8 red. The brief now says "a ticket that needs a design review, Level: risky" and "A line at or below the ticket's own level raises nothing". One citation the fix leans on is wrong (F2 below).
- F4 is fixed. E5 records the 366-line patch, which is the patch's length, and the three added mutants. The Test plan says 5 of 5 walk cases.

### F1 [high] The publisher refuses the move that `stop` now makes for a raft of several tickets, and the design still says it does not touch the publisher
Where: Design item 10 ("`./zn stop <R-id>` ... **empties the raft** and gives it back to the backlog in one published move, for one raised ticket or several (the code now at `#ids == 1` generalises) ... every other member stays `prepared` with `raft:` empty"); Checklist answers, **Guards** ("nothing near the repository guards, publisher or gate changes"); Touched modules (no `z-nile/engine/publish.luau`, no `tests/tooling/light-publish.spec.luau`); `publish.luau:33`, `:191`, `:436-478`; `main.luau:7283`
Evidence: `stop` publishes through `moveOnOrigin`, and `publish.validateMoves` judges every moved document against three rules.
- `publish.movedEdit` (`:189-191`) allows a moved document to change only its `status:` line: "a moved document may only change its status: line".
- The one exception is `publish.raiseEdit`. Its `Raise` type is `{ ticket: string, raft: string, level: string }` (`:32`): one ticket.
- For the raft document, `raiseEdit` returns true only when `before.keys.light == "true" and before.keys.issues == "[<the one ticket>]"` (`:475-477`). For any other document it returns false (`:440-441`).

Take R0306 with c0010, c0011 and c0012, no `light:`, and a final review that says `Level: c0011 risky`. Item 10's `stop` writes `raft: ""` on c0010 and c0012, which is a change beyond `status:` on documents that are not `raise.ticket`. That gives "c0010.md: a moved document may only change its status: line". It also writes `issues: []` on a raft whose `issues:` holds three tickets and which has no `light: true`, so `raiseEdit` is false there too. With two raised tickets, `Raise` cannot name the second one at all. The whole `stop` fails, and the walk keeps answering `release` with a command that cannot succeed.

The existing tooling spec pins the refusal the design needs to lift: `light-publish.spec.luau:462` asserts `raiseEdit("R0001", raftOf("[c0010]"), raftOf("[]"), raise)` is false "-- not light". Neither the Test plan's edited-spec list nor Affected specs names that file. The prototype holds no `main.luau` or `publish.luau`, so no run could have shown this.
Critique: round 3's Recommendation said "in one published move" without following it into the publisher, and the answer copied it. Today's single-ticket path works only because the publisher has a narrow exception for exactly that shape. The tempting fix is to loosen `raiseEdit` until the IO case passes, for example by dropping the `light == "true"` test, letting any member's `raft:` change, or making `level` a map. Each of those widens a guard on what a move may rewrite on origin/main.
Consequences:
- The design changes a publish guard. z-design's Risk paragraph names "a guard" as a reason for `risky`, so G1 (`risk: normal`) and the **Guards** checklist line must be judged again, and the round cap and final-review model that follow from `risk:` change with them.
- The widened exception needs its own refusals, so it still lets through only what `stop` writes:
  - a member of the raft whose `raft:` is cleared but which is not on the raft's `issues:` list;
  - a raised ticket's `risk:` lowered;
  - a body edit;
  - a raft whose new `issues:` is not `[]`;
  - a raise naming a ticket that is not in the move;
  - a partial move (a raised ticket without its raft, or the reverse; the check at `:600-607` today).
- The other way to avoid the guard is two publishes: today's plain `stop`, whose moves change only `status:`, then an in-place edit of the backlog documents. That costs atomicity. If the second publish fails, the raft sits in the backlog with its members still naming it, and the design must say what `stop` and the walk answer then, and whether rerunning `stop` finishes the job.
Recommendation: pick one of the two routes and write it into item 10.
- Route A, one move. Generalise `publish.Raise` to `{ raft: string, raised: { [string]: string }, released: { string } }`. Make `raiseEdit` accept:
  - for each raised ticket, `status`, `risk` (to its raised level, not lower), `design` (`draft`) and `raft` (this raft to `""`);
  - for each released member, `status` and `raft` (this raft to `""`) only;
  - for the raft, `status` and `issues` (from exactly the raised and released ids to `[]`), with no `light:` test.

  Make `validateMoves` require every listed document in the same publish. Add `z-nile/engine/publish.luau` and `tests/tooling/light-publish.spec.luau` to Touched modules, edit the case at `:462`, and add a refusal case for each item in the list above, plus an accepted case for a raft of three that is not light with one ticket raised and one with two raised. Add a Rules row per refusal, with the mutant "the exception accepts it".
- Route B, two publishes. State the order, what each publish writes, and a case for a second publish that fails, then the rerun.

Under either route, rewrite the **Guards** checklist line. Re-judge G1 against the Risk paragraph and record the result in `guesses.md`. Because `stop` is IO and not in the prototype, keep the IO case in `light-path.spec` as the executor's case, and make it assert the published `raft:` of c0010 and c0012 as the publisher accepted it.
Lesson: z-design/instructions-runnable-where-they-run
Erred: z-design
Upstream: zz-review

### F2 [low] `levels` is cited as a map `workread` "already holds", but `workread` holds a list of levels
Where: Design item 10 ("`levels` maps each ticket of the raft to its current `risk:`, which `workread.luau:404` already holds"); refute-003 F3 ("`workread` passes its `levels` map to the reader, which it already holds"); `workread.luau:395-404`
Evidence: `workread.luau:396-403` builds `levels` as `{ Level }` with `table.insert(levels, lvl)`, which feeds `rounds.highest`. It has no ticket keys. A member whose `risk:` is not a level is skipped, so its id would be missing from a map built in the same loop. `raisedBy` would then report that member's `Level: <id> risky` as "no ticket <id> in the raft", which is the wrong problem.
Critique: an executor who trusts the citation will look for a map that does not exist. If they build one in the same loop, members with a bad `risk:` drop out of it.
Consequences: none beyond the map being built. `roundsProblem` already stops a raft with a bad `risk:`, provided the walk checks it before the raise.
Recommendation: say that `workread` builds a new `{ [ticket]: level }` map beside the list, over every member in `issues:`, with `rounds.level`'s result (nil `risk:` is normal). State that a member with an unreadable `risk:` is reported through `roundsProblem`, not as "no ticket in the raft".
Erred: z-design
Upstream: none

### F3 [low] The release text tells a normal ticket raised to risky that it is "not easy"
Where: `work.forRaft`'s `release` text in `experiments/prototype.patch` ("A review of {r.id} says {named} not easy"); Design item 10 ("the walk ... answers `release` naming each raised ticket and its level")
Evidence: AC9's fixture raises c0011, a normal ticket, to risky. The prototype answers "A review of R0306 says c0011 (Level: risky), c0012 (Level: normal) not easy". Before round 2 every raise was of an easy ticket, so "not easy" was true. Now a raise can move a normal ticket to risky.
Critique: the worker reads this text and acts on it. "not easy" names the wrong change for a ticket that was already normal.
Consequences: none. AC9 pins only the ids and the level words.
Recommendation: word it as "raised c0011 to risky, c0012 to normal", and keep the rest of the sentence.
Erred: z-design
Upstream: none

Verdict: changes
