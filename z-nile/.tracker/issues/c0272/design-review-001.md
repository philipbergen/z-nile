# Review 001: c0272 (design mode)
Inputs: prep worktree `prep-lesson-superseding-prep-releases-claim` at dd890b57 plus its uncommitted files: `c0272.md` (blob 9f12b23e68), `check.sh` (ef04557bcd), `harvest.md` (4a67097725), `experiments/E1-takeover.sh`, `E2-prototype.sh`, `E3-walkers.sh`, `ref-lesson.md.txt` (472cae7cac), and `z-nile/skills/z-design/lessons/clone-experiments-drop-the-step-environment.md`; `./zn capture c0272` (07a3a465, no marker); `z-nile/engine/main.luau` (`mergeOrigin`, `setStatus`, `captureScope`, `cmd.sync`), `z-nile/engine/publish.luau`; zz-rules **Whose claim** and Worktrees; c0270's `experiments/ref-lesson.md.txt` and `ref-skill-bullet.txt` and c0271's `experiments/prototype.patch`, read from their prep worktrees.

I ran these myself: `./zn check c0272` (AC4 and AC6 pass, AC1, AC2, AC3 and AC5 fail on `missing:`/`no lesson at`); `lune run z-nile/affected -- <both touched paths>` (prints nothing) and `grep -rlF -e superseding-prep-hands-over-the-claim -e c0272/harvest -e superseding-prep z-nile/tests pickman/tests` (nothing), so **Overrides: none** holds. I also ran a bounded merge probe (`./zn run --time 60`, a `mktemp -d` repository removed at exit, commits as `rv@example.invalid`) and read the claim memories under the main checkout's `.worktree/*/.cache/`. Scope: the capture has no marker. The lesson's `check:` keeps the captured question word for word. Every captured place (the claim, the issue, the old PR) has a design and an AC; F1 and F2 are about whether two of those places work as designed.

### F1 [high] The `Prep moved` line under `## Design` conflicts with both preps' documents, so it never reaches the old worker and it breaks the live prep's next merge
Where: c0272.md Design, Decision 4; Unknowns & experiments, E1; `ref-lesson.md.txt` ("a `Prep moved …` line under its `## Design`"); check.sh `ac3` (pins "`## Design`"); AC3.
Evidence: a prep rewrites its own issue document. This prep did: it replaced the `<!-- Modules and paths… -->` placeholder that follows `## Design` on `origin/main`, along with Non-goals and the frontmatter's `size:`/`solo:`/`design:` lines. The superseded prep did the same on its own branch. I ran a probe in a throwaway repository with three branches. The base was `c0272.md` as at dd890b57. `live` was this worktree's `c0272.md`, with its status line kept at the base's. `old` was the same file with one Design sentence changed. Then I published on `main` what the lesson does:
- the take-over (`status:` → `new-…`, then `preparing-…`): `git merge main` into `live` is clean;
- then the line, inserted right after `## Design`: `git merge main` gives **CONFLICT on c0272.md** in both `live` and `old`.

The same line inserted right after `# c0272: …` merges cleanly into both. So does a line after `## Verification log`, which is the executor's section.

