# Review 001: c0181 (design mode)
Inputs: prep worktree at 6d9318e5 plus its uncommitted draft: c0181.md, check.sh, acceptance/{format,policy,listing,lints,wiring,footer,consolidate,merge,docs}.spec.luau, experiments/E1-E4 (E1 and E4 re-run: they match the document). Read against z-nile/engine/lessons.luau, main.luau (cmd.lessons, READ_ONLY, refuseInMainCheckout), z-nile/check.sh, z-nile/tests/run.luau, tests/tooling/tracker-guarded, c0111/skill-docs, c0116/claims, c0119/scope-lessons, c0120/gate-homes, c0172/merge. `./zn lessons --check` on the tree: "149 lessons, 920 harvest entries, ok".
Scope note: `./zn capture c0181` prints the bare first add (1de8f18e, Problem one line, no Solution) with no marker. The Problem and Solution bullets the brief calls the user's scope arrived in 1397f78f, whose subject is `tracker: new c0175 …` (lesson z-ticket/capture-subject-lists-every-id), so the capture tool cannot see them. Scope was judged against the text at 1397f78f, which the draft keeps word for word; it adds one Non-goals bullet that fences other issues only.

### F1 [high] Two policy.spec cases fail for any correct implementation of the Design
Where: acceptance/policy.spec.luau:47-54 and :70-86; Design, "The policy" rules 3 and 5, "Consolidation".
Evidence:
(a) "passes a tree whose lessons are enforced…" expects `{}` for `zz-test/plain-find` and `zz-test/a-case`. They are in the same skill and `make` gives both `tags: [wiring]` and `check: Is it pinned?`. Matching tags alone score 0.35 × 1.00 = 0.35, which is HARD, inclusive (consolidate.spec:56 pins "0.35 itself" as hard). With E4's word rule the score is 0.68: words {zz-test, plain-find, pinned} against {zz-test, a-case, pinned}. Rule 5 therefore must report the pair, so `toEqual({})` fails.
(b) "caps the body" builds `zz-test/cap` with `enforced_by: {LINT}`. FILES[LINT] holds `lesson = "zz-test/plain-find"`. Rule 3 makes "a lint naming another lesson" a problem, and the same spec's lines 105-112 demand exactly that problem. So line 82's `toEqual({})` fails for the `full` and `part` rows.
Because no prototype was built, these went unnoticed. AC2 is unreachable as written.
Critique: The tempting fix is to loosen the assertion to `has(...)`. That would stop the case from proving "a clean tree passes", which is the only negative case for over-reporting.
Consequences: Fixtures that share tags are a trap in every spec that calls the policy on more than one lesson, because tags alone reach HARD. The same trap makes merge.spec:162-164 pass for the wrong reason: `keep` and `old10` share title and check, so they score 0.65.
Recommendation: In (a), give each lesson its own tags and check words, and assert its score is below 0.20 with `consolidate.similar` in the case itself. In (b), build `files` per case with `lesson = "zz-test/cap"`. In merge.spec, vary the titles and checks so the hard pair is not what turns the policy red, and assert the marker message (`merged`, `tighten`). Then run these cases against a few-dozen-line scratch `codify.policy`/`similar` and record the result (z-design step 4).
Lesson: z-design/prove-specs-pass-on-a-prototype

### F2 [high] merge.spec seeds a lesson with no source, so `lessons --check` can never exit 0 there
Where: acceptance/merge.spec.luau:41, :148, :170, :174; lessons.luau:424-426.
Evidence: `zz-arch/foreign` is `lesson("both", "wiring", "Another skill.")`. It has no `from:`, and no harvest line in SEED names it. The unchanged `lessons.check` adds `zz-arch/foreign: no source: no harvest entry names it and it has no from`. Lines 148 and 174 (`toBe(0)`) therefore fail for a correct `lesson-merge`. Line 170 (`toBe(1)`, "no lesson zz-test/old1, and it says it was merged") passes even if the late reference is never detected and the hint is never printed.
Critique: AC8 fails today for a correct implementation, and its one case for the stale-reference hint is vacuous.
Consequences: Once foreign has a source, line 170 depends on the hint, which no other case pins (F11).
Recommendation: Give foreign `from: test`. At line 170, assert the output holds `R0010/harvest.md: design-review-001 F3: no lesson zz-test/old1 (merged into zz-test/keep)`. That also pins the Design's `merged into` hint.
Lesson: z-design/prove-specs-pass-on-a-prototype

