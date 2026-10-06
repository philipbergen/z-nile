# Review 001: R0026 (design mode)
Inputs: prep worktree `prep-guards-and-numbering` at 3665e5d: `tracker/rafts/R0026/{R0026.md,check.sh}`; c0074, c0075, c0076, c0077, c0078, c0079 and c0080 (each `<id>.md`, `check.sh`, `acceptance/*.spec.luau`); `tracker/issues/c0078/review-of-round6-fixes.md`; the review, testing, tracker, ticket-prep and execute-raft skills; the prototype `.worktree/proto-r0260` (read, plus the runs below).
Runs, one at a time, outside any other sandbox, nothing printed `REPOSITORY CHANGED`:
- in the prototype, `lune run tests/run -- tests/acceptance/c0058/lock.spec.luau`: 1 passed, 8 failed (F1);
- in the prototype, `tracker/issues/c0079/acceptance/watchdog.spec.luau` with the launcher's `"kill 'KILL', -$pid;",` line deleted (backed up with `cp -p`, restored, `cmp` identical): 6 passed, 0 failed (F5);
- in a scratch folder under `$TMPDIR` (since removed), the prototype's git shim against a stand-in "cache" holding a fixture whose own config sets `core.worktree` outside it (F3), and plain git on `core.worktree` discovery.

### F1 [high] c0077's sentinel write makes `scripts/lib/fence.sh` depend on `replace-file.pl`, which breaks the promoted c0058 lock and fence specs. Its `Overrides: none` is wrong
Where: c0077 Design, "`scripts/lib/fence.sh`" (`printf … | perl "$here/scripts/lib/replace-file.pl" "$sentinel"`); c0077 Regression guard and `Overrides:` line; raft E5.
Evidence:
- `tests/acceptance/c0058/lock.spec.luau:145` and `tests/acceptance/c0058/fence.spec.luau:103` build fixture checkouts from `tests/run.luau`, `tests/lib`, `scripts/lib/ac.sh`, `scripts/lib/fence.sh`, the git hooks, `.luaurc`, `rokit.toml` and `.gitignore`. They don't copy `replace-file.pl`. `tests/tooling/fence-leftovers.spec.luau:46-56` does the same.
- The nested runner sources the fixture's own `fence.sh` with `$here` set to the fixture (`fence.luau:600`). So the sentinel write runs `perl <fixture>/scripts/lib/replace-file.pl`, the file is missing, and `pickman_fence` returns 1.
- Run on the prototype: c0058/lock gives `1 passed, 8 failed`, with `Can't open perl script ".../.cache/c0058-lock/real/scripts/lib/replace-file.pl": No such file or directory`. c0058/fence uses the same parts list, so it fails the same way.
- c0077 names both specs under Affected specs ("by grep"), but its Regression guard only claims that the sentinel's text and refusals don't change. Raft E5 says every check passes on the prototype. No full gate (RC0) was run there, so this went unseen.
Critique: there are two tempting fixes, and both are poor:
- Add `replace-file.pl` to the c0058 copies as an override, which a chore may do. That turns a guard's internal dependency into a rule every future fixture copy of the runner must remember.
- Fall back to `mv -f` when the file is missing. That brings back the very behaviour the raft removes.
Consequences: the guard has to stay self-contained, so partial copies keep working. The review of round 6 already found the sentinel write sound ("Items checked without findings: `fence.sh` sentinel"): the link is unlinked and a folder refused just before it. The only reason to touch it is AC6's `mv -f` ban, so the ban can be met without the new file. The c0078 skill sentence "every unjailed writer under `.cache` goes through `replace-file.pl`" must then name this exception, and `cachepaths.ALLOWED` keeps the `mktemp "$here/.cache/.sentinel.XXXXXX"` line.
Recommendation:
- Keep fence.sh's exclusive `mktemp` in `.cache` and replace only the move: `perl -e 'rename $ARGV[0], $ARGV[1] or die "rename: $!\n"' "$fresh" "$sentinel" || { rm -f "$fresh"; return 1; }`. That is `rename(2)`, with no file dependency, and AC6 still passes.
- Update the c0077 Design, its cachepaths entries and the c0078 skill-text bullet to match.
- Then run the full gate on the prototype (RC0), and record it in raft E5 and in each issue's mutation record. Today the "every check passes" claim leaves out the one check that runs every promoted spec.
- If prep keeps the replace-file route instead, c0077 needs an `Overrides:` line naming `c0058/lock.spec.luau` and `c0058/fence.spec.luau`, and `fence-leftovers.spec.luau` added to its Touched modules.

