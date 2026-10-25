# Review 003: R0043 (code mode)
Inputs: `impl-r43` at efd3c10, diffed against `origin/prep-z-nile-home` (8ff448b) after `git fetch origin`; fix delta `39b88d5^..HEAD` (39b88d5 added review-002 together with the F1 fix; efd3c10 adds refute-002, the lesson and the harvest); review-001/002, refute-001/002, c0114.md, both `check.sh` files, `scripts/hooks/stop.sh`, PR #97 and #98 descriptions, `./zn lessons --when build`.
Dropped from review-002: F1 (fixed in 39b88d5, AC9 passes), F2 (PR #97 now lists the floor removal as guess 0).

What I ran and checked:
- `z-nile/check.sh --full`: GATE PASSED, 1887 passed, 0 failed, 274 spec files, 74.7 s.
- `bash z-nile/.tracker/issues/c0114/check.sh`: 14/14. `bash z-nile/.tracker/rafts/R0043/check.sh`: 5/5.
- Sequestration: over the four item-root globs, `origin/prep-z-nile-home...HEAD` gives 108 `R100` and the same 2 `D` as earlier rounds (`tracker/templates/{issue,raft}/check.sh`, templates moved to `z-nile/templates/`). Nothing else.
- Fix delta: 39b88d5 is `M .claude/skills/testing/SKILL.md` (one line) plus `A review-002.md`; efd3c10 is `A` lesson, `M harvest.md`, `A refute-002.md`. The reworded stop-hook line names no old path and still matches `scripts/hooks/stop.sh`, which runs the old gate path's forwarder with `--affected` when a file outside every registry root changed under `src/`, `tests/` or `z-nile/`. It adds no behaviour; it is text only.
- Repository safety (item 8): the delta touches no spec, `check.sh`, script or guard (`tests/lib/fence.luau`, `z-nile/lib/fence.sh`, `z-nile/lib/git-hooks/`, the fence in `z-nile/lib/ac.sh`, `repo-fence.spec.luau` are unchanged since round 002). Round 001's line-by-line pass of the "Caught only by review" list stands for the unchanged rest.
- Lessons: the new `execute-raft/fix-rounds-rerun-every-member-check` is general (any raft whose fix touches text an unpromoted spec judges can fail it), not a restated finding; its How-to-apply also covers review-002's note that a reviewer's proposed wording must pass the same checks. No build lesson is repeated by the delta.

## Judged criteria (code mode only)
- JC1: pass. PR #98's description lists the one `c0114: move` commit, 9e178c4, which is still 703 `R100` and nothing else, `tracker/next` not among them. No commit added since round 002 moves a file: 39b88d5 is `M`/`A`, efd3c10 is `A`/`M`/`A`. Neither `tracker/next` nor `z-nile/next` is in the branch diff.

Verdict: approve
