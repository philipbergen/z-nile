# Review 002: c0115 (design mode)
Inputs: `prep-c0115` at 3854e30 (the refute 2242670 plus the merge of c0120's prep 98b5154); `design-review-001.md`, `design-refute-001.md`, `harvest.md`; `c0115.md`, `check.sh`, `acceptance/*`, `experiments/rename-lesson-ids.luau`; the capture (`./zn capture c0115`, fb7fd80) and the `Decided` lines from ab750c0 and 4c2b747 on main; `./zn lessons --when design --full` (33 lessons); the prototype `proto-c0115` at b720763 on `proto-c0120` c9c6070; `impl-c0120` (c4e9c49) and `impl-r43` for what moved since. Run in two scratch clones under the scratchpad, never in the repository: the F2 probes again on the prototype; the move plus the rename script on the merged prep tree; the prototype with the merged prep tree's lessons and ledgers overlaid, then `./zn lessons --check` and AC3, AC4, AC5's specs.
Dropped from review-001: F1 to F9 (all fixed, checked below).

Re-review of round 001:
- F1: the lesson-id scan in `absence.spec` catches `architecture/guards-trust-only-origin` in `publish.luau`, and `testing/no-vacuous-pass` and `review/no-scope-cut-as-fix` in a skill, and leaves `zz-review/…` alone (spot-run in the scratch clone).
- F2: fixed. The old probe now refuses. With `.claude/skills` linked to an outside folder holding a foreign link, `./zn skills` exits 1 with `.claude/skills: a link (to …)`, and the foreign link survives with nothing written beside it. `--check` refuses the same way. A linked `.claude` is refused by both forms, and nothing is written in its target. A committed `.claude/skills` link (mode 120000) gives `tracked itself (mode 120000)`. `apply` checks `linkedParents` again itself. `readlink` treats a failure as "not a link"; that is safe here, because it fails only when the path is not a link or can't be read.
- F3 to F9: fixed as the refute says (steps 1, 9 and 10 fetch first; §11; the patch is committed; M37 to M45; the readme's token walk; §10's override; AC13).
- The rename on the merged prep tree: after the move (43 files, all `R100`, `execute-raft/lessons` included), the script rewrote 194 ids across five ledgers and two lessons, exited 0, and a second run rewrote 0. A scan of every ledger and lesson leaves no old id whose new lesson exists. The only hits are look-alikes inside `zz-review/…`. All 33 lessons land in a new folder. With the merged lessons and ledgers on the prototype, `./zn lessons --check` gives "33 lessons, 175 harvest entries, ok". The rename itself covers everything. Two of the specs don't (F1, F3).
- Scope (item 11): unchanged since round 001. The title, Problem and Non-goals match the capture. The Solution only gains the marked "(Added in prep)" block. No new scope commit for c0115 on main since 4c2b747.
- Guesses: G1 to G10 are as round 001 judged them. G11 is reasonable: c0114's AC13 sets the precedent. It runs at `./zn check` and `done` on the branch, before the squash, and c0034 only lists a finished item's checks.
- Overrides (item 4): since 0f79caf nothing outside the tracker changed under `tests/`, `pickman/tests`, `z-nile/engine`, `z-nile/lib` or `zn`. c0120's `homes.spec` on this tree is byte for byte the one at c9c6070, and c0120's `c0114-overrides.patch` is already in c9c6070. So round 001's override count stands.

### F1 [medium] AC5's "no lesson names an old skill's id" keeps the word-list rule that the refute removed elsewhere, and it fails on the prep tree's own lesson
Where: `acceptance/lessons.spec.luau` `oldIds` and the case "no harvest.md under any root, and no lesson, names an old skill's id"; §5; E4.
Evidence:
- Overlay setup: on the prototype, with the merged prep tree's lessons and ledgers overlaid after the rename (staged, so `git ls-files` sees them), AC5 fails: `z-nile/skills/zz-test/lessons/absence-scans-cover-every-form.md: tracker/next`.
- That lesson was written by this prep, and the prototype (21 lessons) never carried it.
- `oldIds` flags every `<old>/<word>` after a space, comma, backtick or parenthesis, in lesson bodies as well as ledgers.
- The refute fixed this exact look-alike problem in the rename script ("it now reports a missing id only in a `harvest.md`") and in AC4 (the existence filter). AC5 got neither fix.
- After promotion, any later lesson that mentions `` `tracker/next` ``, `(testing/…` or a similar path turns `tests/acceptance/c0115/lessons.spec.luau` red.

Critique: the tempting fix is to reword the one lesson. That leaves a promoted rule that forbids ordinary prose in every future lesson. It also leaves three copies of one rule: the script, `absence.spec`'s `oldLessonIds` and `lessons.spec`'s `oldIds`. Round 001 already found a hole in this mechanism (F1), and this is a second hole in it.
Consequences: lesson bodies and ledgers then need different strictness. A ledger token is always an id, and a missing one is a problem. A lesson-body token counts only where `<new>/<slug>.md` exists. That is the split the script already makes.
Recommendation:
- Give AC5's real-tree case the script's rule. Every `<old>/<slug>` in a `harvest.md` counts. In a lesson body, a token counts only where the mapped lesson exists and it doesn't follow `/`, `.` or a name character (`absence.spec`'s rule). Both specs could call one shared function, or each could keep the identical rule and run the same planted texts.
- Planted cases: a lesson body containing `` `tracker/next` ``, `scripts/tracker/x` and `testing/unknown-slug` passes, and one containing `testing/no-vacuous-pass` (where `zz-test/no-vacuous-pass` exists) fails.
- Add a mutant row: the body rule widened back to the word list.
- Rerun AC3 to AC6 against the merged prep tree's lessons and ledgers, not only the prototype's 21 lessons (lesson ticket-prep/prove-specs-pass-on-a-prototype).

