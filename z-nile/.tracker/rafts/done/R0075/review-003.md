# Review 003: R0075 (code mode)
Inputs: HEAD cdd0e5afd1e8154b2d5d98d8d03ead1272b90ef7 (branch R0075-scaffold-arcade-homes; it holds origin/main 604e2c7b, and origin/main is now 89724239, which only adds c0245's stub); `git diff origin/main...HEAD` (140 files); the fix delta `git show cdd0e5af` (review-002's answers); R0075.md and its check.sh; c0184.md, its check.sh and acceptance/; c0244.md, its check.sh and acceptance/homes.spec.luau; review-001/002, refute-001/002 and harvest.md (read after the findings below were formed).
Dropped from review-002: none. F1 (format), F2 (the two hook cases), F3 (filed as c0245, which is on origin/main at 89724239) and F4 (bookkeeping) are fixed. See the evidence below and F3 of this round.

Evidence run (in the worktree unless it says otherwise; the scratch clone is `git clone --shared` of HEAD under $TMPDIR with its remote removed; every probe went through `./zn run --time`):
- `z-nile/check.sh --full`: GATE PASSED (full) in 224.3 s. pickman 1811/0, z-nile 1345/0, and arcade, portal, snake, invaders and asteroids 21/0 each.
- `bash z-nile/.tracker/rafts/active/R0075/check.sh`: 4/4 PASS (RC0 gate, c0184, c0244, promote-check), exit 0.
- `./zn promote-check R0075`: OK. `./zn lessons --check`: 229 lessons, ok.
- Sequestration: `git diff --find-renames=100% --name-status origin/main...HEAD -- 'tracker/**/check.sh' 'tracker/**/acceptance/**' '*/.tracker/**/check.sh' '*/.tracker/**/acceptance/**'` lists only `A …/c0244/acceptance/homes.spec.luau` and `A …/c0244/check.sh` (the emergent issue's own new files, as expected). `git diff --summary origin/main...HEAD | grep -i 'mode change'` finds nothing. Both check.sh files are 100755.
- The hook end to end (JSON piped into the branch's `z-nile/guard-bash` with `ZN_CHECKOUT` set to the worktree): `snake/tests/run` 0, `arcade/tests/run` 0, `nowhere/tests/run` 2, `pickman/tests/run` 0. A plain `ls` call takes 0.024 s.
- c0244 mutants in the scratch clone (`cd z-nile && lune run tests/run -- .tracker/issues/active/c0244/acceptance/homes.spec.luau`, baseline 9/0; each mutant's `git diff --stat` was printed to confirm it applied):
  - A, `projects.load(call.cwd)`: killed ("the registry is read from ZN_CHECKOUT…").
  - D, a hand list of the five after reading: killed ("the hook takes its homes from the registry it is pointed at…").
  - F, no `/` filter: killed.
  - E, the `""`/`.`/`..` filters removed: **survives, 9/0** (F3).
- The home rule and Rojo's object form of `$path` (F1). In the scratch clone, add `"Pick": { "$path": { "optional": "../pickman/src/shared" } }` under `ReplicatedStorage` in `snake/default.project.json`:
  - `cd snake && lune run tests/run -- tests/meta/home.spec.luau`: 1 passed, 0 failed.
  - c0184's `homes.spec`: 5/0.
  - `rojo build snake/default.project.json` (Rojo 7.7.1): "Built project", and the place holds pickman's `Pellets` (and the rest of pickman's `src/shared`).
  - The same mapping as a plain string, `"$path": "../pickman/src/shared"`: snake's home.spec FAILS. So only the object form gets past the rule.
  - A pure probe of `home.problems` (a copy of home.luau) on a fixture tree with the object form: 0 problems.
  - `git ls-files '*.project.json' | xargs grep -n '"\$path"' | grep -v '"\$path": "'`: no hits. No project file uses the object form today.
- The search for hand-named pickman paths in live tooling (the one I ran): `git grep -nE '"pickman(/[^"]*)?"|pickman/(tests|src|scripts|skills|\.tracker)' -- z-nile/engine z-nile/lib z-nile/*.luau z-nile/check.sh scripts zn .claude/settings.json`. Hits:
  - `boundcmd.luau:25`: `TOOLING`'s `pickman/tests/run`, kept as the fallback when the registry can't be read, by c0244's Design.
  - `main.luau:2451` and `:2478`, and `skills.luau:408`: frozen history.
  - Comment examples in `affected.luau:31`, `check.sh:63`, `compact.luau`, `spend.luau` and `main.luau:4388`.

  Nothing new since review-001's search.
- `lune run z-nile/affected -- snake/src/server/Main.server.luau` selects nothing, and `snake/check.sh --affected --plan` still plans format, lint, both type stages, the build and snake's specs. The graph selector is c0185's (Non-goals).
- Lessons: `./zn lessons --when build` was read against the delta. The hits are zz-arch rule 7 and zz-test/walk-the-returned-table (F1), z-design/restated-rules-move-together (F2), and zz-test/fixtures-leave-nothing-a-guard-trusts (F3).

### F1 [medium] The home rule skips any `$path` that is not a string, so a place can map another project's folder through Rojo's `{ "optional": … }` form and every home check passes
Where: `z-nile/tests/lib/home.luau`, `paths()` (collects `$path` only when `type(value) == "string"`, and otherwise recurses into the value, where no `$path` key exists).
Evidence: see the evidence above. With `"$path": { "optional": "../pickman/src/shared" }` in snake's place, snake's `home.spec` passes 1/0 and c0184's `homes.spec` passes 5/0, and `rojo build` copies pickman's `src/shared` into snake's place. The same path written as a string fails home.spec. The README ("Every `$path` is a folder of the home") and AC1's rule ("every `$path` stays inside the home", Rules table, run against the string form only) state a rule that a second spelling of the same key gets around.
Critique: the rule is a guard (a game must not build another game's code into its place), and it fails open on a shape it doesn't know (zz-arch rule 7). c0185 is about to widen this exact check for `../arcade/...`, so the next author to meet the "outside the home" refusal has a working bypass at hand. The tempting fix is to also read `value.optional`. That alone leaves every other non-string shape skipped, so the next shape Rojo adds is the next hole.
Consequences: an optional `$path` may name a folder that doesn't exist (Rojo skips it). The fix has to decide whether that is "no folder of the home" (today's rule for strings) or allowed while `inside` holds. Every other `$path` value (a number, a table without a string `optional`) must be reported, not skipped. homes.spec is c0184's sequestered spec and can't take the case, so the case needs a home that isn't sequestered.
Recommendation: in `paths()`, treat a `$path` table with a string `optional` as that path, run it through the same `inside` / `isDir` / `physicallyInside` / link checks (keep "no folder of the home" for a missing optional folder, the stricter reading, unless the lead decides otherwise), and report any other non-string `$path` as `<file> maps a $path of a form this rule does not read`. Put the cases in a new, non-sequestered spec (for example `z-nile/tests/tooling/home-rule.spec.luau`, calling `home.problems` on a fixture home under `z-nile/.cache/<unique>` and removed in a `pcall` teardown), or in a small emergent issue as c0244 was. The cases:
- `{ "optional": "../pickman/src/shared" }` is reported as outside the home.
- `{ "optional": "src/shared" }` passes.
- `{ "optional": "src/none" }` is reported.
- `"$path": 5` and `"$path": {}` are reported.

Mutant: the object form skipped again. Then tell c0185's design (the lead's report) that the widened check must keep both forms.
Lesson: zz-test/walk-the-returned-table

### F2 [low] zz-test's Bounded commands bullet still says the gate's tooling is the `TOOLING` list, which "a new Lune entry the gate runs joins"
Where: `z-nile/skills/zz-test/SKILL.md:144` ("a bare `lune run` of anything but the gate's tooling (`TOOLING` in `boundcmd.luau`: a new Lune entry the gate runs joins it)").
Evidence: since c0244, `<home>/tests/run` for every home of the registry is tooling with no edit to `TOOLING` (`homeRunner`, filled from `guard-bash.luau`), and a registry that can't be read falls back to the list. The bullet was not touched in this diff (`git diff origin/main...HEAD -- z-nile/skills/zz-test/SKILL.md` changes lines 21, the Gate spec bullet and the Hooks bullet only). c0184's Problem asks that "the skills and docs say so".
Critique: the next author who adds a home reads that its runner must be added to `TOOLING`, and recreates the hand list c0244 removed.
Consequences: none (prose). The c0184 docs.spec pins other zz-test sentences, not this one.
Recommendation: "(`TOOLING` in `boundcmd.luau`, and `<home>/tests/run` of every home in the registry, c0244, which is read at the hook's checkout and falls back to `TOOLING` alone when it cannot be read; a new Lune entry the gate runs joins `TOOLING`)".
Lesson: z-design/restated-rules-move-together

### F3 [low] c0244: the `""`/`.`/`..` filters in `homeRunner` are dead, the case meant to test them is half vacuous, and refute-002 says that assertion was removed when it wasn't
Where: `z-nile/engine/boundcmd.luau` `homeRunner`. `z-nile/.tracker/issues/active/c0244/acceptance/homes.spec.luau:43-44`. refute-002.md, F2 ("The `../x` assertion was already removed in round 1").
Evidence: mutant E (those three checks removed) passes 9/0 in the scratch clone. Line 44 still asserts `refused("lune run ../x/tests/run", …)`. `normalise` strips every leading `../` and `./` before `homeRunner` sees the target, so it compares `x/tests/run`, which no home matches whatever the filter. Only the `a/b` assertion tests a filter (the `/` one, mutant F, killed). A relative target can never normalise to `/tests/run`, `./tests/run` or `../tests/run`, so the three checks can't change a verdict. Separately, the two fixture-registry cases remove their `z-nile/.cache/c0244-*` folders after the hook calls but not in a `pcall`, and no case asserts they are gone (review-002 F2's Consequences, zz-test/fixtures-leave-nothing-a-guard-trusts). Nothing reads a registry under `.cache` today (the hook reads `ZN_CHECKOUT`'s), and none was left after this round's runs.
Critique: dead guards look like coverage. A reader trusts the case name "a home name that is not a plain folder adds nothing" for `..`, and the review record says the vacuous half is gone.
Consequences: the spec is sequestered and can't be edited now.
Recommendation: in `homeRunner`, keep only the `/` test, with a comment that `normalise` already removes `.`, `..` and empty prefixes, or keep the three checks with that comment as defence in depth. Correct the record in refute-003 (the `../x` assertion stays, and it is vacuous). No spec change.

Verdict: changes