### F3 [high] The one statement of the process cannot sit in zz-rules' Lessons section without breaking c0111/skill-docs (Overrides: none)
Where: Design, "The process", first bullet ("Its **Lessons** section gains the one statement of the order"); docs.spec:79-86; z-nile/tests/acceptance/c0111/skill-docs.spec.luau:51-85; zz-rules SKILL.md:176 (its only `## Lessons`, the shared paragraph).
Evidence: c0111 reads `section(text, "Lessons")` in every SKILL.md and expects all 14 to be byte-identical apart from `--skill <name>` (line 79). docs.spec reads the same `section(zz-rules, "Lessons")` and requires the order inside it: `./zn lessons --consolidate --for <id>`, then `` `enforced_by` ``, then `- codify <lesson id>:`, then `./zn lessons --check --policy`, then `lune run z-nile/lints`, plus `not codifiable: <why>` and `` `Codify:` ``. Both specs pass only if the whole statement is copied into all 14 skills. That contradicts "stated once … the 14 skill paragraphs point at it" and the bullet's own "(zz-rules skill, Lessons)". Any other placement turns c0111/skill-docs red, an override the document doesn't name.
Critique: The author will be tempted to copy the statement into all 14 paragraphs. That is the restated-rules defect the Design cites as its model.
Consequences: Moving the statement to a new section changes the pointer text in the 14 bullets and the section docs.spec reads. A heading that starts with "Lessons" is caught by `section()`'s prefix match, which reads the first `\n## Lessons…`.
Recommendation: Put the statement in a new zz-rules section whose heading does not start with "Lessons", for example `## Writing a lesson: consolidate, then codify`. Point the shared bullet there ("(zz-rules skill, Writing a lesson)"). docs.spec reads that section. Add a docs.spec case that the order phrase (`./zn lessons --consolidate --for`) occurs in exactly one SKILL.md, which pins "once". Keep `Overrides: none` true by leaving the 14 shared paragraphs identical.
Lesson: z-design/restated-rules-move-together

### F4 [high] `codify.ledger` turns every historical `- codify` line into a permanent lock on the lesson's state
Where: Design, "The policy" (`codify.ledger`), "The process" step (3) ("`codify.ledger` fails a line that disagrees with the lesson"), lesson-merge ("`part` unless every merged lesson was full, `not_codifiable` only if none is enforced"); policy.spec:162-178.
Evidence: The sweep records `- codify X: not codifiable: …` in this raft's harvest.md, which goes to `done/` with the raft. A later item (c0192 or c0193, or anyone who sharpens X and finds a lint) sets `enforced_by` on X. From then on the done/ line disagrees, `./zn lessons --check --policy` fails on every gate, and the only fix is to edit a done ledger. `lesson-merge` hits the same wall by design: it rewrites `- codify old1: not codifiable: …` to `- codify keep: …` while giving `keep` an `enforced_by` union. The Design also never says what a codify entry is in `Entry`. Today `parseHarvest` rejects it as `not an entry`. If it is parsed into `lessons`, `lessons.sources` counts it as a source and `check`'s "no source" rule is bypassed. If it is parsed as a review entry, `check` looks for a review file named `codify`.
Critique: A ledger is history, and the Design treats it as current state.
Consequences: The fix changes which harvest lines the gate judges, and `parseHarvest`, `sources`, `uncovered` and `check` all read the new kind.
Recommendation: Keep the `codify` record, since it is captured. The gate checks only its shape and that its lesson exists or is named in some lesson's `merged:`. Agreement with the lesson's state is checked only where the record is written: z-design 5.5 and zz-execute Phase 5 run `./zn lessons --check --policy --item <id>`, or `ledger` judges only items outside `done/` and `retired/`. Specify `Entry.codify = { lesson: string, ref: string?, reason: string? }`: not a source, never counted by `uncovered`, skipped by `check`'s review branch. Cases: a done/ ledger line `not codifiable` for a lesson now enforced passes the gate; the current item's disagreeing line fails `--item`; a codify line alone does not count as a source.