Lesson: testing/absence-scans-cover-every-form

### F2 [medium] AC2 runs c0115's new `./zn skills --check` and its changed `--plan` in the real checkout, so a wrong `--check` writes `.claude/skills` and then passes on the links it wrote
Where: `check.sh` AC2; §4; M37.
Evidence: AC2 is `./zn skills --check && z-nile/check.sh --plan | grep -qx "skills: .claude/skills" && grep …`, run where `check.sh` runs: the raft's worktree, unjailed (`check.sh` files get no jail). M37 is the mutant "`--check` falls through to the write". Under M37, AC2 removes and writes links in that checkout and then reports ok on them. AC1 kills M37 in its fixture, but that doesn't stop AC2's write: every check runs, and order guarantees nothing. `--plan` is changed too, because it gains the `skills:` line.
Critique: the tempting answer is "AC1 already kills M37". The lesson exists because that answer was given before (c0120 review 001 F2).
Consequences: running `--check` in a copy checks the committed links, which is what CI's fresh checkout sees. That is stricter, and it is the intent ("a branch that forgot to commit a link fails there"). The gate's own stage still runs in place, because that stage is the product, not a check of it.
Recommendation:
- AC2 makes a copy of HEAD under `.cache/c0115-ac2`: a `git clone -q --no-hardlinks` of the checkout into a fresh folder there, never `git worktree add`, which writes the real `.git`. It runs `./zn skills --check` and `z-nile/check.sh --plan` there and asserts that `git status --porcelain` in the copy is empty afterwards.
- It keeps the `grep -qxF` of the stage line, which only reads the real file.
- Add a mutant row: M37 against AC2, killed by the clean-status assertion.

Lesson: testing/new-commands-run-in-a-copy

### F3 [low] The document's base and counts no longer match the merged prep tree, and §11 covers only c0120
Where: the Design intro; §1 and §3 ("its four lessons"); G3; AC3; E4; Verification log; §11.
Evidence:
- The merge brought R0043's later edits to the testing skill: the Writers and Gate spec bullets, which now name `z-nile/`, and the Hooks line. c9c6070, and so the prototype's `zz-test`, lacks them. `impl-c0120` has them.
- §11 (a) rechecks only "every line c0120 adds or changes". It says nothing of R0043, which sits under c0120 in the same stack.
- `architecture/lessons` now holds five lessons, including R0043's `guard-no-is-explicit`. Yet §1, §3, G3 and AC3 say four, and §4 cites `zz-arch/guard-no-is-explicit` "where it exists".
- E4 says 185 ids, and the log says "30 lessons, 166 entries". On the merged tree it is 194 ids, and 33 lessons with 175 entries.

Nothing breaks, because the move is a folder `git mv`, but an executor who starts from the prototype will hit cherry-pick conflicts in `zz-test` that no step names.
Recommendation:
- §11 names the whole stack under c0115 (R0043, then c0120) and the merged base this round was measured on. Item (a) becomes "every line the stack adds or changes in `testing/SKILL.md`".
- Say "every architecture lesson (five on the prep tree)".
- Refresh E4 and the log with this round's numbers.

### F4 [low] The rename rewrites a historical example in a lesson body into a false statement, and AC4 forbids restoring it
Where: `testing/lessons/absence-scans-cover-every-form.md` ("**Why:** … `testing/no-vacuous-pass` left in a skill and `architecture/guards-trust-only-origin` in a code comment passed both absence specs"); §5 "Text".
Evidence: after the script runs, the Why reads "`zz-test/no-vacuous-pass` left in a skill … passed both absence specs". That misstates review 001 F1, which was about the old id. `absence.spec`'s lesson-id scan then fails if the old token is put back.
Recommendation: reword the lesson now, so its example names the old id without writing it as a token (for example "the old testing-skill id of no-vacuous-pass"). Or add to §5 that lesson bodies quoting an old id as history are reworded by hand after the run.

## Lessons
Candidate (for the lead, not written by the reviewer). zz-test: a rule enforced in several places (a migration script and two specs) is one function, or every copy runs the same planted cases. Why: c0115 review 002 F1: the look-alike fix reached the script and AC4 but not AC5, which then failed on the prep's own lesson. Check: "For each rule this design checks, where else is it implemented, and does every copy pass the same planted texts?"

Verdict: changes
