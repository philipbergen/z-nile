# Idea review 003

## Findings

- F1: Problem 3's count does not reproduce. At `c530e048b`, `grep -rn 'require("@znile/engine/' z-nile/.tracker/issues/**/acceptance/ | wc -l` prints 274, not 277 (`git grep` at that commit agrees).
- F2: Solution 2's "a ticket designed after this lands carries that line and no table" is false for tickets captured before it lands. The template is copied at capture, so 61 of the 132 open z-nile tickets already carry `### Rules and mutants` with no rows and no `Mutants:` line (c0460 itself, `c0460.md:60`). Non-goal 3 treats "designed before this lands" and "no `Mutants:` line" as the same set, and these tickets break that. Designed afterwards, they keep a table z-design no longer says to fill, item 0 still audits it, and `finish` never asks them for `mutants.md`.
- F3: Solution 3 says the spec case "must fail on an assertion", but no sentence says what happens when it passes. `finish` refuses only a row with no result, so a row recording a surviving mutant finishes. The executor cannot fix the weak case, because it sits in a sequestered spec (`z-nile/skills/zz-execute/SKILL.md:32`, stop condition at `:103`). The prep check being dropped was the one point where the designer could still change that case.
- F4: The two `none:` lines are not the smallest solution. `finish` must already read `risk:` and classify the layer's diff to validate them, so the one-line file only restates what `finish` computed. The third refusal case exists only to catch that restatement being wrong.
- F5: Solution 8 names the one promoted case that stays green and omits the two that Solution 2 turns red. `z-nile/tests/acceptance/c0043/ticket-prep.spec.luau:28` asserts that z-design step 3 asks for the table, and `z-nile/tests/acceptance/c0043/table.spec.luau:11` asserts that the template has `### Rules and mutants` after Test plan. Neither requires `@znile/*` or `@scripts/*`, so Non-goal 1 does not cover them, and no sentence says they change.

## Verdict

revise
