# Review 001: c0170 (design mode)
Inputs: prep worktree `prep-helper-spec-tier` at aea2fbb7 plus the uncommitted `c0170.md`, `check.sh`, `acceptance/tiers.spec.luau`, `acceptance/layout.spec.luau`, `experiments/c0170.patch`, `experiments/mutants.py`; prototype base 69282043 (`origin/R0059-frame-roundtrip-tolerance`'s tip); `origin/main` ace1d22b; `./zn capture c0170` (235bf8b6). Runs were made in a scratch clone (`$TMPDIR/tmp.5QOCK2zxMy/repo`, 69282043 + the patch + `acceptance/` + the worktree's `check.sh`, committed as `reviewer@localhost`): `mutants.py` (BASE 12 passed; T1–T8, T10, T11 killed; T9 survived, as recorded), `./zn check c0170` 3/3, `./zn promote-check c0170` OK, plus the reviewer's own mutants and probes quoted below.

### F1 [high] AC2 passes with a meta case that drops every require but the helpers', so a helper spec that requires a feature or a fixture passes the gate
Where: `acceptance/layout.spec.luau`, case "the tier case hands tiers every helper and unit spec with its requires, and every tests/lib helper"; Rules and mutants row "the meta case judges unit specs too" / T9's row.
Evidence: the case compares the *file list* for every spec, but the *requires* of one spec only, `tests/helper/plain/plain.spec.luau`, whose requires are `@tests/lib/plain` and `@tests/lib/t`. Two reviewer mutants of the meta case in the clone, run on both acceptance specs:
- R1, `table.insert(requires, spec)` → `if string.sub(spec, 1, 7) == "@tests/" then table.insert(requires, spec) end`: `SURVIVED`.
- R2, the same keeping only `@tests/lib/` requires: `SURVIVED`.
Under R2 the meta case never hands `tiers` a `@logic/…`, `@tests/fixtures/…` or `@shared/…` require, so a `tests/helper/plain/x.spec.luau` that requires `@logic/Maze` (the helper rule's first bullet) is green in every gate. AC2's label says the case hands tiers "every helper and unit spec with its requires"; a wrong implementation passes it.
Critique: the obvious fix, "also compare a second spec's requires", is another sample: a filter that keeps `@logic/` and drops `@tests/fixtures/` would survive whichever sample is picked.
Consequences: comparing every spec's requires needs an expected value the spec builds itself. Built with the same reader (`graph.stripComments` + `graph.REQUIRE_PATTERN`) it is still independent of the meta case's code path, which is what the mutants change; order and duplicates must be compared as the Design states them ("requires as written"), or sorted on both sides.
Recommendation: in that case, for **every** file in `seenSpecs`, compare `byFile[file]` (sorted) with the requires the spec reads itself from that file (sorted), and assert the tree holds at least one spec whose requires include a non-`@tests/` require (today's unit specs do), so the comparison can't be vacuous. Add R1 and R2 as Rules and mutants rows ("the meta case hands every require, not only the helpers'") and run them. Also add R3, `r == own` → `string.sub(r, 1, #own) == own` (survives today: `@tests/lib/plainx` would count as the own helper), with a tiers.spec assertion that a helper spec requiring `@tests/lib/plainx` and not `@tests/lib/plain` breaks the rule.
Lesson: zz-test/pin-call-site-arguments

### F2 [medium] The rule judges a require by its spelling, so a unit spec requires a helper through a relative path or an alias in another case and the meta case stays green
Where: Design, "The rule" (`tests/unit/…`: "each require that starts `@tests/lib/`"); `tiers.luau` (`string.sub(r, 1, #LIB) == LIB`).
Evidence: in the clone, `pickman/tests/unit/Maze/zz_probe.spec.luau` with `require("../../lib/plain")` and `require("@Tests/lib/plain")` (graph.resolve lowercases aliases, `graph.luau:305`): the probe ran (`1 passed`), and `lune run tests/run -- tests/meta/architecture.spec.luau` gave `10 passed, 0 failed` with it in the tree. Relative requires of `tests/lib` are not exotic here: `tests/lib/t.luau:4` and `tests/lib/renamed.luau:4` use them. The same holds for the helper tier's own-helper test (a helper spec requiring `../../lib/plain` "does not require its helper").
Critique: the tempting fix is to add the relative and upper-case spellings to the prefix test, which misses the next spelling (`@znile/../pickman/tests/lib/plain`, `@shared/../../tests/lib/plain`).
Consequences: judging resolved targets means the meta case resolves each require (`graph.resolve(file, spec)`, the graph library's one reader of what a require names, lesson zz-arch/one-reader-per-format), so `Spec` changes shape (`requires` keeps the text for the messages, plus a `targets` list of resolved paths, `nil` for `@lune/`); an unresolved require is already a failure of "every require resolves", and `tiers` must say what it does with one (judge the text, or skip it). `@tests/lib/t` resolves to `tests/lib/t.luau` (the re-export), so the allowed set becomes targets `tests/lib/t.luau` and `tests/lib/<helper>.luau`.
Recommendation: decide by resolved target: `tiers` stays pure over `{ file, requires, targets }`, and the meta case fills `targets` with `graph.resolve`. tiers.spec gains cases with a relative and an upper-case alias spelling (unit spec → one violation; helper spec → its own helper found), and layout.spec's every-spec comparison (F1) covers the targets. Mutant rows: "judge the text instead of the target" (killed by the relative case).

### F3 [medium] The helper tier can't hold sim's existing spec, and the new skill sentence contradicts where that spec sits
Where: Design, "The tier" ("may require only `@tests/lib/<helper>`, `@tests/lib/t` and `@lune/` builtins"); the new "Choosing a tier" sentence ("A spec of a `tests/lib` helper itself goes in `tests/helper/<helper>/`"); Non-goals ("Specs for helpers that have none today (`sim`, …)").
Evidence: `pickman/tests/scenario/harness.spec.luau` ("scenario: walker story") is a spec of `tests/lib/sim` itself: it requires only `@tests/fixtures/sim/walker`, `@tests/lib/sim` and `@tests/lib/t`, and asserts sim's trace. So sim has a spec today, and under the designed rule it can't move to `tests/helper/sim/` (the fixture require is a violation), while the new sentence says it belongs there. `pickman/tests/lib/fakeengine.luau:22-28` requires six Logic features, and its specs need a built place (`@tests/lib/place`), so a fakeengine helper spec can't meet the rule either. Two of the four pickman-only helpers can't have a spec in their own tier.
Critique: the tempting fix is to delete the sentence or narrow the tier to "plain-like" helpers, which leaves a tier defined for every `tests/lib` helper that half of them can't use, and the next helper spec goes to `tests/unit` or `tests/scenario` by default.
Consequences: allowing `@tests/fixtures/<helper>/…` answers sim; fakeengine needs either "the modules the helper itself requires" (read from the graph: a second input to `tiers`) or an explicit statement that a spec driven through sim or a built place stays in scenario or place. Either way pickman-test's "Choosing a tier" has to say which, in one place, and the harness.spec location has to agree with it.
Recommendation: allow `@tests/fixtures/<helper>/…` in a helper spec (row and rule text, tiers.spec case: `tests/helper/sim/x.spec.luau` requiring `@tests/fixtures/sim/walker` passes; requiring `@tests/fixtures/other/y` fails), and write the "Choosing a tier" sentence so it agrees with the sim rule above it ("anything driven through `@tests/lib/sim` … goes in `tests/scenario/`"): either harness.spec moves to `tests/helper/sim/` in this item's renames commit, or the sentence names scenario's sim specs as the exception. Correct the Non-goal's claim. Say in the Design what a fakeengine spec would do.

### F4 [medium] The promoted layout.spec pins today's answers of files it doesn't own, one of them in another project that never selects it
Where: `acceptance/layout.spec.luau`, cases "the gate selects …" (`toEqual({ "ALL" })` twice), "plain.spec sits in tests/helper/plain/ …" (`caseOf(plainSpec, "<two case names>")`), and "pickman-test and zz-test name the helper tier" (zz-test's sentence).
Evidence:
- `affected("pickman/tests/lib/plain.luau")` must be exactly `{ "ALL" }`. The captured outcome is that a helper's specs are selected when it changes; a selector that one day selects the dependents of a `tests/lib` file (correct, and faster: zz-test, Speed) turns c0170's promoted spec red.
- plain.spec's case names are R0059's own spec's text, not sequestered and freely edited; renaming either case reddens c0170's promoted spec, an override nobody would expect.
- zz-test is z-nile's: `lune run z-nile/affected -- --project pickman z-nile/skills/zz-test/SKILL.md` prints nothing (it prints `ALL` for z-nile alone), so a z-nile raft that rewrites that sentence passes its affected gate and turns *pickman's* full gate red: by zz-test's own definition a graph miss. No pickman spec reads a z-nile skill today: `git grep -nE 'z-nile/skills' -- 'pickman/tests/**.luau'` has no hits. The same holds for `z-nile/affected.luau` itself, which the selection case runs.
Critique: the tempting fix is to drop the pins, which loses the restated-rules pin the Design promises (lesson z-design/restated-rules-move-together).
Consequences: a check.sh-only assertion runs at check and `done`, never after, which is what a claim about another project's text needs; the pickman-test pins can stay in the spec (precedent: `pickman/tests/acceptance/c0003/pipeline.spec.luau:9`, `c0064/docs.spec.luau:9` read the same skill).
Recommendation: the selection case asserts the rule: for the helper's own change and for `tests/lib/plain.luau`, the answer is `{ "ALL" }` or contains `tests/helper/plain/plain.spec.luau`. The plain.spec case asserts the file has at least one case and every case passes, with no names. The zz-test pin moves to check.sh: a `grep -qF` in AC2's line, or its own AC (lesson zz-review/recommendations-pick-spec-or-check: it is a claim about today's z-nile text, so check.sh).
Lesson: zz-test/promoted-specs-pin-rules-not-sets

### F5 [medium] Implementation steps 2 and 3 fail as written
Where: Implementation steps 2 and 3.
Evidence: in a fresh clone at 69282043, step 2's `git mv pickman/tests/unit/plain/plain.spec.luau pickman/tests/helper/plain/plain.spec.luau` gives `fatal: renaming … failed: No such file or directory` (rc 128): `tests/helper/plain/` doesn't exist. With the folder made and the move committed, step 3's "`git apply` it after step 2 with the rename already done" gives `error: pickman/tests/unit/plain/plain.spec.luau: No such file or directory` (rc 1), because the patch holds the rename. `git apply --exclude='pickman/tests/unit/plain/*' --exclude='pickman/tests/helper/plain/*' <patch>` applies (rc 0).
Critique: the "or copy its hunks" fallback works, but an executor who runs the commands as given hits two errors in the first two steps.
Consequences: none beyond the text.
Recommendation: step 2 is `mkdir -p pickman/tests/helper/plain && git mv …`; step 3 quotes the `--exclude` apply above (re-run once F1–F4's changes reach the patch).
Lesson: z-design/instructions-runnable-where-they-run

### F6 [low] The existing-work sweep's hit list is shorter than its search
Where: Design, Checklist, "Existing work" ("hits are acceptance-tier specs only …: c0153's, f0109's, f0126's").
Evidence: `git grep -nE '@tests/lib/(sim|place|fakeengine|plain|renamed)' origin/main -- 'pickman/.tracker/issues/*' 'pickman/.tracker/rafts/*' ':!pickman/.tracker/issues/done/*' ':!pickman/.tracker/rafts/done/*' ':!pickman/.tracker/issues/c0170/*'` also hits c0159 (`acceptance/narrowed.spec.luau:24`, `experiments/narrow.patch`), f0143 (`acceptance/controls.spec.luau:12`, `hud.spec.luau:11`, `place.spec.luau:10`) and f0158 (`acceptance/place.spec.luau:18-19`). Every hit is an acceptance-tier spec or a patch of `tests/acceptance/` files, so the conclusion holds.
Critique: the list reads as complete.
Consequences: none.
Recommendation: paste the search and its per-item hits.
Lesson: zz-review/lists-paste-their-search

### F7 [low] The sentences c0170 edits still list the helpers without `plain`, and layout.spec's header names an AC4
Where: the zz-test sentence the patch edits ("its `sim`, `place` and `fakeengine` helpers"); pickman-test, "Running pickman's specs" ("`sim`, `place` and `fakeengine` are pickman's helpers"); `acceptance/layout.spec.luau:2` ("c0170 AC2, AC3 and AC4").
Evidence: the tier is named for `tests/lib` helpers and its first member is `plain`, which neither list names; the issue has AC1–AC3, and layout.spec runs under AC2 only.
Critique: an exhaustive list beside the new tier that omits its first helper.
Consequences: none (no pin reads those lists).
Recommendation: add `plain` to both lists in step 4; fix the header to "AC2".
Lesson: zz-rules/exhaustive-lists-name-new-things

## Candidate lessons (for the lead)
- zz-test (sharpen pin-call-site-arguments): a spy that checks what a call site gathers compares it for every element it gathers, never one sample, and the sample tree holds an element of every kind the gatherer could drop; check: would a gatherer that filters out one kind of input still pass the spy case? (F1)
- zz-arch or pickman-arch: a rule over what a file requires judges the resolved target (`graph.resolve`), never the spelling; check: does a relative path or another alias case to the same module pass the rule? (F2)
- zz-test: a project's promoted spec never reads another project's files, because that project's changes don't select it; such a pin goes in check.sh; check: does `lune run z-nile/affected -- --project <spec's project> <the read file>` select the spec? (F4)

Verdict: changes
