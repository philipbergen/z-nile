# Review 001: c0460 (design mode)
Inputs: worktree `prep-behavioral-acceptance-and-build-mutants` at 72e115a82 plus its uncommitted prep files: `z-nile/.tracker/issues/c0460/c0460.md`, `check.sh`, `guesses.md`, `acceptance/finish-mutants.spec.luau`, `acceptance/skills-text.spec.luau`; `./zn capture c0460` (capture commit 72e115a8; Problem, Non-goals and Solution are byte-identical to it); `./zn check c0460` run by me (AC1 4 passed / 4 failed on an assertion, AC2 0/4, AC3 pass, which confirms E1); `lune run z-nile/affected` over the skills and template; `engine/main.luau` `cmd.finish`, `engine/approval.luau`, `engine/contract.luau`, `engine/rounds.luau`, `engine/trail.luau`, `tests/lib/seal.luau`, `tests/lib/trackerfix.luau`, the c0043 specs and c0458's capture.

### F1 [high] Once the template carries `Mutants: mutants.md`, every fixture ticket carries it too: c0460's own "without the line" case goes red, and so do promoted finish-driving specs that the Overrides line does not name
Where: c0460.md Design, Checklist answers "Existing work"; Regression guard ("every finish-driving spec ...: tickets with no `Mutants:` line are never refused"); `acceptance/finish-mutants.spec.luau:58-61` and the case at `:116`
Evidence: fixtures copy the checkout's `z-nile/` tooling, templates included (`tests/lib/trackerfix.luau`, KEY over `z-nile`; `engine/main.luau:163` `TEMPLATES = "z-nile/templates"`), and `./zn new issue` renders `templates/issue/doc.md` (c0460's own capture shows the template's Test plan verbatim). After Implementation step 4 edits the template, every fixture ticket made with `new issue` has `Mutants: mutants.md` in its Test plan and `risk: normal`. Consequences:
(1) `finish-mutants :: a ticket without the line is never refused for mutants.md` sets `line = false`, but that only skips adding a line. The template's own line stays, the layer changes `SRC`, and there is no `mutants.md`, so the correct implementation refuses. The case passes at step 3 and turns red at step 4. It is sequestered, so the executor cannot fix it.
(2) Twelve promoted specs both run `"new", "issue"` and drive `"finish"` (`tests/tooling/finish-deleted`, `live-events`, `watch-map`, `tests/acceptance/c0120/promote-home`, `c0001/tracker-lifecycle`, `c0038/deferred`, `c0008/done-order`, `c0084/commit-phase`, `c0067/ready`, `c0034/locator`, `c0080/consequences`, `c0074/done-gate`). For example, `finish-deleted.spec.luau:71` writes the `.luau` file `MAZE` and finishes, and `c0001/tracker-lifecycle.spec.luau:287-289` writes `notes/f0031.txt` and expects `finish f0031` to succeed. Neither writes a `mutants.md`, so both are refused. Sequestered specs outside `done/` that drive finish (`d0331/acceptance/*`, `c0251/acceptance/floor.spec.luau`) have the same exposure. None of these is named on `Overrides:`, and E1 ran the cases only against today's template, so it could not see this.
Critique: the design assumes "no line" means "designed before this lands". The capture makes the template carry the line, so in fixtures "no line" is now the exception. The tempting fix is to name a few of the red specs as overrides and move on. That still leaves c0460's own case unpassable, and any spec nobody ran stays red.
Consequences: every narrowed promoted spec is an override with its own case, which grows the Overrides line and the size. A helper that strips the line from every fixture (in `trackerfix` or `seal.prep`) would change what all fixtures see and would also strip the line from c0460's `line = true` cases, since they add it before `seal.prep` runs.
Recommendation: (a) Make `finish-mutants` independent of the template. When `line` is false, remove the line (`string.gsub(text, "\nMutants: mutants%.md\n", "\n")`), and when it is true, add it only if it is absent. Add a case that renders the post-change template as it is, with no edit, and shows that ticket is refused without `mutants.md`. That case proves the template line really arms the rule. (b) Build the prototype (template, `mutants.luau` and the `cmd.finish` call), then run every promoted and sequestered spec outside `done/` that drives `finish` (find them with `grep -rln '"finish"'` and `"new", "issue"`). Record each red one in Unknowns & experiments. Name each on `Overrides:` with its narrowing (the fixture writes an all-killed `mutants.md`, or removes the line), as a first-step chore like the c0043 ones. (c) Rewrite the "Existing work" and Regression guard sentences to match what that run shows.
Lesson: z-design/quote-other-preps-before-promising
Erred: z-design
Upstream: none

