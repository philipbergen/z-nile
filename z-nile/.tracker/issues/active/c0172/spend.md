# Spend: c0172 Local ci only

| # | when | commit | +lines | -lines | minutes | attribution | phase | tokens |
|---|---|---|---|---|---|---|---|---|
| 1 | 2026-10-28 05:57 | design-review-001 | 0 | 0 | 20.0 | spend | design-review |  |
| 2 | 2026-10-28 05:57 | design-refute-001 | 0 | 0 | 30.0 | spend | design-review |  |
| 3 | 2026-10-28 06:35 | design-review-002 | 0 | 0 | 20.0 | spend | design-review |  |
| 4 | 2026-10-29 03:22 | design-review-003 | 0 | 0 | 30.0 | spend | design-review |  |
| 5 | 2026-10-29 03:22 | design-refute-003 | 0 | 0 | 40.0 | spend | design-review |  |
| 6 | 2026-10-29 03:48 | design-review-004 | 0 | 0 | 20.0 | spend | design-review |  |
| 7 | 2026-10-29 03:48 | design-refute-004 | 0 | 0 | 25.0 | spend | design-review |  |
| 8 | 2026-10-29 04:08 | design-review-005 | 0 | 0 | 18.0 | spend | design-review |  |
| 9 | 2026-10-29 04:08 | design-refute-005 | 0 | 0 | 10.0 | spend | design-review |  |
| 10 | 2026-10-29 04:52 | design, acceptance specs, and the cicd prototype; design-review minutes already recorded | 1037 | 1 | 180.0 | spend | prep |  |
| 11 | 2026-10-29 05:44 | c0172: verify on the merging machine and let Actions only deploy  A merge runs the local full gate in a clone outside the repo, then lune run scripts/cicd. GitHub Actions publishes a ready pull request and is not read. | 1015 | 898 | 25.0 | focus | build |  |
| 12 | 2026-10-29 05:50 | c0172: record the promote-check stop  The sequestered cicd spec does not type-check once promoted, so the raft check cannot pass and execution stops. | 0 | 0 | 10.0 | focus | build |  |

**Total:** +2052 / -899 lines, 428.0 agent-minutes, 0 tokens over 12 records
<!-- totals: added=2052 removed=899 minutes=428.0 records=12 tokens=0 -->
