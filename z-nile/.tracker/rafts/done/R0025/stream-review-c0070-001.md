# Review 001: c0070 (stream mode)
Inputs: `git diff R0025-ready-raft...ws-c0070` (main.luau, tracker and execute-raft skills, c0081 publish-guard spec, c0070.md); `scripts/tracker.sh check c0070` run in the stream worktree: 5/5. The diff stays inside c0070's Touched modules plus its own doc (the c0081 spec is in Touched modules and the Override is recorded). No other file is touched.

Checked and found sound (no finding): every `publish.commit` site (moveOnOrigin for ready/stop, reserveOnOrigin, new issue, new raft, setStatus, start, remap) is wrapped in `published(`; each non-remap site still has `refuseStale()` on the line right before the publish, as `publishFresh` ran it, and remap has none, as before. Removing `publishFresh` changed no message or order. `refreshBoard`: ff-only merge only on `main`, a failed merge (dirty overlap or diverged) only warns and skips `sweepStale`, the sweep runs only after a successful fast-forward, the board is built by the main checkout's `tracker.sh board -O` (tracker.sh `cd`s to its root, so never the worktree's `.cache`, never a browser), no refresh when `sha` is nil (`publish` returns no sha for a no-op) and none when `PICKMAN_PUBLISH=0` or with no origin. `sync` rebuilds only in the main checkout. Skills: Landing step 4 uses `"<root>/scripts/tracker.sh" sync`, all board-row tokens are present, none of the 13 banned phrases appears, no skill says `git -C <root> pull --ff-only`.

### F1 [medium] The rewritten c0081 guard no longer pins `refuseStale()` to each publish site
Where: tests/acceptance/c0081/publish-guard.spec.luau, `mentions` and case "main.luau refuses a stale tree before every publish.commit but remap's"
Evidence: `refused` becomes true at any earlier line of the same top-level function. `cmd.new` (two publishes) and `cmd.start` also call `refuseStale()` near their top (before the `if`), so deleting the per-site `refuseStale()` directly before `published(publish.commit(` in either leaves the case green. The old case made that impossible, since every publish went through `publishFresh`. A `refuseStale()` inside a dead or unrelated branch would pass too.
Critique: the Override keeps c0081's intent for functions with one publish (a dropped call in setStatus, reserveOnOrigin or moveOnOrigin goes red), but the intent is only half kept for the multi-publish functions. The tempting fix is a bare "line before" rule.
Consequences: every current site has `refuseStale()` as the previous code line, so a "previous non-blank, non-comment line is `refuseStale()`" rule passes today; a future site that computes something between the two would then fail and need a comment or a reorder (acceptable, and the right nudge). The finder-sanity sample needs a case with an earlier `refuseStale()` followed by an unrelated line then a publish, expected `refused = false`.
Recommendation: track `refused` as "the previous code line contained `refuseStale()`" and add that sanity case. This is an edit to a promoted spec, so it needs the user's okay under the existing Override, or record it as accepted risk in the Override text.

### F2 [medium] The 20% fallback evidence is within rounding of the threshold
Where: c0070.md, Verification log, 2026-10-05 Timing
Evidence: "before 32 s, after 38 s and 38 s (about +19%)": one before sample, whole-second resolution. 32 to 38 is +18.75%, and the rounding range is roughly +15% to +22%. The gate's own `slowest:` line says 55.2 s against the raft baseline 44.7 s, which is +23.5%, explained only as machine load.
Critique: the rule is "more than 20%: apply the fallback". The record can't show it is under 20%. The tempting fix is another single run.
Consequences: if the fallback is needed it edits `scripts/tracker/board.luau` and `main.luau` (in-process `board.build(root)`), which the stream has not done and which would change `refreshBoard` and `sync`'s step 4.
Recommendation: before merge, record at least three alternating before/after runs of c0053 commands.spec on a quiet machine (or the median, with sub-second timing), and apply the fallback if the median is above +20%.

### F3 [low] No spec case for a dirty main checkout
Where: acceptance/board-refresh.spec.luau
Evidence: the only failure case is a main checkout on another branch. Nothing shows that `merge --ff-only` with a dirty overlapping tracked file fails and only warns, leaves the file untouched, skips `sweepStale` and still succeeds. By reading, the code does this (the merge refuses, `m.ok` is false, one warning), and the sequestered spec can't be edited now.
Critique: untested guard on the "never touch uncommitted work" rule. A mutant using `git merge` with `-X theirs` or `reset --hard` would pass.
Consequences: none for the stream; the spec is sequestered.
Recommendation: note it for the raft review, or add the case in a follow-up chore.

### F4 [low] Leftover `pull --ff-only` advice and a detached-HEAD message
Where: scripts/tracker/main.luau:1886 (`cmd.worktree`) and `refreshBoard`
Evidence: the message `run git -C {mainRoot()} pull --ff-only` still tells the user to bypass `sync`, so the board stays stale; AC5 scans only skills so it passes. In a detached HEAD, `branch --show-current` is empty and the warning reads "is on , not main".
Critique: cosmetic, but it contradicts the new Landing step 4 rule.
Consequences: changing the message at 1886 is a wording change that a promoted spec may pin; grep before editing.
Recommendation: say `{mainRoot()}/scripts/tracker.sh sync` in that message (if no spec pins the old text), and print `(detached)` for an empty branch.

Verdict: changes
