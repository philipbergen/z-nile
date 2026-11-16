# Review 001: R0101 (raft mode)
Inputs: branch `raft-narrow-ramp-pins` at bc9d26d51 (merge base with origin/main 72d779924); `pickman/.tracker/rafts/R0101/R0101.md` and `check.sh`; c0176's and c0177's documents, `check.sh`, `acceptance/narrowed.spec.luau` and `experiments/narrow.patch`; f0147's document, `check.sh` and `acceptance/`; R0094.md, R0095.md; `pickman/.tracker/game-design.md`; `z-nile/engine/main.luau` (ready's `depends_on` refusal); the z-raft lessons; a joint run in a throwaway `git clone --no-hardlinks` under `$TMPDIR` (below).
Grouped: [c0176@dbb95d47c319, c0177@0a19d9c5e821]

Checked and sound, so not raised:
- **Files.** `git apply --numstat` of the two patches: c0176 changes `c0153/golden`, `f0023/session-ghosts`, `f0100/drops`, `f0100/shots` and `f0101/airborne` (22+, 9-); c0177 changes `f0125/speeds` (71+, 15-). No file is in both, and neither touches `src/`. Since the grouping, the branch has changed only the two `raft:` lines and the raft document.
- **Bases.** All six blobs, at HEAD and at origin/main, equal the blobs in the members' step 1.
- **The pins don't cross.** c0176's `narrowed.spec` reads its five files and `done/{f0023,f0100,f0101,c0153}/check.sh`. c0177's reads `speeds.spec` and `done/f0125/check.sh`. Neither member changes a file the other reads. `git grep` of the six paths over `pickman/tests`, every issue and every raft finds only these other readers: their own items' `check.sh`, f0147's AC5 (it runs them and pins no text) and c0153's golden (c0176's override). The four c0176 files never read `ghostTuning`. Apart from f0147, no open issue's Touched modules or Overrides name any of the six.
- **Joint run.** Done in a clone at bc9d26d51 with both patches applied, each step through `./zn run`. `./zn check c0176` passed 2 of 2 and `./zn check c0177` 2 of 2. `z-nile/check.sh --project pickman --affected` passed: format, lint, types, both builds, and 6 spec files at 82 of 82. `./zn promote-check R0101` printed OK. This reproduces the Experiments phase claim and adds the gate and the promote-check.
- **Waits.** c0177's only `depends_on`, f0125, is in `done/`, and c0176 has none. f0147 has `depends_on: [f0126, f0125, c0176, c0177]`. f0126 and f0125 are done, so c0176 and c0177 are its last two. The other waits of R0094's members (f0146, d0151, f0126, f0109, c0159, f0110) are all done. `./zn ready` refuses a member whose dependency outside the raft is not done (`main.luau` 3619–3634), so "z-ready refuses R0094 until they are done" holds. R0094's own Cross-raft waits names both chores. f0147's design pins what c0177 reads loosely: its Interface names `Levels.Ramp.top`, `Levels.ghostRate` and `Set.ramp`, and its ramp.spec checks `R.top == 34`.
- **Order.** Free, as stated. Each member's step 1 reads `HEAD:` blobs that the other layer does not touch.

### F1 [medium] The Theme's quoted user decision is not in the repository, and it states a different factor
Where: R0101.md, Theme, third paragraph.
Evidence: The Theme says `User decision quoted by the designs: game-design.md's Slower-ghosts row, "Ghosts are 10% slower, as a tuning multiplier on the level tables" (f0125)`. `git grep -n 'tuning multiplier on the level tables'` finds only R0101.md. The row (game-design.md:21) reads "Ghosts run at **1 / 1.1** of the classic hunting, tunnel and frightened speeds, never changing the eyes, through `Session.GAME_CONFIG.ghostTuning` (f0125).", and c0177's Design quotes exactly that.
- Read literally, "10% slower" is ×0.9. The shipped `ghostTuning` is `1 / 1.1` (`Session/init.luau:172`), about 9.1% slower, and that is what makes the player 10% faster (f0125's title).
- "On the level tables" is the very baseline c0177 replaces.
- The Theme does not quote c0176's relied-on decision at all: game-design.md, Scoring and rules, "**Levels** (the classic rules, kept for the default config the specs use; the shipped game follows *Levels by picked walls*, f0147)".
Critique: z-raft §3 asks the Theme for "the user decisions their designs quote", and raft mode asks whether it quotes them. This line is an agent's paraphrase, in quotation marks, credited to the user. z-ready carries the raft document into the prompt that the executor and the final reviewer read. The tempting fix is a better paraphrase, which is still the same defect.
Consequences: Quoting word for word makes the Theme longer. It also puts c0177's added sentence next to the user's, and that sentence is c0177's prep's, so it must not read as the user's. This is not an edit to a member's design: the grouped record is unchanged and no new review is needed.
Recommendation: Replace the paragraph with the two decisions, copied word for word from the members' Design lines:
- c0177's: the Slower-ghosts row's sentence above, then "c0177's prep added: …" for the "(On the shipped ramp, …)" sentence, marked as the prep's and not the user's.
- c0176's: the Levels line above.
Check: `git grep -nF` of each quoted string finds it in `pickman/.tracker/game-design.md`.
Lesson: z-design/agents-quote-the-users-words

### F2 [medium] No RC backs "only spec files change, so nothing in the game moves", and the Exit criteria say no RC could
Where:
- R0101.md, Theme: "neither changes anything in `pickman/src/`".
- Whole-raft design: "No change to `pickman/.tracker/architecture.md`".
- Risks & rollback: "Only spec files change, so nothing in the game moves".
- Exit criteria: "No raft-level RCn checks are added: the members share no file and no interface a raft check could test beyond their own".
- check.sh: no RC lines after RC0.
Evidence: Nothing in check.sh fails when the raft changes a game file. Each member's digests pin only that member's own files, and each AC2 only runs specs. Suppose an executor makes a compatible change to `src/shared/Logic/Session/init.luau`, for example to make a narrowed case pass: those specs stay green. Neither member can pin this itself. c0176 deliberately has no branch diff (zz-test/no-change-claims-check-behaviour-not-the-raft-diff), because a member can't tell its own changes from its raft mate's. The raft is the one level that knows the union of both.
Probe, in the scratch clone: `git -C pickman diff --quiet origin/main...HEAD -- src default.project.json lobby.project.json scripts .tracker/architecture.md` exits 0 with both patches committed, and 1 after one more committed line in `Session/init.luau`. On this branch it exits 0. Precedents: R0032's RC2 and R0037's RC1.
Critique: The rollback claim and the Theme rest on a statement that nothing checks, which is exactly what the lesson covers. The tempting fix is a Risks sentence saying the code review will catch it, and that is not a check.
Consequences:
1. If an emergent member of this raft really needs a game file, RC1 goes red. Once the raft is readied the RC is sequestered, so that becomes a stop-and-escalate. That is the right outcome, because the raft's rollback statement would then be false. Risks should say so.
2. RC1 is a negative claim, so it passes on a branch where nothing has been executed yet. The positive side (the six files are the narrowed ones) is already pinned by the members' digests, so no second RC is needed.
3. Adding RC lines changes the raft's `check.sh`, not a member's design, so the grouped record stands.
Recommendation:
- Add to check.sh, after the RC0 lines: `check "RC1: no game file changes: src, the place projects, scripts and architecture.md are as they were when the branch left main" git diff --quiet origin/main...HEAD -- src default.project.json lobby.project.json scripts .tracker/architecture.md`. ac.sh runs it from `pickman/`.
- Replace the last sentence of the Exit criteria with what RC1 pins.
- Add the emergent-member stop to Risks.
- Run RC1 on this branch (it passes) and on a scratch clone with one committed `src` line (it fails), and record both results.
Lesson: z-raft/rc-pins-the-claims-it-makes

### F3 [low] Two member facts are misstated: "step 0", and what landed with c0177's prep
Where: R0101.md, Experiments phase ("Each member's step 0 checks the base blobs") and Risks ("the member's step 0 stops"); Whole-raft design ("The one sentence c0177's design adds to game-design.md's Slower-ghosts row landed with its prep").
Evidence: In both c0176.md and c0177.md, the base-blob check is step 1 of the Implementation steps. c0177's prep commit 3d412ca07 also changed `done/f0125/check.sh`: the AC1 and AC3 labels. c0177's `narrowed.spec` reads that file and counts five `check "` lines that run speeds.spec.
Critique: An executor looking for "step 0" finds none. A reader judging what changed outside the raft misses an edit to a finished item's `check.sh`.
Consequences: none.
Recommendation: Write "step 1" in both places. Add "and the AC1 and AC3 labels of `done/f0125/check.sh` (commands unchanged)" to the Whole-raft sentence.

### F4 [low] Cross-raft waits names only R0094, but more work waits on this raft through it
Where: R0101.md, Cross-raft waits.
Evidence:
- f0148 (R0095) has `depends_on: [f0147]`.
- d0149 (R0066) and c0182 depend on f0143 and f0158, which reach `done/` only with R0094 (R0094 design-review-001 F1).
- c0196 has `depends_on: [f0147, f0158]`.
- R0095.md:32 still describes c0176 and c0177 as "still `new` with no raft on 2026-11-12".
Critique: How much this raft unblocks is its priority, and a lead choosing the next raft reads this section.
Consequences: none. The stale text in R0094 and R0095 is theirs, and this raft needs no edit there.
Recommendation: Add one bullet: "Through R0094 also: R0095 (f0148), R0066 (d0149), c0182 and c0196."

Lesson candidate (for the lead to harvest; a reviewer writes no lesson file):
- Skill: z-raft.
- Rule: a Theme quotes each member's relied-on decision by copying the member's own quoted line, and never paraphrases inside quotation marks.
- Why: R0101's Theme put an invented sentence in quotes as the user's decision, and that sentence stated ×0.9 where the decision is 1 / 1.1.
- Check: does `git grep -F` of every quoted string in the Theme find it in game-design.md or in the member's document?

Verdict: changes
