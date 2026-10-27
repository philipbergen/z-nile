# Review 004: c0141 (design mode)
Inputs: prep `prep-check-paths-home` dac87e8a (`git diff 3524a78d..dac87e8a`: c0141.md, check.sh, acceptance/touched-from-home.spec.luau, design-refute-003.md, harvest.md, the lessons zz-test/any-rule-places-the-decider-first-and-last and zz-test/kill-mutants-where-the-value-is-built); prototype `proto-check-paths-home` 46f7d115 (`git diff 83f41f9c 46f7d115`: only the header of `z-nile/tests/acceptance/c0120/checkpaths.luau`). Probes ran in a `--no-hardlinks` scratch clone of 46f7d115 with c0141's two acceptance specs copied to `z-nile/tests/acceptance/c0141/` (scratchpad `dr-chores-7/c0141`).
Dropped from design-review-003: F1, F2, F3

Rulings on refute 003:
- F1 fixed. Baseline: touched-from-home 4/4. Mutant N7 (`fromTop = first ~= nil and table.find(homes, first) ~= nil`, the last entry decides): touched-from-home 2 passed, 2 failed. Mutant N7b (a `break` after the first entry, so the first entry decides): 3 passed, 1 failed. c0120's check-paths stays 4/4 under both, as expected. One wording slip, not a finding: E2 says the home-first case kills N7b, but under "the first decides" the home-first case passes. N7b is killed by the existing home-last case `{ ".models.toml", "z-nile/x" }` and by the new middle case.
- F2 fixed, and the refute is right that my suggested `game2/new` case was vacuous. c0120's `PREFIXES` doesn't read `game2/…` as a path, so the case never reached the rule. The author's c0008 (Touched `game2/x` + `scripts/new`, `cd .. && test -f scripts/new`) reaches it through `scan`. Mutant N2 (`scan` builds `homes` as `{ "pickman", "z-nile" }`, registry loop removed): touched-from-home 3 passed, 1 failed. The consequence the author reported, that a check.sh naming a third project's path is never checked, is c0120's literal rule and outside c0141's capture. Reporting it to the coordinator for an issue is the right route.
- F3 fixed. `git grep -nE "entry's own text|existence check|one reading per entry"` in the c0141 folder now hits only design-refute-001, design-review-002 and design-review-003, which record the old rule. In the prototype's `z-nile/tests z-nile/skills` it finds nothing.
- The two new lessons: each is a mistake another raft could make (a loop that overwrites a flag; a value the test passes in, so the caller that builds it goes unchecked). Neither just restates a finding. Fine.
- Overrides and scope: unchanged since round 003 (the prototype diff is a comment). The capture's outcome still has its Design and AC1–AC3.

No findings.

Verdict: approve