### F2 [high] AC1's "writing mutants.md leaves the approval hash unchanged" has no check that can fail
Where: AC1; `acceptance/finish-mutants.spec.luau:109-113`; Test plan `mutants.spec :: hash`; E3; the Rules and mutants row "mutants.md leaves the hash alone"
Evidence: the case named "every row killed finishes, and the ticket's approval hash is unchanged by mutants.md" throws the document away (`local r, _ = finish(...)`) and asserts only `r.ok`. The fixture calls `seal.prep`, not `seal.stamp`, so it has no `approval.md`. With no record, `approval.refusal` (`engine/approval.luau:162-170`, called from `cmd.finish`) compares no hash, so E3's claim that the finishing case pins it is false. The unit case is a tautology: `contract.hash(parts)` hashes a `Parts` table of texts, so writing a file beside them cannot change its result. Its listed mutant, "add `mutants.md` to `contract.HEADS`", makes no sense, because HEADS are section headings. The plausible wrong implementation is one that lets the file reach the parts: `approval.collect`/`partsOf` walking the whole issue folder, or a `mutants.md` written under `acceptance/`. Every listed case passes that mutant.
Critique: this is a Checked criterion with no real check. The tempting fix, comparing the document text before and after, proves nothing either, because the hash is not the document.
Consequences: stamping the fixture makes `finish` enforce the approval. If the fixture's raft is readied with `Lands: approved`, `finish` only prints `note: ... is not approved` and goes on (`main.luau` f0399 branch). The assertion then has to read that output too.
Recommendation: in `finish-mutants`, call `seal.stamp(f.main)` (an allowed `@tests/lib` helper) before the prep commit, assert that it returned 1 so the case cannot be vacuous, and in the killed case assert `r.ok` and that the output has no `not approved` note and no drift refusal. On the prototype, show that a mutant adding `mutants.md` to `approval.partsOf`'s parts turns that case red, and record the result in E3. Replace the `mutants.spec :: hash` case with one over `approval.partsOf(id, files)`, where `files` includes `mutants.md` and `acceptance/mutants.md`, and the hash equals the hash without them. Fix the table row's mutant to match.
Erred: z-design
Upstream: none

### F3 [high] The rule is armed only by an exact text line, so a missing or misformatted line fails open, and the captured "every ticket designed after this lands carries the line" has no check
Where: Solution bullet 2 and its Design; `mutants.carries` (exact line, near-miss `Mutants: mutants.txt` is false); the zz-review item 0 change; Checklist "Guards ... fails closed"
Evidence: a ticket is unarmed in each of these cases:
- the designer of a ticket captured earlier forgets to replace its empty `### Rules and mutants`, which 61 open tickets still carry (idea review 003 F2);
- the designer deletes the line;
- the designer writes it as the skills quote it, `` `Mutants: mutants.md` `` with backticks, or as `**Mutants:** mutants.md`, or `Mutants: mutants.txt`.
An unarmed ticket is never refused by `finish`. Design item 0 skips it, because its table is empty or absent and the new item 0 sentence covers only tickets that carry the line. The code-mode audit runs only "when the ticket carries `Mutants: mutants.md`". So nobody verifies its mutants, and nothing reports that. The Solution's outcome "so every ticket designed after this lands carries `Mutants: mutants.md` and no `### Rules and mutants` heading" has no acceptance criterion.
Critique: the Checklist says the guard fails closed, but its trigger is opt-in by formatting. The tempting fix is to accept more spellings in `carries`, which leaves a missing line silent.
Consequences: refusing near-misses adds a refusal that existing tickets could meet, but none of them has a `Mutants:` line today (grep), so none fails. A review rule for tickets with neither the line nor table rows applies only to designs reviewed after this lands, which fits Non-goal 3 (it says what such a ticket owes at finish, not what its review may ask).
Recommendation: (1) make `mutants.refusal` fail closed on a near-miss. Strip a list marker, backticks and `*` from a Test plan line outside a fence. If what remains starts with `Mutants:` but is not exactly `Mutants: mutants.md`, refuse with "write exactly `Mutants: mutants.md`". Add unit cases for the backticked, bold and `.txt` forms, and change the Test plan's `Mutants: mutants.txt` → false expectation. (2) Have zz-review design item 0 say that a ticket under design with neither the line nor a table that has rows, or with an empty `### Rules and mutants` heading left in place, is a high finding. Pin that sentence in `skills-text` (for example `has(design, "neither")` on the exact phrase you choose). (3) Add rows for these rules to the table.
Erred: z-design
Upstream: none