### F2 [high] The sweeper's interlock is tied to the top Lune process, which a Ctrl-C kills first, so an interrupted run sweeps nothing
Where: c0076 Design, "`fence.enter()`" (`… perl -e <SWEEPER> <myPid()> …`) and SWEEPER step 3 (an `ESRCH` exits 70); prototype `fence.luau` `jail()` and `fence.SWEEPER`.
Evidence:
- The interlock is `if (kill(0, $outside) || !$!{EPERM}) { … exit 70 }`, with `$outside` = `myPid()`, the top Lune.
- Lune has no signal handler: an INT ends it at once with 130 (`review-of-round6-fixes.md` F1, observed). A Ctrl-C reaches the terminal's foreground group, which holds the top Lune and the launcher. So the top Lune dies and is reaped by the shell.
- Meanwhile the launcher forwards INT to the specs' group. The sweeper ignores it, its child dies, `waitpid` returns, and `kill 0` on the reaped top pid gives `ESRCH`. The sweeper prints "not in a jail…; nothing swept" and exits 70, and every detached leftover lives on.
- The same happens for a TERM sent only to the top process (a caller's timeout).
- An interrupted run is the likeliest moment for leftovers. Neither the spec nor AC5 nor RC1 interrupts a run: all three end normally.
Critique: the tempting fix is to also accept `ESRCH`. But that removes the protection the "pid is gone" case exists for. A sweeper that wrongly believes it is jailed would `kill 0` over every process the user owns.
Consequences: the interlock needs an outside process that is guaranteed alive through the sweep, same user, and outside the jail. That is the launcher: the sweeper's own parent, since the REAPER child `exec`s `sandbox-exec … env … perl`, and the launcher `waitpid`s on it. That brings two new rules:
- If the launcher is already gone, `getppid()` returns 1. `kill 0, 1` gives `EPERM` (root) even unjailed, so pid 1 must be refused, as must any pid that changed since the start.
- If the launcher is SIGKILLed, the watchdog kills the specs' group, sweeper included. Then no sweep and no unlink happen. That is a remaining gap the skill must state.
Recommendation:
- The real prefix passes a marker (for example `-`) that makes the sweeper read `getppid()` once, at its start. It refuses (70) if that pid is 1, or if `getppid()` differs at sweep time. The spec cases keep the explicit-pid form.
- Add a row and a check: a real jailed suite in a fixture, whose probe leaves a `setsid` process and then sleeps. The check sends INT to the fixture run's top process and to the launcher (as the terminal does), then requires the process gone (an AC5 or RC1 variant).
- Add an AC4-style static case pinning the marker in the prefix.
- c0078's skill text adds: "a SIGKILL of the launcher skips the sweep and the unlink".

### F3 [high] The git shim's fast path never checks the work tree. A fixture whose own config sets `core.worktree` outside `.cache` lets `add`, `checkout -- .` and `reset --hard` reach the real checkout
Where: c0075 Design, "The shim", step 1 (fast path); prototype `tests/lib/fixture.luau` `SHIM`; c0075 AC1 ("…or with a work tree, outside the checkout's `.cache` … however it gets there: … `-c core.worktree`").
Evidence:
- Git honours `core.worktree` from a discovered repository's own config. Only `-c` is ignored. In scratch, `git init fx && git -C fx config core.worktree <victim>` made `git rev-parse --show-toplevel` in `fx` print `<victim>`. With `-c core.worktree=<victim>` on a clean repository it printed `fx`.
- So prep's E4 note "git ignores `-c core.worktree`" is true only of `-c`.
- With the prototype's shim first on `PATH`, and a stand-in cache holding `fx` with that config:
  - `git add -A` took the fast path (a `.git` folder under the cache, no leading option) and staged the victim's files;
  - after `rm victim/t`, `git checkout -- .` took the fast path and wrote `victim/t` back;
  - only the calls with a leading option (`git -c … commit`, `git --no-pager status`) took the slow path, and the `show-toplevel` check refused them.
- A shell string such as `git config core.worktree "$REAL" && git reset --hard` therefore passes the fence. The first command runs in the fixture (allowed), and the second takes the fast path.
- The spec only tries `-c core.worktree` (`shell-git.spec.luau:79`), so the prototype passes AC1.
Critique: the tempting fix is to drop the fast path. That costs the +33% that E1 measured, and the fallback (shim only for `sh -c`) would then be needed.
Consequences: the fast path must hand off to the slow path whenever the found repository could carry a work tree elsewhere. That covers `core.worktree` in its config, and an `[include]` that could set it, since prep hasn't proved whether discovery follows includes. Reading the config has to stay process-free (`mapfile`/`read` builtins, not `$(<…)` or `grep`), or the time budget comes back. `GIT_CONFIG_PARAMETERS`/`GIT_CONFIG_COUNT` behave like `-c` in discovery. Pin that with a case, rather than assume it.
Recommendation:
- In the fast path, after finding `$d/.git` as a folder, read `$d/.git/config` with a bash builtin. If it mentions `worktree` or `include` (case-insensitive), fall to the slow path.
- Add a case to `shell-git.spec`: "a fixture whose own config points core.worktree at the real checkout is refused" (`git config core.worktree "$real"; git status` and `git checkout -- .`, each refused with `fixture git`).
- Add a case: "GIT_CONFIG_COUNT setting core.worktree doesn't reach the real checkout" (refused, or stayed in the fixture).
- Add a Rules row: mutant = today's fast path.
- Re-time E1 with the extra read.

### F4 [high] c0074's spec drives the "outside a spec run" branch by clearing `PICKMAN_FENCE_SPECS`, which turns off the spec-mode guards for everything the fixture's `done` starts
Where: `tracker/issues/c0074/acceptance/done-gate.spec.luau` `done()` (`PICKMAN_FENCE_SPECS = if nested then "1" else ""`); c0074 Implementation step 3 (an `ALLOWED` entry in `repo-fence.spec` so it may name it).
Evidence: `PICKMAN_FENCE_SPECS` is a guard variable, not a mode flag for `done` alone. With it empty:
- `pickman_fence` (`scripts/lib/fence.sh:17`), run by every `ac.sh` the fixture's `done` starts (the raft `check.sh`), drops to `checks` mode. It runs `unset GIT_CONFIG_COUNT` and rebuilds the list with three keys, so the inherited `protocol.allow=never`, `protocol.file.allow` and the empty `credential.helper` entries no longer apply.
- `reference-transaction:46` again allows fetch-style ref updates in a protected repository.
- `pre-push:20` again lets a push to a network URL through to `chain`.

On macOS the jail still holds. On Linux (CI, unjailed) these are the guards. The repo-fence gate spec bans `PICKMAN_FENCE_` names precisely so that a spec can't do this, and step 3 asks a reviewer to bless it.
Critique: the tempting fix is "the fixture has no origin and the gate is a stub, so nothing happens". But the testing skill rates any weakening of the guards as high, whatever the current content of the subtree. The next edit to the stub or the fixture inherits a fenceless environment.
Consequences: the outside branch needs a seam that can only *add* work and never remove a guard. `done` runs the gate when it isn't nested, or when a dedicated variable (for example `PICKMAN_DONE_GATE=1`) asks for it even though it is nested. The seam must never skip the gate. A fixture that sets it while the real gate is in place would recurse, so the seam is documented as "stub gates only", and the c0001, c0008, c0034, c0038, c0045 and c0050 fixtures don't set it.
Recommendation:
- Replace the clearing with the add-only seam, and keep `PICKMAN_FENCE_SPECS=1` in every case.
- The AC1 and AC2 cases set the seam. The AC3 case keeps the plain nested run and requires no gate call.
- Add a row: "the seam can't skip the gate" (mutant: the seam read as "skip when set").
- Add a row: "nested without the seam runs no gate" (exists).
- Drop step 3's `ALLOWED` entry for `PICKMAN_FENCE_SPECS`: the spec then names no guard variable.

### F5 [medium] c0079's "a normal end … leaves nothing of its group behind" can't fail for its listed mutant, because the watchdog cleans up after the launcher exits
Where: c0079 Rules and mutants, row "the status passes through, and the group is gone after a normal end" (`reasoned`, mutant: no `kill 'KILL', -$pid` after `waitpid`); `watchdog.spec.luau` third case.
Evidence:
- With that line removed from the prototype's REAPER, the spec still passes 6/6 (run above).
- The launcher exits, its pipe's write end closes, the watchdog's `sysread` returns end-of-file, and the watchdog kills the group within the case's 3-second wait.
- The mutant is not harmless. c0077's unlink is specified to run "after `kill 'KILL', -$pid`". With the mutant, the unlink runs while leftovers in the group still live, so they can swap a link in after it.
Critique: the tempting fix is a timing assertion (the group is gone "immediately"). That races the watchdog, which fires within milliseconds.
Consequences: the order (kill the group, then unlink, then exit) can't be observed deterministically from outside without a seam that disables the watchdog. A seam in the runner's launcher is a new guard bypass, so it is worse.
Recommendation:
- Pin the order statically in the same case, as AC4 already does for the forks: `waitpid($pid, 0)` precedes `kill 'KILL', -$pid`, which precedes the `PICKMAN_REAP_CACHE` unlink, which precedes `exit`, found in that order in `fence.REAPER`.
- Mark the row `run` with the static case, and record the mutation result above in E4.

### F6 [medium] The shim passes `init` and `clone` through unchecked, on both paths: a shell that `cd`s into the real checkout can reinitialize it, move its `.git`, or clone into its working tree
Where: c0075 Design, the shim steps 1 and 2 ("Subcommand `init`, `clone`, `version`, `help`, or none: `exec` the real git").
Evidence:
- `sh -c 'cd "$REAL" && git init --separate-git-dir=/elsewhere'` is a reinitialization, so git *moves* the existing repository's git directory and leaves a gitfile.
- `git init` alone reinitializes in place.
- `git clone <fixture>` with no target creates a directory in the real working tree.
- None of these updates a ref, so the Linux ref guard doesn't fire. c0075's own Problem names exactly this class: changes to working files with no ref update.
- The rule it borrows ("creating a repository at a named path needs no check") is the helper's rule for raw git in specs, where the path is literal in the spec. Through a shell string, the target is wherever the shell happens to be.
Critique: the tempting fix is to refuse `init` and `clone` through the shim. That breaks `shell-git.spec`'s own init/clone case, and any tracker or `gh` stub that clones a fixture.
Consequences: the check is on the target, which is the same rule as everything else. The target is the last non-option argument of `init`, or cwd if there is none. For `clone` it is the second positional, or the name derived from the source in cwd. A `--separate-git-dir` value is a target too. Each must resolve physically under `.cache`. A missing parent folder resolves through its nearest existing ancestor.
Recommendation:
- Check those targets in both paths.
- Add cases: "init or clone aimed at, or run from inside, the real checkout is refused" (cwd form, path form, `--separate-git-dir` form).
- Keep "init and clone under .cache still work".
- Add a row each.
- AC3's twelve specs show whether any helper-run command clones outside `.cache`; prep found none by reading.

### F7 [medium] c0077's `build_place` change (rename through replace-file, and removal of its temporary folder, review F4) has no row and no case. The gate stand-in stops before `build_place` runs
Where: c0077 Design "`scripts/check.sh`" item 3; Rules and mutants (no `build_place` row); `replace-file.spec.luau` `gateCopy` (stub `rojo` "every call fails").
Evidence:
- `scripts/check.sh` runs `rojo sourcemap … -o sourcemap.json` (line 44) before the concurrent stages. The stub `rojo` fails there under `set -e`, so `build_place` never runs in either gate case.
- The case "the gate removes links at the top of .cache" passes because of the new top-level `find … -type l` unlink, not `build_place`.
- A `build_place` that still leaves its `mktemp -d` folder behind (review F4's complaint), or writes `.cache/check.rbxl` with `cp`, passes every check. AC6 only bans `mv -f`.
Critique: the tempting fix is a grep for `replace-file.pl` in `build_place`. That pins the text, not the behaviour, and says nothing about the cleanup.
Consequences: driving `build_place` means the stand-in gate must get past `rojo sourcemap` and the concurrent static stages. That needs stubs for `rojo` (sourcemap and build write their `-o` file), `stylua`, `selene`, `luau-lsp` and `lune` (`--version`, then fail at the tests stage, which comes after the build). The stubs go in the case's own `bin`, with `HOME` already isolated.
Recommendation:
- Add a case: "the build lands as a regular file over a link to a directory, and leaves no build folder in TMPDIR". Link `.cache/check.rbxl` to a stand-in folder *after* the top-level unlink: the stub `rojo build` makes the link itself before writing its `-o` file, so the link is deterministically there when the rename runs. Then require the path to be a regular file, the folder's listing unchanged, and `TMPDIR` empty.
- Add rows "build_place renames, never writes through" (mutant: `cp "$d/check.rbxl" .cache/check.rbxl`) and "the build folder is removed" (mutant: no `rm -rf "$d"`).

### F8 [low] Counting `Operation not permitted` as alive also changes the *unjailed* lock code: a stale lock whose pid now belongs to another user's or root's process is never taken over
Where: c0078 Design "`fence.alive`" ("Used by the lock code (`anyAlive`, `takeOverIfStale`) as today").
Evidence:
- The lock is taken and judged by the top Lune, outside the jail. There, `EPERM` from `kill -0` means only "a process of another user or of root has this pid now".
- Today such a lock is stale and is taken over. With the change, every later run waits 240 s and fails "another test run (pid N)…" until someone removes the lock by hand.
- macOS pids wrap at 99999, and the lock records several (`pid`, `pid-N`).
Recommendation: count `EPERM` as alive only when jailed (`PICKMAN_TEST_JAIL == "sandbox-exec"`), and add that branch to the AC2 case. Mutants: `EPERM` always alive (this case), and never alive (the existing case).

### F9 [low] The `.cache` allowlist trusts variable definitions and covers only `scripts/`, so a new write through a listed variable, or a runner write, passes. The skill sentence c0078 adds would overstate it
Where: c0077 "The reviewed list of `.cache` paths"; prototype `cachepaths.ALLOWED` (`defs=.cache/globalTypes.d.luau`, `local FOCUS_FILE = ".cache/tracker-focus"`, `local sentinel=…`, `local out = given or ".cache/board.html"`); c0078 skill bullet "every unjailed writer under `.cache` goes through `scripts/lib/replace-file.pl`".
Evidence:
- `printf x > "$defs"` or `fs.writeFile(FOCUS_FILE, id)` contains no `.cache`, so the scan never sees it.
- The runner's own unjailed writes, which aren't scanned, don't go through replace-file either: `fence.luau` `mkdir` of the lock and the takeover mutex, `fs.writeFile(lock/pid)`, and `fence.sh`'s `gh-none` folder.
Recommendation: word the skill text as what is true ("each `.cache` line in `scripts/` is reviewed; the writers listed there replace by rename"). Optionally make `scan` also flag lines that use a listed variable name (`$defs`, `FOCUS_FILE`, `sentinel`) unless they are listed too, with a planted case.

### F10 [low] Order and skill text don't agree with the designs
Where: R0026 Order & dependencies; c0078 Implementation step 6; the tracker skill's `done` row; c0076/c0078 skill bullets.
Evidence:
- The raft orders c0078 (4th) before c0075 (5th). c0078 step 6 says its skill edits wait until c0075 is in, so that AC4's "shim" fact is true.
- c0074 changes `done`'s order (moves before ready, a full gate in between) and the window during which an interrupted `done` leaves an uncommitted, moved tree. The tracker skill's `done` row (order, and the recovery advice "run `git reset --hard HEAD` and re-run `done`") isn't in anyone's Touched modules.
Recommendation:
- Either move c0075 before c0078 in the raft order, or make step 6 the raft's last code step and say so.
- Add `.claude/skills/tracker/SKILL.md` to c0074's Touched modules, with the new order and "an interrupted gate leaves the tree moved: `git reset --hard HEAD`, then re-run `done`".

### F11 [low] Unproven: what the kernel logs for ~100,000 refused signals per sweep pass
Where: c0076 E1 and Scalability ("a sweep pass is 99,998 `kill 0` calls, about 40 ms"); c0078 signal rule.
Evidence: E1 measured the time, but not the side effect. Sandbox denials are normally reported to the unified log, and with the new rule every `kill 0` to an outside pid is a denial. Every gate makes at least one pass, and parallel worktrees make more. Nothing records whether this floods `log` or `sandboxd`, or whether it is throttled.
Recommendation: add an experiment. Run one sweep in prep and count `log show --last 1m --predicate 'sender == "Sandbox"'` lines. If it floods, use `(deny signal (with no-log))`, re-run E1 (c0078) to confirm the rule still refuses, and record the result.

Verdict: changes
