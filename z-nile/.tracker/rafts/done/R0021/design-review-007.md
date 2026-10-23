# Review 007: R0021 (design mode)
Inputs: prep worktree `30cb08b` (R0021.md, R0021/check.sh, c0058.md + check.sh + fence/lock specs, c0059.md + check.sh + adapt.spec, c0060.md + check.sh + fixture/retrofit specs, design-review-006, design-refute-006). Read for context: R0020's re-prep (`prep-r0200-mktree` `98984ee`: c0053.md, c0053/check.sh, c0053 acceptance specs, `experiments/prototype.patch`) and its prototype `proto-r0200-mktree` `a4c4ee7` (`scripts/tracker/main.luau`). Prototype `proto2-c0058` `fcd7bd7` (`scripts/lib/fence.sh`, `tests/tooling/repo-fence.spec.luau`).
Runs:
- In `proto2-c0058`: one spec file, `repo-fence.spec`: 7 passed. `git status` was clean before and after.
- Through `tmprun.sh` (a `$TMPDIR` clone of `proto2-c0058`, no origin): the gate scan with the post-R0020, post-done layout planted (see F1).
- The tracker CLI of `proto-r0200-mktree`, copied into a scratch repository under the session scratchpad, with a local bare origin (see F2). No spec runner was involved, and the scratch directories were removed afterwards.
- Nothing printed `REPOSITORY CHANGED`. No git write ran in any worktree or in the main checkout.

Dropped from design-review-006: F2, F3, F4, F5 and F6. The refutations hold. F2 is gone with the reorder. F3: `protocol.allow=never` is in `fence.sh` and case 5, and `repo-fence` passes. F4: the `chain` case and C2-C6 are recorded as run. F5: the helper's refusals and the wider scan are designed and self-tested. F6: each item was addressed. F1's order question is settled by the user, but the adaptation that replaced it has its own defects (F1-F3 below).

Summary: c0058's guards are sound, and I found no path by which a spec or check writes the real repository, or pushes to its remote, that the design doesn't either block or name as review-only. The problems are about delivering this on the first attempt after R0020:
- the gate scan turns red on files R0020 and this raft themselves put in place;
- c0059's acceptance spec fails for every implementation;
- the refusal c0059 designs can't do what its Design says, and AC2 lets wrong versions through.

### F1 [high] The gate scan flags files that R0020 and this raft put in place: c0053's `check.sh` (at E30) and the promoted c0059 and c0060 specs (after `tracker.sh done`)
Where: c0058 Design, Gate spec item 6 (scope: every `.luau`, `.sh` and extensionless file under `tests/` and `scripts/`, and every `check.sh` under `tracker/`; Exempt; Allowlist); `prep-r0200-mktree:tracker/issues/c0053/check.sh:78`; `c0059/acceptance/adapt.spec.luau:67,106,127`; `c0060/acceptance/fixture.spec.luau:130,133`
Evidence:
- **R0020's re-prep gave c0053 an AC9** that greps for the index variable by name: `grep -nE "GIT_INDEX_FILE|read-tree|update-index|write-tree"`. After R0020's `done`, that file is `tracker/issues/done/c0053/check.sh`, which the scan reads. c0058 seeds `ALLOWED` only for c0053's two promoted specs.
- **c0059's spec names three banned names**: `PICKMAN_TEST_FENCE` (line 67), `GIT_CEILING_DIRECTORIES` as a literal (line 106), and `"GIT_CONFIG_" .. "COUNT"` (line 127, where the literal half is still `GIT_CONFIG_`).
- **c0060's `fixture.spec` names two**: `GIT_DIR` and `GIT_WORK_TREE`, in the pointed-elsewhere case.
- **Neither spec is exempt or allowlisted.** c0059 adds only the publisher's entry, and c0060 adds only the helper's.
- **Reproduced.** In a `$TMPDIR` clone of `proto2-c0058`, with those files planted where they will be, `repo-fence` failed:
  ```
  tests/acceptance/c0059/adapt.spec.luau names GIT_CEILING_DIRECTORIES
  tests/acceptance/c0059/adapt.spec.luau names PICKMAN_TEST_FENCE
  tests/acceptance/c0059/adapt.spec.luau names GIT_CONFIG_
  tests/acceptance/c0060/fixture.spec.luau names GIT_DIR
  tests/acceptance/c0060/fixture.spec.luau names GIT_WORK_TREE
  tracker/issues/done/c0053/check.sh names GIT_INDEX_FILE
  ```
