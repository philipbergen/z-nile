# Review 001: c0080 (stream mode)
Inputs: merge-base 397445f..ws-c0080; scripts/tracker.sh check c0080 (4/4 PASS); diff of main.luau, the two promoted specs, both skills, c0080.md. Sequestered check.sh and acceptance/consequences.spec.luau unchanged (no tracker/**/check.sh or acceptance path in the diff; only c0080.md is touched under tracker/).

Scope: the diff touches exactly the allowed files. The c0038 changes are `; consequences: none` appended to `fixed` lines plus stylua rewrapping; with `-w` the only non-wrapping change is one `refused(... "- F1: ignored" ...)` call that was split and re-added in the same position with identical arguments. The c0001 changes are the appended text and a rewrap. Nothing else changed.

Rule: only lines starting `fixed` are checked, against `consequences:%s*%S` from init 6 (just past `fixed`), so `refuted` and `deferred` take the old path. The message names the finding id. The check reads the single-line capture `[^\n]*`, so `consequences:` with nothing after it, or only spaces, is refused.

### F1 [low] The full gate before every review round can block on the known flaky f0013 bench
Where: .claude/skills/execute-raft/SKILL.md, Phase 4 step 1
Evidence: the stream's own log shows `scripts/check.sh --full` failing once on the f0013 wall-clock bench under load and passing alone. Step 1 now says "a red gate is fixed before a reviewer is launched" with no word on a flaky failure.
Critique: an executor may loop on the bench, or skip the rule. The tempting fix is to name f0013 in the skill, which goes stale.
Consequences: a generic sentence, with no test name, adds no rule to keep in step; a named test would need updating when the bench is fixed or renamed.
Recommendation: optional. Add "rerun a failing spec alone; a failure that passes alone and is not in the diff's area is recorded in the review comment, not hidden". No spec needed.

### F2 [low] The `consequences:` pattern matches anywhere after `fixed`, including inside the description
Where: scripts/tracker/main.luau `reviewProblem`
Evidence: `- F1: fixed abc: renamed consequences: x` passes with no `;` separator.
Critique: this is what the Design specifies ("anywhere after `fixed`"), so it is not a defect, only a known looseness. Requiring `; consequences:` would be stricter but would reject the design-refute style (`fixed: <what>; consequences:` is also semicolon-led, so it would hold there).
Consequences: tightening would change the sequestered spec's accepted inputs only if it uses a non-semicolon form; check before changing.
Recommendation: leave as is.

Verdict: approve
