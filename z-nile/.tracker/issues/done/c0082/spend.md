# Spend: c0082 Tracker integrity audit

| # | when | commit | +lines | -lines | minutes | attribution |
|---|---|---|---|---|---|---|
| 1 | 2026-10-05 14:58 | R0027: ids, audit, allocation from tracker/next, compact, remap, list and renumber <dir>, skills

Implemented from prep's prototype (c0081 experiments/prototype.diff), plus the
round-4 skill text it predates: the ORIG_HEAD way back from a plain merge, and
the counter-only commits in Published or carried. | 417 | 24 | 9.8 | raft+proportional |
| 2 | 2026-10-05 15:01 | R0027: tracker/next at 901/271 (c0084 landed since prep); verification logs | 0 | 0 | 2.5 | raft+proportional |
| 3 | 2026-10-05 15:18 | R0027: review 001 fixes (remap once after a conflicting merge, scratch cleanup, templates untouched, usage, duplicate hint, space and level unions) | 101 | 13 | 10.1 | raft+proportional |
| 4 | 2026-10-05 15:18 | R0027: refute-001 | 0 | 0 | 1.5 | raft+proportional |
| 5 | 2026-10-05 15:18 | R0027: final counter after merging origin/main; addressed during execution | 0 | 0 | 1.5 | raft+proportional |
| 6 | 2026-10-05 15:20 | tracker: done R0027 | 0 | 0 | 1.2 | raft+proportional |

**Total:** +518 / -37 lines, 26.6 agent-minutes over 6 commits
<!-- totals: added=518 removed=37 minutes=26.6 commits=6 -->
