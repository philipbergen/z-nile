# Review 001: R0076 (code mode)
Inputs: `git diff origin/main...HEAD` at head 9735c804 (origin/main and merge base 2005d168); R0076.md; c0185.md, its check.sh, acceptance/ and experiments/ (c0185.patch, mutants.py).
Sequestration: `git diff --find-renames=100% --name-status origin/main...HEAD -- '*/.tracker/**/check.sh' '*/.tracker/**/acceptance/**'` lists one line, `M z-nile/.tracker/issues/active/c0185/check.sh`. That is the user-approved edit recorded in c0185's Verification log (Deviation, 2026-11-04), so it is not a finding here. `git diff --summary` shows no mode change. acceptance/ and experiments/ are untouched since `tracker: start` (8b027049).

## What was run (this round, on 9735c804)
- **Patch fidelity.** I cloned to a scratch dir at 2005d168, ran `git mv pickman/tests/lib/place.luau z-nile/tests/lib/place.luau` and `git apply --reject experiments/c0185.patch`, then compared every changed file with the branch.
  - The branch matches the patch in every file but three.
  - `z-nile/lib/graph.luau` differs only in stylua's line wrapping of one `table.insert` in `walkMappings`.
  - The patch rejected one hunk of `z-nile/skills/zz-test/SKILL.md` and both hunks of `pickman/skills/pickman-test/SKILL.md`. The branch's text of those hunks is the patch's text with main's newer `plain` helper and `helper` tier kept.
  - Each hand-merged sentence is pinned:
    - zz-test by `docs.spec` ("`place` re-exports the shared harness's ...", "`.luaurc` or any `*.project.json` ...").
    - pickman-test by check.sh AC7 ("and so is `place` (the Rojo-built place, ...", "every change to what the place is built from").
  - This answers zz-execute lesson run-every-hand-merged-hunk.
- **`./zn check c0185`: 8/8 PASS.** AC4 includes the five new homes' `check.sh --full` and pickman's static stages.
- **`./zn promote-check R0076`: OK.**
- **Full spec suites** (spec runner only, not the full gate):
  - `cd pickman && lune run tests/run`: 1815 passed, 0 failed, 269 spec files.
  - `cd z-nile && lune run tests/run`: 1369 passed, 0 failed, 200 spec files. This includes c0120 `check-paths`, `finished` and `graph-homes`, c0002/c0041/f0061 through pickman's run, tooling `affected` and `game-roots`.
- **The check.sh edit, with and without its line.** I ran `ac6_fixture`, extracted from check.sh, through `./zn run --time 120 -- bash <script>` from `z-nile/`:
  - Without the `cp .../tiers.luau` line: `error requiring module "@tests/meta/tiers": could not resolve child component "tiers"`, then "the clean home:" and rc=1.
  - With it: rc=0.
  - `tiers.luau` requires nothing (its only `require` words are in comments), so copying one file closes the fixture's closure. `git log origin/main -- pickman/tests/meta/tiers.luau` is R0065 (b3549564), as the log says.
  - The edit is the minimal correct fix. It changes nothing that AC6 asserts.
