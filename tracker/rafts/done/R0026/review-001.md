# Review 001: R0026 (code mode)
Inputs: HEAD 36a40c5 (branch R0026-guard-follow-ups) against origin/main 7d8dee1 (`scripts/tracker.sh sync --fetch`, no merge); `git diff origin/main...HEAD`; R0026.md (with "Addressed during execution"); c0074, c0076, c0077, c0078, c0079, c0080, c0096, c0097 documents, `check.sh` files and acceptance specs; stream-review-c0074-001.md, stream-review-c0080-001.md; the review, testing, tracker and architecture skills.

Runs (macOS, outside any other sandbox; every run was jailed: no "not jailed" note, and the jailed-case markers were written):
- `bash tracker/rafts/active/R0026/check.sh`: 11/11 PASS (RC0 full gate, the 8 members, promote-check, RC1).
- `scripts/check.sh --full`: GATE PASSED, 1308 passed, 0 failed, 187 spec files; selene 0 errors, 0 warnings, 0 parse errors; no `sweeper: stopped` line.
- `scripts/tracker.sh check <id>`: c0074 6/6, c0076 6/6, c0077 6/6, c0078 4/4, c0079 4/4, c0080 4/4, c0096 1/1, c0097 1/1.
- No run printed `REPOSITORY CHANGED`. `git status` stayed clean.
- Experiments, in the scratchpad only:
  - two `sandbox-exec` instances with an identical profile can't signal each other ("same-sandbox" is per instance), so concurrent runs in different worktrees can't sweep each other;
  - `git worktree add` into a symlink to an empty directory (F2);
  - `kill(0, 1)` from an unjailed Perl gives EPERM (F1);
  - the Claude Code binary's own sandbox profile contains `(allow signal (target same-sandbox))` (F3).

Sequestration: `git diff --find-renames=100% --name-status origin/main...HEAD -- 'tracker/**/check.sh' 'tracker/**/acceptance/**'` lists R100 moves plus:
- c0076's `sweeper.spec.luau` and c0078's `jail-signals.spec.luau`: delete and add pairs, 99% similar. Each changes exactly one line, the `.cache` base folder (`c0820-sweeper` to `c0076-sweeper`, `c0840-signals` to `c0078-signals`). That is the user's "Fix the specs" decision as c0096 records it, and nothing more. c0096's AC1 checks that each spec's folder matches its `check.sh` marker before and after promotion.
- c0096's and c0097's `check.sh` files: new, for emergent issues, as the tracker skill's Emergent issues rule requires.
- c0097's edit of the promoted c0049 spec matches its Overrides line and the user's "Exempt tests-run in c0049": `tests-run` added to `SHARED_BY_DESIGN`, a comment, and one case.

No other change to a sequestered file. Not a violation.