In a prep worktree, `./zn sync` is `mergeOrigin()` (main.luau `cmd.sync` → `mergeOrigin`). On a failed merge, that runs `git merge --abort` and fails with "merging origin/main failed (merge aborted)". So the old worker's document never holds the line, and the old worker gets an abort it has to resolve by hand, choosing a side inside its own Design. The live prep, the one the user kept, gets the same conflict on its next sync. Its PR conflicts with `main` until it resolves that. E1's "prep-old's next sync holds it" is the empty case: E1 makes both worktrees from `origin/main` and never edits `c0272.md` in either before the land.
Critique: the line is the issue leg of the captured check ("leave the new branch name on … the issue"). As written, it doesn't reach the other worker, and it damages the prep it points to. AC3 pins the wrong placement (`## Design`), so a corrected lesson fails check.sh. The tempting fix is "tell both preps to resolve the conflict". That adds a manual repair at every sync of both branches. The old worker is the one that reads nothing, so it won't follow the repair.
Consequences: a placement no prep edits stays clean. The line stays in the issue after the live prep lands. A second hand-over adds a second line, so the lesson must say which line is current. Any reader of the text right under the title would also see the line. I grepped `store.luau`, `board.luau` and `boardview.luau` and found no reader that takes the first paragraph after the H1, but the re-run should show it.
Recommendation: put the line directly under the issue's `# <id>: <title>` heading, newest first. The lesson body reads: "a `Prep moved (<date>): live on <branch> (PR #<n>)` line directly under its `# <id>: <title>` heading (the newest is the top one), landed from a `capture-<slug>` worktree with `./zn land`". This is outside the Problem and Solution, so the captured scope is untouched. `captureScope` takes any body line while `design: draft` holds on both sides and the status line is unchanged. Update Decision 4. In check.sh `ac3`, replace "`## Design`" with "`# <id>: <title>`". Re-run E1 so that, before the land, `prep-old` and `prep-live` each commit a rewritten `c0272.md`: the frontmatter `size:`/`design:` lines, Non-goals and Design replaced, with different text in each. E1 then asserts that:
- the land is accepted;
- both worktrees' `./zn sync` exit 0 and both documents hold the line;
- `./zn capture c0272` and the stamp are unchanged;
- `./zn status c0272` and `./zn lessons --check` still read the document.

Add a `run` mutant to E2, "the line placed under `## Design`", which AC3 must fail.
Lesson: z-design/design-the-execution-window

### F2 [high] The holder search fails from where the lesson is read, and after the take-over it names two worktrees, so "the claim" doesn't name the live branch
Where: `ref-lesson.md.txt` ("Find the holder: `./zn status <id>`, `ls .worktree/*/.cache/tracker-claim-<id>` (the worktree that made the claim)…"); Decision 3; E1; check.sh `ac3`.
Evidence: these were all run in the real repository:
1. The superseding session is a prep lead in its own prep worktree. From this prep worktree, `ls .worktree/*/.cache/tracker-claim-c0272` gives `ls: .worktree: No such file or directory`. Decision 3 says "(from the main checkout)", but the lesson body doesn't.
2. After the take-over, the search lists both the live worktree and the superseded one. Decision 3 and E1 both say the old worktree "still remembers the stale stamp". So "(the worktree that made the claim)" doesn't single out the live branch. The "on the claim" leg of the captured check, which Decision 3 defines as this listing, names two branches.
3. A memory's contents can't settle which worktree holds the claim:
   - `./zn status c0272` prints `preparing`, with no stamp.
   - Of the 50 claim memories under the main checkout's `.worktree/*/.cache/` today, 22 hold a `new-…` stamp. They include c0270's (`new-silver-lynx-copper`; `origin/main` has `preparing-lynx-falcon-badger`), c0271's, and this prep's own: `new-lynx-silver-marble`, written at 06:57:15, three seconds after dd890b57 published `preparing-marble-raging-sunny`.
   - The cause, which I read in the code: under dispatch, `publish.commit` pushes through the broker (publish.luau:601), which doesn't move the local `origin/main`. `rememberClaim` (main.luau:1686) then reads the document before it catches up. A take-over run by a dispatched session would remember the stamp it replaced too. That is Decision 2's path once the user answers `questions.md`. E1 ran with the broker unset.