### F5 [high] The captured guard "runs in the gate and fails on a fixture that breaks its rule" is designed only for lints
Where: Solution bullet 5 (captured); Design rule 3; "The checks a lesson points at", Specs.
Evidence: (a) Rule 3 accepts any `*.spec.luau` not under a `.tracker/` folder outside `done/`. The gate runs only `<home>/tests/**` (run.luau:178 `collect("tests")`, from each home), so rule 3 accepts `z-nile/.cache/x.spec.luau`, `z-nile/.tracker/issues/done/c0999/acceptance/x.spec.luau` (allowed explicitly, never run; done items have no acceptance folder, see `ls …/done/*/acceptance`: none), an `experiments/x.spec.luau`, or `z-nile/lints/x.spec.luau`. (b) For a spec ref nothing proves the case fails on a fixture that breaks the rule. A lint has `selfTest` over `bad`; a spec case, existing or new, has no counterpart. Neither the Design nor any AC addresses it.
Critique: Half of the captured guard is missing for one of the two ref kinds, and 13 of E2's 30 codifiable lessons are spec or helper refs.
Consequences: (b) needs a mechanism that is either static or recorded, and a promoted case cannot be edited to add a negative fixture.
Recommendation: (a) A spec ref must lie under a registered project's home `tests/` folder (projects.load → homes) and never under `.cache`. Cases: `.cache`, `done/…/acceptance` and `experiments/` refs refused; `pickman/tests/unit/x.spec.luau` accepted. (b) Pick one and design it:
(i) A spec ref is valid only if a case named `[<lesson id>] …` exists in a gate-run spec and plants the breaking input itself (statically checkable by name). For an existing promoted case, the sweep adds a new spec file beside it.
(ii) The harvest `codify` line records the mutation run (`mutant: <what>; failed: <case>`), and the policy checks that the line exists. It is weaker: a record, not a rerun.
If neither is acceptable, escalate to the user: keep the outcome and pay for a mutation stage in the gate (a scratch copy per spec ref, costly in CPU), or accept (ii) as the proof.

### F6 [high] The sweep's fully-enforced floor rests on engine refusals the Design never designs, and the override check skipped them
Where: Design, "The backfill sweep" ("the plan is experiments/E2-classification.tsv"); E2 rows; Regression guard (`Overrides: none`); E6(c).
Evidence: The floor is 8 fully enforced out of the 9 E2 calls F. Of those 9:
- `z-design/finished-overrides-land-before-ready` is "engine: ready refuses …".
- `z-ticket/capture-subject-lists-every-id` is "engine: land refuses …".
- `zz-test/run-the-pinned-tools` is "gate stage: lune --version …", which is neither a lint nor a spec, the only ref kinds rule 3 allows.
- `zz-test/sequestered-edits-parse-and-list` is a "lint" that runs `bash -n` and `AC_LIST=1`, not a pure scan over texts.

Among the partly enforced rows, `z-raft/rafted-member-changes-stay-in-the-raft` plans "status <R-id> preparing refuses a raft with grouped members". c0116/claims.spec.luau:414 pins `trOk(E, { "status", "R0090", "preparing" })` on a raft holding prepared c0070. None of these refusals has a signature, message, Rules row, spec case or override check, and `affected` for main.luau prints ALL, so nothing narrows the risk. If two of the four fall, the floor fails and the executor stops for the user, which is a known stop written into the plan.
Critique: The floor's honesty depends on work the Design leaves to Phase 1.
Consequences: Designing these refusals adds behaviour to `ready`, `land` and `status`. That brings new refusals for every caller (lesson z-design/new-refusals-reach-every-caller) and possibly overrides.
Recommendation: For each F or P row that changes a command's behaviour, either design it now (the refusal, its message, a Rules row, a sequestered case, and the override check against c0116/claims, c0053/commands-prep and the land specs), or reclassify it to a lint or spec ref that reads texts and recount E2. If the recount leaves fewer than 9 F, escalate to the user: G1's floor of 8 is a guess. Either keep it and design the refusals (about 300 more lines and their override checks), or the user moves the floor.

