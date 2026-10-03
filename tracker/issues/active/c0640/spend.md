# Spend: c0640 Checks never touch the real repository

| # | when | commit | +lines | -lines | minutes | attribution |
|---|---|---|---|---|---|---|
| 1 | 2026-10-03 07:36 | c0640: bring in the repository guards (fence.sh, git hooks, ac.sh, fence.luau and its runner call, gate spec, overrides, rule in AGENTS.md and the skills) | 1140 | 43 | 20.0 | focus |
| 2 | 2026-10-03 07:38 | R0210: experiments (E30 on the landed c0510 code) | 0 | 0 | 5.0 | focus |
| 3 | 2026-10-03 08:26 | R0210: case lookups in c0640/c0660 check.sh ignore line breaks (user-approved fix of sequestered checks) | 0 | 0 | 5.0 | focus |
| 4 | 2026-10-03 08:27 | c0640: verification log | 0 | 0 | 2.0 | focus |
| 5 | 2026-10-03 16:36 | R0210: review 001 fixes (jail denies IP networking and every ancestor; scan bans network/credential overrides and reads env identities; helper refuses core.worktree and env config; outer guard must exist) | 174 | 9 | 45.0 | explicit |
| 6 | 2026-10-03 16:38 | c0640: testing skill states the stronger jail and scan; verification log | 2 | 2 | 5.0 | focus |
| 7 | 2026-10-03 16:39 | R0210: refute-001 | 0 | 0 | 5.0 | focus |
| 8 | 2026-10-03 16:56 | R0210: review 002 fixes (jail writes only .cache and the temp folder, loopback open, no proxies; outer sandboxes must prove home, folders and network closed; GIT_ALLOW_PROTOCOL pinned; sentinel rewritten; identities read in any case) | 140 | 63 | 50.0 | explicit |
| 9 | 2026-10-03 16:59 | c0640: testing skill states the write allowlist; verification log | 1 | 1 | 5.0 | focus |
| 10 | 2026-10-03 17:00 | R0210: refute-002 | 0 | 0 | 5.0 | focus |
| 11 | 2026-10-03 21:48 | R0210: jail writes only .cache and the user temp mktemp uses (no shared /tmp, TMPDIR inside .cache); sentinel replaces a directory too (review 003, user's choice) | 31 | 18 | 25.0 | explicit |
| 12 | 2026-10-03 21:51 | c0640: testing skill and verification log for the narrowed temp folder | 1 | 1 | 3.0 | focus |

**Total:** +1489 / -137 lines, 175.0 agent-minutes over 12 commits
<!-- totals: added=1489 removed=137 minutes=175.0 commits=12 -->