### F4 [medium] AC2 passes a skill edit that leaves z-design asking for Rules and mutants rows, and it pins none of three Solution rules
Where: `acceptance/skills-text.spec.luau:43-50`, `:53-58`; Design "Skills and template"
Evidence: the z-design case forbids only the bold forms `**Rules and mutants**` and `**Mutation check**`. An implementation that deletes the two bullets at `z-design/SKILL.md:39` and `:56` passes, even if it leaves step 5.3 (`:68`) saying "Add their Rules and mutants rows and spec cases" and the easy path (`:61`) saying "no mutation check". The Design says both are reworded, but nothing checks it. These Solution rules have no assertion at all:
- bullet 2's instruction to replace an earlier ticket's empty `### Rules and mutants`;
- bullet 4's rule that a survivor's kill case goes under the project's `tests/` and "never in the sequestered `acceptance/` folder";
- bullet 1's "reaches z-nile's behaviour only through `./zn` or `lune run` commands".
The `@tests/lib/*` and `@lune/*` checks search the whole skill, not step 4.
Critique: a wrong implementation passes AC2 while the skill still tells designers to fill the table this ticket removes.
Consequences: the new pins must not forbid "Rules and mutants" anywhere in z-design. Step 3's migration sentence has to name `### Rules and mutants` to tell designers what to replace.
Recommendation: in `skills-text`, assert that z-design has no "Add their Rules and mutants rows" and no "fill the table from the mutation check". Assert that step 3 (section "3.") contains `Mutants: mutants.md` and a phrase of the captured-earlier replacement. Assert that step 4 (section "4.") contains `@tests/lib/*`, `@lune/*` and `./zn`. Assert that zz-execute Phase 2 says the kill case goes under `tests/` and never in `acceptance/` (choose the exact words and pin them). Add a row to the table for each.
Erred: z-design
Upstream: none

### F5 [medium] `skills-text` depends on heading texts that its dependency c0458 is set to change, and the Design misstates c0458's plan
Where: `acceptance/skills-text.spec.luau:54`, `:65-68`; Design "zz-review/SKILL.md ... (which c0458 moves into Final mode)"; Checklist "Existing work"
Evidence: the spec looks up the exact headings `## Code mode (one layer)` and `## Phase 2: Implement, one issue at a time in the raft's order`. c0458 is in prep (`c530e048b tracker: c0458 preparing`). Its Solution says Code mode "no longer runs one layer at a time", which makes "(one layer)" stale and a rename likely. If either heading changes, `part()` returns `""`:
- the Code mode negative assertion (`:68`) becomes vacuous;
- the positive `mutants.md` assertion depends on Final mode alone, and the Design tells the executor to put the audit "in whichever section holds the check list", which c0458's Solution says stays Code mode. If the audit goes there, AC2 is red and the executor cannot edit the spec.
The Design's "c0458 moves [the check list] into Final mode" contradicts c0458's capture ("zz-review's Code mode section stays as the list of checks that Final mode applies").
Critique: a sequestered spec built on undesigned text of an in-flight dependency can strand the executor.
Consequences: matching headings by prefix keeps the check working whatever c0458 calls its sections. It needs a non-empty assertion so that a missing section fails loudly rather than passing.
Recommendation: match by prefix (`\n## Code mode`, `\n## Final mode`, `\n## Phase 2`) and assert each part is non-empty, as the template case already does. Quote c0458's planned headings from its prep worktree and record the agreement in both documents. Fix the Design sentence about c0458. Name the section that will hold the `mutants.md` audit rather than leaving it to the executor, which is also an unrecorded judgement call.
Lesson: z-design/quote-other-preps-before-promising
Erred: z-design
Upstream: none

