# Review 002: c0460 (design mode)
Inputs: worktree `prep-behavioral-acceptance-and-build-mutants` at 70782b1a5 plus its uncommitted prep files (`c0460.md`, `check.sh`, `guesses.md`, `harvest.md`, `acceptance/finish-mutants.spec.luau`, `acceptance/skills-text.spec.luau`, `acceptance/requires.spec.luau`); `design-review-001.md` and `design-refute-001.md`; `./zn capture c0460` (capture 72e115a8); `./zn check c0460` run by me (AC1 5 passed / 10 failed, every failure on an assertion; AC2 0/7 on an assertion; AC3 PASS); `engine/main.luau` `cmd.finish` (`:4265`–`:4330`); `tests/lib/engine.luau` `engine.copy`; `tests/lib/trackerfix.luau` `buildAt`; `skills/zz-execute/SKILL.md` Phase 2; c0458's prep worktree (`prep-collapse-reviews-and-tighten-caps`: `c0458.md` Design item 3 and 4, `acceptance/docs.spec.luau`).

Round 1's answers, checked:
- F1 accepted. `engine.copy` is where `trackerfix.buildAt` takes its tooling, and `fxclone` copies a fixture that is already built, so a strip there reaches every trackerfix family. `finish-mutants` now puts the real template back for its armed cases and strips the line for the no-line case. The red-spec list was deferred to the executor's E4 instead of a prototype run. I accept that because the strip leaves those specs' tickets as they are today.
- F2 accepted. The killed case stamps the ticket and passes on today's engine, so `seal.stamp` sealed at least one approval. `cmd.finish` fails on `approval.refusal`'s drift (`main.luau:4318-4320`), so a `partsOf` that let `mutants.md` in would turn that case red. The stale unit case is still in the Test plan (see F1 below).
- F3 accepted (the low F6 below is a gap in the near-miss rule).
- F4 accepted, apart from the vacuous `./zn` pin (F5 below).
- F5: only partly fixed (F3 below). The prefix matching works, and c0458's prep keeps the `## Code mode` prefix (its Design item 4). But the Design quotes only c0458's capture, not its prep design, and that design adds a 13-name check list that the new item misses.
- F6 accepted. The grep lists 24 files in exactly the three lesson folders now named in Touched modules.
- F7: fixed in a way that cannot pass outside prep (F2 below).
- F8 accepted. `"/" .. path` with a plain find of `/.tracker/` is a segment test, and `notes.txt` covers the exemption.
- F9: fixed, but the new procedure can destroy uncommitted build work (F4 below).
- F10 accepted. The call sits after the merge-base check (`:4303`) and before `runCheck` (`:4323`), and the failing-check case's negative assertion uses the real message `check.sh failed`.
- F11 accepted.

### F1 [high] The Problem section no longer matches the capture: the new Test plan lines were spliced into its first bullet, and the real Test plan still holds the cases round 1 removed
Where: `c0460.md:21-29` (Problem) and `:127-133` (Test plan)
Evidence: `./zn capture c0460` gives the first Problem bullet as one line: "z-design step 3 has the designer write a `### Rules and mutants` table inside the hashed `## Test plan`, and step 4's mutation check runs that table ...". In the document, that bullet stops at `` `## Test plan `` (`:21`). Lines `:22-27` follow, and they are the revised Test plan bullets (`finish-mutants`, `skills-text`, `requires`, `mutants.spec`, `mutants-fixtures`, the narrowed c0043 cases). Then comes a blank line, and the bullet's tail resumes at `:29` as a line that starts with `### Rules and mutants`. That is a level-3 heading inside the Problem, so section readers end the Problem there. Meanwhile the real `## Test plan` (`:127-133`) is the round-1 text:
- "near-miss `Mutants: mutants.txt` false", which contradicts Design `:58`, where it returns the message;
- "a 3-cell row", where the Design now says a 5-cell row;
- "`tests/tooling/mutants.spec.luau :: hash` builds the five hashed parts with `contract.hash` ...", the tautology that round-1 F2 asked to replace with `partsOf`, which the refute says was replaced;
- "the same acceptance specs' requires → AC3", although AC3 is now `requires.spec`;
- no `mutants-fixtures` line.
The Affected specs paragraph (`:113`) still says "New: the two sequestered specs in `acceptance/` (`finish-mutants`, `skills-text`)" and leaves out `requires` and `mutants-fixtures`.
Critique: scope fidelity, item 11. The capture's Problem text was changed by something other than added detail, which is high by rule. The hashed `Problem` and `Test plan` parts are what the owner approves, and the executor builds the Test plan's cases, so it would write the vacuous hash case again. The tempting fix is to move lines 22-27 back. That leaves `:131-132` and `:113` stale.
Consequences: none beyond the text. The sequestered specs already match the revised plan.
Recommendation: restore the Problem's first bullet byte for byte from `./zn capture c0460`. Replace the whole `## Test plan` list with the revised bullets, so `:131-132`'s old `carries`/`rows` expectations and the `contract.hash` case are gone. Fix `:113` to name all three sequestered specs and `mutants-fixtures`. Then diff Problem, Non-goals and Solution against the capture and grep the document for `contract.hash`, `3-cell` and `mutants.txt` false, so the refute's "fixed" is shown by the text.
Lesson: z-design/restated-rules-move-together
Erred: z-design
Upstream: none

