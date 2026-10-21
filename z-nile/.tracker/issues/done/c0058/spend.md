# Spend: c0058 Checks never touch the real repository

| # | when | commit | +lines | -lines | minutes | attribution |
|---|---|---|---|---|---|---|
| 1 | 2026-10-03 07:36 | c0058: bring in the repository guards (fence.sh, git hooks, ac.sh, fence.luau and its runner call, gate spec, overrides, rule in AGENTS.md and the skills) | 1140 | 43 | 20.0 | focus |
| 2 | 2026-10-03 07:38 | R0021: experiments (E30 on the landed c0053 code) | 0 | 0 | 5.0 | focus |
| 3 | 2026-10-03 08:26 | R0021: case lookups in c0058/c0060 check.sh ignore line breaks (user-approved fix of sequestered checks) | 0 | 0 | 5.0 | focus |
| 4 | 2026-10-03 08:27 | c0058: verification log | 0 | 0 | 2.0 | focus |
| 5 | 2026-10-03 16:36 | R0021: review 001 fixes (jail denies IP networking and every ancestor; scan bans network/credential overrides and reads env identities; helper refuses core.worktree and env config; outer guard must exist) | 174 | 9 | 45.0 | explicit |
| 6 | 2026-10-03 16:38 | c0058: testing skill states the stronger jail and scan; verification log | 2 | 2 | 5.0 | focus |
| 7 | 2026-10-03 16:39 | R0021: refute-001 | 0 | 0 | 5.0 | focus |
| 8 | 2026-10-03 16:56 | R0021: review 002 fixes (jail writes only .cache and the temp folder, loopback open, no proxies; outer sandboxes must prove home, folders and network closed; GIT_ALLOW_PROTOCOL pinned; sentinel rewritten; identities read in any case) | 140 | 63 | 50.0 | explicit |
| 9 | 2026-10-03 16:59 | c0058: testing skill states the write allowlist; verification log | 1 | 1 | 5.0 | focus |
| 10 | 2026-10-03 17:00 | R0021: refute-002 | 0 | 0 | 5.0 | focus |
| 11 | 2026-10-03 21:48 | R0021: jail writes only .cache and the user temp mktemp uses (no shared /tmp, TMPDIR inside .cache); sentinel replaces a directory too (review 003, user's choice) | 31 | 18 | 25.0 | explicit |
| 12 | 2026-10-03 21:51 | c0058: testing skill and verification log for the narrowed temp folder | 1 | 1 | 3.0 | focus |
| 13 | 2026-10-03 21:52 | R0021: refute-003 | 0 | 0 | 3.0 | focus |
| 14 | 2026-10-03 22:13 | R0021: review 004 fixes (no recursive deletes, .cache must be a plain folder and is unchangeable in the jail; run-private temp folder with a mktemp stub instead of the user temp folder) | 204 | 27 | 45.0 | explicit |
| 15 | 2026-10-03 22:14 | R0021: refute-004 | 0 | 0 | 5.0 | focus |
| 16 | 2026-10-03 22:27 | R0021: review 005 F1/F3 (jail forbids symlinks at the top of .cache, leftovers unlinked; mktemp stub honours -t) | 26 | 2 | 20.0 | explicit |
| 17 | 2026-10-03 23:36 | R0021: review 005 F2 (specs run in their own process group, reaped when they end; setsid listed as review-only); verification log | 133 | 1 | 40.0 | explicit |
| 18 | 2026-10-03 23:36 | R0021: refute-005 | 0 | 0 | 5.0 | focus |
| 19 | 2026-10-04 06:59 | R0021: review 006 fixes (top-of-.cache writers rename into place; post-run link cleanup; outer sandboxes must refuse links; watchdog kills the specs' group if the launcher dies; luau-lsp pattern) | 65 | 13 | 45.0 | explicit |
| 20 | 2026-10-04 06:59 | R0021: refute-006 | 0 | 0 | 5.0 | focus |
| 21 | 2026-10-04 07:00 | R0021: merge origin/main (R0019, R0025 prep, game specs) | 0 | 0 | 2.0 | focus |
| 22 | 2026-10-04 07:08 | tracker: done R0021 | 0 | 0 | 2.8 | raft+proportional |

**Total:** +1917 / -180 lines, 347.8 agent-minutes over 22 commits
<!-- totals: added=1917 removed=180 minutes=347.8 commits=22 -->