### F6 [medium] The restated-rules sweep covers 8 of the 24 lessons that state the old rule, and the rest still tell designers to fill the table
Where: Design Checklist "Restated rules"; Touched modules
Evidence: `git grep -l -i -e "rules and mutants" -e "mutation check" -- '*/lessons/**'` lists 24 files. The 22 z-nile ones include `z-design/lessons/limits-name-the-iterations-they-count`, `ordered-causes-pin-each-neighbouring-pair`, `skips-move-the-checks-they-bypass`, and in `zz-test/lessons/` `source-text-pins-read-the-code` ("does the Rules and mutants table say what the pin leaves to the code review"), `guard-needs-its-own-case`, `pin-fail-safes-where-they-act`, `sort-cases-defeat-pre-order` and others. The two pickman ones are `pickman/skills/pickman-arch/lessons/hysteresis-on-every-boundary` and `tuning-edges-stay-finite`. `./zn lessons` shows designers their `check:` questions, which still ask for rows in a table z-design no longer has. `pickman/tests/lib/fakeengine.luau:30`'s comment refers to the table as well.
Critique: the next design's lessons pass contradicts the new skill.
Consequences: notes on pickman lessons extend Touched modules into `pickman/skills/`. The affected selector over those paths has to be rerun.
Recommendation: put the grep in the Design so it can be rerun, add the note to all 24 lessons (saying that the question now applies to `mutants.md`, written at build time and audited in code review), list them in Touched modules, and rerun `z-nile/affected` over the new paths.
Lesson: z-design/restated-rules-move-together
Erred: z-design
Upstream: none

