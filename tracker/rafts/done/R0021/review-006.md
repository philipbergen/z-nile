# Review 006: R0021 (code mode)
Inputs: HEAD a7922db (branch R0021-check-isolation, PR #49) against origin/main 640af3c (`scripts/tracker.sh sync --fetch`, then `git fetch origin main`; merge-base b955616; main's three new commits are tracker-only). I read `git diff origin/main...HEAD` and `git diff 8c6ff9c..HEAD` (the round-5 fixes); review-001 to 005 and refute-001 to 005; R0021.md, the c0058, c0059 and c0060 docs and their check.sh files; and the review, testing, tracker and architecture skills. Runs, one at a time, outside any sandbox: `scripts/check.sh --full` GATE PASSED (943 passed, 0 failed, 142 spec files, 45.9 s); `tracker.sh check c0058` 10/10, `check c0059` 4/4 (its AC3 runs the full gate a second time; that is inside the check, I did not start it), `check c0060` 5/5. I did not run the raft check, since its RC0 is a third full gate. Scratch experiments ran only under my own folder in `$TMPDIR`, against a scratch `.cache` and victim files there, and in a `--no-hardlinks` clone there. Nothing printed `REPOSITORY CHANGED`, `git status` stayed clean, and I killed every process I started.
Dropped from review-005: F2 (the process-group reaping works: `fence-leftovers.spec` passes, a plain `&` child is reaped, exit codes pass through, and Ctrl-C/TERM/HUP are forwarded; `setsid` is listed under "Caught only by review" as the user decided) and F3 (the stub turns `-t p` into `$TMPDIR/p.XXXXXXXXXX`, and the gate asserts it). F1 is repeated as F1 below: the deny holds for `symlink`, `link`, `rename` and `clonefile`, but not for an atomic swap.

Sequestration: the name-status diff lists only R100 renames, plus c0058's and c0060's `check.sh` as D/A pairs. Those are the user-approved case-lookup edits (R0021.md, "Addressed during execution"). No commit since review-005 touches a sequestered file.

### F1 [high] A spec still puts a symlink at the top of `.cache` with an atomic swap (`renameatx_np` with `RENAME_SWAP`), and the next gate's rojo or the tracker then writes through it into the real repository (repeat of review-005 F1)
Where: `tests/lib/fence.luau` `profile` (`(deny file-write-create (require-all (vnode-type SYMLINK) (regex …)))`); `fence.enter()` (the leftover-link cleanup runs only when the next spec run starts); `escapes()` (no symlink probe); `scripts/check.sh:50` (rojo, before the tests at `:55`) and `:33` (curl); `scripts/tracker/main.luau` (`.cache/tracker-focus`, `tracker-claim-<raft>`, `board.html`); testing skill, "Jail (macOS)".
Evidence: I reproduced it in scratch, under this profile's exact rules for a scratch `.cache`. Inside the jail:
- `ln -s`, `ln -P` (a hard link to a deeper link), `mv sub/l top` and `clonefile` of a deeper link were each refused with `Operation not permitted`. So the round-5 rule works for every way of *creating* a name.
- `ln -s <victim> sub/a` then `/usr/bin/perl -e 'my ($a,$b)=("sub/a","check.rbxl"); print syscall(488, -2, $a, -2, $b, 2)'` (syscall 488 is `renameatx_np`, flag 2 is `RENAME_SWAP`) printed `0`. Afterwards `.cache/check.rbxl -> <victim>`. The same swap via Python's `renamex_np` also worked. At the time of the check the destination is a regular file, so the symlink-create rule never matches.

Then, unjailed:
- `rojo build default.project.json -o <scratch>/.cache/check.rbxl` printed `Built project to check.rbxl`. The link was still there, and the victim now began `<roblox!`.
- Lune's `fs.writeFile("<scratch>/.cache/tracker-focus", "c0058\n")` through a link swapped in the same way replaced the victim with `c0058`.

The swap only needs a name that already exists at the top. Every gate leaves `.cache/check.rbxl`, so a spec that swaps a link to `/Users/philipbergen/code/pickman/.git/config` onto it gets the shared git config of every worktree overwritten by the next `scripts/check.sh` in that worktree. The Stop hook runs that gate after any agent turn that touched `src/` or `tests/`. The runner's leftover cleanup doesn't help, for two reasons: it runs when the *next* spec run starts, and `check.sh` runs rojo at line 50, before its tests at line 55. The tripwire can't see the write either, because it happens after the run. Only system tools are needed (`/usr/bin/perl`), and the gate scan flags none of this.

Two more routes to the same writers:
- **Outer sandbox mode:** `escapes()` doesn't probe symlink creation. So the runner accepts an outer sandbox that lets specs make plain top-level links, against the skill's "An outer sandbox is accepted only if probes show it closes all of that too". The gate's jail case would flag it, but only after specs have run, and only in runs that include `repo-fence.spec`.
- **Testing skill:** the Jail bullet still doesn't mention the top-level symlink rule at all, and still says "Nothing a spec does can change the repository" without qualification.
Critique: the tempting fix is another SBPL rule for the swap. I found none that fits:
- At check time, the swap's destination is a regular file and its source a deeper symlink.
- Denying writes on deeper symlink vnodes breaks fixtures that make and delete links, such as c0055's setup spec.

The other tempting fix is to move the leftover cleanup earlier in `check.sh`. That covers rojo but not the tracker's writers or curl.
Consequences: the sandbox can't hold the "no top-level link" invariant alone, so the guarantee has to move to the boundary where jailed work ends. Once the specs' process group is reaped, no process inside the group can plant anything. What's left is a `setsid` survivor, which is already listed as review-only and is the same race as review-005 F2. A cleanup at that boundary must unlink, never follow, and must run in every top-level mode: the jail, an outer sandbox, and a fixture of a guarded run.
Recommendation:
- **Runner (main fix):** in `fence.enter()`, after the launcher returns (the group is reaped) and before the second snapshot, unlink every symlink at the top of `.cache`, exactly as the start-of-run cleanup does. This covers the swap, the outer-sandbox route and any other way a link appears, for every unjailed writer at once.
- **Defence in depth in the writers, as review-005 F1 already asked:**
  - `check.sh` builds to a fresh name (`rm -f .cache/check.$$.rbxl`, `rojo build -o` it, then `mv -f` it onto `.cache/check.rbxl`), and does the same for curl's defs file.
  - The tracker writes `<name>.tmp.<pid>` and renames it over the name.
  - A rename replaces a symlink and never follows it.
- **`escapes()`:** add the same `ln -s /nonexistent .cache/<probe>` probe the gate case uses, so the runner refuses an outer sandbox that allows top-level links.
- **Spec case** (`tests/tooling`, macOS only; Linux has no jail): with a copied runner in a fixture, as in `fence-leftovers.spec`, run a probe spec that swaps a link into the top of the fixture's `.cache` with `/usr/bin/perl` syscall 488. Expect no symlink at the top once the nested run returns, and the link's target unchanged. Mutant: the end-of-run cleanup removed is killed.
- **Testing skill:**
  - The Jail bullet says links can't be created at the top of `.cache`, and that the runner unlinks any found there when a run starts and ends (a swap gets past the sandbox).
  - "Caught only by review" adds to the `setsid` bullet that a survivor can also swap a link into the top of `.cache` after the run.
  - Qualify "Nothing a spec does can change the repository" with "while it runs in the specs' process group".

### F2 [medium] The specs now outlive a SIGKILL of the run's process group, keeping the lock: a hung run that its caller kills holds the checkout's lock until someone finds and kills it
Where: `tests/lib/fence.luau` `REAPER` (`setpgrp(0, 0)` in the child; reaping happens only in the launcher, after `waitpid`).
Evidence: in a scratch clone, I started `lune run tests/run -- tests/probe/slow.spec.luau` (a probe spec that runs `sleep 15`) in a session of its own, waited 5 s, and sent `kill -KILL` to that session's process group, as a caller that kills a timed-out command by group does. The top Lune and the launcher died. Five processes survived in group 69578: both levels of the jailed `lune run tests/run`, and the `sleep 15`. They were parented to launchd, and the lock under the clone's `.cache` was still held. Before round 5 the specs shared the caller's group, and the same kill stopped them. A spec that hangs, which is the usual reason a caller kills a run, now keeps running with the lock held. Every later run in that checkout then waits 240 s and gives up with "another test run … gave up", until a person kills the orphan group by hand. INT, TERM and HUP are forwarded, so Ctrl-C, `timeout`'s default TERM and a closed terminal still work. Only an uncatchable kill of the caller's group, or of the launcher, leaves the orphans. The processes stay jailed, so this is not a repository hole.
Critique: the tempting fix is to forward more signals. SIGKILL can't be caught, so that doesn't help.
Consequences: the specs' group has to notice for itself that the launcher died. That needs a member of the group that waits on something only the launcher holds. That member must not keep the lock alive on its own, and it must not fire when the lock spec kills only the top Lune (the launcher survives that).
Recommendation:
- **Watchdog:** in `REAPER`, before forking the child, open a pipe. In the child, after `setpgrp`, fork a watchdog that closes the write end, blocks reading the pipe, and on EOF runs `kill 'KILL', 0` (its own group). Then exec the command, with the read end closed for the command (close-on-exec).
- **Launcher:** it holds the write end, and closes it after `waitpid`. That gives the same end-of-run reaping as now, and also when the launcher itself is killed.
- **Spec case** in `tests/tooling` (it can share `fence-leftovers.spec`'s fixture): start the copied runner in a session of its own with a probe spec that sleeps, `kill -KILL` that session's group, and expect the probe's process gone within a few seconds. Mutant: the watchdog removed is killed.
- **Recheck:** confirm the lock spec's "a run whose top process was killed keeps the lock" still passes, since the launcher lives on there.

### F3 [low] Every gate now prints a luau-lsp warning for the regex-escape pattern in `profile`
Where: `tests/lib/fence.luau:304` (`"[%.%[%]%*%^%$%(%)%+%?%{%}%|\\]"`).
Evidence: the full gate's "types (tests + scripts)" stage prints `tests/lib/fence.luau(304,36): FormatString: Invalid match pattern: expected a magic character after %`. At runtime the pattern works: I checked a path holding every special character, and each was escaped. So this is noise in the gate's output, which hides real warnings in the future.
Recommendation: write `{`, `}` and `|` without `%`, since they aren't magic in Luau patterns, for example `"[%.%[%]%*%^%$%(%)%+%?{}|\\]"`. Then check that the stage prints nothing for the file, and that the escaped output is unchanged for a path holding every special character.

## Main question
On macOS one deterministic path remains, beyond the review-only list: F1. A spec swaps a symlink into an existing name at the top of `.cache`, and the next gate's rojo (the Stop hook included), curl, or the tracker's focus, claim and board writers write through it into `.git` or a tracked file. The round-5 rule stops every other way of making such a link (`symlink`, `link`, `rename`, `clonefile`).

Still closed and live-probed:
- direct writes to the checkout, the main checkout and `.git`;
- the `.cache` entry itself;
- home, `/tmp`, `/private/tmp` and the user temp folder;
- the folders above the checkout;
- non-loopback IP, git's network transports and proxies.

Deeper planted links don't reach the `check.sh` copy flows: c0058's `make_copy` and c0049's gate copy both `rm -rf` their folder before copying, and `rm -rf` doesn't follow links. Only a `setsid` survivor races them, and that is listed.

On Linux CI: no jail, as documented. The launcher needs only `perl`, which ubuntu-latest has. `fence-leftovers.spec` should pass there, because the reaping doesn't depend on the jail. CI has skipped every push of this draft PR, and no `workflow_dispatch` run exists, so none of this round's code has run on Linux yet. The gate on the ready PR is the first proof.

## Judged criteria (code mode only)
None: c0058, c0059 and c0060 have no Judged criteria.

Verdict: changes
