# Review 006: c0118 (design mode)
Inputs: `prep-c0118` at cbb60388 (`c0118.md`, `check.sh`, `acceptance/*.spec.luau`, design-review-005 and design-refute-005, the post-approval commit 75655a23); `origin/main` at 6684f411 (c0115 landed as 34950af3, c0116's prep squashed as 49957817, R0050 readied); `origin/prep-c0117` at bd31f2d7; the branches `impl-c0116` b858953c, `impl-c0117` 26c344d0 and `impl-c0118` bf244e30; `proto-c0116` df187f26, `proto-c0117` 7ef60b4c and `proto-c0118` 00e6dede; `./zn lessons --when design --full`; `./zn capture c0118`. I also built a scratch stack in the scratchpad (`dr-c0118/stack`, its own clone, origin unset): `impl-c0117` merged with `impl-c0116` and then `impl-c0118`, conflicts resolved by hand, and c0116's and c0117's sequestered specs copied to `z-nile/tests/acceptance/c0116` and `c0117` to simulate both landing first.
Dropped from review-005: F1 and F2. Both are fixed as the refute says: the "a reader that cannot read one compaction's map…" and "a map moved and changed in one commit…" cases are in the Test plan, with mutants M72 and M73.

What I verified:
- **The rebase changed almost nothing in c0118.** Since 2cf234a0 (approval), its folder differs only by 75655a23 (specs take paths from the project home or the top, and the fixture registries drop `home`, with no assertion changed; I read the diff and it is as described) and the merge's lesson-id renames in `c0118.md` and `harvest.md`. `grep -nE 'launch-raft|execute-raft|ready-raft|ticket-prep|make-issue|stop-raft|\.claude/skills'` over the folder finds nothing. Scope matches the capture as in earlier rounds.
- **c0116's raft changes.** Membership comes from the issue's `raft:` line (`board.luau` `members[issue.raft]`), never from the raft's `issues:` or `grouped:`, as c0116 §11 asks. `retiredOf` reads `rafts/retired/<R>` and its `retired:` keeper. History treats `retired/` as no area, so a recombine move is no arrival. z-raft's coherence review is a `design-review-NNN.md` in the raft folder, so it counts as a design round. Its spend (`spend <R> --phase design-review`) is shared out to the members' `spend.md`, which is where §7 reads rows. A preparing raft whose members are "prepared, no raft" puts those members in the raft column with no band, which c0116 allows.
- **c0117's run state and model cell.** `state.json` has `step`, `model` and `outcome` (c0117 §200), and `questions.md` is at `.cache/dispatch/<id>/questions.md` (c0117 Problem). `ledger.Row.model` is nil for an empty cell. A dispatched reviewer's row is `design-review` or `code-review` (c0117 "Who records what"). All of this matches §7 and §10.
- **Landed c0115.** The override of `readme.spec` is right: main has `at(pic, "c0118, planned", …)`.
- **On the scratch stack** (c0116 + c0117 + c0118 together):
  - `bash z-nile/.tracker/issues/c0118/check.sh` passes 7/8. AC5 failed only on conflict markers that my merge left in the README. Once I resolved the README (c0117's models and dispatcher nodes, c0118's board node), `docs.spec` passes 3/3.
  - c0115 `readme` and `docs` and the promoted c0116 and c0117 `docs` pass 25/25.
  - `z-nile/check.sh --full` exits 0: pickman 1404 passed, z-nile 1328 passed, 0 failed.
  - So nothing in c0116's or c0117's current designs turns a c0118 spec red, and c0118 turns none of theirs red.

### F1 [medium] The sequestered docs spec pins a board row that contradicts §3 and the user's G6: "ready … its raft has no branch yet", "run … its raft has a branch"
Where: `acceptance/docs.spec.luau` lines 35-36; Design §3 "Launched"; Decisions G6; AC5
Evidence: §3 and G6 (decided with the user) say a raft that was stopped and readied again keeps its old branch and is **ready** until a commit lands after its latest arrival in `active/`. R0045 is that shape today. The spec requires the zz-rules board row to contain `"ready (readied, in \`active/\`, its raft has no branch yet)"` and `"run (its raft has a branch \`<R-id>-…\`, local or on origin)"`. `impl-c0118`'s row says exactly that. So the skill every agent reads states the rule review 001 F3 replaced: a reader who sees R0045 in "ready" with a branch present is told the board is wrong. Because the spec is sequestered, execution can't correct the sentence.
Critique: one rule, restated in a pinned doc, did not move with the rule. The tempting fix is to delete the two phrases from the spec. That drops AC5's pin on the column definitions.
Consequences: the new phrase must be short enough to keep in one table cell, and both the README and the row must say it the same way.
Recommendation: pin the rule's words instead, for example "ready (readied, in `active/`, and its raft's branch has no commit since that ready)" and "run (its raft's branch `<R-id>-…`, local or on origin, has a commit after its latest ready)". Add a mutant row: the row states "has a branch" alone.
Lesson: z-design/restated-rules-move-together

### F2 [medium] c0118 enters c0116's flow without `size:` and with status `new`, so z-raft's no-argument plan skips it and nothing says how it becomes `prepared`
Where: frontmatter (`raft:` empty, no `size:` or `solo:`, `status: new-…`, `design: ready`); c0116 §3 and §10 (`raftplan.plan` skips and names a candidate with no `size:`; "a raftless issue goes to z-raft"; z-design ends with `./zn status <id> prepared`)
Evidence: c0117, rebased onto the same c0116, added `size: 4800` and `solo: true` (its G14). c0118 has neither. Its prep was done under the old flow but made no raft. After c0116 lands, three things follow:
- `./zn raft-plan` names c0118 as skipped ("no size:"), and per c0116 §10 it goes back to z-design.
- c0118 is not `prepared`, so z-raft's commands don't take it at all.
- `ready c0118` sends it to z-raft.
Nothing in the document says who runs `status c0118 prepared` or what its size is.
Critique: this is an existing item that a new rule hits on the day the rule lands. The tempting fix is just to write a number into `size:`.
Consequences:
- Under c0116 a chore with a size under `raftplan.CAP` (1500) is binned with other prepared chores. c0121 is the obvious neighbour, and the user's "Split: static board, then server" decision may or may not count as the "lands as its own raft" decision that `solo: true` needs.
- `impl-c0118` already changes about 1,220 lines of engine and tests, without the acceptance specs, so an honest size is near the cap, and the cap decides whether the plan folds c0118 at all.
Recommendation: add `size:` (z-design §3's estimate, against the counted lines). Ask the user whether "Split: static board, then server" makes c0118 `solo: true`, and record the answer as a `Decided with the user` line. Say in the document that, once c0116 has landed, c0118's prep ends with c0116's `./zn status c0118 prepared` and is then rafted by z-raft.
Lesson: z-design/new-rules-migrate-existing-work

### F3 [medium] "metrics counts rounds by the board's rule" is unpinned, and the Design describes the metrics code from before c0116
Where: Design §1 (`main.luau` row), §6 bullet 2, Implementation step 6, AC8, the Rules row "metrics counts code rounds by the shared rule" (M45)
Evidence:
- c0116's `metrics` (in `impl-c0116`) has its own counters: `designRoundsIn` (`^design%-review%-%d+%.md$`), a local `codeRounds` (`^review%-%d+%.md$`), `raftDesignRounds`, `retiredRafts()` rows and a new "Design rounds per issue" table.
- `impl-c0118`'s edit, which was written without c0116, conflicts with that whole block.
- On the scratch stack I resolved the conflict by keeping c0116's counters and dropping every `boardview` call and require from `main.luau`. AC8 still passes (it ran inside the 7/8 above), and the full gate is green.
- The two patterns are character for character the ones in `boardview.rounds`, so no output can tell the two copies apart. M45 ("code read as design") breaks metrics itself, not the sharing.
Critique: the Design claims one rule for the chart and the table, but AC8 can't fail when there are two. The step that would make it one (step 6) names code that no longer exists in that form. The tempting fix is to rewire only the raft loop, as `impl-c0118` did. That would leave `designRoundsIn` (the per-issue table, the cost per round and the before/after split) and the retired rows on the old copy.
Consequences: making every c0116 counter call `boardview.rounds` puts a `boardview` require into metrics' helpers. That is fine: `boardview` is pure, with no cycle. A pin on the source (the one matcher lives in `boardview`) must not flag `lessons.luau` or `trail.luau`, which name review files for other purposes.
Recommendation:
- Rewrite §6 bullet 2 and step 6 against c0116's functions: `designRoundsIn(dir)` and `codeRounds(dir)` become `boardview.rounds` over that folder's paths, and `raftDesignRounds`, the retired rows and the per-issue table go through them.
- Add a case that fails while metrics keeps its own pattern. Either:
  - a tooling case that stubs `boardview.rounds` (a module that counts `coherence-*` too, injected) and expects the metrics table to follow it; or
  - a text pin that `main.luau` contains no `design%-review%-%d+` or `^review%-%d+` pattern.
- Add the mutant row "metrics keeps its own counters".
Lesson: zz-test/one-rule-one-function

### F4 [medium] Implementation step 1 always fires, because c0118's own dependencies change the files it watches, and its `<prep base>` names no commit
Where: Implementation step 1; Verification log ("on `proto-c0118` (base `proto-c0117` 6ff822f5)")
Evidence:
- Step 1 says: if any raft changed `board.luau`, `board.html`, `history.luau`, `main.luau`, zz-rules `SKILL.md`, the README or the six overridden specs since prep, "stop and escalate for a re-prep".
- c0115 (landed) already changed the README and zz-rules, and created `c0115/readme.spec.luau`.
- c0116 (R0050, PR #121) changes `main.luau`'s metrics.
- c0117 changes the README's picture and five-parts text, `main.luau`, and `tests/lib/cachepaths.luau` (a `dispatcher.luau` entry beside c0118's `board.luau` entry).
- c0116 and c0117 also edit the same `readme.spec` lines that c0118 overrides.
- Merging the three implementations gives conflicts in exactly those files: `main.luau`, `README.md`, `cachepaths.luau` and `c0115/readme.spec.luau`.
- So an executor who follows step 1 escalates every time, and "<prep base>" is no sha anyone can diff against.
- The prototype evidence (73 mutants, the full gate, E1) sits on `proto-c0117` 6ff822f5 → c0116's prototype 5fa0a8d1 from 2026-10-21. Both have since been rebuilt (`proto-c0116` df187f26, `proto-c0117` 7ef60b4c), and the Verification log records no run against the current ones.
Critique: the guard is right to exist, because the overrides are whole-case edits, but it doesn't separate the changes it expects (its own dependencies) from surprises. The tempting fix is to delete step 1. That would let a real conflicting change through unnoticed.
Consequences: an expected-changes list has to be kept current whenever c0116 or c0117 re-preps again. Pinning it to their landed squash commits ends that.
Recommendation:
- Name the prep base as a sha.
- List the expected upstream hunks with how to merge each: c0116's metrics block (rewire per F3), c0117's README models and dispatcher nodes and its `cachepaths` dispatcher entry (keep both), and the c0116 and c0117 lines in `c0115/readme.spec` (keep theirs and replace only `c0118, planned`). Stop only for anything else.
- Record in the Verification log a `check.sh` and full-gate run on the current upstream. The stack described above passes: check.sh 8/8 once the README is resolved, and the full gate 1404 + 1328, 0 failed.
Lesson: z-design/prove-specs-pass-on-a-prototype, z-design/design-the-execution-window

### F5 [low] c0118's tokens chart and card depend on c0117 guesses that are still pending, and the document doesn't say which ones
Where: §7 (the "unrecorded model" series), §8 (card model), §10 (`questions.md` at the top level only); c0117 Decisions G6 and G13 (pending the user), c0117 §189 (`ZN_DISPATCH_DIR` is the step's own state folder, nested for reviews)
Evidence: §7's "a row with no model is the unrecorded series" relies on c0117's G6 ("the model cell of a row with no model stays empty"). If the user decides G6 another way (a placeholder model, say), that placeholder becomes a model series. §10 reads `questions.md` only at `.cache/dispatch/<id>/`, but a nested step writes into its own `<step>-<mode>-<id>-<n>/` folder. Today only z-ticket, z-design, z-raft and z-run carry the headless section that writes it, so this is latent.
Critique: if G6 or the headless section changes, the card and chart are silently wrong, and no c0118 spec notices, because c0118's fixtures are its own.
Consequences: none beyond a note, and a re-check when c0117's guesses are decided.
Recommendation: under Unknowns, name G6 and "Who records what" as inputs, with what changes if they are decided otherwise. Say that nested steps' `questions.md` are out of scope for c0118 (the card shows the top-level step), and let c0121 pick them up.

Lesson candidates (for the lead):
- A "stop if these files changed since prep" step must name its base sha and the changes its own dependencies are expected to make. Otherwise it fires with certainty, or gets ignored. Check: do the item's own `depends_on` items touch any file this step watches, and does the step say what to do with their hunks?
- An item prepared under a flow that a dependency replaces needs the new flow's frontmatter and its route into that flow, written down when it is rebased. This is a note on z-design/new-rules-migrate-existing-work. Check: after the rebase, which command takes this item next, and does it accept the item as it stands?

Verdict: changes
