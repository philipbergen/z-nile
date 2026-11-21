# Review 001: d0328 (design mode)
Inputs: prep worktree `.worktree/prep-spend-session-cwd-slash` at f919a8ece2f9e44365e19dfe4445cd96b2dc7afd (= origin/main) with its uncommitted `d0328.md`, `check.sh` and `acceptance/spend-session-cwd.spec.luau`; `z-nile/engine/sessionread.luau` (unchanged from main); `z-nile/tests/tooling/work.spec.luau:275-290, 421-432`; `z-nile/tests/acceptance/f0399/land.spec.luau:747-770`; capture commits 9638a8b8c / 3cadd2cef and idea revision 3290615a3; `~/.claude/projects` on this machine (read only).

Checks run: the acceptance spec on today's code fails both cases on `expected "claude-opus-4", got nil` (spec lines 38 and 45), as E3 says. `lune run z-nile/affected -- z-nile/engine/sessionread.luau` prints the 20 specs the document lists. `stylua --check` and `selene` are clean on `acceptance/`. No `guesses.md`.

### F1 [high] AC2 pins a folder spelling Claude Code does not use, so `./zn spend` still misses the session of any checkout whose path has a `_` (or any other character outside letters, digits and `-`)
Where: d0328.md Non-goals line 24 (third clause), Design "Not reused" line 33, AC2 line 98, Rules and mutants row 4 line 92; acceptance spec lines 43-48.
Evidence: Claude Code maps every character outside `[A-Za-z0-9-]` to `-`, `_` included. On this machine `$TMPDIR` is `/var/folders/b1/97q05hyx277_zqbc5mcchvlw0000gn/T/`, and the project folder Claude Code made for a probe there is `~/.claude/projects/-private-var-folders-b1-97q05hyx277-zqbc5mcchvlw0000gn-T-tmp-kKEFmqjbMc-zn-final-c0262-probe`: the `_` became `-` and so did the `.` of `tmp.kKEFmqjbMc`. None of the 149 folders in `~/.claude/projects` holds any character outside `[A-Za-z0-9-]` (`ls ~/.claude/projects | grep -E '[^A-Za-z0-9-]'` prints nothing). The repo already knows this: `sessionread.claudeDirs` (sessionread.luau:259-266, f0399) says "every character outside letters, digits and "-" becomes "-"". So for `/a/b_c/.worktree/x/` Claude Code writes `-a-b-c--worktree-x`, and the designed rule reads `-a-b_c--worktree-x`, a folder that never exists: spend records `unmeasured tokens,ai` there, the exact symptom of the Problem. AC2 seeds the session under the folder Claude Code would never write and makes that wrong spelling a permanent promoted spec, and the Rules row 4 lists the correct implementation (`claudeDirs`' mapping) as the "mutant". The capture (3cadd2cef) asked for the session "under the real folder name"; the clause "no character other than `/` and `.` is mapped" was added by the author at the idea revision (3290615a3), has no `Scope decision` or `Decided with the user` line, no guess and no evidence, and narrows "the real folder name" to two of its characters.
Critique: the tempting fix is to delete AC2 and keep the two-character rule. That still leaves every `_`, space, `+` or `@` path unmeasured, silently, and no spec says so.
Consequences: mapping with `[^%w%-]` is `claudeDirs`' strict spelling, but `claudeDirs` does not strip the trailing `/` (its pattern turns it into a trailing `-`), so `span` must strip first, then map. `claudeDirs` also returns the older dotted spelling second; if `span` reads every folder it returns, one session present under both names would be counted twice, so it reads the first that exists. The Solution's words ("maps both `/` and `.` to `-`") stay true under the wider rule; only the Non-goal's third clause and the "Not reused" bullet change. The work.spec `span` case (cwd `anywhere`) and `claudeDirs` case keep their values under this rule.
Recommendation: the Non-goal clause was the author's, not the user's, and it contradicts the captured outcome, so drop it (or, if the author wants to keep it, put it to the user with the evidence above, stating that keeping it leaves such paths unmeasured). Then: key = cwd with trailing `/` removed, every character outside `[%w%-]` mapped to `-` (preferably `span` calls `sessionread.claudeDirs(stripped)` and reads the first folder that exists, so one rule serves `span` and `id`). Replace AC2 with "a `_` in the cwd becomes `-`: a session seeded only under `-a-b-c--worktree-x` is measured for `/a/b_c/.worktree/x/`", and rewrite Rules row 4 as "map every character outside letters, digits and `-`" with mutant "only `/` and `.` mapped (reads `-a-b_c--worktree-x`)". If `span` reads the older dotted spelling as a fallback, add a row and case for it (session only under `-a-b-.worktree-x` is measured) and one that a session under both names is counted once.
Erred: z-design
Upstream: z-ticket

### F2 [medium] The sibling `sessionread.running` makes the same `.` mistake and is neither fixed nor captured, leaving three different Claude folder spellings in one module
Where: sessionread.luau:216 (`running`: `string.gsub(cwd, "/", "-")`); d0328.md Design "Siblings" line 35.
Evidence: `running()` strips the trailing `/` (line 207) but maps only `/`, so with `CLAUDE_CODE_SESSION_ID` set in `.worktree/<name>/` it looks for `…-pickman-.worktree-<name>/<sid>.jsonl`, which Claude Code never writes (F1's listing: every worktree folder is `…-pickman--worktree-<name>`). `running()` feeds the `finish` row (main.luau:4216) and the `done` binding commit (main.luau:5574), so every spend row those write from a worktree is unmeasured, the same symptom. The Design's Siblings bullet names `encode` and `claudeDirs` and omits `running`. The defect checklist (`z-nile/skills/z-design/checklists/defect.md`, Siblings) requires every place with the same mistake to be fixed in the issue or captured as its own; neither is done, and no open issue mentions it. After this design the module has `span` (`/` and `.`), `running` (`/` only) and `claudeDirs`/`id` (strict, then loose): exactly the "made canonical the same way in every reader" defect the lesson below names, whose note was written about this very function pair.
Critique: the tempting fix is a second copy of the new `gsub` pair in `running`, which keeps two hand-written rules that can drift again.
Consequences: `running` reads `process.cwd`, which a spec cannot set in-process, so a case for it either needs `running` to take the cwd (a signature change the Design says it avoids) or one shared folder function that `span`, `running` and `claudeDirs` all call and that a spec tests directly. Switching `running` to `claudeDirs` keeps f0399's `land.spec.luau:755` green, because that case seeds the loose spelling and `claudeDirs` tries it second.
Recommendation: either fix `running` in this issue through the same function as `span` (simplest: loop over `sessionread.claudeDirs(cwd)` as `id()` does at lines 274-277), with a Rules row and a case on the shared function, and add `running` to Siblings; or capture it as its own defect and name that id in Siblings. Say which in the Design.
Lesson: zz-arch/compare-canonical-spellings
Erred: z-design
Upstream: none

### F3 [medium] A `.` rule that maps only a dot right after `/` (or only `.worktree`) passes both cases
Where: acceptance spec lines 37 and 44; Rules and mutants row 3 line 91.
Evidence: in both cwds (`/a/b/.worktree/x/`, `/a/b_c/.worktree/x/`) the only `.` follows a `/`. `gsub(stripped, "/%.", "--")` then `gsub(_, "/", "-")`, or a hard-coded `gsub(_, "%.worktree", "-worktree")`, both give `-a-b--worktree-x` and `-a-b_c--worktree-x` and pass AC1 and AC2, yet leave `/Users/x/my.repo/` as `-Users-x-my.repo` (Claude Code: `-Users-x-my-repo`). An implementer who reads the Problem's only example (`…-pickman--worktree-<name>`) can plausibly write the `.worktree` special case. zz-test "Hard to fake" requires a case a partial implementation fails; the table lists no such mutant.
Critique: the tempting fix is to add `.` mid-segment to one existing cwd; fine, as long as each rule's row still names the case that kills it.
Consequences: none beyond the new row; under F1's rule the same case also covers a dot inside a segment.
Recommendation: add a dot inside a segment, e.g. a case for `/a/b.c/.worktree/x/` measured under `-a-b-c--worktree-x` (or change AC1's cwd to that), and a Rules row "map every `.`, not only one after `/`" with mutant "`/.` mapped to `--`, other dots kept", killed by that case.
Erred: zz-test
Upstream: z-design

### F4 [low] Each `check` runs the whole spec file, and AC1's label claims `./zn spend` while the spec calls `sessionread.span`
Where: check.sh lines 12-13; d0328.md AC1 line 97.
Evidence: both checks run `lune run tests/run -- "$A/spend-session-cwd.spec.luau"` (the runner has no case filter), so a failure of the AC2 case also fails the AC1 check and vice versa: E2's "fails AC2 only (AC1 passes)" holds for spec cases, but `./zn check d0328` would report both criteria failed. AC1 says "`./zn spend` … measures", but nothing runs `cmd.spend` (main.luau:7560) or `record.luau:95`; the spec calls `span` directly. The callers pass `process.cwd` unchanged and the fix is inside `span`, so the gap is wording, not a hole.
Critique: low, since the spec does pin the rule; but the labels must say what their command verifies.
Consequences: none.
Recommendation: put each AC's case in its own spec file (e.g. `spend-session-cwd.spec.luau` and `spend-session-cwd-underscore.spec.luau`) so each check runs only its criterion, and word AC1 as "`sessionread.span`, which `./zn spend` and `record` call with `process.cwd`, measures …".
Erred: zz-test
Upstream: z-design

### F5 [low] The prototype that E1 and E2 ran is not kept, and Affected specs says 19 where it lists 20
Where: d0328.md Unknowns E1/E2 lines 70-71; Affected specs line 44.
Evidence: E1 says the rule was applied and reverted; the issue folder has no `experiments/prototype.patch`, so the `run` rows' results cannot be rerun after F1-F3 change the rule and the cases. The affected selector prints, and the list holds, 20 specs (c0172 ×4, c0246 ×1, f0399 ×6, tooling ×9); the text says 19.
Critique: low; for a one-line change the patch is small, but the revision after this review needs to rerun every row.
Consequences: none.
Recommendation: commit the prototype as `experiments/prototype.patch` and rerun E1/E2 on it after the revision; correct the count.
Lesson: z-design/prove-specs-pass-on-a-prototype
Erred: z-design
Upstream: none

## Categories with nothing found
- Unknowns: the one assumption (Claude Code's naming) is the subject of F1; otherwise none unproven.
- Regressions / Overrides: `Overrides: none` holds. The work.spec `span` case (cwd `anywhere`, line 282) keys the same under the designed rule and under F1's; the `claudeDirs` case (lines 421-432) and f0399 `land.spec.luau:755` (via `sessionread.id` → `claudeDirs`) do not go through `span`; `c0322/wiring.spec.luau` greps text that the change does not touch; no other spec seeds `.claude/projects`.
- Architecture: `span` stays an adapter; no new require or edge.
- Repository safety: the spec writes only under `<home>/.cache/d0328-spend-session/`, sets `HOME` in-process and restores it, starts no process and runs no git; `check.sh` runs only `tests/run`.
- Bounded commands: the experiments ran through the spec runner; no step asks for an unbounded command.
- Scope fidelity: apart from F1's Non-goal clause, the captured outcomes (strip once in `span`, a spec seeded only under the real folder that pins the measured model, tokens and AI time) each have a Design line and a Checked criterion.
- Executability: the implementation step is concrete enough to deliver without questions.

Verdict: changes