### F1 [medium] The sweeper's explicit-pid form fails open: an EPERM from any other user's pid passes the interlock unjailed, and a `PICKMAN_SWEEP_ONLY` that can't be opened widens the sweep to every pid
Where: `tests/lib/fence.luau:474` (interlock) and `:477-478` (candidates); c0076 Design steps 3–4 ("it can only narrow the sweep").
Evidence:
- The interlock is one probe: `!kill(0, $outside) && $!{EPERM}`. Outside any sandbox, `kill(0, 1)` (root's launchd), or `kill 0` on any root or other-user pid, also fails with EPERM (checked: `perl -e 'kill(0,1)'` gives EPERM). So `perl -e SWEEPER 1 <cmd>`, run unjailed on Linux CI or on a Mac without `sandbox-exec`, passes the interlock and goes on to `kill STOP/KILL` every process the user owns except its ancestors.
- The `-` form is protected by the `parent == 1` check and by its parent being the launcher. The explicit form, exported as `fence.SWEEPER` and documented "Explicit pids are for specs", has only the probe.
- The test seam makes it worse: `if (defined $only && $only ne '' && open(...)) { @cand = ... }`. A set but missing or unreadable `PICKMAN_SWEEP_ONLY` (a typo in a spec's path, a file not yet written) leaves `@cand = 2 .. 99999`, the widest sweep. Inside the jail that kills every sibling spec worker of the run, since they share the sandbox (the spec's own header says so). With the hole above, unjailed, it kills the user's session.
- Today's callers (the c0076 spec) pass the top Lune's pid, and only when jailed, so nothing fires today. This is a trap in an exported API.
Critique: the c0076 Rules table claims "the interlock refuses outside a signal-refusing jail". It really refuses only outside a jail *or* a pid of another user, and the seam is "narrowing-only" only when the file opens. The tempting fix is to check that the pid isn't 1, which still passes any other root or other-user pid (`_windowserver`, `postgres`).
Consequences:
- A real ownership check needs `ps` or `pgrep -U`, and `/bin/ps` can't run in the jail (setuid). That is an untested dependency.
- Treating a set-but-unopenable seam as "refuse" adds an exit path that the sequestered spec doesn't pin. Its cases always write the file first, so they keep passing.
- Refusing the explicit form off macOS doesn't affect the c0076 spec's unjailed cases: they expect 70 anyway. The orphan case expects "no launcher above me", so the platform refusal must come after that check, in the interlock.
Recommendation:
- (a) In the interlock, refuse (70) unless `$^O eq 'darwin'`: there is no jail anywhere else.
- (b) A set, non-empty `PICKMAN_SWEEP_ONLY` that can't be opened is a refusal (70, "test seam unreadable; nothing swept"), never a widening.
- (c) For the explicit form only, also require `$ENV{PICKMAN_TEST_JAIL} eq 'sandbox-exec'`. The threat is a mistake, not a malicious spec, and the variable is what the runner gives specs. The `-` form keeps its launcher rule.
- Add cases to a non-sequestered spec (for example `tests/tooling/`), each listing only a background process the case started and expecting it alive afterwards:
  - unjailed, explicit pid `1`, gives 70;
  - unjailed or jailed, a missing seam file gives 70;
  - explicit form without `PICKMAN_TEST_JAIL` gives 70.
- Update c0076's Rules table and the testing skill's Sweeper bullet to say what the interlock proves.

### F2 [medium] The reviewed `.cache` list gives a false reason for `.cache/tracker-remap-base`: `git worktree add` writes through a symlink to an empty directory
Where: `tests/lib/cachepaths.luau` (the `local scratch = ".cache/tracker-remap-base"` entry, and `UNLINKED`); `scripts/tracker/main.luau:1271-1285`; c0077's verification note ("git refuses to add a worktree over an existing path and … the top-level links are unlinked first").
Evidence: in a scratch repository, with `.cache/tracker-remap-base -> ../../empty` (an empty directory outside the repository), `git worktree add -q --detach .cache/tracker-remap-base HEAD` exits 0 and writes `.git` and the tree's files into `empty/`. git refuses only a non-empty path, and it follows the link to judge that. `compactLib.apply` and `git add -A` then work in the link's target, and `worktree remove --force` deletes there.
- The "unlinked first" half is also untrue for remap. Nothing unlinks before remap runs. The launcher unlinks after each run and `check.sh` at its own start, so a link swapped in by a run going on in the same checkout at the same time (c0077 E1: the jail can't refuse a swap) is still there when remap runs.
Critique: c0077's whole defence is "every unjailed writer under `.cache` replaces by rename, and every `.cache` line is on a reviewed list whose reasons are true". This entry is an unjailed writer of a whole directory tree, which `replace-file.pl` can't cover, and its reason is wrong. The tempting fix is to `rm -f` a link at `scratch` just before `worktree add`. That still loses to a swap between the check and git's write: a directory at the top of `.cache` can be swapped just as a file can.
Consequences: moving the scratch worktree out of `.cache` (a fresh `mktemp -d` under the user temp folder, which the jail closes to specs) has these effects:
- the worktree is registered at a path outside the checkout;
- a crash leaves a stale registration, which the existing `worktree prune` after it and `tracker.sh worktree-prune` clear;
- the runner's tripwire lists only worktrees under `.cache`, so it ignores this one, as it should (remap never runs inside a spec run);
- no spec pins the path (grep finds it only in `cachepaths.luau`, `main.luau` and docs), so nothing sequestered changes;
- the ALLOWED entry goes stale, so the cache-paths scan forces its removal.
Recommendation: build the remap base in `mktemp -d "${TMPDIR:-/tmp}/tracker-remap-base.XXXXXX"` (Lune: `sh.must("mktemp", {"-d", …})`) and add the worktree inside it, never at a fixed name under `.cache`. Remove the ALLOWED entry. Add a case in an existing tracker remap spec that the remap base never appears under `.cache`, and keep the rule "a writer of a directory tree never writes under `.cache`" in the testing skill's Writers bullet.

### F3 [low] c0078's premise that an outer sandbox "(Claude Code's own) allows" signals is false, so `fence.alive` reads a live lock holder outside such a sandbox as dead
Where: c0078 Non-goals and the `fence.alive` Design; `tests/lib/fence.luau:68-77`; testing skill, Signals bullet.
Evidence: the installed Claude Code binary's sandbox profile has `(allow signal (target same-sandbox))` under a default deny. Inside it, `kill -0` on a same-user process outside it gives `Operation not permitted`. An unjailed run accepted as "outer sandbox (protects the repository)" calls `takeLock` in the top Lune, where `PICKMAN_TEST_JAIL` is unset. A lock held by a live run in the user's terminal then reads as stale and is taken over: two suites in one checkout, the 2026-09-30 failure.
Critique: this is pre-existing (the old `alive` also returned false on EPERM) and needs an uncommon outer-sandbox configuration in which `.cache` is writable and the rest of the checkout isn't. So it isn't a regression, but the raft re-specified `alive` and wrote down a reason that is wrong in a mode it supports. The sequestered spec pins only the `"none (unjailed)"` and `"sandbox-exec"` cases, so a third branch doesn't touch it.
Consequences: counting EPERM as alive in the outer-sandbox mode means a stale lock whose pid was reused by a root process waits out the limit and fails with "another test run (pid N)". The user then removes the lock by hand. That is the safe failure.
Recommendation: before `takeLock`, have `fence.enter` set the top Lune's own `process.env.PICKMAN_TEST_JAIL` to the jail verdict only when it starts with `outer sandbox`, and have `fence.alive` count EPERM as alive for that value too. Correct the c0078 Non-goal text. Add a case to a non-sequestered spec: `fence.alive("1")` with `PICKMAN_TEST_JAIL = "outer sandbox (protects the repository)"` is true.

### F4 [low] A spec can stop the sweeper (SIGSTOP or SIGTSTP; same sandbox): the run then hangs instead of failing, which the testing skill doesn't say
Where: `tests/lib/fence.luau` REAPER `waitpid($pid, 0)`; testing skill Sweeper bullet ("A spec can kill the sweeper …; the run then fails").
Evidence: the signal rule allows signals inside the sandbox, so a spec process can `kill -STOP <sweeper>`. `waitpid` without `WUNTRACED` never returns for a stopped child. The launcher waits forever, and Ctrl-C only forwards INT, which the sweeper ignores (and it's stopped). The run hangs until someone SIGKILLs the launcher. The watchdog then kills the group, and leftovers outside the group survive unswept.
Critique: it needs a deliberate or very odd spec, and it fails visibly (a hang), not silently. The tempting fix, `WUNTRACED` plus SIGCONT, lets a spec ping-pong STOP and CONT.
Consequences: treating "stopped" like "killed" (fail with the same message) gives the launcher one more exit path to test.
Recommendation: either add a sentence to the Sweeper bullet ("a spec can also stop it; the run then hangs, and SIGKILL of the launcher skips the sweep"), or have the launcher wait with `WUNTRACED` and treat a stopped sweeper as killed: kill the group and fail with the existing message. Add a case to the c0076-style tooling spec with `PICKMAN_REAP_SWEPT=1` and a command that stops itself.

### F5 [low] The tracker skill's `done` row doesn't mention the new `consequences:` requirement
Where: `.claude/skills/tracker/SKILL.md`, `done` row ("each finding answered `fixed`, `refuted`, or … `deferred <id>: <why>`").
Evidence: `reviewProblem` now refuses `- F1: fixed abc: …` without `consequences:`. Only execute-raft says so. The tracker skill, which the AGENTS.md table names for "finishing tracked work", still lists the old answer forms.
Critique: an agent following the tracker skill alone hits an unexplained refusal from `done`.
Consequences: none beyond keeping the two skills in step.
Recommendation: in the `done` row, write `fixed <sha>: <what>; consequences: <…>`. No spec needed. c0080's AC2 already pins execute-raft's form.

## Judged criteria (code mode only)
None. No member of this raft has a Judged criterion.

Verdict: changes
