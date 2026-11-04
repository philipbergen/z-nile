# Review 005: c0184 (design mode)
Inputs: the prep worktree `prep-scaffold-arcade-homes` at ea72258d, with its uncommitted rounds 1-4 edits (c0184.md, check.sh, acceptance/{homes,generic,docs,skills}.spec.luau, experiments/, design-review-001..004, design-refute-001..004, harvest.md). The prototype clone is at 9f07ec53 ("c0184 prototype 10"). Its four c0184 specs, `home.luau`, `homespec.luau` and the ten skills are byte-equal to the worktree's (`cmp`).
Replay: origin/main is 6411536d (`git ls-remote`); since round 4's 5480e8a0 only tracker files changed. In a throwaway clone of 6411536d I ran Implementation steps 2-3 from the worktree's `experiments/`. `git apply --check tooling.patch` was clean, I made the ten `.claude/skills` links by hand and committed. On that tree:
- the five round-4 overrides: 28/28;
- c0184 homes, docs and skills specs with c0120 layout and graph-homes: 27/27;
- generic.spec: 5/5;
- `places.luau`: exit 0;
- pickman's meta specs (home.spec included) with c0003 pipeline and c0064 docs: 26/26.

About 45 other promoted spec files that read the real tree or name a Touched path also pass, among them c0115 absence, docs, skills and lessons, c0183's four, c0114 layout, docs, classified and guards, c0116 promote and retired, c0049 spec-isolation, c0172 merge, c0041 src-aliases and graph-build, tooling affected and fence-every-home. Two fail (F1).
Round-4 fixes, ruled on:
- F1 holds for the five specs it widened, and for the two breaks it fixed (the Lessons paragraph and the README row). Its Consequences claim that none of the five is in c0172's narrowed list is wrong, so the fix turns a sixth spec red (F1 below).
- F2 holds: homes.spec pins only `ping: ping/.tracker/architecture.md`.
- F3 holds: the sentence is appended to each skill's opening paragraph, and AC7 greps it.
- F4 holds, apart from one restatement round 4 didn't name (F3 below).
- F5 holds as written down.

### F1 [high] Two promoted specs the design doesn't name go red on the prototype and on main plus c0184: c0172 `narrowed.spec`, which pins c0120 `docs.spec` by digest, and c0115 `layout.spec`, which pins `.claude/skills` to z-nile's and pickman's folders
Where: Regression guard ("None is in c0172's narrowed.spec list"), `Overrides:` (seven entries), Touched modules, check.sh AC9; `z-nile/tests/acceptance/c0172/narrowed.spec.luau:76-80`; `z-nile/tests/acceptance/c0115/layout.spec.luau:131-150`.
Evidence: on the replay clone (main 6411536d plus c0184), run from `z-nile/`:
```
lune run tests/run -- tests/acceptance/c0172/narrowed.spec.luau
FAIL … :: each narrowed spec is exactly the narrowed text
  narrowed.spec:113: expected "a9c5f2a2c47d32b1aa5ad13300621b9ab941f81c13ff65c3c8284c0221d98c12", got "d56347352d2dea63cc8e7c524c1723ec06a4b5b2a9a55923d2a44aa29b4bfe1c"
lune run tests/run -- tests/acceptance/c0115/layout.spec.luau
FAIL … :: .claude/skills tracks one relative link per skill folder and nothing else
  layout.spec:139: expected "../../z-nile/skills/arcade-arch", got "../../arcade/skills/arcade-arch"
6 passed, 1 failed
```
Both specs fail the same way on the prototype (9f07ec53): `6 passed, 2 failed, 2 spec files`.
- c0172's `PINNED` holds `{ "z-nile", "c0120", "docs.spec.luau", "a9c5f2a2…" }`. The c0184 override of c0120 docs changes that file's text, so its digest changes. Round 4's grep (`c0120/docs`) couldn't match the row, because it is written as three separate strings. The design copied the resulting "none" into the Regression guard.
- c0115 layout reads every tracked `.claude/skills/*` link. It takes the link's base from `if fs.isDir("pickman/skills/<name>") then "pickman" else "z-nile"` and compares the link names with `folders("z-nile/skills")` plus `folders("pickman/skills")`. Neither form is a one-line brace list, so Design 3's search regex can't find it.
- zz-review item 4's grep, run with each path's basename, finds both. `git grep -lF -e docs.spec.luau` lists narrowed.spec, and `git grep -lF -e .claude/skills` lists c0115 layout.
- check.sh AC9 also leaves out c0114 `docs.spec`, one of the seven overrides, which the Test plan maps to AC9.

