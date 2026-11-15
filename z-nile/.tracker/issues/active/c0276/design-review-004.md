# Review 004: c0276 (design mode)
Inputs: prep worktree `.worktree/prep-board-shows-lost-work` at 5d8fb89f with the working-tree c0276.md (sha256 88b3f77174e4…), check.sh (e128f9515cec…, unchanged since round 003), acceptance/board.spec.luau (eb25196e02ef…, unchanged since round 003), acceptance/verdicts.spec.luau (0f76c1caa1e4…), design-review-001..003, design-refute-001..003 (refute 003 e7f0b3ec2616…), harvest.md (2a988189e7b7…) and the lesson note it adds; prototype origin/proto-c0276 5944e221 (its check.sh and both specs are byte-identical to the prep's); `git diff origin/proto-c0265-raft origin/proto-c0276 -- z-nile/engine z-nile/README.md z-nile/skills` (159 added, 14 removed lines); c0265's document at origin/prep-work-heartbeat; the c0275 hand-off; origin/R0084-board-live-server d46bd5f8 and origin/prep-ticket-provenance (c0284 hand-off); `./zn capture c0276` (8577a496, a confirmed capture: title, Problem and Non-goals unchanged, the Solution only gained detail). Since the prototype's base 1758cf21, main changed none of the files the specs load except `tests/lib/fakecli.luau` (unused by both specs), and proto-c0265-raft (bf5aa3c3) is still an ancestor of the prototype. All runs were in scratch clones of 5944e221 with origin removed, under /private/tmp/claude-501/-Users-philipbergen-code-pickman/3fbf9326-e053-49c8-ab1e-bfbc221fe8f4/scratchpad/r4 (`proto` for the mutants, `probe` for the probe cases and E9; mutants in `muts.json`, run by `scripts/mut.py` through `./zn run`). Nothing in the repository was edited. Baseline on the bare prototype: verdicts.spec and board.spec 19 passed, 0 failed.
Dropped from review-003: F1 (X12 re-run: verdicts 5 passed, 1 failed at :195), F2 (X4: verdicts 5p/1f at :285), F3 (`--alert` is #ff8a80 in dark mode, 7.9:1 on #15171a by relative luminance; `.mark` has `margin-left`; OC1 still names one colour scheme, left as a note), F4 (the c0180 row now says what is true), F5 (E1 and E3 match the prototype: 6 and 13 cases).
Re-run from earlier rounds, one at a time: N10 (verdicts 5p/1f at :289), Mc (5p/1f at :278), Mh (board 12p/1f at :325), M10 (12p/1f at :362), N18 (12p/1f at :338). All die as recorded.
E9 re-run (c0265 moved it to c0276; E4 cites the hand-off's run on the monolith): markers at the entry of `boardVerdicts` and after its guard, then c0042 (5), c0118 (7), c0070/board-refresh, `tooling/board` and `tooling/board-review`: 131 passed, 0 failed. The function was entered 4 times in the clone's own checkout and read nothing there; all 17 reads were in `.cache` fixtures. AC3's protection premise holds on this prototype.

### F1 [high] The board that `land` rebuilds has no criterion and no case; a land that rebuilds without the marks passes check.sh
Where: the capture's second outcome ("The board's own rebuilds (after every publish, `land` and main-checkout `sync`) keep the marks"); AC2 and its check.sh label ("the board every publish rebuilds and the one a main-checkout `sync` rebuilds"); Rules and mutants, row "the board every publish, `land` and `sync` rebuild carries them" (c0276.md:148); board.spec.
Evidence:
- `grep -c '"land"' acceptance/board.spec.luau` → 0, and `grep -c land check.sh` → 0. The Rules row claims `land` and cites "board :: the board every publish rebuilds…", a case that runs `status` and `sync` only.
- `land` calls `refreshBoard()` itself after its push and fetch (main.luau:2849-2850), not through `published()`.
- Mutant L1 makes land's page build without the verdicts. After `refreshBoard()` in `cmd.land`, it adds ``sh.writeReplacing(`{mainRoot()}/.cache/board.html`, board.build(nil, mainRoot()))``. Result: board.spec 13 passed, 0 failed. AC3's c0070/board-refresh can't see it either, because its fixture holds no claim that isn't live.
- The plausible wrong implementation of the same shape hands the verdicts down from `published()` and from `sync` instead of reading them inside `buildBoard`. Land is then forgotten, and check.sh stays green.
- I added a probe case to a scratch copy of board.spec, just before the protected case:
  - in a worktree `capture-landprobe` that holds no claim, `new issue c land-probe`, an edit, and a commit;
  - remove the main checkout's board, then `land` with `PICKMAN_LAND_GATE=true` (how c0072 lands without the gate) and `ZN_NOW=LATE`;
  - expect `itemOf(<main's board>, "c0010").heartbeat == "lost"`.

  On the prototype it passes (15 passed, 0 failed, with F2's probe). Under L1: 14 passed, 1 failed at :365, `expected "lost", got nil`.
Critique: The capture names three triggers and the criteria pin two of them. The tempting fix is to write "land" into AC2's text and call it covered because land and publish share `refreshBoard`. That is true of the prototype, not of a wrong implementation, and catching a wrong implementation is check.sh's job.
Consequences: One more land in the fixture. Layer rule:
- the capture worktree holds no claim, so c0275's autobeat beats nothing there, and so does land's tick (which runs only in a worktree that holds entries);
- its name doesn't end in `-<n>`, so c0277 can't read it as a numbered copy;
- no command runs in `wt` afterwards.

`land` fetches main before `refreshBoard`, so `fresh = true` is right there.
Recommendation:
- Add the probe above to board.spec as "the board a land rebuilds carries the verdicts".
- Name `land` in AC2 (the document and the check.sh label) and in the Test plan.
- Split the Rules row so that land has its own row, with this case and L1 (run).
Lesson: zz-test/pin-fail-safes-where-they-act

### F2 [medium] A rebuild whose reads failed writes a page that looks as if nothing is lost; the only word of it is on the stderr of whoever published
Where: Design §3 ("Each failure prints exactly one `warning: board:` line"); Usability ("a read that failed says why in one `warning: board:` line instead of silently dropping the marks"); board.html `#problems` (lines 222-226).
Evidence:
- A second probe case on the scratch clone: with the heartbeats unreadable (`lsfail`), `wt2` gives back c0080 (a publish).
  - The publisher's stderr: `warning: board: heartbeats unreadable; built without lost-work marks`.
  - The main checkout's rebuilt page: `marks=0 problems=0`, and no "lost-work" anywhere in its text.
  - In that fixture c0010, c0050 and R0020 are lost. The page a person reloads draws them like live claims.
- The rebuild runs in whichever process published: under the dispatcher a headless agent's, otherwise another terminal's. The person who opens the board ran none of those commands.
- The page already says on itself what it could not read: `model.problems`, drawn in `#problems` as "N files could not be read: …". The verdict reads don't use it.
- The failures that reach this path:
  - an offline machine;
  - the beat fetch losing the ref lock twice (`netRetry` retries once);
  - origin/main or its registry unreadable;
  - a vanished document.

  Unreadable pull requests already show on the page as `stale?`.
Critique: The capture wants the board to show each claim's verdict and still build when the reads fail. A built page that silently drops every lost mark reads as "nothing is lost", the opposite of "take lost work first". The tempting fix is to push the warning into `model.problems`. That changes the model of every failed build through a key c0118 owns, and its sentence ("N files could not be read") mislabels the note.
Consequences:
- A new optional model key (for example `verdictsNote`), set only when a read was tried and failed. It stays nil when nothing was read on purpose (a protected checkout, no origin, `PICKMAN_PUBLISH=0`), so the byte-identical rule, c0042, c0070 and `tooling/board` hold.
- The engine edge returns the note beside the verdicts. `board.build`'s new parameter carries both (one trailing optional record `{ verdicts, note }`), so there is still no change to an existing signature.
- c0257 reads an additive key. The served page is Q1.
Recommendation:
- For each failure that drops or weakens marks, draw one note on the page, with the warning's own text, in the `#problems` area.
- Cases:
  - the `lsfail`, `mainfail`, `noregistry` and `noshow` cases assert the note in the page's model;
  - the `lsfail` publish case asserts it on the main checkout's rebuilt page;
  - the protected and `PICKMAN_PUBLISH=0` cases assert the key is absent;
  - verdicts.spec's page case asserts it is drawn.
- Add a Rules row "a failed read is named on the page" with the mutant "note dropped".
- Correct Usability.
Lesson: z-design/results-land-on-every-path

### F3 [medium] Every worktree cut before c0276 lands rebuilds the main board with its own engine, without marks, and the design never says so
Where: Design §3; §5 Existing work ("no prepared, active or mid-prep item fails a rule on landing day"); Usability; the zz-rules board row.
Evidence:
- How a rebuild runs:
  - `./zn` runs `lune run z-nile/engine/main` from its own checkout (zn:25);
  - `buildBoard` builds in-process with that engine's `board.build` and template (main.luau:545-547);
  - before c0276, `buildBoard` is `board.build(nil, root)` (`git show origin/proto-c0265-raft:z-nile/engine/main.luau`, line 550).
- So once the raft merges, every publish from a worktree that hasn't merged that main (claims, spend rows, status moves) rewrites the main checkout's `.cache/board.html` without marks. The marks come back only at the next publish from an updated engine.
- `git worktree list | awk '{print $1}' | grep -c /.worktree/` → 70 worktrees today, every one cut before c0276 can land.
- c0265's document has no transition rule for older engines either: `git show origin/prep-work-heartbeat:z-nile/.tracker/issues/c0265/c0265.md | grep -nE "older engine|old engine|transition|worktrees? (cut|made|branched) before"` → nothing.
Critique: The capture's second outcome is that the board's own rebuilds keep the marks. For days after landing the marks will come and go with whichever worktree published last, at the moment people are learning to trust them, and nothing tells the reader. The tempting fix is code in c0276's engine, which can't reach the old engines.
Consequences:
- The old engines can't change, so the transition can only be stated and shortened (a `./zn sync` in each worktree).
- Later board changes would have the same skew. They avoid it only if the main checkout's page is built by the main checkout's engine (a second `./zn board -O` there), at the cost c0070 measured: a second Lune process per publish, about a third more on c0053's commands spec. That trade-off is the user's.
Recommendation:
- State the transition in §3, in §5's Existing work, in Usability and in the zz-rules board row. Until a worktree merges a main that holds c0276, its publishes rebuild the board without marks. A `./zn sync` there, or `./zn board` or `sync` in the main checkout, restores them.
- Have AC4 grep that sentence.
- Put the forward-proofing option and its cost to the user in the prep report, beside Q1. Not a cut: the outcome holds once every worktree has merged.

### F4 [low] Two stated rules have no case or row: one warning when the pull requests can't be read, and `./zn board` fetching main itself
Where: Design §3 ("Each failure prints exactly one `warning: board:` line"); AC2's "exactly one warning" list; board.spec, "unreadable pull requests leave stale claims stale"; Rules and mutants.
Evidence:
- Unpinned warning count:
  - mutant W1 prints the pull-request warning twice: board.spec 13 passed, 0 failed;
  - the case checks only `has(r.stderr, "pull requests unreadable")`, and AC2's exactly-one list leaves the pull requests out;
  - the plausible form is one "shown unconfirmed" line per stale claim, three lines in this fixture.
- Missing row: `./zn board` passes `fresh = false`. Round 002 showed its mutant N1 dies in the unreachable-origin case, but no Rules row names "`./zn board` fetches main itself".
Critique: These are small rules, but a wrong implementation of either passes the criteria.
Consequences: none.
Recommendation:
- Add `t.expect(warnings(r.stderr)).toBe(1)` to the pull-request case, and add unreadable pull requests to AC2's exactly-one list.
- Add Rules rows for W1 and N1.
Lesson: z-design/spec-design-correspondence

### F5 [low] Implementation step 6 lets an executor finish with Q1 unanswered
Where: Implementation step 6 ("until then nothing here wires it, and the Verification log says so"); §4, the c0121 row.
Evidence:
- z-design step 5 sends a scope question to the user before `design: ready`, and §4 says the served wiring "is not claimed as done".
- Step 6 instead describes executing without the answer and noting that in the Verification log. That would end with the issue done, the served board unwired and no Scope decision line.
- Round 002 F2 asked for the answer to be "recorded in this document before `ready`".
Critique: Q1 is the user's, and the document handles it rightly everywhere except in this step, which an executor reads as permission.
Consequences: none.
Recommendation: Reword step 6:
- the answer is a line in the Problem before `design: ready`;
- an executor who finds none stops (zz-execute stop conditions);
- if the answer is yes, the issue goes back to z-design for the wiring's AC, cases and Rules rows.

Lessons added this round (harvest.md): the note on zz-test/seed-every-enumerated-case (a "keeps its place" rule needs each kept value seeded where a wrong rule would move it) is a lesson another raft could fail, not a restated finding. `./zn lessons --check`: 268 lessons, ok. `./zn lessons --uncovered c0276`: every finding is covered.

Candidate lesson for the lead (from F3): a change to a shared file that every checkout's engine rewrites in-process (the main checkout's board) states what the older engines write until every worktree has merged it. Check: which shared files does each checkout's own engine rewrite, and what do engines cut before this change write there meanwhile?

Verdict: changes
