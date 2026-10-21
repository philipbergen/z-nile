# Review 005: R0021 (code mode)
Inputs: HEAD 8c6ff9c (branch R0021-check-isolation, PR #49) against origin/main ad3925a (`scripts/tracker.sh sync --fetch`, then `git fetch origin main`; merge-base b955616). I read `git diff origin/main...HEAD` and `git diff 8fa6043..72fef43` (the round-4 fixes); review-001 to 004 and refute-001 to 004; R0021.md, the c0058, c0059 and c0060 docs and their check.sh files; and the testing, tracker, architecture and review skills. Each run happened once, one at a time, outside any sandbox: `scripts/check.sh --full` GATE PASSED (942 passed, 0 failed, 141 spec files, 44.2 s); `tracker.sh check c0058` 10/10, `check c0060` 5/5, `check c0059` 4/4. Scratch experiments ran only under my own folder in `$TMPDIR`. Nothing printed `REPOSITORY CHANGED`, and `git status` was clean after every run.
Dropped from review-004: F1 and F2. Both fixes hold:
- **F1:** `fence.sh` refuses a symlinked or file `.cache` and a `.cache/.git` folder, it unlinks a `.cache/.git` symlink with `rm -f`, and it has no `rm -rf` left. `ac.sh` exits on the refusal, and `fence.enter()` refuses before it writes anything. Under the profile's rules, `rm -rf .cache`, `mv .cache`, `touch -c -r .cache .cache` and `chmod .cache` all fail with `Operation not permitted`, and the entry survives (reproduced in scratch).
- **F2:** the user temp folder is closed. The gate probes it, and `escapes` probes it too.

Sequestration: the name-status diff lists only R100 renames, plus c0058's and c0060's `check.sh` as D/A pairs. Those are the user-approved case-lookup edits. No commit since review-004 touches a sequestered file.

### F1 [high] The jail still lets a spec create symlinks inside `.cache`, and unjailed writers then write through them into the real repository: rojo in every gate (the Stop hook included), and the tracker's focus, claim and board files
Where: `tests/lib/fence.luau` `profile` (`(allow file-write* (subpath "<cache>"))` covers creating symlinks in `.cache`); `scripts/check.sh:50` (`rojo build … -o .cache/check.rbxl`, unjailed) and `:33` (`curl -o .cache/globalTypes.d.luau` when the file is empty or missing); `scripts/tracker/main.luau:1267` (`fs.writeFile(".cache/tracker-focus", …)`), `:923`/`:960` (`.cache/tracker-claim-<raft>`) and `:1657` (`.cache/board.html`); testing skill, "Jail (macOS)" ("Nothing a spec does can change the repository").
Evidence: I reproduced both steps in scratch under `$TMPDIR`.
1. Under `sandbox-exec` with this profile's rules for a scratch checkout, `ln -s <victim>/HEAD <checkout>/.cache/check.rbxl` succeeds (`PLANTED-IN-JAIL`). A hard link (`ln <protected file> .cache/h`) is denied, so only symlinks get through.
2. Unjailed, `rojo build default.project.json -o .cache/check.rbxl` printed `Built project to check.rbxl`. The symlink was still in place, and `<victim>/HEAD` now began `<roblox!` (the rbxl binary). Lune's `fs.writeFile(".cache/tracker-focus", "c0058\n")` through a planted link also replaced the target's contents.

So a spec that runs `ln -sf /Users/philipbergen/code/pickman/.git/config .cache/check.rbxl` replaces the shared git config of the main checkout and every worktree (remotes, branches' upstreams, identity) at the next `scripts/check.sh` in that worktree. The Stop hook runs that gate after every agent turn that touched `src/` or `tests/`, so no person needs to act. Pointed at `.git/HEAD` it detaches every session's main checkout; pointed at a tracked file it rewrites it. `tracker.sh focus`, `start` and `board` do the same with their own contents. The tripwire can't see any of this: these writes happen after the run, outside it.

Round 4 closed the `.cache` entry itself, so this is the same class one level down. Review-004 F1 noted these writers only as "junk files" behind a symlinked `.cache`; through a per-file link they overwrite existing files. "Caught only by review" doesn't name it, and the gate's scan doesn't flag `ln -s`.
Critique: the tempting fix is a scan for symlinks in `.cache` after the jailed child exits. That doesn't hold: a jailed process can outlive the run (F2) and plant the link after the scan. Making each writer careful (`[[ -L ]]` before rojo, then `rm -f` before writing) has the same race, and it leaves rojo and curl, which open their output path themselves.
Consequences: the sandbox can refuse symlink creation by vnode type. In scratch I ran `(deny file-write-create (require-all (vnode-type SYMLINK) (regex #"^<cache>/[^/]+$")))` after the `.cache` allow.
- What it blocks: `ln -s x .cache/top` fails, and so does `mv .cache/sub/deep .cache/check.rbxl` (renaming a deeper link up).
- What it still allows: links deeper in fixtures (`.cache/sub/deep`), which fixtures may need, and moving a whole folder that holds links (`mv d2 .cache/check2`). The unjailed writers above all target top-level names, so this closes them.

The fix brings new rules:
- The cache path must be regex-escaped, in both its written and resolved forms.
- The rule must also be measured against the full gate, since any spec that symlinks at `.cache`'s top level would now fail.
- It leaves the deeper paths that unjailed `check.sh` flows build and then use. Those are covered in F2.
Recommendation:
- **Jail:** add the top-level symlink deny above for the cache, written and resolved, with the path regex-escaped.
- **Gate probe:** in the gate's jail case, add a live probe that `ln -s /dev/null .cache/repo-fence-link-<tag>` fails, removed at once if it succeeds.
- **Defence in depth:** each unjailed writer into `.cache` replaces its file instead of writing through it. The tracker writes `<name>.tmp.<pid>` and renames it over the name, since a rename replaces a symlink and never follows it. `scripts/check.sh` sends rojo's output to a fresh `mktemp` file under `.cache` and renames it onto `check.rbxl`, and does the same for curl.
- **Spec case** (`tests/tooling`, not sequestered): plant a top-level link in a scratch checkout's `.cache` under the runner's jail and expect `Operation not permitted`. Mutant: the deny removed is killed by the probe.
- **Testing skill:** the Jail bullet says symlinks can't be made at the top of `.cache`, and why.

### F2 [high] A spec's background process outlives the run, still able to write `.cache`, and can rewrite code that unjailed `check.sh` flows copy into `.cache` and then run
Where: `tests/lib/fence.luau` `fence.enter()` (`process.exec(command, argv, { stdio = "forward" })` waits only for the jailed `bash`; the lock is then released and the run temp folder removed); `tracker/issues/active/c0058/check.sh` `make_copy`/`chain`/`outer` (`cp` the runner and guards into `.cache/c0058-chain`, then the unjailed shell runs `cd "$copy" && lune run tests/run`); `tracker/issues/done/c0049/check.sh` `gate_static_failure` (`rsync` into `.cache/c0049-gate`, then `cd "$d" && scripts/check.sh --full`); testing skill, "Caught only by review".
Evidence: the jailed run doesn't take its descendants with it, and a copy's runner starts unjailed. I showed both in scratch.
- **The background process survives:** from Lune, `process.exec("sandbox-exec", {"-p", <profile>, "bash", "-c", "(sleep 2; ln -s /etc/hosts <cache>/late-link) … &"}, {stdio = "forward"})` returned at once (`returned 0`, no link yet). The link appeared two seconds later, after the "run" had ended.
- **The copy's runner starts unjailed:** I left a jailed poller behind. Then an unjailed flow shaped like `make_copy` deleted and re-made `<cache>/chain`, wrote `tests/run.sh` and then `tests/probe/chain.spec`, and ran `bash tests/run.sh`. The poller had already rewritten `run.sh`, so the run printed `UNJAILED-CODE-RAN` and created `<checkout>/escaped`, outside `.cache`, with no jail.

In the real flow, `lune run tests/run` in the copy runs the copy's `tests/run.luau` and `tests/lib/fence.luau` unjailed, because they build the jail. c0049's flow runs the copy's `scripts/check.sh` unjailed. A spec run earlier in the same `tracker.sh check c0058`, at AC1 to AC8, can leave a poller that waits for `chain.spec.luau` to appear and then keeps rewriting `tests/run.luau`. That code then runs with the person's keychain and network, and can `cd` to the real checkout and push. The same surviving process can also race `pickman_fence`'s sentinel between its `rm -f` and its `printf >`; F1's jail rule closes that one, since `.cache/.git` is a top-level name.

This is neither "a daemon" nor "`check.sh` files' own commands" as listed: the code is the spec's, and the `check.sh` only runs what it copied. These `check.sh` files are sequestered, so the fix can't be made in them.
Critique: the tempting fix is to kill the jailed child's process group after it exits. A spec escapes that with `setsid`, for example `perl -MPOSIX -e 'setsid; …'`. Holding the lock until a pipe inherited by every descendant closes also fails, because a deliberate spec can close the descriptor.
Consequences:
- **Best-effort reaping:** process group, plus an inherited pipe whose survivors keep the lock and fail the run with a message naming them. This handles accidental leftovers (a forgotten `&` or a test server) but not a deliberate spec.
- **What stays open:** a deliberate surviving process. It needs a person's decision: close it by other means (for example, under the jail a `check.sh` flow never runs code from `.cache` that existed while jailed processes could write it, which would need the sequestered c0058 and c0049 `check.sh` files changed, so escalate), or document it as review-only.
Recommendation: this goes to the person, and both parts are needed:
- **(a) Best effort, in `fence.enter()`:** start the jailed child as its own process-group leader, give it an inherited pipe, and after it exits kill the group. While the pipe still has a writer, keep the lock and fail the run with `a spec left processes running (pids …); a check must not leave background processes`. Spec case in `tests/tooling`: a spec that starts `sleep 30 &` makes the run fail, and no `sleep` survives. Mutant: the reaping removed is killed.
- **(b) Document what (a) can't catch:** add to "Caught only by review": "a process a spec leaves running past the run (detached with `setsid` or with its inherited descriptors closed): it stays jailed but can still write `.cache`, racing unjailed `check.sh` flows that copy code into `.cache` and run it (c0058's AC9 and AC10, c0049's gate copy)". Also qualify "Nothing a spec does can change the repository" in the Jail bullet.

No sequestered file is edited by either.

### F3 [low] The `mktemp` stub treats `-t`'s prefix as a template, so `mktemp -t name` still goes to the closed user temp folder and fails inside the jail
Where: `tests/lib/fence.luau:494` (`for a in "$@"; do case $a in -*) ;; *) exec /usr/bin/mktemp "$@" ;; esac; done`).
Evidence: `TMPDIR=<dir> mktemp -t foo` and `mktemp -d -t foo` both printed `/var/folders/…/T/foo.…`, because macOS `-t` ignores `TMPDIR`. The stub sees `foo` as a non-flag argument and passes the call straight through, so inside the jail it gets `Operation not permitted`. No spec uses `-t` today, so this fails loudly rather than silently, and it isn't a safety hole.
Recommendation: in the stub, handle `-t <prefix>` as `"$TMPDIR/<prefix>.XXXXXXXXXX"`. Add to the gate's jail case an assertion that `mktemp -t pickman` lands inside `TMPDIR`.

## Main question
Beyond c0058's review-only list (Linux, `check.sh` files' own commands, handing work to a process outside the jail), two paths remain on macOS:
- **F1 (deterministic, automatic):** a spec plants a symlink at a top-level name in `.cache`. Rojo in the next gate, or the tracker, then writes through it into the shared `.git` or a tracked file.
- **F2 (needs a surviving background process):** that process rewrites code an unjailed `check.sh` flow copies into `.cache` and then runs.

Closed and live-probed:
- direct writes to the checkout, the main checkout and `.git`;
- the `.cache` entry itself;
- home, `/tmp`, `/private/tmp` and the user temp folder;
- the folders above the checkout;
- hard links into `.cache`, which the sandbox denies;
- non-loopback IP, git's network transports and proxies.

The run temp folder is removed with `fs.removeDir`, which doesn't follow a symlink: a spec that replaces it with a link loses only the link (checked). On Linux CI there is no jail, as documented. `fence-cache-entry.spec` passes there too, because its runner case refuses before any write and reads `stat -c %y`. The new probes in `repo-fence.spec` run only in the macOS branch.

## Judged criteria (code mode only)
None: c0058, c0059 and c0060 have no Judged criteria.

Verdict: changes
