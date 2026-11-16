# Review 001: c0160 (design mode)
Inputs: prep-check-paths-third a5b9ef59 (c0160.md, check.sh, acceptance/third-project.spec.luau, experiments/c0160-on-c0141.patch); c0141 on origin/main (0c015c62) and its prototype origin/proto-check-paths-home 46f7d115. Reproduced on a scratch clone of today's origin/main 8a58bb11 with c0141's prototype (its c0120 folder diff against d24aabc8) and the c0160 patch applied, c0141's two specs promoted, rokit Lune 0.10.5.

Claims re-run:
- c0160's spec: 5 passed three times. With c0120's check-paths and finished specs and c0141's two specs: `20 passed, 0 failed, 5 spec files`.
- `./zn check c0160` on the prototype (c0160's check.sh and acceptance in its issue folder): `4/4 criteria passed`.
- Linux CI run 40431848097: completed, success (gate z-nile, gate pickman), head 974690d6 on `ci-c0160-proto`. Its checkpaths.luau, rewrites.luau and spec are byte-identical to my prototype. Its base is 03798eaf, older than the 5a5c05dc the log names; my macOS runs on today's main pass, so this costs nothing.
- Mutants M0–M7: not re-run. Each row's case was read and is plausible. F1 is a mutant that is not in the table, and I ran it.

### F1 [high] The registry default ("called alone, the running checkout's registry") is never pinned: a hand-listed default passes check.sh
Where: c0160.md Rules and mutants row "the default is the running checkout's registry", and rewrites' row; spec cases "called without homes, …" and "c0120's finished-file reader …" (third assertion); AC2, AC3.
Evidence: in a scratch copy I made `checkoutHomes()` return `{ "pickman", "z-nile" }` in both `checkpaths.luau` and `rewrites.luau`, honouring the `homes` argument when one is given. `lune run tests/run -- tests/acceptance/c0160/third-project.spec.luau` gave `5 passed, 0 failed`. The default is checked only in this checkout, whose registry is exactly the old hand list, so "never a hand list" (AC2) is met by a hand list. M2 (default `{}`) and M5 (the hand list ignoring `homes`) are the only default mutants in the table, and neither is this one.
Critique: this is the mutant zz-test/kill-mutants-where-the-value-is-built names: the value comes from the registry inside `checkoutHomes`, and every case either hands `homes` in or reads a registry that equals the hand list. The author's likely fix is to assert that the default equals `homesAt(<this checkout>)`. That fix still passes the mutant, because both sides are `{pickman, z-nile}` here.
Consequences: the default is read once per process from `git rev-parse --show-toplevel`. Only a separate process whose working folder is a different checkout can show it, which raises three needs. The fixture needs a git repository: `git init` inside `.cache`, with no commit and so no identity. It needs a child `lune` that requires the real modules by a path relative to its script. And it needs the fence's ceiling to let `rev-parse` find the fixture's own `.git`. I checked the mechanism unjailed. The fixture was `.cache/rvfx` with `git init` and a `z-nile/projects.toml` registering only `tern`. A script in `.cache/rv/` required `../../tests/acceptance/c0120/checkpaths` and `…/rewrites` and was run with that fixture as its working folder. It printed `tern/c.luau,rw:tern/c.luau` for `test -f pickman/a.luau tern/c.luau`, so the modules' own `@znile/…` requires still resolve, and `show-toplevel` names the fixture. The jailed run is still unproven.
Recommendation:
- Add a spec case to third-project.spec, not a check.sh AC, because "the default is the registry's" is a rule. It runs the child `lune` from a fixture checkout under `.cache/c0160-default/` (`git init`, a registry that registers `tern` and not `pickman`) and asserts that both readers' defaults read `tern/…` and not `pickman/…`.
- Add rows M8 (checkpaths' default is a hand list) and M9 (rewrites' default is a hand list), run them, and record each kill.
- Run the new case in the jail (`./zn check c0160`) and on Linux CI.
- Keep the current in-process "called without homes" case: it pins that this checkout still reads pickman and z-nile.

### F2 [medium] E4 (c0141's `done` reddens the z-nile gate) has no tracker record, and AC4 names c0141's specs one by one
Where: c0160.md Unknowns E4 ("reported to c0141's stream"); check.sh AC4 (`"$PWD/tests/acceptance/c0141/touched-from-home.spec.luau" "$PWD/tests/acceptance/c0141/uses-module.spec.luau"`); Implementation step 1.
Evidence: c0141 is `design: ready` on origin/main and is in no raft, so there is no stream to report to. `git grep -ln "uses-module" origin/main -- z-nile/.tracker` lists only c0141's own files (c0141.md, check.sh, design-refute-001/002, design-review-002/003). No capture records the architecture.spec failure. E4 says c0141's `done` turns `tests/meta/architecture.spec.luau` and c0116's promote spec red, so c0141 cannot finish as prepared, and c0160 (`depends_on: [c0141]`, step 1 "Confirm c0141 is done") is blocked behind it. c0141's sequestered spec can't be changed in execution, so the likely fix is a re-prep of c0141. That re-prep may rename or split `uses-module.spec.luau`, which would strand c0160's sequestered AC4 on a missing file.
Critique: the design depends on a path that a known open defect breaks (z-design/check-open-defects-on-the-path), and the only record of that defect is a sentence in this issue.
Consequences:
- The defect needs a tracker record, either a capture or a c0141 re-prep, with its id in c0160's E4. As the prep's lead, the author captures it.
- AC4 should stop depending on c0141's file names. A glob does that: `"$PWD"/tests/acceptance/c0141/*.spec.luau`. With no match, bash leaves the word literal and the runner fails. I ran it under bash: `FAIL tests/acceptance/c0999/*.spec.luau: could not load spec … 0 passed, 1 failed`, `rc=1`. The glob also holds a `$`, so the check-paths scan doesn't read it.
Recommendation:
- Capture E4 as an issue against c0141 (`./zn new issue c … --project z-nile`) and name its id in E4. Add it to `depends_on` only if c0160 cannot be done without it. It can't, since AC4 runs c0141's specs and step 1 needs c0141 done.
- Change AC4 to run c0141's promoted folder by glob.
- Rerun `AC_LIST=1` and the prep tree's check-paths spec after the change.
Lesson: z-design/check-open-defects-on-the-path

### F3 [low] The "own work exempt" case doesn't show that its `tern/…` word was read before it was exempted
Where: third-project.spec, case "a third project's own work, named in its Touched modules, is exempt as the others' is".
Evidence: the case asserts only that no `c0003` line is in `bad`. Under M0 (the `tern/` prefix unknown), `cd .. && test -f tern/src/new/init.luau` is not a literal at all, and the case still passes. Only `src/new` shows an exemption that actually happens.
Critique: "not found" and "checked and exempt" look the same here (zz-test/no-vacuous-pass). Case 2 kills M0 already, so this case adds nothing for the third project's `<home>/` path.
Consequences: none beyond one assertion.
Recommendation: in that case, also assert that `checkpaths.literals(<the check.sh text>, { "pickman", "z-nile", "tern" })` contains `../tern/src/new/init.luau`. Or check `bad` with the Touched entry removed, so that the word reaches the exemption.

## On the points the author asked to have attacked
- **G1 (rewrites.luau, pending user): the recommendation is sound; the change is inert.**
  - With today's registry, the prefixes are the same set. They are only appended in a different order, and the loop doesn't break on a match, so the order can't matter.
  - Beyond today: `rewrite` and finished.spec's live case act only where `world.before(dir..path)` holds. Every top-level folder of the pre-move tree (`git ls-tree --name-only c5b436ca~1`: `.claude .github scripts src tests tracker z-nile`, plus root files) is already a fixed prefix.
  - I re-ran finished.spec's live loop with an extra home `skills`, `engine` or `lib`. Those names collide with z-nile's subfolders and change what both readers read in 29 finished files: `#rewrites.literals` differs for c0037 … R0031. It still flags 0 with each name, so registering such a project leaves c0120's promoted spec green.
  - The only non-inert path left is `cd <dir> && <home>/…` with that path present before the move. Nothing in today's finished files matches it.
- **G2 (FILES, FOLDERS stay; pending user): sound.** pickman and z-nile aren't in either list (a bare `find pickman` is unread today), so a third project is read the same way the Problem asks.
- **Cached `checkoutHomes()`:**
  - It reads `git rev-parse --show-toplevel` of the process's working folder. Under tests/run and `./zn check`, that is the home of the checkout or worktree under test.
  - The fence keeps `rev-parse` usable: c0120's specs already read `TOP` this way.
  - When git fails, the fallback is `projects.load(".")` from the home, which errors with `no z-nile/projects.toml in .`. That fails closed.
  - Its only gap is F1.
- **check.sh AC4 through `$PWD`: sound.** ac.sh has already moved to the home. Words containing `$` are never literals, so main's unfixed scan doesn't read them (c0141's AC3 note), and the 4/4 run above passes. The only change needed is F2's glob.
- **Overrides / regressions:** `lune run z-nile/affected -- z-nile/tests/acceptance/c0120/rewrites.luau` lists `z-nile/tests/acceptance/c0120/finished.spec.luau`. checkpaths.luau doesn't exist on main yet. `git grep -lF -e rewrites.luau -e checkpaths.luau -- z-nile/tests/acceptance pickman/tests/acceptance` gives c0114/finished.luau, c0114/finished.spec.luau, c0120/finished.luau and c0120/finished.spec.luau. The c0114 hits name c0114's own rewrites.luau. The Overrides line covers both files.
- **Repository safety:** the spec writes only `.cache/c0160-third/`, starts no git and calls no subprocess. F1's case adds `git init` inside `.cache/c0160-default/`, with no commit.
- **Scope:** the capture's Problem (a third project resolved and validated the same way) has a Design and AC1–AC3. No outcome is dropped.

Candidate lesson (for the lead): zz-test/kill-mutants-where-the-value-is-built, add a note. A default that "comes from the running checkout" is killed only from a different checkout, in a child process. In-process cases see a registry that equals the old hand list. Check: does the default's source ever hold a value different from the hand list it replaces?

Verdict: changes