The merge's `--full` turns both red, and the executor can't fix them without editing promoted specs the design doesn't name.
Critique: the tempting fix is two more lines on `Overrides:`. That isn't enough on its own, because the digest depends on the final text of c0120 docs.
Consequences:
- The narrowed digest has to be computed last, after stylua, with the spec's own `exact`, as c0183 did for the same file (c0183.md Regression guard, "Those four rows get the digests of the overridden files, computed by the spec's own `exact` … after stylua", and its step 4, `E2-rehash.py`). Any later edit to c0120 docs, including a comment's wording, needs a fresh rehash.
- The c0115 layout case has to take each link's owner from the registry, or the next home breaks it again.
- Both become Touched modules, AC9 entries and Rules rows.
- Round 4 found a hole in this same mechanism: the regression lists are hand-picked runs (E9, E16) plus a regex search. One more name won't close it; the selection itself has to be complete.
Recommendation:
- Add two overrides, making nine.
  - c0172 `narrowed.spec` :: "each narrowed spec is exactly the narrowed text": the c0120 `docs.spec.luau` row takes the digest of the overridden file, computed as the final step with the spec's `exact`. Add a Rules row with the mutant "old digest left", run.
  - c0115 `layout.spec` :: ".claude/skills tracks one relative link per skill folder and nothing else": the expected target is `../../<the skills.folders entry holding name>/<name>`, and `all` is the folder names of every `skills.folders(projects.load(TOP))` entry, so the case keeps "one relative link per skill folder and nothing else". Add a Rules row with two mutants: a `snake-arch` link to `../../z-nile/skills/snake-arch`, and a missing `.claude/skills/portal-test`.
- Add both files to Touched modules, and add both, plus c0114 `docs.spec`, to check.sh AC9 and the Regression guard. Strike "None is in c0172's narrowed.spec list".
- Replace the hand-picked regression evidence with a selection anyone can rerun:
  1. Run item 4's `git grep -lF` with each Touched path and its basename over `*/tests/acceptance` and `z-nile/tests/tooling`.
  2. Run every hit that reads the real tree, in batches, on the prototype.
  3. Record the command and the result in E9.

  This stays within "one `--full` at the merge".

