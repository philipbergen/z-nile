# Review: R0210 round-6 and post-done fixes, c0840 (code mode)
Inputs: merge 116646a (R0210, PR #49) against the last reviewed head a7922db: `git diff a7922db 116646a -- scripts/check.sh scripts/deploy-beta.luau scripts/lib tests/lib tests/tooling`, plus the `sh.writeReplacing` call sites in `scripts/tracker/main.luau`. Context: review-001 to 006, refute-006, the review skill and the testing skill ("Specs never touch the real repository"). Worktree `.worktree/capture-r0210-leftovers` at e31b51f.
Runs, one at a time, outside any sandbox: `lune run tests/run -- tests/tooling/fence-cache-entry.spec.luau` gave 7 passed, 0 failed. `luau-lsp analyze --platform=standard tests/lib/fence.luau` printed no FormatString warning. Scratch experiments ran only in my own folder under `$TMPDIR`, which I have since removed. No full gate ran, nothing printed `REPOSITORY CHANGED`, `git status` stayed clean, and no process I started is still running.
One experiment was not run. A probe spec in a scratch clone would have shown that a jailed spec can stop the runner's top process. The permission system declined it, so that route is reasoned from the profile below, not observed.

### F1 [high] A symlink to a directory at the top of `.cache` still gets every converted writer to write into the folder it points at, and the post-run unlink can be skipped. So "a symlink at the top of `.cache` is never written through" does not hold
Where:
- `scripts/lib/sh.luau` `sh.writeReplacing` (`mv -f tmp path`);
- `scripts/check.sh:36-41` (`mv -f "$t" "$defs"`, and `build_place`'s `mv -f "$d/check.rbxl" .cache/check.rbxl`);
- `tests/lib/fence.luau` `fence.enter()` (the post-run unlink loop runs in the top Lune process, after `process.exec("perl", …)` returns);
- `profile()` (`(allow default)`, with no `signal` rule).

Evidence:
- **`mv -f` follows a directory link.** `mv -f SRC DEST` treats a DEST that is a symlink to a directory as the target directory and moves SRC *into* it. I checked this on macOS in scratch: `mv -f f c/link` with `c/link -> victim/` left the link in place and created `victim/f`. BSD `mv -h` and GNU `mv -T` turn this off, but neither is used.
- **The tracker writer does the same.** In scratch, with `.cache/tracker-focus -> <victim dir>`, `sh.writeReplacing(".cache/tracker-focus", "c0840")` returned normally. It created `<victim>/tmp.QDOoflAnsq` (mode 0600, content `c0840`) and left the link in place. `build_place` would drop `check.rbxl` into the folder the same way, and the defs download a `tmp.*` file.
- **What that does to the shared git folder.** Pointed at the shared `.git/refs/heads`, this leaves a file the tripwire does not look at. In a scratch repository, files dropped there made every later `git branch` and `git for-each-ref` print `warning: ignoring broken ref refs/heads/check.rbxl`.
- **The spec does not catch it.** The new spec case in `fence-cache-entry.spec` links to a *file* (`victim-d`), so it passes with this behaviour.
- **The post-run unlink can be skipped.** It is the main fix, but it runs only if the top Lune survives until the launcher returns. Lune has no signal handler: in scratch, `kill -INT` stopped a `lune run` blocked in `process.exec` with code 130, and nothing after the call ran. So:
  - Ctrl-C reaches the terminal's foreground group (top Lune and launcher). Lune dies at once, and the launcher forwards INT to the specs. That skips the unlink, the second snapshot and the lock removal.
  - A TERM sent only to the top process (a caller's timeout) does the same.
  - The jail's profile is `(allow default)` with no `signal` rule, so nothing stops a jailed spec from signalling the runner's own unjailed processes. I reasoned this route from the profile; it was not run.
- **Result.** A directory link swapped in during an interrupted run is still there when the next `scripts/check.sh` (the Stop hook included) reaches `build_place`. The next `tests/run` start-of-run unlink comes too late, because `check.sh` builds before its tests stage.

Critique: there are two tempting fixes:
- Add `-h` to every `mv`. That is BSD-only: GNU `mv` on Linux CI rejects it.
- Only move the unlink earlier in `check.sh`. That leaves the tracker writers, and any later writer, depending on cleanup that a signal can skip.

Consequences: the writers' guarantee has to hold on its own, whatever is at the path, and must work on both macOS and Linux:
- A rename into place must use `rename(2)` itself, which replaces a link of any kind and fails on a real directory (`EISDIR`/`ENOTDIR`) instead of moving into it.
- `rename(2)` fails across filesystems, so the temporary file has to be a sibling in the same folder, created exclusively (a random name, `O_EXCL`). Leftover siblings after a crash then appear in `.cache`, so they need a recognisable prefix that the snapshot ignores and the next writer may delete.
- `board --out` takes user paths. With `rename(2)`, `--out some/dir/` becomes an error rather than a silent `some/dir/tmp.*`, and the 0600 mode from `mktemp` should be widened to the old 0644.

Moving the post-run unlink into the Perl launcher (which outlives the top Lune and already handles INT/TERM/HUP) closes the interrupted-run gap for those signals, but not a SIGKILL of the launcher.

Recommendation:
- **Writers.**
  - Make `sh.writeReplacing` create `<dir>/.<name>.tmp.<random>` exclusively, write it, `chmod 0644`, and `fs.move` it onto the path (Lune's move is a `rename`).
  - Give `check.sh` a small helper with the same rule (`perl -e 'rename $ARGV[0], $ARGV[1] or die'`; perl is already required) for the defs file and `check.rbxl`, and build into a sibling under `.cache` rather than `mktemp -d`.
- **Cleanup.**
  - Do the top-of-`.cache` unlink in the launcher after `kill 'KILL', -$pid` as well as in Lune.
  - Run the same unlink at the top of `scripts/check.sh`, before `build_place`.
- **Signals.** Consider `(deny signal (target others))` with `(allow signal (target pgrp))` / `(target children)` in the profile, and check it against the specs that signal processes they started (the lock spec, `fence-leftovers.spec`) before adopting it.
- **Spec cases** (`fence-cache-entry.spec`): `writeReplacing` over a link *to a directory* leaves the directory's listing unchanged and the path a regular file (mutant: plain `mv -f`). It must also fail, without writing anything, when the path is a real directory.

### F2 [medium] If the watchdog's `fork` fails, the specs never start and the run hangs while holding the lock
Where: `tests/lib/fence.luau` `REAPER`: `"if (!fork) { open STDIN … while (kill 0, $launcher) { sleep 1 } … exit }"`.
Evidence: Perl's `fork` returns `undef` on failure (EAGAIN at the per-user process limit, which parallel agents and gates can reach). `!undef` is true, so the *child itself* runs the watchdog branch instead of falling through to `exec`:
- it points its stdio at /dev/null;
- it loops while the launcher lives;
- it never runs the specs.

The launcher waits in `waitpid($pid, 0)` for that child, so the run hangs with no output. The lock stays held by live processes, so every later run in the checkout waits 240 s and gives up, until someone kills it by hand. The outer fork checks `defined`; the inner one does not.
Critique: the obvious fix is `defined(my $w = fork) or die`.
Consequences: a `die` in the child after `setpgrp` exits it with 255 before `exec`. The launcher reports 255, and the run fails with `fork: Resource temporarily unavailable` on stderr, which is the wanted behaviour. The watchdog's parent is then gone, but there are no specs to reap.
Recommendation:
- Write `my $w = fork; die "fork: $!" unless defined $w; if (!$w) { … }`.
- In the same edit, have the watchdog ignore INT, TERM and HUP. Today the launcher's forwarded signals kill it first, and with it the review-006 F2 protection for the rest of the run.
- Also prefer the pipe-EOF design review-006 asked for over `kill 0, $launcher` polling. A pid probe can be fooled by a reused pid. If `getppid` already returned 1 and the run is as root (some containers), the watchdog never fires.
- c0850's watchdog spec should include the fork-failure case if it can be forced cheaply (for example `ulimit -u` in a subshell that runs only the launcher); otherwise record it as reasoned.

### F3 [medium] The outer-sandbox link probe treats any `ln` failure as "refused", so an existing file at its predictable name passes a sandbox that allows top-level links
Where: `tests/lib/fence.luau` `jail()`: `linkProbe = {cache}/pickman-link-probe-{myPid()}` and `if process.exec("ln", { "-s", "/nonexistent", linkProbe }).ok then`.
Evidence: `ln -s` fails with `File exists` when that name is already a regular file. The start-of-run cleanup removes only *symlinks*, and jailed specs may create regular files at the top of `.cache`. So a file left at `pickman-link-probe-<pid>` makes the probe report that links are refused, and the run accepts the outer sandbox. Other probes in this file already compare the error text (the network probe requires `Operation not permitted`); this one does not.
Critique: the tempting fix is `ln -sf`.
Consequences: `-f` unlinks whatever is there, which is fine at the top of `.cache`. But a *directory* at that name still makes `ln -s` create the link inside it and report success. That case fails closed today (counted as a leak), and must stay that way.
Recommendation:
- Make the probe name unpredictable (`mktemp -u` in `.cache`, or pid plus random).
- Count the probe as refused only if `ln` failed with `Operation not permitted`. Any other failure refuses the run with its own message.
- Spec case (unit level, on `jail`'s probe helper if it is factored out): a regular file at the probe name does not turn a permitted link into "refused".

### F4 [low] `check.sh` now goes on silently when the type-definitions download fails, and leaks the temporary file
Where: `scripts/check.sh:35-38`.
Evidence: `curl … -o "$t" … && mv -f "$t" "$defs"` sits inside an `if` body under `set -euo pipefail`. A failure in a non-final `&&` element does not trigger errexit. I checked in scratch: the script continued, and the `mktemp` file was left behind. Before the change, a failing `curl -o "$defs"` ended the gate right there. Now the gate goes on to the src type stage with no (or a stale, linked) definitions file, and fails there with a less direct message. Each failed download also leaves a temporary file behind. `build_place` likewise leaves an empty `mktemp -d` folder in the user temp folder on every gate.
Recommendation: `curl … -o "$t" || { rm -f "$t"; echo "could not download …" >&2; exit 1; }`, then the rename (see F1 for which rename). Remove the build folder after the move, or build into a sibling under `.cache` as F1 suggests.

### F5 [low] The testing skill still does not describe the round-5 and round-6 mechanisms
Where: `.claude/skills/testing/SKILL.md`, "Jail (macOS)" and "Caught only by review".
Evidence: the merge changes no line of the testing skill. The Jail bullet still doesn't say:
- that links can't be created at the top of `.cache`;
- that the runner unlinks any found there before and after a run;
- that unjailed writers there rename into place;
- that a watchdog stops the specs if the launcher dies.

It still says "Nothing a spec does can change the repository" without qualification, and "Caught only by review" does not mention a spec that signals the runner's own processes (F1). Review-006 F1 asked for these edits.
Recommendation: make the review-006 F1 skill edits, add F1's signal route to "Caught only by review" (or to the Jail bullet if the signal rule is adopted), and name the rename rule for writers at the top of `.cache` so future writers follow it.

## Items checked without findings
- **Escape pattern in `profile`.** The old and new patterns give identical output for a path holding every special character (checked in scratch), and luau-lsp no longer warns.
- **`fence.sh` sentinel.** A link is unlinked, a folder refused, a fresh `mktemp` file in `.cache` is renamed onto a name already checked to be neither. Only a running survivor could race it, which is review-only.
- **`deploy-beta.luau`.** It builds into a fresh temp folder (`sh.must` trims the path). This is fine, though the place file is left behind; that is harmless on CI.
- **Watchdog stdio.** It reopens 0, 1 and 2 on /dev/null, so it holds no caller pipe open.
- **Fork, setpgrp and signals in the launcher.** The child calls `setpgrp` before forking the watchdog, so the watchdog is always in the specs' group. If the launcher dies before the handlers are installed, the watchdog fires (as non-root). Exit-code mapping is unchanged.
- **`repo-fence.spec` `gh-none` split.** It asserts the same value. Splitting the string to stay out of c0470's literal-folder scan follows that spec's own concatenation idiom. `gh-none` is the fence's folder, not a fixture, so no fixture sharing is hidden.
- **Watchdog spec.** It has none, but c0850 tracks that, so it is not repeated here.

## Judged criteria (code mode only)
None: c0840 has no Judged criteria.

Verdict: changes