### F2 [high] AC3 cannot pass during execution or after promotion: `requires.spec` reads `issues/c0460/acceptance`, which exists only in prep, and then requires at least one file
Where: `acceptance/requires.spec.luau:10`, `:71-80`; `check.sh:12`
Evidence: `own` is hard-coded to `{ITEMS}/c0460/acceptance`. `./zn ready` moves the ticket to `z-nile/.tracker/issues/active/c0460/`, and `done` promotes its specs to `z-nile/tests/acceptance/c0460/`, so `own` is absent in both places. `armed()` adds only tickets whose Test plan carries the line. No z-nile ticket does today: `grep -rlx "Mutants: mutants.md" z-nile/.tracker/issues` prints nothing, and c0460 itself carries the table, not the line (`:136`). The template change that would make later tickets carry it is in c0460's own raft. So during execution `files` is empty, `t.expect(#files > 0).toBe(true)` fails, and AC3 is red with no way for the executor to fix the sequestered spec. After `done`, the promoted spec is red on main until some later z-nile design carrying the line merges. AC3 passes only now because the prep folder is still at `issues/c0460/`. A second defect: `armed()` matches only `\nMutants: mutants.md\n`, while `mutants.carries` also arms `- Mutants: mutants.md` (Design `:58`). So a ticket armed with the list marker is never scanned, and the walk and the rule disagree about which tickets carry the line.
Critique: this is the defect a sibling-path lesson names: a sequestered spec must resolve its own files from the backlog folder, from `active/` and after promotion. The tempting fix is to also try `active/c0460`. That still fails after promotion, and the `#files > 0` guard keeps the promoted spec fragile.
Consequences: reading the spec's own folder from its own path covers all three states. After promotion, the own folder is `tests/acceptance/c0460`, which holds the spec itself, so `files` is never empty. Matching the line the way `carries` does adds the marker form and also has to skip fenced lines.
Recommendation: derive `own` from the spec's own location (`debug.info(1, "s")`, or the path the runner passes, whichever `tests/lib` already offers). Fall back to finding the `c0460` folder in any state folder by name, and to `tests/acceptance/c0460`. Keep the non-empty guard, since `own` always holds `requires.spec` itself. Make `armed()` match a Test-plan line that trims to `Mutants: mutants.md`, with an optional `- `, outside fences, and pin that with a scanner-style unit case over a text with the marker form. Run the spec from a copy at `issues/active/c0460/acceptance/` and at `tests/acceptance/c0460/`, both under `.cache`, and record that both pass in Unknowns & experiments.
Lesson: zz-test/specs-find-siblings-by-own-path
Erred: zz-test
Upstream: z-design

