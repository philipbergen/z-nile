# Review 002: R0260 (design mode)
Inputs: prep worktree `prep-guards-and-numbering` at 6039316 (round 1's changes: `git diff HEAD~1 -- tracker/`): `tracker/rafts/R0260/{R0260.md,check.sh}`, `design-review-001.md`, `design-refute-001.md`; c0800, c0810, c0820, c0830, c0840, c0850 and c0860 (each `<id>.md`, `check.sh`, `acceptance/*.spec.luau`); `tracker/issues/c0840/review-of-round6-fixes.md`; the review, testing, tracker, ticket-prep and execute-raft skills; the prototype `.worktree/proto-r0260` (read, plus the runs below).
Dropped from design-review-001: F1, F2, F3, F5, F7, F8, F10, F11 (their fixes hold: read, and F2's AC6 and F5's static order case checked against the prototype's code). F4, F6 and F9 were fixed, but each fix opened a new gap, reported below as F1, F2/F3 and F6.
Runs, one at a time, outside any other sandbox, nothing printed `REPOSITORY CHANGED`:
- in the prototype, `tracker/issues/c0800/acceptance/done-gate.spec.luau` with `cmd.done`'s condition changed to `if process.env.PICKMAN_DONE_GATE ~= "1" then` (skip the gate unless the switch is set). `scripts/tracker/main.luau` was backed up with `cp -p`, restored, and `cmp` showed it identical. Result: `5 passed, 0 failed` (F1);
- in a scratch folder under `$TMPDIR` (since removed): the prototype's shim, generated from `SHIM` with a stand-in cache, run against a stand-in "victim" repository outside it (F2, F4); and plain `git init a/b/new/../../../escaped` (F3).

### F1 [high] Since round 1's F4 fix, nothing drives `done` outside a spec run, so a `done` that runs the gate only when `PICKMAN_DONE_GATE=1` passes every check, and the real `done` still never runs the gate
Where: c0800 Design step 4, Rules and mutants, AC1; `done-gate.spec.luau` `done()`; `check.sh` AC1–AC4.
Evidence:
- All three behaviour cases run nested (`PICKMAN_FENCE_SPECS=1`, inherited). AC1 and AC2 set the switch, and AC3 leaves it empty. The branch c0800 exists for (no spec run, no switch: an agent's real `tracker.sh done`) is never run.
- Mutant: `if process.env.PICKMAN_DONE_GATE ~= "1" then <skip the gate> else <gate>`. Run on the prototype (above), the spec gives `5 passed, 0 failed`. AC4's six fixture specs run nested without the switch, so they also take the skip branch either way. With that mutant, `scripts/tracker.sh check c0800` is green and real `done` behaves exactly as today: the R0210 bug.
- No row in Rules and mutants names this mutant. "the switch read as skip" is the opposite mutant, and "the gate always run" is caught by AC3.
Critique: there are two tempting fixes, and both are poor:
- Drive the outside branch from the spec by clearing `PICKMAN_FENCE_SPECS`. That is round 1's F4, which this round's fix rightly removed.
- A grep that `main.luau` contains the two-variable condition. That pins the text, not the behaviour, and any rewording breaks it.
Consequences: the decision must be testable without leaving the spec run's guards. One way is to make it a pure function of an environment table and call it with `process.env`. That brings:
- the promoted spec naming `PICKMAN_FENCE_SPECS` as a table key, never in a process's environment. That needs a reviewed `ALLOWED` entry ("a pure function's input; never exported to a process"). This is a weaker need than step 4's entry for `main.luau`, which lets that file name the whole `PICKMAN_FENCE_` prefix;
- the wiring: AC1 and AC3 already show that `done` reads both variables from `process.env`, so only the "neither set" branch rests on the function.

The other way is a check in `check.sh`, which runs outside any spec run, that drives a fixture `done` directly in bash. That puts a shell fixture (clone, commits as `@example.invalid`, stub gate) into a sequestered `check.sh`, which only review protects ("`check.sh` files' own commands"). It is heavier, so prefer the pure function.
Recommendation:
- Export `doneGate(env: { [string]: string? }): "full" | "promoted"` from a tracker module, and have `cmd.done` call it with `process.env`.
- Add a case "with neither variable set, done runs the full gate", plus the table cases `{}` → `full`, `{FENCE_SPECS="1"}` → `promoted`, `{FENCE_SPECS="1", DONE_GATE="1"}` → `full`, and `{DONE_GATE="1"}` → `full`.
- Add a Rules row: mutant "the gate only when `PICKMAN_DONE_GATE=1`", mark it `run`, and record it in E5.
- Add the `ALLOWED` entry for the promoted spec, with its reason.

### F2 [high] The shim's `init`/`clone` branch ignores `--git-dir`, `--work-tree`, `GIT_DIR` and `GIT_WORK_TREE`, and `worktree add` isn't checked at all. A shell string can reinitialize another repository, write `core.worktree` into its config, or check files out into another work tree, all of which AC1 says are refused
Where: c0810 Design, "The shim" step 2 (`init`/`clone` checks only positionals, `--separate-git-dir`, `--template`, then `exec`s before steps 3–4 see `lead` or the variables); prototype `SHIM`; c0810 AC1 ("nor make a repository outside it with `init` or `clone`. That holds however it gets there: … `--git-dir`, `--work-tree` … or a repository variable set inside it").
Evidence: the prototype's shim, with a stand-in cache, run in a fixture under it against a "victim" repository outside it:
- `git --git-dir=$T/elsewhere init` gives rc 0 and creates `$T/elsewhere`. `GIT_DIR=$T/elsewhere2 git init` does the same.
- `GIT_DIR=$T/victim/.git GIT_WORK_TREE=$T/cache/fx git init` gives rc 0: "Reinitialized existing Git repository in …/victim/.git/". The victim's config gained `worktree = …/cache/fx`, after which `git -C victim status` reported the fixture's tree (` D a`, `?? sub/`). Against the real checkout on Linux, this silently retargets every later git command there.
- `GIT_WORK_TREE=$T/wt git clone -q $T/victim sub2` gives rc 0, and `$T/wt` holds `a`: a checkout into a foreign work tree.
- `git worktree add -q $T/victim/wt-from-fixture` gives rc 0 and makes a work tree inside the victim. `worktree add` takes the fast path, because the repository is the fixture.
- The F6 spec case tries only positionals, `-C`, `cd` and `--separate-git-dir`, so the prototype passes AC1.
Critique: the tempting fix is to run the init branch only after the slow path. But `init` legitimately runs where there's no repository yet, so the slow path would refuse it.
Consequences: the rule round 1 adopted ("every path a repository is made at must resolve under `.cache`") has to cover every way such a path is named:
- for `init`: `--git-dir`'s value or `GIT_DIR` (the repository) and `--work-tree`'s value or `GIT_WORK_TREE` (written into its config as `core.worktree`);
- for `clone`: `GIT_WORK_TREE`/`--work-tree` (where files are checked out);
- for `worktree add`: its path positional (skipping `-b`, `-B`, `--reason` and their values).

Each is a `target` check, so legitimate fixture uses still work: `GIT_DIR=<fixture>/.git git init`, and the tracker's `worktree add` into the fixture's `.worktree/`, which c0041, c0440 and c0420 exercise.
Recommendation:
- In the `init`/`clone` branch, `target` every `--git-dir`/`--work-tree` value in `lead` and every set `GIT_DIR`/`GIT_WORK_TREE`.
- Add a `worktree add` branch that `target`s its path.
- Add spec cases, each aimed at a stand-in outside `.cache` (see F3), never the real checkout: `GIT_DIR=<outside> git init`, `git --git-dir=<outside> init`, `GIT_DIR=<outside repo>/.git GIT_WORK_TREE=… git init` (the stand-in's config must be unchanged), `GIT_WORK_TREE=<outside> git clone <other> <under cache>` (nothing in the outside folder), and `git worktree add <outside>` (refused, nothing made). Also add a case that `GIT_DIR=<under cache> git init` still works.
- Add a Rules row each, and re-time E1 (only the init, clone and worktree-add paths change).

### F3 [high] Round 1's new `init`/`clone` cases aim writes at the real checkout and rely on the code under test (or the macOS jail) to stop them. On Linux, a wrong or unfinished shim reinitializes the real repository or creates a repository inside its working tree
Where: `tracker/issues/c0810/acceptance/shell-git.spec.luau`, case "init or clone aimed at, or run from inside, a folder outside .cache is refused" (`denied('cd "$1" && git init -q')`, `denied('git -C "$1" init -q')`, `denied('git init -q "$3/new/../../../c0810-escape-$5"')`, with `$1` = the real checkout's root and `$3` = `<root>/.cache/c0810-shell-git`); the spec's header ("Every probe of the real checkout here is read-only (rev-parse), so even a wrong implementation changes nothing"); c0810 E5 ("The real repository was checked untouched after the `init` mutant (the jail refused its write)").
Evidence:
- `git init` in an existing repository writes into its git directory. In scratch, a reinit of a clone added `description` and every `hooks/*.sample` that was missing. So `cd "$1" && git init` and `git -C "$1" init` are writes to the real repository whenever the shim doesn't refuse them: before the executor writes it (tests first), with the `init` mutant, or with any bug.
- `$3/new/../../../c0810-escape-$5` resolves to `<root>/c0810-escape-<tag>`, inside the real checkout. Plain git creates the missing folders and then the repository: in scratch, `git init a/b/new/../../../escaped` made both `a/b/new` and `escaped`. With the "no `..` guard" mutant (E5 lists it as run), that is a new repository in the real working tree. `denied` passes no `made` path for it, so nothing even checks or cleans it up.
- On macOS the jail refuses these writes, which is the only reason E5 found the real repository untouched. On Linux (CI, and any developer's Linux machine) nothing does. The testing skill: "Every command that changes anything must run in a fixture under `.cache/<unique name>`", and review item 9 makes any path to the real repository high.
Critique: the tempting fix is "the jail covers it, and CI's checkout is disposable". But the spec runs where the jail doesn't, and the rule exists so that a spec's safety never depends on the implementation it tests.
Consequences: a stand-in outside `.cache` proves the same rule, because the shim's test is "under `.cache`", and the run's `TMPDIR` is outside `.cache`, writable in the jail and removed after the run.
- The stand-in is made by raw `git init` to a named path, which the skill allows, plus a commit as `c0810@example.invalid` through `fixture.git`. `fixture.git` refuses a directory outside `.cache`, so commit through the helper is impossible there: commit in a fixture under `.cache` and clone it out with `git clone --no-hardlinks` to the named `TMPDIR` path.
- The `..` case needs a start point under `.cache` that resolves into `TMPDIR`. Use a symlink below the top of the fixture (allowed: c0530 does it) pointing to the stand-in's parent, for example `$3/out -> $TMPDIR/c0810-outside`, then `git init "$3/out/new/../escaped"`. Plain git would then create the repository in `TMPDIR`.
- Then assert something stronger than today: the stand-in's `.git` listing and config are unchanged, and no `escaped` folder exists in `TMPDIR`.
Recommendation:
- Replace every write aimed at `$1` (the real root) in this case with the stand-in, and give the `..` case its symlinked start and a `made` path.
- Correct the header comment.
- Keep the real root only in read-only probes (`rev-parse`), as the other cases do.
- Re-run the `init`, `..` and clone-destination mutants and record in E5 that the stand-in is what they touched.

### F4 [low] The shim's fast path checks the folder holding `.git`, not `.git` itself, so a `.git` symlink into another repository passes
Where: c0810 Design step 3; prototype `SHIM` (`if [[ -d $d/.git ]]; then under "$d" …; exec "$real" "$@"`).
Evidence: in scratch, a folder under the stand-in cache whose `.git` is a symlink to the victim's `.git` (whose config has no `worktree` or `include` line) took the fast path: `git add zz` gave rc 0, and `git -C victim status --short` then showed `AD zz` in the victim's index. The slow path would have refused it, because its `check "git dir"` resolves with `cd -P`.
Recommendation: in the fast path, also require `builtin cd -P "$d/.git"` to land `under` the cache (still no process start), or fall to the slow path when `$d/.git` is a symlink (`-L`). Add a case ("a .git symlink to a repository outside .cache is refused", against a `TMPDIR` stand-in) and a Rules row with today's fast path as the mutant.

### F5 [medium] `PICKMAN_REAP_SWEPT` and `PICKMAN_REAP_CACHE` leak from the launcher into every spec, so a nested, unjailed launcher treats its plain `bash` as a killed sweeper
Where: c0820 Design, "`fence.enter()`" ("The launcher's environment gets `PICKMAN_REAP_SWEPT=1`. Unjailed runs … are unchanged"); c0830 "`fence.enter()`: it passes `PICKMAN_REAP_CACHE=<cache>`"; prototype `fence.enter` (`process.exec("perl", launched, { …, env = reapEnv })`) and the jail prefix (`env -u PICKMAN_SWEEP_ONLY` only).
Evidence:
- Lune's `env` adds to the inherited environment (c0810 E3). The launcher's children (sandbox-exec, the sweeper, `bash`, `lune`, every spec) all inherit both variables, and only `PICKMAN_SWEEP_ONLY` is removed.
- A nested fixture run (c0640's lock and fence specs, `fence-leftovers`) goes through `jail()`'s "fixture of a guarded checkout" branch. That branch's `reapEnv` sets only `PICKMAN_REAP_CACHE`, so its launcher still sees `PICKMAN_REAP_SWEPT=1`. A signal death of its `bash` then prints "the jail's sweeper was killed … Stop and report this." and exits 1 instead of 128+n, although there's no sweeper. An agent that follows that message stops with a false `BLOCKED:`.
- The specs that run `fence.REAPER` directly inherit both. c0820's spec already has to pass `PICKMAN_REAP_SWEPT = ""` to see 137. c0850's cases, and c0830's signal case, run with the outer run's `PICKMAN_REAP_CACHE`, so their launchers unlink links at the top of the *outer run's* `.cache` in the middle of the run.
- AC3's "Without it, a signal death is still 128+n" is true only for a caller that clears it.
Critique: the tempting fix is to set `PICKMAN_REAP_SWEPT = ""` in the unjailed `reapEnv`. That fixes the nested launcher, but every direct REAPER user still inherits both.
Consequences: the variables are addressed to the launcher alone, so they must stop there. Unsetting them at the start of the `bash -c` line covers jailed and unjailed runs alike, since the launcher reads them before `exec`. The REAPER cases in c0830 and c0820 already set what they need explicitly, so they don't change.
Recommendation:
- Begin the runner's `bash -c` string with `unset PICKMAN_REAP_SWEPT PICKMAN_REAP_CACHE;`. Alternatively add both to the jail prefix's `env -u` and to the unjailed path.
- Add a case to c0820's spec: "a launcher started by a spec, whose command dies of a signal, exits 128+n without clearing anything". It runs `perl -e fence.REAPER sh -c 'kill -KILL $$'` with no `env`, and must give 137 in a jailed run.
- Add a Rules row with today's prefix as the mutant, and correct c0820's sentence "Unjailed runs … are unchanged".

### F6 [low] The raft document and two issue texts still describe the designs from before round 1
Where: R0260 Whole-raft design (diagram and interfaces); c0800 Maintainability and Test plan.
Evidence:
- The diagram routes "`deploy-beta`, `fence.sh` sentinel" through `replace-file.pl`, and the interfaces say replace-file is "Used by … `scripts/lib/fence.sh` and `scripts/deploy-beta.luau`. c0840's skill text names it as the only way unjailed code writes under `.cache`". c0830 now says `fence.sh` uses an inline rename, `deploy-beta` doesn't write under `.cache`, and c0840's text no longer claims "only" (round 1's F1 and F9). An executor who reads the raft first could put `replace-file.pl` back into `fence.sh` and break c0640's lock and fence specs again.
- "`alive(pid)` … counts `Operation not permitted` as alive" leaves out "only when jailed" (round 1 F8). The SWEEPER contract `perl -e SWEEPER <outside-pid> …` leaves out the `-` form (round 1 F2).
- c0800 Maintainability: "The nested-run switch is the fence's own variable, read in one place": there are now two variables.
- c0800 Test plan: the `check.sh :: AC5` bullet sits between the spec's cases, so the AC1 case appears nested under it.
Recommendation: bring the raft's diagram and Interfaces in line with c0830, c0840 and c0820 as they now are. Fix c0800's Maintainability sentence and Test plan list.

Verdict: changes
