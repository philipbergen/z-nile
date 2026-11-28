# Idea review 002

## Findings

- F1: The count of skills that swap is not checkable, because `zz-rules` is itself one of the 26 (its `## Lessons` paragraph is at `z-nile/skills/zz-rules/SKILL.md:214`). "Written once, in zz-rules" and "each of the 26 swaps its `## Lessons` paragraph for a one-line pointer to zz-rules" cannot both hold for it. Either 25 skills swap and `zz-rules` keeps the text, or `zz-rules` points at itself, and the `./zn skills --check` rule ("one of those 26 has no Lessons pointer") inherits the same ambiguity.
- F2: "With their `pin.digest` updated" is false as written, because neither spec has a recorded digest to update. `pin.digest` is a helper in `z-nile/tests/lib/pin.luau`, and the promoted digest list in `z-nile/tests/acceptance/c0172/narrowed.spec.luau` names neither `c0111/skill-docs.spec.luau` nor `c0117/docs.spec.luau`. If a new whole-file pin of the changed specs is meant, the sentence should say that and where the pin lives.
- F3: The solution is not the smallest, because a missing pointer is caught twice: by a new failure in `./zn skills --check` and by the changed specs, which "check the pointers". `./zn skills --check` today only checks links ("28 skills, one link each, ok"), so this is new engine behaviour. `c0111/skill-docs.spec.luau` is listed with `*` in `z-nile/tests/inputs.tsv`, so the spec already covers the rule. The idea should drop one of the two or say what `--check` catches that the specs do not.

## Verdict

revise
