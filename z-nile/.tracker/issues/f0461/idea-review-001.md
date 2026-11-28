# Idea review 001

## Findings

- F1: The last Solution sentence names no lessons, and for one of the two the rough idea names it is false: `z-design/spec-design-correspondence` (434 sources) asks whether every Design behaviour has a spec case that fails without it, whether every assertion follows from a Design sentence and whether each check label says what its command verifies. A check that pairs criteria with check lines catches none of that, the third non-goal rules it out, and under c0455 a graduated lesson's file fails `./zn lessons --check`, so graduating it removes a review question nothing replaces.
- F2: The other lesson, `z-design/experiments-record-their-bounded-command`, records a result written with no command at all (c0278 design review 001 F8). Problem 4 and Solution 4 cover only a command that is cited without a time limit, so the lesson's own mistake passes the check and its graduation is not earned as worded.
- F3: "An issue cannot be marked prepared while that check reports any problem" is false as written or wider than intended: `./zn stop` stamps `prepared` without `./zn status <id> prepared` (`z-nile/engine/main.luau:7193`, `:7230`, also `:2623`). No non-goal fences tickets designed before this lands (c0460 has such a fence), nor easy tickets, which still run `./zn status <id> prepared` with no acceptance folder and a test written later with the code (`z-nile/skills/z-design/SKILL.md:61`).
- F4: Problem 3 says a declaration can be written "wrongly" but Solution 3 reports only "missing or malformed", and "malformed" is not defined. A reader cannot tell whether an unfilled template placeholder, an entry without its chore, or a well-formed `Overrides: none` on a design that turns a promoted spec red (the case zz-review item 4 rates high) is reported, so the sentence cannot be found true or false and may leave the commonest mistake to review.
- F5: Problem 3's "only review finds it" is not true on the easy path: `light.overridesNone` (`z-nile/engine/light.luau:160`) already reads the line, and `./zn ready` refuses with "its Regression guard does not say Overrides: none". The idea does not say whether the new check reuses that reader or adds a second one for the same line.

## Verdict

revise