### F7 [high] Lint baselines keyed by item paths go stale on the next `ready` or `done` and turn main red
Where: Design, Lints (`allow` "a sequestered file mid-prep"); Chore checklist, Existing work (d); `lint.baseline` ("allow entries not scanned … a problem"); E3.
Evidence: c0083 is in the backlog (`./zn find c0083` gives `z-nile/.tracker/issues/c0083`), and its check.sh:184-186 holds the `| grep … || true` hits that `pipe-filter-keeps-the-failure` will find. The baseline key is `z-nile/.tracker/issues/c0083/check.sh`. `./zn ready` moves it to `active/c0083/check.sh`, so the key is no longer scanned (a bad baseline, which fails closed) and the hits at the new path are violations. The gate goes red for every branch that merges main. `touched-paths-exist`'s baseline over 14 designed pickman issues fails the same way at each one's `ready` and again at `done` (done/ is skipped).
Critique: Lesson zz-test/allowlist-keys-exist is cited for `lint.baseline` but not applied to the keys themselves.
Consequences: Any key form has to survive lifecycle moves and compaction renumbering.
Recommendation: Key an item's baseline by item id (`item:c0083`), matched in any lifecycle folder of any root. A key whose id no folder holds is a problem, and the reason is still required. Cases in lints.spec: an `item:` key clears the same file under `issues/c0083/` and `issues/active/c0083/`; it is a problem once no folder holds c0083; a path key keeps today's rule.
Lesson: zz-test/allowlist-keys-exist

### F8 [medium] lesson-merge's rewrite scope is both too narrow and too wide
Where: Design, `lesson-merge` ("rewrites every `<from>` token in the skills' `*.md` and `AGENTS.md`"); merge.spec:127, :133.
Evidence:
- Too narrow: the lint module's `lesson = "<from>"` field, every `lint-ok <from>: …` mark in the repo, and `[<from>]` case names are not rewritten. Merging an enforced lesson leaves rule 3 ("lint names another lesson") and wiring.spec's registry-and-lessons cases red, and its `lint-ok` marks stop clearing hits.
- Too wide: lesson files are `*.md` under the skills folders, so a literal reading rewrites the survivor's own `merged: zz-test/old1, zz-test/old2` and `<!-- merged from zz-test/old1` to `zz-test/keep`. merge.spec expects them kept. The same reading turns `into`'s `distinct_from: <from>` into itself, which the policy refuses as "itself", and leaves duplicate entries in other lessons' `distinct_from`.
Critique: The sweep merges after it codifies (step 8), so merging an enforced lesson is a path the plan itself takes.
Consequences: Promoted spec case names can't be edited, so a `[<from>]` case name stays stale. That is cosmetic only if case names are never refs.
Recommendation: Specify the rewrite set. Lint modules' `lesson` field and `lint-ok` marks in every file the lint runner scans are rewritten, or the merge refuses with "re-point lint X first". `merged:` lines and markers are never touched. `from` ids are dropped from `into`'s `distinct_from`. Other lessons' `distinct_from` is rewritten and deduplicated. Cases: a merge whose `from` a registered lint names (rewritten or refused, as chosen); `into` listing `from` in `distinct_from`; a third lesson listing both.

### F9 [medium] `lessons --for` collides with c0166's selector, and the reconcile table says there is no overlap
Where: Design, Reconciling (c0166 row); consolidate.spec:117-120; c0166.md Solution ("`./zn lessons --for <id>` or `--paths <p>...`").
Evidence: c0166 proposes `lessons --for <issue id>` to select relevant lessons. c0181 gives `--for` to `--consolidate` (a lesson id) and pins `lessons --for zz-test/a` → exit 2 in a spec that will be promoted. c0166's prep would then have to override c0181's promoted case.
Recommendation: Use `--consolidate [<lesson id>]` (positional) or another name, and drop line 120's `lessons --for` assertion. Quote c0166's `--for` in the reconcile row and say how the two divide.
Lesson: z-design/quote-other-preps-before-promising