### F2 [medium] The hand-list search still misses rules over "every skill" or "every live file" that stop at pickman, because they aren't written as one-line brace lists
Where: Design 3, "Promoted rules over every skill or every home's specs" (the search and its "Not changed" classification); `z-nile/tests/acceptance/c0115/docs.spec.luau:180-196`; `z-nile/tests/acceptance/c0115/absence.spec.luau:93,101,120`; c0117's sequestered `z-nile/.tracker/issues/active/c0117/acceptance/wrapper.spec.luau:122`.
Evidence: `git grep -nE 'pickman/(skills|tests)|"pickman/"|isDir\(.pickman' -- z-nile/tests z-nile/engine z-nile/lib scripts zn pickman/tests ':!z-nile/tests/acceptance/c0184'`, with fixtures, frozen lists and history read out, leaves these hits that apply a rule to every member:
- c0115 docs.spec:185-186, "every skill's lessons paragraph names the real folder": `ALL` (z-nile's) plus `table.insert(dirs, "pickman/skills/pickman-arch")` and `pickman-test`. The ten new skills are never checked.
- c0115 absence.spec:93, `LIVE_DIRS = { "z-nile/", "pickman/", ".claude/", "scripts/", ".github/" }`, with `pickman/skills/` and `pickman/tests/acceptance/` excluded by hand at :101 and :120. The old-skill-name scan never reads `snake/` and the other new homes.
- c0115 layout:138/145 (F1).
- Sequestered, not promoted yet: c0117 (R0052, active) wrapper.spec:122, "every gh command the skills name is allowed", over `{ "z-nile/skills", "pickman/skills" }`. c0117 also overrides c0115 `readme.spec`, which c0184 now overrides too, and Existing work names impl-c0117 only for `cachepaths` and `repo-fence`.

None of these is red today. I widened absence.spec in the replay clone (the five homes added to `LIVE_DIRS`, `^%a+/skills/` treated as docs): 6/6 pass. `grep` finds no old skill name and no `` `gh `` in the ten skills. So these hand lists exempt new members silently, which is what Design 3 says no longer happens.
Critique: the design states the outcome as delivered ("every hand-named pickman path … takes its homes from the registry"), on a search that can't see `table.insert` lists, prefix lists or `isDir` branches.
Consequences: widening absence.spec and c0115 docs.spec makes two more overrides, neither digest-pinned (c0172's rows are listed under F1). Each keeps what it pins. Absence must treat every home's `skills/` as documents and every home's `tests/acceptance/` as sequestered, both from the registry. c0117's spec is sequestered, so c0184 can't touch it.
Recommendation: paste the wider search above in Design 3, with every hit classified.
- Override c0115 docs.spec:185, taking the skill folders from `skills.folders`.
- Override c0115 absence.spec, taking the live prefixes, the docs folders and the sequestered folders from `projects.load`.
- Add both overrides to `Overrides:`, Touched modules and AC9. Add a Rules row with two mutants, both to run: "`snake-arch` names `.claude/skills/testing`" and "a new skill's Lessons paragraph without the real-folder sentence".
- In Existing work, name c0117's `readme.spec` override (different hunks, merged by hand by whichever lands second) and its wrapper.spec hand list, which goes to c0117's lead (the lead's to send; record it in the report).

If the author decides a hand list stays, the classification must give the reason, as it does for the freeze lists.
Lesson: zz-review/lists-paste-their-search; zz-rules/exhaustive-lists-name-new-things

### F3 [low] The Checklist still says two overrides
Where: c0184.md Checklist, "**Overrides.** See the Regression guard's `Overrides:` line: two promoted c0120 cases, each still pinning what it did for the aliases the tooling uses."
Evidence: the `Overrides:` line lists seven entries after round 4, and nine after F1. Round 4 F4's search (`two meta|nothing in .pickman/. changes|pickman keeps`) wasn't rerun for "two promoted".
Recommendation: say "the promoted cases on the Regression guard's `Overrides:` line" without a count, and rerun `grep -nE 'two promoted|seven|None is in' c0184.md`.
Lesson: z-design/restated-rules-move-together

### F4 [low] Two of the three deps-block outcomes have no case
Where: `experiments/lib/home.luau:252-259` ("has N deps blocks", "has a deps block that is not closed"); homes.spec `ping` (a map with no block only); Design 1 ("requires exactly one, closed").
Evidence: `grep -n deps acceptance/*.luau` finds only the prefix pin. A mutant that counts only opening fences (`opened == 1`) passes homes.spec. So does one that ignores a second block.
Recommendation: add one fixture home to homes.spec's wrong-files case with two blocks, and one with an unclosed block, each pinned by prefix and path only (as `ping` is, so that c0163's `deps.parse` switch still overrides nothing). Add a Rules row with the mutant "opening fences counted only", to run.

Candidate lesson (for the author to harvest): **A reviewer's or author's "not pinned" search greps the pin's own spelling.** Rule: when checking whether a digest or golden list pins a file, grep the file's basename and read the pin table, not `<id>/<file>`, because pin tables split project, id and file name into separate strings. Why: c0184 design review 004 F1 grepped `c0120/docs` in c0172's `narrowed.spec`, found nothing, and the design repeated "None is in c0172's narrowed.spec list". The row is `{ "z-nile", "c0120", "docs.spec.luau", … }`, and the override turned it red. Check: for every overridden spec, does `git grep -lF -e <basename> -- '*/tests/acceptance'` list a pinning spec, and is that spec named on `Overrides:`?

Verdict: changes
