# Spend: c0068 Stop raft

| # | when | commit | +lines | -lines | minutes | attribution |
|---|---|---|---|---|---|---|
| 1 | 2026-10-06 04:02 | R0025: experiments | 0 | 0 | 2.5 | raft+proportional |
| 2 | 2026-10-06 05:34 | R0025: addressed during execution | 0 | 0 | 0.2 | raft+proportional |
| 3 | 2026-10-06 05:42 | R0025: record the sequestered-fix rule | 0 | 0 | 0.1 | raft+proportional |
| 4 | 2026-10-06 05:50 | c0068: tracker.sh stop, status refuses readied items, stop-raft skill | 200 | 74 | 35.0 | explicit |
| 5 | 2026-10-06 14:53 | Merge origin/main (R0026, R0033 and preps) into R0025 | 522 | 20 | 1.1 | raft+proportional |
| 6 | 2026-10-06 15:01 | R0025: promote-check fixes (spec type correction, cleanup return type, c0077 reviewed .cache lines) | 0 | 0 | 0.7 | raft+proportional |
| 7 | 2026-10-06 15:24 | R0025: review 001 fixes (membership agreement, CI raft branch, PR reuse, wording, guard pin, design-round rule) | 69 | 4 | 14.9 | explicit |
| 8 | 2026-10-06 15:30 | R0025: refute-001 | 0 | 0 | 0.6 | raft+proportional |
| 9 | 2026-10-06 15:41 | R0025: review 002 fixes (one member set for every move; ready-members spec both directions) | 73 | 28 | 17.4 | explicit |
| 10 | 2026-10-06 15:47 | R0025: refute-002 | 0 | 0 | 0.3 | raft+proportional |
| 11 | 2026-10-06 15:59 | R0025: review 003 fixes (stop gives back by claim stamp; specs for late members, raft: drift and PR reuse) | 83 | 25 | 17.5 | explicit |
| 12 | 2026-10-06 16:03 | R0025: format | 0 | 1 | 0.1 | raft+proportional |
| 13 | 2026-10-06 16:09 | R0025: refute-003 | 0 | 0 | 0.3 | raft+proportional |
| 14 | 2026-10-06 16:18 | R0025: review 004 fixes (unique claim stamps, resumed start keeps its claim, no-stamp refusal pinned; stop looks up after its pull) | 47 | 5 | 15.2 | explicit |
| 15 | 2026-10-06 16:24 | R0025: refute-004 | 0 | 0 | 0.3 | raft+proportional |
| 16 | 2026-10-06 16:33 | R0025: review 005 fixes (claims.taken with a real git grep and strict exit codes; resumed start reuses its claim only while origin carries it) | 63 | 2 | 15.0 | explicit |
| 17 | 2026-10-06 16:39 | R0025: refute-005 | 0 | 0 | 0.3 | raft+proportional |
| 18 | 2026-10-06 16:56 | R0025: final verification log entries | 0 | 0 | 0.6 | raft+proportional |

**Total:** +1057 / -159 lines, 122.1 agent-minutes over 18 commits
<!-- totals: added=1057 removed=159 minutes=122.1 commits=18 -->
