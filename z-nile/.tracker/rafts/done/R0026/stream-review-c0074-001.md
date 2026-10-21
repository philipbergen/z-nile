# Review 001: c0074 (stream mode)
Inputs: `git diff cb1d57f...ws-c0074` (merge-base with origin/R0026-guard-follow-ups); tracker/issues/active/c0074/c0074.md, check.sh, acceptance/done-gate.spec.luau (unchanged by the diff).

Checks run in the stream worktree:
- `scripts/tracker.sh check c0074`: 6/6 passed (AC1-AC6).
- `scripts/check.sh --affected` (selector said "infrastructure changed: running all specs"): selene 0 errors, 0 warnings, 0 parse errors; types and rojo build clean; 1280 passed, 1 failed, 180 spec files. The one failure is `tests/acceptance/f0013/bench.spec.luau :: 50 players x 60 s ... under 4 s` (4.84 s) while the gate's slowest specs ran 100-160 s, i.e. under heavy machine load. Re-run alone, the spec passes (2 passed, 0 failed). A wall-clock flake, unrelated to this diff (see F2).

Scope: the diff touches exactly main.luau, gate.luau (new), the tracker skill, repo-fence.spec.luau and c0074.md. Sequestered files (check.sh, acceptance/) are unchanged. No other files.

Design adherence, verified by reading:
- Order is promote, move members then raft, gate, ready, FOCUS_FILE removal and commit. `raft` is reassigned from `move`, so `recordAndCommit` writes spend.md into done/<id>.
- `doneGate` is pure (reads only the two keys); `PICKMAN_DONE_GATE` is read nowhere else under scripts/ (grep).
- Messages match the Design, including the c0008-pinned promoted message. Failed gh ready still rolls back, now through `rollback()`.
- Skill row states order, auto rollback, spec-run skip and the Ctrl-C recovery.
- ALLOWED entries are two narrow file-and-prefix entries with reasons; the gate.luau one only reads the variable.

### F1 [low] rollback's empty-folder cleanup ignores ignored files such as .DS_Store
Where: scripts/tracker/main.luau, `rollback()` in `cmd.done`
Evidence: `git mv <dir> <dest>` renames the whole directory, including untracked-but-ignored files (.gitignore has `.DS_Store`, `*.rbxl`). `git reset --hard HEAD` restores the tracked files into active/<id> but leaves the ignored file in done/<id>. `#fs.readDir(dir) == 0` is then false, done/<id> stays, and `store.find` sees a duplicate id, which breaks every tracker command (the failure the Design says must not happen).
Critique: only reachable when an item folder holds an ignored file (a Finder-created .DS_Store is the plausible case), and the tree must still be clean per `git status --porcelain`. The tempting fix is to delete done/<id> unconditionally.
Consequences: an unconditional delete could destroy tracked content if reset ever failed halfway. Safer is to remove a destination only when `git ls-files <dir>` is empty after the reset (nothing tracked there), then delete it recursively.
Recommendation: optional. Either accept and note the limit in the Design, or use the `git ls-files` emptiness test instead of `readDir`. A spec case would need an ignored file planted in the raft folder before a failing gate.

### F2 [low] wall-clock bench flaked under the gate's own load
Where: tests/acceptance/f0013/bench.spec.luau (not in the diff)
Evidence: 4.84 s against a 4 s limit during the all-specs run, passes alone.
Critique: not caused by c0074, but `done` now runs the full gate a second time per raft, so more chances to hit it. Mention to the lead; no change in this stream.
Consequences: none for this issue.
Recommendation: none here. Re-run the affected gate on a quiet machine before landing.

### F3 [low] a failing `move` in the new pre-gate loop leaves a half-moved tree with no rollback
Where: scripts/tracker/main.luau, the `for _, m in members do move(m, "done")` loop and `raft = move(raft, "done")`
Evidence: `sh.git({"mv", ...})` throws on failure (for example a destination that already exists). The moves used to run after the commit-bound steps; now a throw leaves promoted specs plus some moved folders uncommitted, with no `rollback()`.
Critique: previously a throw there was equally unrolled, but the window is now before the gate and ready call. The tracker skill recovery (`git reset --hard HEAD`) covers it.
Consequences: wrapping in pcall and calling `rollback()` is cheap, but needs a message and a case.
Recommendation: optional; fine to leave since the documented recovery applies.

No high or medium findings.

Verdict: approve