- **Timing.** The `c0053/check.sh` line fails the first gate after the guard files land, which is c0058 step 4 / E30. The two specs pass every gate during execution, because the scan reads specs only under `tests/`. They break the first gate after `tracker.sh done` promotes them (`done` runs only the promoted specs and `tests/meta`, not `repo-fence`), so the red shows up on the PR's CI, or on `main`.
- **No legitimate way out at that point.** The executor's only fixes are a new `ALLOWED` entry ("weakening a guard", a stop condition) or an edit to a sequestered file. Either one means an escalation.
Critique: E30 promises that c0053's only conflicts are the two specs. It missed the done `check.sh`, which R0020's re-prep added in the same week to prove the very thing this raft wanted. The scan also never sees prepared specs until they are promoted, so a prep-time spec that names a guard can't fail any gate before `done`. The tempting fix is to compose the names (`"GIT_" .. "DIR"`), which line 127 already does. That teaches the scan's own blind spot, which is a string split, and it doesn't cover the `check.sh`.
Consequences:
- **Allowlist entries for test files**: each one needs a reason and review, like the helper's.
- **Keys by location**: `ALLOWED` is keyed by exact path, so an entry for a spec must name its promoted path (`tests/acceptance/c0059/adapt.spec.luau`), and one for a done `check.sh` its `done/` path.
- **Scanning prepared specs** (`tracker/**/acceptance/*.spec.luau`) moves the failure to prep time. It also reads every other in-flight prep's specs on `main`. That is stricter, which is what we want, but entries must then match the same file in each lifecycle location, as `EXEMPT` already does for c0058.
- **The R0020 option**: changing the AC9 grep is R0020's re-prep, before R0020 starts, and is cheaper than an entry. For example `grep -nE "GIT_INDEX_FIL[E]|read-tree|…"`. It is the same kind of split, but in a `check.sh` that only proves absence.
Recommendation:
- **R0020's re-prep** (report to the user, since it is the other prep): rewrite AC9's pattern so the file doesn't spell the name, and add a note to its doc. If the user prefers, seed c0058's `ALLOWED` with `["tracker/issues/done/c0053/check.sh"] = { GIT_INDEX_FILE = "proves the publisher does not use it" }` instead. Either way, update E30 to name it.
- **The two specs**:
  - give each an `ALLOWED` entry, keyed so that the entry matches the spec in every lifecycle location (a helper like `EXEMPT`'s loop): c0059's `adapt.spec` gets `GIT_CEILING_DIRECTORIES`, `PICKMAN_TEST_FENCE` and `GIT_CONFIG_` ("asserts the scan refuses them"), and c0060's `fixture.spec` gets `GIT_DIR` and `GIT_WORK_TREE` ("asserts the helper refuses them");
  - name each entry in the issue that adds it, in Design and Touched modules.
- **Prepared specs**: scan them where they sit (`tracker/**/acceptance/*.spec.luau`), so a prep-time spec like these fails the first gate rather than the one after `done`. Add a row with mutant G10 "prepared specs not scanned", killed by planting a banned name in a fixture's `tracker/issues/c9999/acceptance/x.spec.luau` in the planted-bypass case.
- Then re-run the `tmprun` scan above. It must pass with only the allowlisted names present.

### F2 [high] c0059's AC2 spec fails for every implementation: `tracker.sh new` refuses in a main checkout that has an origin, and `"probe two"` is not a valid slug
Where: `c0059/acceptance/adapt.spec.luau:91-99` (`work` is a plain clone with `origin`), `:142` and `:153`; `scripts/tracker/main.luau` `cmd.new` (`refuseInMainCheckout("new")`, line 157 on main, line 281 in `proto-r0200-mktree`, kept by R0020's patch); c0059 Unknowns E1
Evidence:
- **Reproduced** with `proto-r0200-mktree`'s `scripts/` and `tracker/templates` copied into a scratch repository: `work` built as the spec builds it, and a local bare origin pushed and tracked.
  - `bash scripts/tracker.sh new issue c "probe two"` printed `new must run inside a worktree: cd "$(scripts/tracker.sh worktree <target>)"` and exited 1. With origin removed, it printed `invalid slug: probe two (lowercase words joined by hyphens)`.
  - The guarded case's command `new issue c probe` gave the same main-checkout refusal, before any publish code, so `not publishing` can never appear.
  - In a linked worktree of `work`, `new issue c probe-two` published, and origin's tip moved. So the scenario works once it runs from a worktree.
- **Consequence of each case:**
  - the "outside" case errors on `not r.ok`, so AC2 fails;
  - the guarded case fails its `not publishing` assertion;
  - this is true for any implementation, so the executor's first `tracker.sh check c0059` is red, and the spec is sequestered (escalate).
- **Also in that run:** the published commit's author was the person's own identity (`Philip Bergen <philip.bergen@me.com>`), because `work` sets no fixture identity. That breaks the "fixtures commit as `@example.invalid`" rule c0058 states, which the static rule can't see. On a CI host with no global identity, `commit-tree` depends on git's auto-detected address.
- **Prep calls these cases unrunnable** (E1, "c0053's code doesn't exist in prep"; every row `reasoned`). But R0020's prototype exists. The run above took seconds, and with `proto2-c0058`'s guards in a `$TMPDIR` clone the whole spec could have been run, and mutated.
Critique: this is the raft's executability question in miniature. The one issue that has to start from code prep didn't run is the one whose spec was never run against the code that does exist. The tempting fix during execution, using `PICKMAN_PUBLISH` or editing the spec, is a sequestration breach.
Consequences:
- Running from a worktree means the fixture needs `tracker.sh worktree <name>`, or `git worktree add`, inside `work`. That needs `.gitignore` entries for `.cache/` and `.worktree/`, as c0053's seed has. It also needs the lifecycle directories (`tracker/issues/{active,done}`, `tracker/rafts/{active,done}`), or `store` may fail on missing directories, which is untested.
- The guarded case's `pickman_fence "$PWD"` must then run in the worktree. Its common git dir is `work/.git`, which is what the refusal compares, so that still works.
Recommendation:
- **Rebuild the fixture like c0053's seed**: `.gitignore`, the lifecycle directories with `.gitkeep`, a fixture identity (`user.email e2e@example.invalid`) in `work`, and a linked worktree `work/.worktree/probe`. Run both commands there, with valid slugs (`probe`, `probe-two`).
- **Run it in prep**, in a `$TMPDIR` clone of `proto2-c0058` with `proto-r0200-mktree`'s `scripts/tracker/` and c0053's promoted specs merged in. Then re-run the Rules and mutants table (A1-A3, P1-P4, plus F3's rows), turn each row to `run`, and record the outcome as an experiment. That clone is also the evidence E30 asks for, and it replaces "not runnable in prep".

### F3 [high] The refusal is specified inside `publish.commit`, where "return as `PICKMAN_PUBLISH=0` does" isn't possible, and AC2 passes refusals that drop the stub or fail the command
Where: c0059 Design item 3; Rules P1-P4; `adapt.spec` guarded case (asserts only origin's tip and `not publishing`); `prototype.patch` `publishing()` and `cmd.new`
Evidence:
- **`PICKMAN_PUBLISH=0` is decided in `main.luau`** (`local function publishing(): boolean … hasOrigin() and … v ~= "0"`), and each command chooses its local path from it. Under `PICKMAN_PUBLISH=0`, `new` writes the stub into the working tree.
- **`publish.commit` has no local path.** It returns a `Result`, so a refusal inside it can only be:
  - `ok = false`: `new` then fails with `could not publish to origin/main … (PICKMAN_PUBLISH=0 creates it locally instead)`, exit 1, and no stub;
  - `ok = true, sha = nil` (no-op success): `new` then runs `mergeOrigin()` (`git merge origin/main`, which in a check at the real root merges into the real checkout's branch) and prints the path of a stub that doesn't exist.

  Neither is "as `PICKMAN_PUBLISH=0` does". `start` and published `status` moves get the same treatment: their claim is the commit.
- **AC2 can't tell.** The guarded case doesn't check `ok`, doesn't check that the stub exists, and doesn't check that HEAD is unchanged. Both wrong versions keep origin's tip and can print `not publishing`, so they pass.
- **E3's premise is half true.** "A fetch would itself be refused by the ref guard in specs mode" holds only where hooks are injected. In the spec's guarded case they are, because `pickman_fence "$PWD"` passes no jail argument. Under a jailed check flow they aren't. So P2's kill depends on the fixture, not on the design.
Critique: as written, the refusal stops the push but leaves the command half-done in a way nobody specified. The checks would accept that. The tempting fix is to return `ok = true` from `commit`, which silently loses the stub and still merges.
Consequences:
- **Moving the decision into `publishing()`** makes a guarded repository identical to `PICKMAN_PUBLISH=0` for every command:
  - `new` writes locally and `start` claims locally;
  - `status` (list) then fails with `status needs an origin remote (PICKMAN_PUBLISH=0 disables it)`, and that message should name the guard;
  - `sync` doesn't consult `publishing()`, so a check at the real root can still fetch and merge. That is a `check.sh`'s own command, which c0058 lists as caught only by review, and the testing-skill sentence should say so;
  - `publishing()` is called several times per command, so it should print the `not publishing` note once.
- The allowlist entry for `PICKMAN_FENCE_` moves from `scripts/tracker/publish.luau` to `scripts/tracker/main.luau`.
Recommendation:
- Design item 3: the check lives in `publishing()` in `scripts/tracker/main.luau`, which returns false, with a single stderr note, when the common git dir is listed. Touched modules and the allowlist entry follow.
- The guarded case asserts all of:
  - `r.ok`;
  - the stub file exists in the worktree;
  - origin's tip is unchanged;
  - HEAD is unchanged, so there was no merge;
  - `not publishing` appears in stderr.
- Add rows P5 "refuse by failing the command" and P6 "no-op success (stub lost, merge run)", both killed by that case, and run them under F2's clone.

### F4 [medium] The publisher's allowlist entry is unchecked: nothing plants a second name in it, and its key `PICKMAN_FENCE_` covers every fence variable
Where: c0059 Design item 2 (publisher entry), Rules A1-A3 (c0053's specs only), `adapt.spec` "c0053's specs may name only …" (plants only in `C0510[1]`)
Evidence:
- The planted case appends names only to `tests/acceptance/c0053/commands.spec.luau`. So no check fails on any of these:
  - `["scripts/tracker/publish.luau"] = { PICKMAN_FENCE_ = …, GIT_DIR = … }`;
  - a whole-file `EXEMPT` entry for the publisher;
  - a later edit that makes the publisher write `PICKMAN_FENCE_REAL_GIT` or `PICKMAN_FENCE_SPECS`.
- The review skill makes any guard weakening high, but here the only defence is review. That is a production file, under `scripts/`, that runs at the real root with credentials.
Critique: review 006 F1 recommended a planted case for exactly this entry. It was lost in the rewrite.
Consequences: a narrower name (`PICKMAN_FENCE_REAL_GIT` as the allowed key) needs the scan's matching to treat the allowed name as covering the banned prefix only for that exact token. Otherwise the file still names `PICKMAN_FENCE_`, and the entry must stay at prefix level.
Recommendation:
- Extend the planted case to the publisher's file (`main.luau` after F3): plant `GIT_DIR` and `PICKMAN_TEST_FENCE`, and expect `<path> names <name>` for each.
- Add row A4 "publisher entry wider than its one name / whole-file exempt", killed by it.
- State in the entry's reason that the file only reads `PICKMAN_FENCE_REAL_GIT`.

### F5 [low] Document gaps
Where and fix:
- **R0021.md Experiments phase** says "Phase 1 has nothing left beyond re-running RC1", while c0058 E30 and c0059 E1/E2 are Phase 1 experiments, with stops. List them.
- **R0021.md Rollout** says "land it first", which now reads as contradicting "R0020 first". Say "land it promptly once R0020 is done, before other rafts".
- **c0060's new testing-skill rule** ("every spec runs git and `tracker.sh` in a fixture through `@tests/lib/fixture`; raw git only for `rev-parse`, `ls-files`, `init` and `clone`") is broken on landing by c0053's promoted specs, c0059's `adapt.spec` (its own checked `git()`), and c0058's specs. Either scope it ("the twelve, and new specs from now on; c0053, c0058 and c0059 check fixtures their own way") or list the exceptions.
- **c0059 Problem** says "or anything that the check starts". A spec started by a check is already in specs mode, and `protocol.allow=never` blocks the https origin, so the sentence only means a check's own commands. Say so, and say that `start`/`done` branch pushes and `gh` from a check stay review-only (c0058's list).

Verdict: changes
