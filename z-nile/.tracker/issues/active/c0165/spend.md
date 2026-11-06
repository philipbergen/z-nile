# Spend: c0165 Reuse passed test results

| # | when | commit | +lines | -lines | minutes | attribution | phase | tokens |
|---|---|---|---|---|---|---|---|---|
| 1 | 2026-10-27 02:45 | capture | 0 | 0 | 25.0 | spend | capture |  |
| 2 | 2026-10-27 05:58 | design-review-001 | 0 | 0 | 16.0 | spend | design-review | 215539 |
| 3 | 2026-10-27 13:32 | design-refute-001 | 0 | 0 | 60.0 | spend | design-review |  |
| 4 | 2026-10-27 14:20 | design-review-002 | 0 | 0 | 20.0 | spend | design-review | 275682 |
| 5 | 2026-10-27 14:37 | design-refute-002 | 0 | 0 | 75.0 | spend | design-review |  |
| 6 | 2026-10-31 21:11 | design-refute-003 | 0 | 0 | 83.0 | spend | design-review |  |
| 7 | 2026-10-31 21:25 | design-review-004 | 0 | 0 | 11.0 | spend | design-review | 5977644 |
| 8 | 2026-11-03 23:53 | design-review-005 | 0 | 0 | 7.0 | spend | design-review | 150000 |
| 9 | 2026-11-03 23:53 | design-refute-004 | 0 | 0 | 25.0 | spend | design-review |  |
| 10 | 2026-11-04 00:25 | design-refute-005 | 0 | 0 | 20.0 | spend | design-review |  |
| 11 | 2026-11-04 00:36 | design-review-006 | 0 | 0 | 5.0 | spend | design-review | 162000 |
| 12 | 2026-11-04 04:09 | design-review-007 | 0 | 0 | 11.0 | spend | design-review | 200000 |
| 13 | 2026-11-04 05:19 | design-refute-007 | 0 | 0 | 30.0 | spend | design-review |  |
| 14 | 2026-11-04 05:49 | design-review-008 | 0 | 0 | 9.0 | spend | design-review | 160000 |
| 15 | 2026-11-04 05:49 | design-refute-008 | 0 | 0 | 35.0 | spend | design-review |  |
| 16 | 2026-11-04 06:02 | design-review-009 | 0 | 0 | 12.0 | spend | design-review | 150000 |
| 17 | 2026-11-04 07:08 | design-refute-009 | 0 | 0 | 40.0 | spend | design-review |  |
| 18 | 2026-11-04 07:19 | design-review-010 | 0 | 0 | 12.0 | spend | design-review | 150000 |
| 19 | 2026-11-04 07:34 | design-refute-010 | 0 | 0 | 20.0 | spend | design-review |  |
| 20 | 2026-11-04 07:34 | prep | 3276 | 1 | 120.0 | spend | prep |  |
| 21 | 2026-11-05 00:42 | c0165: move the selection rules into lib/select.luau (no rule change) | 178 | 130 | 20.0 | focus | build |  |
| 22 | 2026-11-05 00:44 | c0165: isInput, parseInputs, fingerprint and workspace reads | 463 | 9 | 40.0 | focus | build |  |
| 23 | 2026-11-05 00:45 | c0165: context.luau, inputs.tsv files, --graph-only and the three selector Overrides | 441 | 11 | 30.0 | focus | build |  |
| 24 | 2026-11-05 00:47 | c0165: reuseplan and resultsdb | 247 | 0 | 35.0 | focus | build |  |
| 25 | 2026-11-05 00:48 | c0165: the runner records per-file results under PICKMAN_RESULTS; fence.myPid | 85 | 3 | 35.0 | focus | build |  |
| 26 | 2026-11-05 00:56 | c0165: specs.luau orchestrator, check.sh reuse (--fresh, whole-gate record), results on the runner | 514 | 10 | 90.0 | focus | build |  |
| 27 | 2026-11-05 02:54 | c0165: gatefix reads the last argument (user-approved), Verification log | 0 | 0 | 10.0 | focus | build |  |
| 28 | 2026-11-05 02:56 | c0165: zz-test, AGENTS.md and .gitignore wording; repo-fence and cachepaths entries | 37 | 1 | 40.0 | focus | build |  |
| 29 | 2026-11-05 02:57 | c0165: rehash c0172/narrowed's gate-cover digest | 1 | 1 | 5.0 | focus | build |  |
| 30 | 2026-11-05 03:28 | c0165: AC15's proof runs inside the runner (user-approved edit), Verification log | 0 | 0 | 15.0 | focus | build |  |
| 31 | 2026-11-05 03:32 | c0165: step 7, the audit lines and declarations for the specs landed since prep | 46 | 0 | 45.0 | focus | build |  |
| 32 | 2026-11-05 03:34 | c0165: typed empty-table loops, one-value gitState, nil path guard | 21 | 11 | 20.0 | focus | build |  |
| 33 | 2026-11-05 03:43 | c0165: type fixes, Verification log (Phase 3, step 7) | 2 | 2 | 15.0 | focus | build |  |
| 34 | 2026-11-05 03:59 | R0081: review-001 | 0 | 0 | 50.0 | focus | code-review |  |
| 35 | 2026-11-05 04:04 | c0165: review 001 fixes: json()-wrapped reads and a guarded rows, one-call recording, jail name, HEAD rule pinned, wording | 286 | 51 | 60.0 | focus | code-review |  |
| 36 | 2026-11-05 04:04 | R0081: refute-001, harvest, lessons, Verification log | 0 | 0 | 20.0 | focus | code-review |  |
| 37 | 2026-11-05 04:06 | c0165: selene shadowing, pcall expect, re-key the new spec | 6 | 6 | 10.0 | focus | code-review |  |
| 38 | 2026-11-05 04:28 | R0081: review-002 | 0 | 0 | 55.0 | focus | code-review |  |
| 39 | 2026-11-05 04:31 | c0165: review 002 fixes: failed rows, one SQL text, jail verdict from the run, end-to-end orchestrator spec | 578 | 77 | 70.0 | focus | code-review |  |
| 40 | 2026-11-05 04:31 | R0081: refute-002, harvest, lesson, Verification log | 0 | 0 | 20.0 | focus | code-review |  |
| 41 | 2026-11-05 04:50 | R0081: review-003 | 0 | 0 | 30.0 | focus | code-review |  |
| 42 | 2026-11-05 04:54 | c0165: review 003 fixes: results files are untrusted input, links hashed as git stores them, clean pinned | 189 | 24 | 60.0 | focus | code-review |  |
| 43 | 2026-11-05 04:54 | R0081: refute-003, harvest, lessons | 0 | 0 | 20.0 | focus | code-review |  |
| 44 | 2026-11-05 05:08 | R0081: review-004 | 0 | 0 | 30.0 | focus | code-review |  |
| 45 | 2026-11-05 05:12 | c0165: review 004 fixes: nested repository turns reuse off, link text pinned, orchestrator named in zz-test | 50 | 3 | 40.0 | focus | code-review |  |
| 46 | 2026-11-05 05:12 | R0081: refute-004, harvest, Verification log | 0 | 0 | 15.0 | focus | code-review |  |
| 47 | 2026-11-05 05:24 | R0081: review-005 | 0 | 0 | 30.0 | focus | code-review |  |
| 48 | 2026-11-06 06:34 | c0165: review 005 fixes: the digest holds the selection, a submodule turns reuse off, the reused line prints its time | 92 | 1 | 25.0 | focus | code-review |  |
| 49 | 2026-11-06 06:39 | c0165: re-key reuse-e2e.spec in the declared-inputs audit | 0 | 0 | 2.0 | focus | code-review |  |

**Total:** +6512 / -341 lines, 1573.0 agent-minutes, 7440865 tokens over 49 records
<!-- totals: added=6512 removed=341 minutes=1573.0 records=49 tokens=7440865 -->