- **Selector probes** (`./zn run --time 120 -- lune run z-nile/affected -- <path>`):
  - `arcade/src/shared/Info.luau` selects the place spec of all six homes (arcade, asteroids, invaders, portal, snake, and pickman's 10 place specs) plus 40 pickman acceptance specs that load its place.
  - `arcade/src/server/Receipts.luau` selects the same place specs.
- **Formatting and lint.** `stylua --check` over every changed `.luau` passes. `selene` over the six z-nile files reports 0 errors and 0 warnings.
- **Fail-closed selection.** z-nile/check.sh runs under `set -euo pipefail`, and `selection=$(lune run z-nile/affected ...)` is a plain assignment. So a selector that errors on a project file that is not a project (`projectsIn`) stops the gate rather than selecting nothing.

## Judgement against the Design
- **Graph.**
  - `srcAliasAllowed(spec, fromServer)` keeps its one-argument meaning, and its `@game/ServerStorage/` prefix length is 20.
  - `serverFile` follows "longest mapped path within each place, every place that maps it, at least one".
  - `mappings`/`insideFolder` are the one walker and the one "stays inside" test. `place.luau` and `home.luau` use both, and the old copies are gone.
  - `placeInputs` fails closed and keeps the legacy answer.
  - `affectedSpecs` matches at a folder boundary (`underAny`).
  - The shared file `z-nile/tests/lib/place.luau` also matches the place-library suffix (home `z-nile/`, legacy inputs). This is harmless: z-nile has no `src/` or project file, and any z-nile change forces ALL.
- **Selector.** `HOME_FULL` `[^/]*%.project%.json$` is anchored under the home prefix, so a project file one level down is not a place.
- **Place harness.**
  - Roots come from the project file's inside-folder nodes, so the library is not the game's.
  - An unloaded DataModel errors.
  - `place.scripts` is called only in c0002's `place-rules`, on `place.load()`'s own DataModel: `git grep -n 'place\.scripts'`.
- **Home rule.**
  - The two library folders are allowed only at their nodes, by collapsed target and real path.
  - A nested project is refused.
  - The alias, the default-place mappings and the two wrappers are required.
- **Cross-home rules.** `logicOutside` over `g.deps` catches every on-disk escape. An `@game/...` require from Logic is already refused by the engine-word rule, which matches `game` in `"@game/`. The instance-tree spelling is "unresolved". pickman's meta spec wires both rules, and AC6's fixture pins the call-site arguments (`LOGIC`, the shared path, the wrapper, `srcAliasViolations("src")` with no places).
- **Rules and mutants.** The branch equals the prototype on which `mutants.py` recorded 52/52 killed, apart from formatting and the doc hunks above, so every row still has a failing spec. I found no unlisted plausible mutant that a spec misses.
- **Repository safety.** The new specs and the AC6 fixture write only under `z-nile/.cache/c0185-*`, and remove what they write. `place.load` writes the home's `.cache`, which `.gitignore:2` covers for every home. No guard file is touched. My own probes left nothing behind: one interrupted fixture folder of mine was removed, and `git status` is clean apart from this file.

### F1 [low] The five homes' test skills still call `place` a pickman-only helper, in the sentence that says the home has its own `place`
Where: `arcade/skills/arcade-test/SKILL.md:18`, and the same line 18 of `portal-`, `snake-`, `invaders-` and `asteroids-test`.
Search: `git grep -n "are pickman's (\`pickman/tests/lib/\`)" -- '*.md'` gives those five lines and c0184's frozen experiment copies.
Evidence: snake-test line 18 reads: "The helpers `sim`, `place` and `fakeengine` are pickman's (`pickman/tests/lib/`): a snake spec never requires another home's helper. ... as c0185 did for `place` (`tests/lib/place.luau` re-exports it, and `tests/place/library.spec.luau` is this home's place tier)." Design 6 keeps the equivalent sentences in zz-test and pickman-test because of c0170's AC4 text pins. Those pins grep zz-test and pickman-test only, so they don't cover these five skills, and nothing pins "`sim`, `place` and `fakeengine` are pickman's" in them. My search over `z-nile/tests`, `pickman/tests` and every `.tracker` check.sh or spec found no such pin.
Critique: A reader writing a snake place spec is told, in one sentence, that `place` is another home's helper a snake spec never requires, and that the home re-exports it. The rule this raft adds is "require `@tests/lib/place`, never the shared file", and the sentence half-contradicts it. The tempting fix is to delete the "as c0185 did for `place`" clause, but check.sh AC7 pins that clause.
Consequences: if the list drops `place`, the sentence must still say where `place` comes from. AC7's pinned phrase 'as c0185 did for `place`' must survive, and the five skills must stay identical apart from the name.
Recommendation: in all five, read "The helpers `sim` and `fakeengine` are pickman's (`pickman/tests/lib/`): a <name> spec never requires another home's helper. One that needs a helper asks for its move into the shared harness (`z-nile/tests/lib/`), as c0185 did for `place` (...unchanged...)". Then re-run `./zn check c0185` (AC7) and c0184's `generic.spec`/`docs.spec`. This is optional: it is a clarity fix only.

## Candidate lesson (for the lead to harvest; a reviewer writes no lesson file)
zz-test: a check.sh fixture that copies a real spec into a fixture home also copies that spec's home-relative requires (`@tests/...`), or loads it through a one-line re-export. The reason: c0185's AC6 copied only `architecture.spec.luau`, R0065 later made that spec require `@tests/meta/tiers`, and the sequestered check.sh needed a user-approved edit during execution. Check: for each file a check.sh or spec copies into a fixture, which of its requires resolve through the fixture's `.luaurc` rather than the original's, and is each of those copied too?

## Judged criteria (code mode only)
None (c0185 has no Judged criteria).

Verdict: approve
