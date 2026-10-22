# Spend: c0127 Test lock pid reuse

| # | when | commit | +lines | -lines | minutes | attribution | phase | tokens |
|---|---|---|---|---|---|---|---|---|
| 1 | 2026-10-22 04:49 | design-review-001 | 0 | 0 | 6.0 | spend | design-review | 109432 |
| 2 | 2026-10-22 04:56 | design-refute-001 | 0 | 0 | 40.0 | spend | design-review |  |
| 3 | 2026-10-22 05:04 | design-review-002 | 0 | 0 | 6.0 | spend | design-review | 113885 |
| 4 | 2026-10-22 05:14 | design-refute-002 | 0 | 0 | 30.0 | spend | design-review |  |
| 5 | 2026-10-22 05:23 | design-review-003 | 0 | 0 | 8.0 | spend | design-review | 120000 |
| 6 | 2026-10-22 05:23 | design-review-003 | 0 | 0 | 0.0 | spend | design-review | 14364 |
| 7 | 2026-10-22 18:06 | design-refute-003 | 0 | 0 | 55.0 | spend | design-review |  |
| 8 | 2026-10-22 18:14 | design-review-004 | 0 | 0 | 7.0 | spend | design-review | 120272 |
| 9 | 2026-10-22 18:34 | design-refute-004 | 0 | 0 | 45.0 | spend | design-review |  |
| 10 | 2026-10-22 18:58 | design-review-005 | 0 | 0 | 30.0 | spend | design-review | 120000 |
| 11 | 2026-10-22 19:24 | design-refute-005 | 0 | 0 | 40.0 | spend | design-review |  |
| 12 | 2026-10-22 19:30 | prep | 519 | 1 | 120.0 | spend | prep |  |
| 13 | 2026-10-22 20:20 | c0127: a reused pid no longer holds the test lock (start ids recorded with each pid) | 140 | 16 | 20.0 | focus | build |  |
| 14 | 2026-10-22 20:38 | c0127: verification log | 0 | 0 | 2.0 | explicit | build |  |
| 15 | 2026-10-22 20:54 | c0127: verification log (exit criteria) | 0 | 0 | 3.0 | explicit | build |  |
| 16 | 2026-10-22 21:01 | R0047: review-001 | 0 | 0 | 30.0 | focus | code-review |  |
| 17 | 2026-10-22 21:04 | R0047: review-001 F1 F2: read own start id once before waiting; lock-start-ids spec | 245 | 17 | 35.0 | explicit | code-review |  |
| 18 | 2026-10-22 21:05 | R0047: refute-001 | 0 | 0 | 5.0 | focus | code-review |  |
| 19 | 2026-10-22 21:10 | R0047: review-002 | 0 | 0 | 3.0 | focus | code-review |  |
| 20 | 2026-10-22 21:11 | R0047: review-002 F1 F2: no subprocess in writeWhole; fixture identity | 15 | 7 | 6.0 | explicit | code-review |  |
| 21 | 2026-10-22 21:11 | R0047: refute-002 | 2 | 0 | 3.0 | focus | code-review |  |
| 22 | 2026-10-22 21:11 | R0047: final verification log | 0 | 0 | 0.2 | explicit | deliver |  |
| 23 | 2026-10-22 21:43 | tracker: done R0047 | 0 | 0 | 6.6 | raft+proportional | deliver |  |

**Total:** +921 / -41 lines, 500.8 agent-minutes, 597953 tokens over 23 records
<!-- totals: added=921 removed=41 minutes=500.8 records=23 tokens=597953 -->
