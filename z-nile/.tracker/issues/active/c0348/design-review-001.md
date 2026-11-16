# Review 001: c0348 (design mode)
Inputs: worktree `prep-deliver-spend-reaches-main` at 7986ad97b (origin/main aa0c8fdbd: same engine, skills and specs except lessons), with the uncommitted `c0348.md`, `check.sh`, `acceptance/` (deliver-publish, docs, overrides) and `experiments/` (prototype.patch, overrides.patch, mutants.py, affected.txt); `./zn capture c0348` (capture 7970e51d4, no marker); `cmd.spend` in `z-nile/engine/main.luau`, `publish.luau`, `costrow.luau`, `buffer.luau`, `dispatcher.luau`, `trackerstate.luau`; zz-rules, zz-execute; prepared c0325 and c0278. Probes ran in a throwaway clone under `$TMPDIR` with both patches applied, each through `./zn run --time`.

### F1 [high] The deliver publish sends the worktree's whole spend.d file, so rows a branch recorded for other phases reach origin/main with it, and AC1 and AC2 pass anyway
Where: c0348.md Design, `cmd.spend` step 1 ("`build` returns … the file's whole new text (`PlannedFile.text`: what the worktree's file held, plus the new row)"), and `publish.luau` (`measuredReason` takes any rows that parse after origin's bytes); experiments/prototype.patch, the `build` closure in `cmd.spend`; the History paragraph ("This design publishes that one row and nothing else"); The rule ("capture, prep, design-review and `--begin` never publish"); AC1 ("one commit that only appends it"), AC2.
Evidence: in the clone, I copied deliver-publish.spec and added one case right after "the other phases never publish…". It skips `onMain()` and runs `./zn spend c0010 --phase deliver --note probe-deliver`. The command printed `published c0010 deliver to origin/main 56d0dbe…`, and the published diff of `pickman/.tracker/issues/done/c0010/spend.d/m5-max.local-ea1d4411.tsv` added four rows: `capture`, `prep`, `design-review` (rows the case before had committed on the branch only) and the deliver row. The spec's own cases miss this only because each one starts with `onMain()` (`git reset --hard origin/main`), which throws the branch's rows away. The publisher has no rule that could refuse those rows: origin's bytes are a prefix and the text parses. Before #291, spend's publish built each row on origin's text (`ledger.append(read(spendPath), …)`, removed in 94fc92b40). This design builds on the worktree's copy instead.
It happens in any worktree whose copy of a done issue's `spend.d/<writer>.tsv` holds rows that are not on origin/main when it records a deliver row for that issue. `spend` refuses only active items, so a branch can record any phase for a done issue, and this spec does exactly that. c0084's prep-worktree case has the same shape. The raft worktree right after `./zn done` is not affected, because its files equal origin's, and that is why no case sees the leak.
Critique: the prototype breaks the design's own rule, and the acceptance criteria that state the rule pass it. Rows that belong to an unmerged branch reach main without CI. If that branch is abandoned, its rows stay on main. The tempting fix is to build the published text from origin's file (`read(path)` inside `build`) plus the new rows.
Consequences: building on origin's text alone makes the two copies differ. The local commit holds the branch's rows and the deliver row, while origin holds only the deliver row. Both sides then append different lines after the same base, so the branch's later merge conflicts on the file (z-design/one-file-two-write-channels). Limiting the validator to `deliver` rows alone would refuse rows the same call legitimately folds from the measure buffer: `other` rows from `./zn run`, `test` rows from the runner, and the dispatcher's `code-review` line in the author's buffer. A raft's deliver publish could then fail closed. AC1's "only appends that row" is also imprecise today: the call publishes every buffer line it folds.
Recommendation:
1. In `cmd.spend`, after the command's own fetch, compare each planned file's `previous` (the worktree's text before this call) with origin/main's text at that path (`git show origin/main:<path>`, nil when absent). Publish only when the two are equal for every file. The published append is then exactly what this call adds, and the local commit holds the same bytes. The other outcomes:
   - origin's text extends `previous` (the worktree is behind, for example after an F2 warning): fail before writing anything, record nothing, and say "run ./zn sync, then record again".
   - `previous` extends origin's text (this branch holds rows that have not landed): do not publish. Commit on the branch only, as for an item that is not done, and print on stderr `spend: <id>'s rows on this branch are not on origin/main yet, so its deliver row stays on this branch and reaches main with it` (exit 0).
   - neither text extends the other: fail, record nothing, and name the file.
   The publisher's prefix rule stays as the guard against a race on each retry.
2. Add a validator rule (lesson below): `measuredReason` also refuses an append whose new rows hold no `deliver` row, and any new row of a phase whose command commits on its branch at once (`capture`, `prep`, `design-review`, `build`). Before relying on that, list every writer of the measure buffer (`--begin` lines, `./zn run` and runner lines, the dispatcher's code-review line) and confirm none leaves such a row pending.
3. Spec cases:
   - (a) deliver-publish: commit a capture row for done c0010 on the branch with no reset, then record deliver. It exits 0, origin's main does not move and holds no capture row, the new note is on stderr, and the branch holds the deliver row.
   - (b) a worktree behind origin: non-zero exit, nothing recorded, the sync advice.
   - (c) the publisher refuses an append of only a capture row ("no deliver row") and an append of a deliver row plus a prep row, and accepts a deliver row plus an `other` row.
   Add Rules rows with their mutants, both run: no equality check (killed by a), no phase rule (killed by c).
4. Reword AC1 ("appends only the rows this call records: its deliver row and the measure lines it folds"), AC2 (add the case of rows on the branch) and the History sentence. Reword zz-rules' deliver line ("For an item that is not done, or whose rows on this branch have not landed, it commits on the current branch only, and says so"), with docs.spec pins. zz-execute Phase 6 step 2 must also say what to do if either "stays on this branch" note appears at that step: the row would be lost at the cleanup, so do not clean up; post `BLOCKED:` quoting the note. In Scalability, add the one `git show` per planned file.
Lesson: zz-arch/validators-restrict-which-rows

### F2 [medium] A local commit that fails after a successful publish leaves the index staged. `./zn sync` then leaves the row's file deleted, and a re-run is refused with advice that was just followed. The row stays "reasoned" on a reason that does not hold
Where: c0348.md Design, `cmd.spend` step 4; Rules and mutants, last row ("reasoned (see Unknowns: no fixture can break the local commit alone)"); Unknowns, "Left for the executor"; prototype.patch, the `if not added.ok or not committed.ok` branch.
Evidence: in the clone, a case writes a `pre-commit` hook (`exit 1`) into the fixture worktree's common git directory (`git rev-parse --git-common-dir`, then `hooks/`) and runs `spend c0010 --phase deliver`. The fence's `z-nile/lib/git-hooks/pre-commit` stub runs the repository's own hook. As designed, the command exited 0, stderr said `the row is on origin/main (4d58d73…) but could not be committed here (pre-commit refused by the probe): ./zn sync brings it`, and origin moved. But `git status --porcelain` showed `AD …/spend.d/m5-max.local-ea1d4411.tsv`: the `git add` stays staged, and `costrow.restore` removed only the working file. After I removed the hook, `./zn sync` printed `synced to 4d58d73` and HEAD equalled origin's main, yet the status was ` D …tsv`: the file is missing from the working tree. A second `spend c0010 --phase deliver` then failed with `not an append to its rows on origin/main (run ./zn sync, then record again)`, advice that had just been followed. zz-rules, Landing a change, step 4 runs `git worktree remove <path>` without `--force`, which refuses this dirty worktree, and the `branch -D` after `&&` never runs.
Critique: the warning's promise ("./zn sync brings it") is false, and Phase 6's cleanup stops on the state it leaves. The row was left reasoned because "no fixture can break the local commit alone". A hook in the fixture's own repository does exactly that, the way AC3's case already uses `pre-receive` on the bare origin. The tempting fix is to keep the row reasoned and only reword the warning.
Consequences: the unstage (`git reset -q -- <paths>`) can fail for the same cause, an index lock for example. The same staged leak exists on the commit-failure path with no publish, which says "nothing recorded" but leaves the index staged. The prototype's shared branch serves both paths.
Recommendation: on a failed `git add` or `git commit` after a publish:
1. Unstage the written paths (`git reset -q -- <paths>`), then restore them, so the tree is exactly what it was before the command.
2. Call `costrow.writeBuffer`, because the row is recorded.
3. Warn with the sha, say that this checkout does not hold the row, that `./zn sync` brings it, and that it must not be recorded again. Exit 0.
If the unstage fails, the warning names the two commands to run by hand. Unstage on the path with no publish too.
Spec case in deliver-publish, with the hook technique above: exit 0, the warning, origin moved by one commit with one row, `status --porcelain` empty and HEAD unchanged. Then, without the hook, `./zn sync` leaves the worktree's file equal to origin's and the tree clean, and a second deliver publishes exactly one more row. Rules rows, both run: no unstage (the status is not clean), and fail instead of warn (non-zero exit). Replace the "Left for the executor" paragraph.

### F3 [medium] zz-rules' "The direct-push exception" still says `./zn spend` pushes nothing and lists no spend.d file. The Restated rules sweep missed it
Where: z-nile/skills/zz-rules/SKILL.md:196 ("A published change is a tracker-only commit: only `<root>/(issues|rafts)/<ID>/<ID>.md` and `check.sh` … An issue's `spend.md` is not pushed by `./zn spend`: the command commits the appended row on the current branch, and the row reaches main with that branch."); c0348.md, Chore checklist, "Restated rules", which names only the three skill lines, the comment and the spec header.
Evidence: after this change, `./zn spend <id> --phase deliver` pushes `<root>/issues/done/<id>/spend.d/<writer>.tsv` to main. That bullet is the canonical list of what may reach main without a pull request. It lists no such path and says the opposite about `./zn spend`. docs.spec's absence case searches the skills only for "record it before the merge", so it stays green.
Critique: this is the lesson's defect: a restated rule left contradicting the new one. Anyone who reads the direct-push rules, such as a reviewer judging a publish change or the next prep that widens the publisher, is told this push cannot happen.
Consequences: several checks pin that bullet:
- c0081's promoted skill-doc.spec (`z-nile/next`, "only go up");
- done c0084's check.sh (`spend.md` on that line);
- done c0072's check.sh (`./zn land` on that line);
- prepared c0278's docs.spec, which adds its own pins to the same bullet (``one added `wont_do:` line``, "never again once closed").
The edit must keep every one of them, and whichever of c0278 and c0348 lands second merges the two texts.
Recommendation: add to that bullet, on its one line: "and a done issue's `spend.d/<writer>.tsv`, rows appended only and only with a `deliver` row, which `./zn spend <id> --phase deliver` publishes once the work is done on `origin/main` (c0348)". Replace "An issue's `spend.md` is not pushed by `./zn spend`…" with a sentence that keeps `spend.md` but says that only the deliver case is pushed. Add a docs.spec case that pins the bullet (`spend.d/<writer>.tsv`, `--phase deliver`) and the absence of "is not pushed by `./zn spend`", and that re-asserts the four pinned substrings. List the bullet under Restated rules and name c0278 under Existing work (F8).
Lesson: z-design/restated-rules-move-together

### F4 [medium] The failure path's "the measure buffer is not rewritten" has no Rules row, and its mutant survives
Where: c0348.md Design, `cmd.spend` step 2 ("the measure buffer is not rewritten"); Rules and mutants (no row); deliver-publish.spec, "a deliver publish that fails records nothing…", which checks only HEAD, the status, origin and the row counts.
Evidence: in the clone, I added `costrow.writeBuffer(top, planned)` before `costrow.restore(planned)` in the failed-publish branch, and deliver-publish.spec still passed 8 of 8. With that mutant, a failed publish drops the lines it folded: the deliver `--begin` the case before left, and any `./zn run` or runner lines. The retry then records a row without its span or those rows, and every assertion stays green.
Critique: the Design states a rule that no case checks. "Records nothing" includes the buffer.
Consequences: the buffer is ignored state, at `<top>/.cache/measure.tsv` (`costrow.bufferFile`). Asserting on its bytes ties the case to that path, which is stable.
Recommendation: in the failure case, read `{wt}/.cache/measure.tsv` before the failed run and assert it is byte-identical after it. After the successful retry, assert the deliver `begin` line is gone. Add the Rules row (mutant: `writeBuffer` on a failed publish), run it, and record it in E4.

### F5 [low] Two spec headers name the wrong criteria
Where: acceptance/docs.spec.luau:2 ("c0348 AC4"; it checks AC6), acceptance/overrides.spec.luau:2 ("c0348 AC5"; it checks AC7).
Evidence: the AC list was renumbered. The headers now point at AC4 (the publisher's path rule) and AC5 (the landing fixture).
Critique: both files are sequestered once prep merges, so the headers can only be fixed now.
Consequences: none.
Recommendation: change the headers to AC6 and AC7.
Lesson: z-design/restated-rules-move-together (its cross-reference clause)

### F6 [low] docs.spec's inputs row leaves out `z-nile/engine/main.luau`, which the spec reads
Where: Implementation step 5; acceptance/docs.spec.luau:61 (`fs.readFile("engine/main.luau")`).
Evidence: `z-nile/tests/inputs.tsv` is how the selector learns which text files a spec reads (c0239's docs.spec has one row per skill it reads). docs.spec requires no engine module. Without a row, a later `main.luau` edit that brings back "pushed nowhere" does not select it under `--affected`.
Critique: the absence pin in the engine runs only under `--full`.
Consequences: none.
Recommendation: add `tests/acceptance/c0348/docs.spec.luau	z-nile/engine/main.luau` to step 5's list.

### F7 [low] mutants.py rewrites the engine in whatever checkout it runs in, and E4 does not say how it was run
Where: experiments/mutants.py, which writes `z-nile/engine/main.luau` or `publish.luau` in place, runs `lune run tests/run` per mutant with no bound, and restores in `finally`; Unknowns, E4.
Evidence: the docstring says "Run from the checkout's top, on a tree that holds the prototype". Nothing stops it in a worktree of the real repository. A kill between the write and the `finally`, for example when `./zn run --time` reaches its limit, leaves a mutated engine. E4 records neither the checkout nor `./zn run`.
Critique: the script can change a real checkout, and the record cannot show it was bounded (zz-review items 9 and 12).
Consequences: none.
Recommendation: record in E4 that it ran in a throwaway clone through `./zn run --time <s>`. Make the script refuse unless the checkout's top lies outside the real repository, for example unless `git rev-parse --git-common-dir` is under `$TMPDIR`, or under a path given as its first argument.

### F8 [low] Existing work does not name the two prepared items that edit the same lines
Where: c0348.md, Chore checklist, Existing work; Implementation step 1.
Evidence: prepared c0325 changes `cmd.spend` (`--model` and `ZN_MODEL` on capture and prep rows) and the same zz-rules `spend` row: its prototype.patch rewrites that row. Prepared c0278 edits the direct-push bullet that F3 must edit. Step 1 checks only the two override blobs. Once c0325 lands, prototype.patch no longer applies and the zz-rules sentence the Design quotes has moved. I checked docs.spec against c0325's row: its prefix ``| spend | `./zn spend <id> --phase`` and its substrings survive. c0325's refusals apply only to marked items, so c0348's fixture specs are unaffected.
Critique: whoever executes c0348 after c0325 lands has no instruction for a moved base.
Consequences: none.
Recommendation: name both items under Existing work, with that result. Add to step 1: if `cmd.spend` or the zz-rules spend row has moved, apply the Design by hand, using the prototype as a guide, and keep the docs.spec pins.
Lesson: z-design/design-the-execution-window (its "another prepared raft changes the same mechanism" clause)

## Checked, no finding
- Scope: the capture's check ("the row is on the fixture's origin main, or the two skills name one route") became, at the idea challenge, both outcomes. AC5 checks the first and AC6 the second. Nothing was dropped.
- Overrides: on the prototype, c0084/spend-command, c0081/publish-guard, c0053/publish, c0114/publish-roots and c0067/publish-move passed (59 of 59, with docs and overrides), as did the twelve promoted docs specs that read zz-execute or zz-rules (87 of 87). No other promoted spec pins the changed lines.
- The dispatcher records its deliver rows through its own `publishMeasured` on `zn-dispatch` and never calls `./zn spend`, so the Non-goal holds. `trackerstate` takes any path under a root, so the broker, the wrapper and the gates accept the new commit. There is no import cycle: `buffer` requires only `ledger`.
- check.sh: one check per AC in order, fixtures under `.cache`, only spec-runner commands, and the slow-tier spend-command run once.
- No `harvest.md`, so there are no author lessons to judge.

## Candidate lessons (for the lead to write)
- zz-test: a spec that resets its fixture before every case cannot see what one command leaves for the next. When a command publishes a file that other commands also write locally, one case runs it on the state an earlier command left, with no reset. Why: F1, where deliver-publish's `onMain()` before each case hid the leak. Check: does any case run the publishing command right after a command that does not publish wrote the same file, with no reset between them?
- zz-test: "no fixture can make it fail" is rarely true of a git step. A hook in the fixture repository's own hooks folder (`pre-commit` for a local commit, `pre-receive` on the bare origin for a push) fails one step alone, and the fence's hook stubs run it. Why: F2. Check: before marking a failure path reasoned because it cannot be produced, has a hook in the fixture's own repository been tried?
- zz-arch: a command that restores files after a failed `git commit` also unstages them. A restored working file over a staged index leaves the tree dirty, and a later sync leaves the file deleted. Why: F2. Check: after each failure path, is `git status --porcelain` empty, and does the advice in the message work from that state?

Verdict: changes