### F7 [medium] The captured require-rule outcome is checked only on c0460's own two specs, and AC3's grep misses other spellings of require
Where: Solution bullet 1 ("in any such spec written after this lands, a `grep 'require(\"@'` finds no other alias"); AC3; `check.sh:12`
Evidence: AC3 greps `$A/*.spec.luau`, which is only c0460's specs. No check enforces the outcome on later tickets' specs, although the set is measurable: Solution bullet 2 makes "designed after this lands" the same as "the document carries `Mutants: mutants.md`". The grep also misses `require "@znile/..."`, `require('@znile/...')` and `require (` with a space, all valid Luau, and it skips non-spec helpers under `acceptance/` (for example a `record.luau` that a spec requires).
Critique: the capture states a grep-observable outcome. Leaving it as skill text alone makes it unchecked.
Consequences: a promoted tooling spec that reads the real tracker turns red in the prep PR of any later ticket that breaks the rule. That is the intended effect, and it reads only, so the repository is safe. It must skip tickets without the line (Non-goal 1).
Recommendation: add a promoted tooling spec (with its watch file), or extend AC3's check.sh line, that walks every `z-nile/.tracker/issues/**/<id>/` whose document carries the line. It reads every `*.luau` under `acceptance/` and fails on any require of an alias other than `@tests/lib/` or `@lune/`, using the pattern `require%s*%(?%s*["']@`. Pin a case with each spelling. Map it to AC3 and add a table row.
Erred: z-design
Upstream: z-idea

### F8 [medium] The `.tracker/` exemption (G2) is not pinned by any case, and its match is not anchored to a path segment
Where: G2; E2; `mutants.owed`; `finish-mutants :: a layer that changes only .md and spec files is not refused`
Evidence: E2 was answered by reading `recordAndCommit`, not by running it. The docs-only case writes only `note.md` and `x.spec.luau` and passes on today's engine whatever the layer's diff holds. Nobody has seen whether the fixture's `./zn commit` puts a `spend.d` row into the layer diff (`recordAndCommit` skips shares under thresholds). If it does not, the mutant "drop the `.tracker/` exemption" survives every case, and E2's fallback ("if the case shows it does not") cannot fire, because the case cannot show it. "Under a `.tracker/` folder" is not specified as a whole path segment either. A substring test also exempts `src/x.tracker/y.luau`.
Critique: G2 widens the capture's exemption with nothing to show the widening is needed, and nothing to stop it from growing.
Consequences: a hand-written non-`.md` file under the issue folder in the case exercises the exemption deterministically, whatever `commit` does.
Recommendation: in the docs-only case, also write `{root}/issues/active/{id}/notes.txt`, so a correct implementation still finishes and the mutant without the exemption is refused. Run the case on the prototype and record E2's observed answer. Define `owed`'s test as a path segment (`^%.tracker/` or `/%.tracker/`, plain) and add a unit case for `src/x.tracker/y.luau` → owed. Give the exemption its own table row.
Lesson: zz-test/plain-find-for-literals
Erred: z-design
Upstream: none

### F9 [medium] The new zz-execute step does not say how a mutant is applied and undone, which leaves a mutated build or a shared stash one slip away
Where: Design "zz-execute/SKILL.md Phase 2: a new step ..."; Implementation step 4
Evidence: the step says to "apply the mutant to the built code, run the spec case". It says nothing about where the edit is made, how it is reverted, or how the executor knows the tree is clean before `./zn commit`. `finish` refuses a dirty tree, but a mutant swept into `./zn commit`'s `git add -A` is committed and passes `finish` (that layer's `mutants.md` says killed). An executor who reaches for `git stash` uses the stack shared by every worktree. The step also does not say how to tell a failure "on an assertion" from a require or syntax error, which the old z-design step 4 spelled out.
Critique: an executor who has never seen this repo has to invent the procedure, and the procedure is where the harm is.
Consequences: the procedure adds a check before commit, which costs one command.
Recommendation: have the step say four things. (1) Apply each mutant as an uncommitted edit in the layer's worktree. (2) Run the named case with the spec runner (`lune run tests/run -- <spec>`); anything else goes through `./zn run --time`. (3) The case must report an assertion failure (the runner's `expected ... got ...`), not an error. (4) Revert with `git restore <file>`, never `git stash`, and confirm `git status --porcelain` lists only `mutants.md` before `./zn commit`. Pin "never `git stash`" or the restore sentence in `skills-text`.
Erred: z-design
Upstream: none

### F10 [low] The refusal runs after the ticket's whole `check.sh`, and a row containing a `|` is refused with a misleading reason
Where: Design "Adapter" (after `paths`, before `watchcmd.capture`); `mutants.rows`; Usability
Evidence: in `cmd.finish`, `paths` is computed after `runCheck(issue)`, which runs the full acceptance check. An executor missing `mutants.md` waits for that run only to be refused. `base` and `layergit.diffPaths(base)` are both available before `runCheck`. A mutant cell such as `` `a | b` ``, common for shell mutants, splits the row into five cells, so `result = ""`, and the refusal reads as a non-killed row.
Critique: these are a slow failure and a confusing message, though neither gives a wrong result.
Consequences: moving the call earlier does not change what is written, since nothing is written before `runCheck`.
Recommendation: call `mutants.refusal` right after the `merge-base --is-ancestor` check, with `paths` computed there. For a row whose cell count is not 4, refuse with "row N has K cells: escape `|` as `\|`". Add a unit case for that message.
Erred: z-design
Upstream: none

### F11 [low] The Rules and mutants table leaves out rules the Design states
Where: c0460.md `### Rules and mutants`
Evidence: the Design and Test plan state these rules, and no row lists them:
- `carries` ignores a fenced line;
- `carries` accepts the `- ` marker;
- a bad `risk:` value is owed;
- a row with other than four cells has an empty result and refuses;
- `x.spec.luau.bak` is owed;
- the refusal is raised before `watchcmd.capture` writes anything.
The "docs-only" row folds three exemptions (`.md`, `*.spec.luau`, `.tracker/`) into one mutant, so the mutant that drops just one of them is not listed (see F8).
Critique: design item 0 asks for one row per behavioural rule. The unit spec cases already exist in the Test plan, so the gap is in the table only.
Consequences: none beyond the rows.
Recommendation: add one row per rule above, each naming its `mutants.spec` case. Split the docs-only row into the `.md`, spec and `.tracker/` variants, together with the rows that F2, F3, F4, F7 and F8 add.
Erred: z-design
Upstream: none

Verdict: changes
