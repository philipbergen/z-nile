# Review 004: R0025 (design mode)
Inputs: 6f8b93a (clean tree). Reviewed: R0025.md and check.sh; c0071, c0062, c0066 in full (documents, check.sh, c0066's acceptance spec); c0067–c0070 re-checked against design-review-003 and design-refute-003; `git diff origin/main -- tracker/issues/done tests/acceptance .github`; tests/acceptance/c0053/commands.spec.luau, c0038/deferred.spec.luau, c0049/spec-isolation.spec.luau; the done checks of c0037, c0038 and c0053; R0021 (active, branch `R0021-check-isolation` at d6ec749): R0021.md, c0058/c0059/c0060 documents, check.sh and acceptance specs, and the branch's `tests/tooling/repo-fence.spec.luau` and `tests/acceptance/c0053/commands.spec.luau`.
Dropped from review-003: none. F1–F3 are fixed as design-refute-003 states. c0067's AC11 greps only the five prep-edited done checks. RC5 runs c0008, and c0067's Regression guard lists c0008 AC3's phrases. c0067 step 2 gives both refusal texts, and ready.spec:283 checks for "clean". c0070's Callers paragraph gives the real order. c0067's USAGE bullet drops "to the clipboard".

Verification run for this round:
- `bash -n` and `AC_LIST=1` on the three new check.sh files list 5, 4 and 2 criteria.
- stylua and selene are clean on c0066's spec.
- c0062's 23 frozen names equal the current spec's `it(` names, read the way AC1 reads them (joined with `tr -d '\n\t'`).
- The c0049 scan finds no shared literal `.cache/<dir>` across `tests/` and the seven members' `acceptance/` folders (`sim` is exempt).
- c0037's check is red on `main` before this raft (AC2, AC6), as the documents say. c0038's AC3 and c0071's AC5 pass.
- c0062's AC4 command catches a planted `TypeError` without `--platform=standard`.
- A scratch prototype of `tests/lib/cleanup.luau` was run against c0066's spec (F3).

### F1 [high] R0021's gate scan and c0059's spec turn the gate red over this raft's specs and c0062's split, and no Overrides line names them
Where:
- R0025.md Risks ("The specs here follow its rules: … the `GIT_CEILING_DIRECTORIES` fence …");
- c0062 Design ("The GIT_CEILING fence is kept"; `setHook` moves to `tests/lib/trackerfix.luau`), Touched modules and Overrides;
- `GIT_CEILING_DIRECTORIES` in c0067 publish-move.spec:21/377 and ready.spec:22, c0068 stop.spec:22, c0069 prompt.spec:21 and c0070 board-refresh.spec:21;
- on branch `R0021-check-isolation`: `tests/tooling/repo-fence.spec.luau` (banned names at :19, `ALLOWED` at :82–113, the scan at :337–346);
- `tracker/issues/c0059/acceptance/adapt.spec.luau:17` and :107–110;
- `tracker/issues/c0059/experiments/c0059.patch:67`.
Evidence: R0021 is `active`, and its branch is in code review round 3. R0025 will start second, so by the raft's own rule ("Whichever raft starts second merges origin/main first") it executes on top of R0021. In that world:
- **The scan bans the fence.** repo-fence.spec scans every `.luau` under `tests/` and `scripts/`, and fails on any file that names `GIT_CEILING_DIRECTORIES`, `GIT_DIR`, `GIT_INDEX_FILE` or `GIT_WORK_TREE` unless `ALLOWED[path]` lists that name for that file. c0058.md:161 says promoted acceptance specs are scanned once they are in `tests/`. RC0 runs before `done` promotes anything, and `done` runs only `tests/meta` and the promoted specs. So `done` succeeds, and the PR's next full gate fails on five promoted R0025 specs. The PR can't merge, and the specs are sequestered.
- **c0062 keeps the fence** in `tests/lib/trackerfix.luau`, a scanned file with no `ALLOWED` entry, so the gate goes red during execution.
- **`setHook` moves.** Its hook body names `GIT_DIR GIT_INDEX_FILE GIT_WORK_TREE` (commands.spec.luau:80). `ALLOWED` permits those names only in `tests/acceptance/c0053/commands.spec.luau`, which c0062 deletes. Wherever `setHook` lands (the library or a part), the scan fails.
- **c0059's spec reads the deleted file.** c0059's `adapt.spec` (promoted to `tests/acceptance/c0059/` once R0021 is done) hard-codes `C0510 = { "tests/acceptance/c0053/commands.spec.luau", … }` and calls `fs.readFile` on it. Deleting the file turns that promoted spec red. Neither c0062's Overrides line nor R0025's Risks names it.
- **R0025 landing first breaks R0021.** c0059's patch, sequestered spec and design all target `commands.spec.luau`, so R0021's executor would hit a stop condition. Neither order is safe today.
- **c0060 rewrites the testing skill.** It says specs run git through `@tests/lib/fixture`, and names c0053's specs as "convert when next edited". c0062 edits them heavily and adds a second, parallel fixture library.
Critique: the tempting fix is to delete the six `GIT_CEILING_DIRECTORIES` lines and move on. That leaves the `ALLOWED` and `adapt.spec` breakages. If R0021 slips, it also leaves R0025's specs unfenced, which is the R0020 incident the fence exists for.
Consequences: R0025 becomes ordered after R0021. That is a dependency on another raft, so it needs a `depends_on` that `start` (or `ready`) enforces. c0062 then owns edits to two of R0021's files: the promoted `adapt.spec` (a chore may change S in its own raft) and `repo-fence.spec`'s `ALLOWED` table, a reviewed allowlist (review skill, Repository safety).
Recommendation:
- **Order**: put `depends_on: [c0058, c0059, c0060]` on c0062 and c0067 (the earliest), and say in Order & dependencies that R0021 must be in `done/` before `start`.
- **Member specs**: remove the five member specs' own `GIT_CEILING_DIRECTORIES`, since the runner fences after R0021. Correct the Risks bullet to R0021's real rules: no own fence, none of the scan's banned names, identities `@example.invalid`, fixtures under a unique `.cache/<dir>`.
- **c0062**:
  - build the parts on `@tests/lib/fixture` (c0060's helper), or justify `trackerfix` as a thin layer over it, with no fence of its own;
  - keep `setHook` (the only text that names `GIT_DIR`, `GIT_INDEX_FILE` and `GIT_WORK_TREE`) in exactly one file;
  - add to Touched modules and Overrides: `tests/tooling/repo-fence.spec.luau` (`ALLOWED`: move the c0053 fixture-hook entry to that file, keep `publish.spec`'s entry) and `tests/acceptance/c0059/adapt.spec.luau` (its `C0510` list becomes the part files plus `publish.spec.luau`, and its AC1 cases keep their names);
  - add a c0062 AC that runs `tests/tooling/repo-fence.spec.luau` and `tests/acceptance/c0059/adapt.spec.luau`.
- **R0025 RC**: add one that runs repo-fence.spec after a scratch promotion (or simply `scripts/check.sh --full` after `promote-check` in a scratch copy), so a scan-banned name in a sequestered spec is caught before `done`.

### F2 [medium] c0062's grouping has a cross-group dependency, and its fallback can't pass its own sequestered AC2
Where: c0062 Design "Grouping" and E1; check.sh `own_fixtures` (`-ge 4`); commands.spec.luau:504–565 and :245–285.
Evidence:
- **sync --fetch needs the start group's worktree.** "sync --fetch updates origin/main … new issue in a raft worktree does not merge" (group 4, `commands-sync`) runs in `{base}/main/.worktree/resume-r` (line 549), which "a start that dies after its claim is resumed" (group 3, line 510) creates with R0001 started on its branch. A seed commit can't recreate a worktree on a branch with a raft started in it, and `trackerfix.new(name, seed)` only seeds files. E1 will hit this.
- **The fallback contradicts AC2.** E1's fallback ("merge the two groups … AC3's 4-file floor becomes 3") can't be met: AC2, not AC3, holds the floor, and `check.sh` hard-codes `-ge 4`. The fallback is therefore an escalation, not a fallback.
- **The tracker-claim literal pins two cases together.** The literal `.cache/tracker-claim-R0001` appears in "a prepared raft starts once" (:270) and in "a start that dies …" (:518, :540, :542). c0049's gate fails if they land in different files, and the design says "the executor may regroup".
- **Group 1 and group 3 both list case 579.** Its one name ("raft ids come from the union … and an item made ready offline can start") appears as "raft ids from the union" in group 1 and as "an offline-ready raft that starts" in group 3. It also shares `offlineId` with the `PICKMAN_PUBLISH=0` case, so it must stay in group 1.
- **The setup case name must appear once.** "Each file has its own setup case", but AC1 requires "sets up a bare origin, a main checkout and a second terminal" exactly once across the parts.
Critique: none of these is fatal alone, but together they make E1 likely to land on the fallback, which then fails a sequestered check.
Consequences: fixing the grouping now removes the need for the fallback. Recording the c0049 and AC1 constraints keeps an executor's regrouping legal.
Recommendation: freeze the grouping in the design, with every case listed by start line:
- `commands-new` keeps the original setup name: 97, 123, 137, 148, 155, 567, 579, 620;
- `commands-claim`: 169, 199, 209, 216, 231, 297, 327, 372, 386;
- `commands-start`: 245, 489, 504, 546 (sync --fetch follows its worktree);
- `commands-sync`: 289, 418.

Also:
- the other parts' setup cases get new names (for example `sets up the <part> fixture`);
- the two `tracker-claim` cases must share a file (c0049);
- replace the E1 fallback with "split a part further (AC2 needs four or more), or escalate".

### F3 [medium] c0066's spec rejects a listing the design allows, and its lower bound on calls can flake under load
Where: c0066 Design ("left: <up to 20 relative paths>"); acceptance/cleanup.spec.luau `tree()` and "gives up after its bound and lists what is left" (:66–82).
Evidence:
- **The spec needs a breadth-first listing.** `tree()` makes 23 entries: `a`, `a/b`, 20 files in `a/b`, and `top.txt`. The case requires `top.txt` in a listing capped at 20. I wrote a prototype that follows the design exactly, with a depth-first walk in `readDir` order capped at 20. It fails this case 3 of 3 times, because the cap is reached inside `a/b` before `top.txt`. The same prototype with a sorted breadth-first listing passes 6 of 6 runs, in about 0.5 s. `readDir` order also differs between APFS and ext4 (CI), so even an unsorted walk that happens to pass on a Mac could fail on CI.
- **`calls > 1` can fail a correct implementation.** If the first `task.wait(0.05)` oversleeps past the 0.3 s bound (under a 65 s, load-14 gate), an implementation that checks the deadline before retrying raises after one call.
Critique: the tempting fix is to raise the listing cap. That hides the order dependence instead of stating it.
Consequences: the listing order becomes a rule and needs its own Rules and mutants row. The retry rule ("at least one retry after the first race, even when the bound is already spent") needs one too.
Recommendation:
- **Design**: the listing is breadth-first (shallowest first), sorted within each directory, up to 20 entries. After a race, `removeTree` always retries at least once before giving up.
- **Rules and mutants**, two rows: a depth-first listing, killed by `gives up … :: top.txt`; and a deadline check before the first retry, killed by `calls > 1`. That row needs a seam whose first call sleeps past the bound, so it is deterministic: for example `seconds = 0.05` and a seam that does `task.wait(0.1)` and then raises "not empty". Assert `calls >= 2`.
- Add the case to the spec now, in prep.

### F4 [medium] c0071's stop rule can end design review at a round that ticket-prep step 5.5 can't accept, and nothing says what happens then
Where: c0071 Design "The rule" and "Texts to change"; `.claude/skills/ticket-prep/SKILL.md` step 5.5 ("When the latest round has `Verdict: approve`, or only low findings remain and all are answered, set `design: ready`"); c0071 JC1.
Evidence: suppose round 3 has two medium findings, both fixed by rewording a sentence, so the answers are minor. Under c0071, round 3 is final: "Otherwise stop: that round is the final one". Step 5.5 still refuses `design: ready`, because mediums remain in the latest round. The rule sends questions to the user only after round 5. So the agent has a final round, no path to `ready`, and no instruction. JC1 ("decide 'next round or stop' … alone") can't pass, because the stop branch has no defined outcome. Today the same case goes to the user ("Stop after 3 rounds and bring the open questions to the user"). c0071 removes that sentence and replaces it with nothing for rounds 3 and 4.
Critique: the tempting fix is "a final round with mediums goes to the user". That re-creates the very escalation c0071 exists to avoid, for findings the agent already fixed.
Consequences: step 5.5 must accept a final round whose findings are all answered. A refuted (not fixed) high can't be final before round 5, because a high makes the round major. So the only open case is a final round with refuted mediums. Decide whether that needs the user (it doesn't today for code mode, where final-round mediums can be deferred).
Recommendation:
- **Step 5.5**: rewrite it in c0071 as "When the final round (step 5.4) has `Verdict: approve`, or every finding in it is answered `fixed` or `refuted`, set `design: ready`…". Keep `status <R-id> prepared`, which RC7 pins.
- **Round 5**: state that round 5 with an open high, or with an unanswered finding, goes to the user.
- **Touched and checks**: list step 5.5 under "Texts to change", and add a check that greps the `## 5.` section for `final round` near `design: ready`.

### F5 [low] c0071 leaves two round-3 texts in execute-raft step 7, and AC2's lowercase ban trips on natural wording
Where: execute-raft SKILL.md:93 (step 7: "answer it in `refute-003.md`", "(Rounds 1-2 need no such rule: …)", "Medium and low findings in `review-003.md` do not block"); c0071 "Texts to change"; check.sh AC2 (`grep -rnF … 'after round 3' .claude/skills`).
Evidence:
- "Texts to change" names only the `Cap:` sentence and the "If `review-003.md` contains any **high**" sentence. AC2 bans `review-003` everywhere, but not `refute-003`. So an executor can leave "answer it in `refute-003.md`" and "Rounds 1-2 need no such rule", which are wrong once the final round can be 1–5.
- AC2's case-sensitive `after round 3` also fails the plain sentence "rounds 4 and 5 run only after round 3 was major". The design's own wording ("After round 3, 4") passes only because it is capitalized.
Recommendation:
- List all four step-7 phrases in "Texts to change" (`refute-NNN.md` of the final round; "Rounds before the final one need no such rule"), and add `refute-003` to AC2's banned list in prep.
- Write in the design that the phrase "after round 3" must not appear in any case, or narrow AC2 to `Cap: 3 rounds` and `review-003`/`refute-003`.

### F6 [low] c0066's E1 "a wait" conflicts with AC3's exact grep, and its writer uses the raw shell string R0021's testing rule forbids
Where: c0066 Solution and E1 ("If the writer … can be stopped in the fixture (a config setting or a wait), the case does that as well"); check.sh AC3 (`it("cleans up", function()cleanup.removeTree(work)` with newlines and tabs stripped); cleanup.spec.luau:57 (`process.exec("sh", { "-c", … })`); c0060 "Rule in the documents" ("no shell strings").
Evidence:
- AC3 requires `cleanup.removeTree(work)` to be the first statement of `cleans up`. A wait added there, as E1 allows, fails AC3, and `check.sh` is sequestered.
- c0060's testing-skill rule, after R0021, says specs use no raw shell strings. c0060's scan covers only its twelve specs, so this doesn't go red, but the new spec breaks the rule on the day it lands.
Recommendation:
- E1: any stop for the writer goes in the spec's setup (config) or inside `cleanup.removeTree`'s caller before `it("cleans up")`, never in the `cleans up` body.
- Either run the writer through `fixture.exec` in a fixture directory, or record in c0066 why this spec is an exception (the tree is not a repository), so the code reviewer doesn't flag it.

Verdict: changes