### F10 [medium] Stated rules with no case, and one rule with no defined reading
Where: Design rule 7, Listing ("the prompt's build index"), Lints ("prints … the lesson's body (the pointer: the fix)"); Rules and mutants table.
Evidence: (a) Rule 7 (dangling ids in the skills' texts, and the `merged into <id>` hint) has no Rules row and no case: policy.spec has none, and merge.spec:170 is vacuous (F2). Its reading is also open. Does "the skills' `*.md`" include `checklists/` and the lesson files themselves? Does a backticked id have to be the whole token? In every `noLessons` fixture the copied real skill texts (z-design/checklists/chore.md: "lesson z-design/new-rules-migrate-existing-work") dangle, so `--check --policy` is red there for this reason too. (b) AC3 claims the prompt index, but every case goes through `cmd.lessons`. A mutant that hides enforced lessons in `cmd.lessons` instead of `select` leaves `renderPrompt` (main.luau:4174, `select(mine, sources, { when = "build" })`) listing them. (c) The captured "failure message names the lesson and how to fix it" is asserted for lints only as the id and path. The body that follows is not checked.
Recommendation: (a) Add Rules rows and policy cases: a backticked whole-token dangling id; a `lesson <id>` form; a merged id that names its survivor; an id in a lesson body (decide whether it counts); a substring that must not match (`zz-test/old1` in `zz-test/old10`). State the file set exactly. (b) Add a listing case through `./zn prompt` or `ready`'s render in a fixture, or a pure case on the function that builds the prompt index. (c) In lints.spec, seed a lesson file under `--root` and assert its body is printed once after the violation. Also decide where the runner reads lessons from (`--root` or the repository) and pin that.
Lesson: zz-test/kill-mutants-where-the-value-is-built

### F11 [medium] The lint runner reads the disk, not the tree, so its answer depends on local files
Where: Design, Lints (the runner "walks the root (skipping .git, .cache, .worktree)"); E3 (reads `git ls-files`).
Evidence: E3 measured tracked files only. A walk also reads ignored and untracked files: `prompt.md` in `rafts/active/<R>/` inlines check.sh files and specs, as do local scratch notes. It also reads the `.claude/skills/<name>` links if followed, which are a second spelling of `z-nile/skills/…`. A gate on one machine can then fail where a fresh clone passes. Each lint module also holds its `bad` fixture as text. The markers lint's own module carries `<<<<<<<` lines and flags itself, and a `plain-find` lint's fixture flags itself.
Recommendation: In a git work tree, read `git ls-files -co --exclude-standard`. Outside one (the spec's `.cache` root), walk without following links. Every lint skips `z-nile/lints/` unless it opts in. Cases: an ignored file with a hit is not reported; a lint module whose `bad` text would hit passes. Re-measure E3 against that set.
Lesson: z-design/readings-from-text-not-disk

### F12 [medium] Case existence by `it("<case>"` rejects case names stylua wrapped onto the next line
Where: Design rule 3 ("whose text holds `it("<case>"`").
Evidence: In `z-nile/tests` and `pickman/tests`, 398 `it(` calls end their line and put the name on the next one, against 2,311 written inline (grep `^\s*it\($` vs `^\s*it\("`). This draft's own specs do it (format.spec:60-61, docs.spec:111-112). New `[<lesson id>] …` names are longer and wrap more often. A valid ref to such a case is refused.
Recommendation: Match `it%(%s*"<escaped case>"` across whitespace and newlines (with plain matching or escaping, lesson zz-test/plain-find-for-literals). Add a policy case where a wrapped name is accepted and a similar name that is not the same case is refused.

### F13 [medium] The sweep can break promoted specs that pin real lessons and skill text; the Regression guard names neither
Where: Regression guard; Design, lesson-merge (widest `when`, deletes `from`), the sweep; zz-arch edits.
Evidence: c0119/scope-lessons.spec.luau:16-23 requires `z-design/never-narrow-captured-scope` and `zz-review/no-scope-cut-as-fix` to exist, keep `when: design` and tag `scope`, and keep an `R0042 note user correction 2026-10-20` source. Merging either away deletes it. Merging a `build` or `both` lesson into it widens `when`. Either turns c0119 red. c0172/merge.spec.luau:48-52 pins the exact zz-arch row "`z-nile/check.sh`, `affected.luau`, `roots.luau`, `setup.sh` | the gate, …". Adding `lints.luau` to that row, the natural edit, breaks it.
Recommendation: Name both pins in the Regression guard and as sweep constraints: those two lessons are never a `from`, and a merge into them keeps `when: design`. `lesson-merge` should refuse to widen `when` on a lesson a promoted spec pins, or the sweep simply does not merge them. The lints get a new zz-arch row. AC11 adds c0119/scope-lessons and c0172/merge to the specs it runs.

### F14 [low] G3's stated reason is false: `lessons` is not in READ_ONLY
Where: Design G3.
Evidence: main.luau:5624-5634 READ_ONLY = list, audit, find, members, metrics, board, workstreams, promote-check, stamp, and tracker-guarded.spec pins exactly that set. `lessons` already runs `guardRepoRoot`.
Recommendation: Rewrite G3 on the real reason: a writer must refuse the main checkout, while `lessons` must keep running there (zz-rules, Worktrees). The choice itself can stand.

### F15 [low] AC10's label does not match its command, and its pipe hides a crash
Where: check.sh:40-47; Acceptance AC10 ("AC10b prints the share and the weight").
Evidence: AC10's label claims the floor and the weight, but its command checks the policy, the lints and hard pairs. AC10b enforces the floor while its label and the document say it "prints". `./zn lessons --consolidate | grep -qF "must resolve"` runs inside `bash -c` without `pipefail`, so a crashing `--consolidate` reads as "no hard pair".
Recommendation: Capture the output (`out=$(./zn lessons --consolidate) || exit 1`) and grep the variable. Relabel AC10 and AC10b to what each checks, and make the document's AC10 say the same.
Lesson: zz-test/pipe-filter-keeps-the-failure

### F16 [low] The weight floor and the size have no arithmetic behind them
Where: G1 (205,000 bytes, "calibrated"); frontmatter `size: 3000`.
Evidence: Over the 149 files with E2's levels, capping every body at its cap and adding a ~70-byte state line gives about 233,900 bytes. 21 bodies are over their caps today. Reaching 205,000 therefore needs about 29 KB more from bodies already under their caps (roughly 12% of the remaining text) or from merges. The document doesn't say so. The size has no breakdown. By rough count the engine and the lint runner come to about 1,300 lines, 30 checks at about 40 lines each come to about 1,200, the skills to about 150, and the 149 lesson edits add several hundred more.
Recommendation: Record that arithmetic under G1 so the user can judge the guess, and give the size its breakdown. The size doesn't change any decision, since the issue is a raft by itself either way.

### F17 [low] Smaller inaccuracies
Where: Reconciling (c0193 row); Design, Specs (footer); The process step (2).
Evidence: (a) c0193 says "for example a spec helper that runs every scanner over hostile inputs … The prep decides", but the row says it names "this issue's hostile-input helper", and c0181 designs none. (b) The footer prints every lesson whose ref names the failing file, even when the ref names a different case of that file (footer.spec:27 pins `zz-test/two`'s case ref as file-wide). That points the reader at the wrong lesson. (c) Step (2) lists "a tool refusal" as a way to codify, but the only ref kinds are a lint or a spec.
Recommendation: (a) Correct the row. (b) Either filter case refs by the failing case's name, which the runner has, or say in the Design why the whole file is meant. (c) Say that a tool refusal is codified through a spec case that pins it.

Verdict: changes