4. Memories go stale: the incident's own superseded worktree, `prep-readme-states-znile-intent`, still holds `preparing-indigo-mongoose-amber` for c0264, which is in `done/` on `origin/main`.
Critique: the reader runs the search where it stands and concludes there is no holder. After the take-over, the claim still points at the superseded branch as much as at the live one. The tempting fix, "compare each memory with the stamp", fails for every dispatched claim (item 3). Item 3 is also a defect in the engine itself (see Candidates).
Consequences: removing the superseded worktree's memory makes the listing exact. That file is an ignored `.cache` file in another session's worktree. Its only readers are `release` (rafts) and z-raft's carried move (main.luau:1583), and neither runs for this issue in a superseded prep. If the user later revives the old prep, it claims again there, which rewrites the memory. The additions take the body from 1,042 bytes to about 1,200. That cap is the design's own (c0270/c0192), not captured scope: trim elsewhere or state a new cap with its reason.
Recommendation: in the lesson body:
- (a) The memory search runs from the main checkout. Say so ("from the main checkout, `ls .worktree/*/.cache/tracker-claim-<id>`"), or give the form that works anywhere: `ls "$(git rev-parse --path-format=absolute --git-common-dir)/../.worktree/"*/.cache/tracker-claim-<id>`.
- (b) Before the take-over, every listed worktree is a candidate holder. Pair it with `git worktree list | grep -e <id> -e <slug>` (prints each branch, as c0270's bullet does) and `./zn dispatch status <id>`. Never decide by a memory's contents.
- (c) After the take-over, remove the superseded worktree's memory (`rm <main checkout>/.worktree/<old>/.cache/tracker-claim-<id>`), so that the listing names only `.worktree/<live branch>`. Say that this is how the claim names the live branch (zz-rules Worktrees: a worktree is `.worktree/<branch>`).

In check.sh `ac3`, pin "from the main checkout" and the `rm` step. Extend E1 to:
- run the search from inside a worktree using the lesson's form;
- seed a second, stale memory before the take-over;
- assert that after the take-over and the removal, the listing is exactly `prep-live`.

Add `run` mutants to E2: the removal dropped (AC3), and "from the main checkout" dropped (AC3).
Lesson: z-design/instructions-runnable-where-they-run

### F3 [medium] AC4's `land` clause can't fail
Where: check.sh `ac4`, line 62 (`has_all … "land"`); Rules and mutants, row "the commands it names exist" (`reasoned`).
Evidence: `has_all` is `grep -qF`. `./zn help` contains `land` on line 16 (`land [-m <message>]`), line 61 (`done <R-id> … land the stack`) and line 63 (`watch-kick … after a landing`). A usage table with the `land` command removed or renamed still passes AC4. The `dispatch stop` half of the row is `reasoned` because "renaming a command in a clone means editing the engine's usage table". That is a one-line `sed` on `main.luau` in E2's clone, the same edit M13 already makes and restores for every mutant.
Critique: AC4's job is to fail when a mechanism the lesson names moves. For `land`, it only checks that some word containing "land" is there.
Consequences: none beyond the pinned string.
Recommendation: in check.sh `ac4`, pin `"  land [-m <message>]"`, the usage line's exact text, which occurs once. Run both rows in E2: `sed` the `land [-m <message>]` and `dispatch stop|retry|status <id>` usage strings in the clone's `main.luau`, and expect AC4 to fail on `missing:`. Mark them `run`.
Lesson: zz-test/no-vacuous-pass, zz-test/order-pins-anchor-unique-text

### F4 [medium] Nothing checks where the body says the take-over runs
Where: check.sh `ac1` (pins "in the live prep's worktree" only in `front check`), `ac3` (pins "`./zn status <id> new`, then `./zn status <id> preparing`" with no location); Rules and mutants.
Evidence: suppose a body says "The claim: in the old prep's worktree, `./zn status <id> new`, then `./zn status <id> preparing`…", or drops the location entirely, while the `check:` line stays as it is. That body passes AC1, because the location is matched in the frontmatter's `check:` only. It also passes AC3, whose string has no location. Where the take-over runs is the whole of Decision 3: run in any other checkout, the claim memory is written there. No mutant row lists it.
Critique: a plausible wrong lesson body, one that sends the take-over to the wrong worktree, passes check.sh.
Consequences: none.
Recommendation: in check.sh `ac3`, pin the body's own sentence: "in the live prep's worktree, `./zn status <id> new`, then `./zn status <id> preparing`". Add a `run` mutant to E2: in the body only, "live prep's" becomes "old prep's" (AC3).

### F5 [low] Three statements in the document don't match what they cite
Where: Decision 5; Unknowns & experiments, E2 and E1.
Evidence:
- Decision 5: "c0271's lesson makes the other worker read both before a push". c0271's prototype bullet reads `gh pr view <number or branch> --json state,comments`: the state and the comments, not the body. The comment still carries the name, so nothing is lost, but the claim is wrong.
- E2: "`./zn check c0272` fails 2 of 6". I ran it: AC1, AC2, AC3 and AC5 fail, so it passes 2 of 6.
- E1 lands "Prep moved (2026-11-15): the live prep is `prep-live` (PR #999); `prep-old` is superseded, do not push there." The lesson's format is `Prep moved (<date>): live on <branch> (PR #<n>)`.
Critique: a reader of Decision 5 might believe the body is read, and E1 didn't run the format the lesson teaches.
Consequences: none.
Recommendation: Decision 5 says that c0271 reads the comments (the body is for a person reading `gh pr view`). Change E2 to "passes 2 of 6 (AC4, AC6)". Make E1 write the lesson's exact format, with the F1 placement.

### F6 [low] The lesson doesn't say what to do when the other prep has no PR yet
Where: `ref-lesson.md.txt` ("The name: in the old PR's body and a comment, then close it").
Evidence: the Problem covers "preparing the same issue elsewhere", not only closing a PR. A prep often has no PR during design: zz-review's design mode runs "before any PR exists". c0271's bullet has its own case for "a branch with no PR yet". In that case the lesson's step has nothing to act on, and it doesn't say that the claim and the issue line are then the only places.
Critique: a reader with no PR to edit may think the hand-over is incomplete, or open a PR on the other worker's branch to comment on.
Consequences: a few more bytes of body (see F2's cap note).
Recommendation: "in the old PR's body and a comment (if it has one), then close it". check.sh `ac3` pins "(if it has one)".

### F7 [low] The harvested lesson `clone-experiments-drop-the-step-environment` recommends a guard that can never fire
Where: `z-nile/skills/z-design/lessons/clone-experiments-drop-the-step-environment.md` (How to apply; `check:`); E1/E2/E3, line 3 after `unset`.
Evidence: "unset … `ZN_PUBLISH_BROKER` … and exit if `ZN_PUBLISH_BROKER` is still set" comes straight after the `unset`, so the test is always false. E1 does exactly this. The lesson's list is also shorter than E1's: it omits `ZN_DISPATCH_HOME`, `ZN_DISPATCHER_PID`, `ZN_MEASURE_FILE`, `ZN_AGENT_GH_TOKEN` and `GH_CONFIG_DIR`. A reader who copies the lesson's list keeps the step's GitHub credential in the clone. The lesson itself is a good one, one that a different raft could fail; it is not a restated finding.
Critique: the guard gives false assurance. It passes even when a new step variable, one not in the list, still reaches the broker.
Consequences: none.
Recommendation: replace the dead test with one that can fail. After the unset, refuse while any step variable remains (`env | grep -q '^ZN_' && exit 2`), or, before the first publish, refuse unless `git remote get-url origin` is under the temporary folder. Give E1's full list, or "every `ZN_` variable and `GH_CONFIG_DIR`".

## Candidates (for the lead to capture or harvest; a reviewer writes no lesson)
- **A dispatched claim remembers the stamp it replaced.** This is an engine defect, not c0272's design. `setStatus` writes `rememberClaim(id, <the local document's status>)` after `mergeOrigin()`. A brokered publish doesn't move the local `origin/main`, so the memory keeps the pre-claim stamp. 22 of the 50 memories here do. It breaks any rule that compares a memory with the stamp (main.luau:1583's "one this checkout made"). Question that catches it: "does every claim or hold read state that is updated at the moment the claimed thing changes?" That is the check of `zz-arch/lock-reads-live-state`, which this repeats. Capture: `./zn new issue d dispatched-claim-memory-stale --project z-nile`.

Verdict: changes
