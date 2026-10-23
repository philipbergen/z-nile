# Spend: c0076 The jail sweeps every process a run leaves behind

| # | when | commit | +lines | -lines | minutes | attribution |
|---|---|---|---|---|---|---|
| 1 | 2026-10-06 04:08 | R0026: experiments | 0 | 0 | 0.8 | raft+proportional |
| 2 | 2026-10-06 04:20 | c0076, c0078: the jail's sweeper, the signal rule, fence.alive and fence.linkProbe | 54 | 5 | 25.0 | explicit |
| 3 | 2026-10-06 05:40 | R0026 review 001 F1, F3, F4, F5: sweeper interlock only where a jail is proven, fence.alive in an outer sandbox, skill text | 57 | 6 | 14.2 | explicit |
| 4 | 2026-10-06 05:59 | R0026 review 002 F1-F3: record the AC2 refinement (user's decision), update c0076/c0077 docs, interlock cases check their own refusal | 6 | 2 | 7.5 | explicit |
| 5 | 2026-10-06 14:07 | tracker: done R0026 | 0 | 0 | 0.6 | raft+proportional |

**Total:** +117 / -13 lines, 48.1 agent-minutes over 5 commits
<!-- totals: added=117 removed=13 minutes=48.1 commits=5 -->