### F3 [medium] The new Code mode item is missing from c0458's `work.CODE_CHECKS`, so the final-review brief that c0458 makes every raft's one review never names the `mutants.md` audit
Where: Design `:69` ("Code mode's check list gains one item after the last numbered one ... whatever c0458 does to the section's heading"); Checklist "Existing work" `:74`
Evidence: c0458's prep design (`prep-collapse-reviews-and-tighten-caps`, `c0458.md:67`) introduces `work.CODE_CHECKS`, a list of 13 names that the final-review brief prints for every raft. It says zz-review's `## Code mode` carries them "as its bold item names (the docs case pins the same 13 names in the skill, so the two cannot drift)". Its `acceptance/docs.spec.luau:25-29` pins those 13 by presence only. c0460 is `depends_on: [c0458]`, so c0458 lands first. c0460 then adds a 14th Code mode item that has no bold name and no entry in `CODE_CHECKS`. Every final review's brief would list 13 checks and leave out the only audit of `mutants.md`'s rows. Round 1's F5 asked the author to quote c0458's prep, not only its capture. The fix quoted the capture, so this list stayed out of sight.
Critique: c0460's code-review audit is the step that checks whether a row's spec case can fail and whether a plausible mutant is missing. If the reviewer's brief omits it, a `mutants.md` of killed rows nobody audited passes. The tempting fix is to rely on the reviewer reading the whole section. c0458 made the brief the list of checks precisely so they would not drift.
Consequences: adding the name to `CODE_CHECKS` touches `z-nile/engine/work.luau`. Its affected specs, including c0458's `walk.spec` AC6, which checks that all the names are present, must be rerun. c0458's docs pins stay green, because they check presence. If c0458 changes again before c0460 executes, the list may have a new name or place.
Recommendation: give the new item a bold name, for example `**Mutants**`. Have the Design add it to `work.CODE_CHECKS` when that list exists at execution time, and add `z-nile/engine/work.luau` to Touched modules. Pin the bold name inside the `## Code mode` section in `skills-text`. Quote c0458's design at the commit you read (its Design item 3 and 4) in Checklist "Existing work", and say what the executor does if c0458 has landed without `CODE_CHECKS`.
Lesson: z-design/design-the-execution-window
Erred: z-design
Upstream: none

### F4 [medium] The mutant procedure says "revert with `git restore <file>`" but never says to commit the built layer first, so restoring a mutated file can erase uncommitted build work
Where: Design `:68` (zz-execute Phase 2 step); `skills-text.spec.luau:79-91`
Evidence: zz-execute Phase 2 step 3 says to commit "at meaningful green steps", not before every check. The new step runs "after the layer's specs are green and before finishing". It applies the mutant as an uncommitted edit, then reverts with `git restore <file>`, which resets the file to the index. When the executor's last build edits to that file are not yet committed (green specs do not require a commit), `git restore` throws them away along with the mutant. The closing check that `git status --porcelain` lists only `mutants.md` implies the code was committed, but the step never says so, and the check comes after the restore that did the damage.
Critique: this is the procedure round-1 F9 asked for, and it now has a destructive step for a reader who has never seen this repo. The tempting fix is to say `git stash` instead, which the same step correctly forbids.
Consequences: committing first adds one `./zn commit` per layer before the mutant pass. The `git status --porcelain` check then moves before the first mutant (empty) as well as after the last one (only `mutants.md`).
Recommendation: open the step with "commit the layer (`./zn commit -m ...`) so `git status --porcelain` prints nothing before the first mutant", and keep the after-check. Pin "commit the layer" (or your exact words) in the zz-execute Phase 2 case of `skills-text`, and add a table row for it.
Erred: z-design
Upstream: none

### F5 [low] The step-4 pin on `./zn` cannot fail: z-design step 4 already says `./zn` eight times
Where: `acceptance/skills-text.spec.luau:75`
Evidence: `sed -n 48,62p z-nile/skills/z-design/SKILL.md | grep -c './zn'` finds `./zn` 8 times in today's step 4, so `has(s4, "./zn")` passes before and after any edit. `lune run` (`:76`) is absent today, so that pin is real. The captured clause "reaches z-nile's behaviour only through `./zn` or `lune run` commands" is therefore pinned only by `lune run`.
Critique: this assertion is weak, though not wrong.
Consequences: none.
Recommendation: replace `has(s4, "./zn")` with the exact phrase step 4 will carry, for example "only through `./zn` or `lune run`".
Erred: zz-test
Upstream: z-design

### F6 [low] Whether a near-miss line refuses an easy ticket or a docs-only layer is not specified
Where: Design `:58` and `:61` (`refusal`'s four conditions); Test plan `refusal` unit cases
Evidence: `carries` returns `(false, msg)` on a near-miss and "`refusal` turns it into a refusal". `refusal` is nil "unless all four hold", the first of which is `carries(testPlan)`, and that is false on a near-miss. The Design does not say whether the near-miss refusal also needs `risk ~= easy` and `owed(paths)`. The acceptance near-miss cases use only a normal ticket with a source change, so either reading passes.
Critique: two executors can build different rules and both pass every case.
Consequences: refusing regardless means an easy ticket with a typo is refused, which is closed but noisy. Following the exemptions keeps easy and docs-only layers quiet.
Recommendation: state which one holds (the exemptions also apply to a near-miss, if you follow "the exemptions are the only way through"), and add a `refusal` unit case for a near-miss with `risk: easy`.
Erred: z-design
Upstream: none

Verdict: changes
