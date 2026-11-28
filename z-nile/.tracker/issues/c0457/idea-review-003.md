# Idea review 003

## Findings

- F1: Problem line 2 names two promoted specs, but two more require the Lessons copy in every skill, and the Solution does not override them. `z-nile/tests/acceptance/c0115/docs.spec.luau:204` ("every skill's lessons paragraph names the real folder") needs three phrases of the full text inside each skill's `## Lessons`. `z-nile/tests/acceptance/c0136/docs.spec.luau:100` needs the "A lesson goes to the step that erred" paragraph, the same line, in each non-alias skill. Both fail on a one-line pointer, so the Solution as written cannot pass the gate.
- F2: The Solution does not say whether the `## Headless (under `./zn dispatch`)` and `## Lessons` headings stay above the pointers. `z-nile/tests/acceptance/f0399/docs.spec.luau:59` and `:68` require the Headless heading in z-design and z-raft. If "replace their `## Headless` section" removes the heading, that is a third promoted spec the Solution does not name.
- F3: The dispatcher's step prompt names one file: "Read `<skillPath>` and follow it for <id>" (`z-nile/engine/dispatch.luau:277`). After the change, that file holds a pointer instead of the unattended rules (never guess a ruling, write `questions.md` and stop, never push to `main`). The non-goal "the dispatcher's headless runtime behaviour does not change" fences only the dispatcher's code. Nothing in the Solution says how a dispatched step still reads those rules, and no check named covers it.
- F4: Non-goal 1 fences copies of the Lessons rule in `architecture.md` files, but none of the six `<project>/.tracker/architecture.md` files contains the word "lesson", and z-nile has no `architecture.md`. That part of the fence surrounds nothing.

## Verdict

revise
