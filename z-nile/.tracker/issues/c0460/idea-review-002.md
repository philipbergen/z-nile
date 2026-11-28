# Idea review 002

## Findings

- F1: The Problem's second bullet and the Solution's last bullet name the wrong review mode. `z-nile/skills/zz-review/SKILL.md:92` is item 0 of `## Design mode` (heading at `:88`). `## Code mode` (`:115`–`:129`) has no item 0 and never mentions mutants, and the promoted spec `z-nile/tests/acceptance/c0043/review-skill.spec.luau:47` pins that it doesn't. So "code mode audits only the prep table" is false, "in place of the prep table" replaces a step that isn't there, and no Solution bullet says what happens to design mode's item 0, which would audit a table the idea removes.
- F2: The `./zn finish` bullet contradicts the second non-goal. It refuses any layer whose `mutants.md` is missing, while the non-goal says the new rules apply only to tickets designed after this lands. Nothing says what `finish` or the reviewer reads to tell the two apart, and 47 tickets under `.tracker/issues/` are already past draft (42 `design: ready`, 5 `design: reviewed`). A reader can't tell whether one of those layers is refused.
- F3: The `none: no code` exemption is wider than its name. It is defined as "no `.luau` file outside `tests/` and `acceptance/`", but the repo tracks 105 `.go` files under `z-nile/go/` (the `zn` and `znlive` commands), 37 `.sh` files and the bash `zn`. A layer changing only those has behavioural rules, yet would owe one line and pass `finish`.
- F4: The require allowlist is wider than the Problem. The Problem evidences only `@znile/engine/` requires, but the allowlist also bans `@arcade/*` and `@shared/*`. Acceptance specs in `arcade`, `pickman` and `portal` use those on 43 lines today (for example `@arcade/Logic/PaidPlay`, `@shared/Games`), and a game has no `./zn` command to go through instead. No Problem sentence says those pin internals. The closing `grep` checks only `@znile/` and `@scripts/`, so it cannot show the allowlist holds.
- F5: The count in the Problem's third bullet is false at this HEAD. `require("@znile/engine/` appears on 427 lines of tracked acceptance specs: 274 sequestered under `z-nile/.tracker/issues/` and 153 promoted under `z-nile/tests/acceptance/`. Neither is 279, and the sentence concludes about sequestered specs from a count of all tracked ones.

## Verdict

revise
