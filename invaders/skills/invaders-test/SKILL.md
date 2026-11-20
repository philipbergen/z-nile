---
name: invaders-test
extends: pickman-test
description: How invaders's game is tested - from invaders's home, with pickman's spec tiers and helpers, and which of them invaders has. Read with zz-test (the gate, check.sh, the guards) before writing a invaders spec.
---

# Testing (invaders)

This is invaders's half of testing. The gate, the runner, `check.sh` files, sequestration, the affected-spec selector and the repository guards are z-nile's, in the zz-test skill, and bind here too. The spec tiers, the shape of a spec and the simulation harness are pickman's, in `pickman/skills/pickman-test/SKILL.md`: read it.

## Running invaders's specs
Specs run from invaders's home, `invaders/`: `cd invaders && lune run tests/run -- tests/unit/Foo`, or `invaders/check.sh` for invaders's whole gate. Every path in pickman-test is relative to the project's home, so for invaders it is relative to `invaders/`, where `invaders/.luaurc` points `@tests`, `@logic` and `@shared` at invaders's own folders and `@arcade` at the library's `src/shared` (`../arcade/src/shared`). The assertions (`@tests/lib/t`) and `renamed` are the shared ones, re-exported from `invaders/tests/lib/`.

## What invaders has
- `tests/meta/architecture.spec.luau` runs pickman's structural rules from this home (the pickman-arch rules, on `invaders/src`).
- `tests/meta/fence.spec.luau` proves the run is guarded and jailed to `invaders/.cache`, as pickman's does.
- `tests/meta/home.spec.luau` checks this home against the home rule (z-nile/README.md, A project's home), so a missing file or a wrong setting fails its gate.
- A tier folder (`tests/unit/<Feature>`, `contract`, `scenario`, `place`) appears with its first spec. The helpers `sim` and `fakeengine` are pickman's (`pickman/tests/lib/`): a invaders spec never requires another home's helper. One that needs a helper asks for its move into the shared harness (`z-nile/tests/lib/`), as c0185 did for `place` (`tests/lib/place.luau` re-exports it, and `tests/place/library.spec.luau` is this home's place tier).

## Lessons
Search with `./zn lessons <terms>` when you are about to do something a lesson might cover.

A lesson goes to the step that erred: the skill whose instructions the author was following when the mistake was made, or the skill of an earlier step that should have prevented or caught it (that skill is `<the skill the lesson improves>` below). The harvest line names that step as `(erred <skill>[, upstream <skill>])` before its colon (zz-rules skill, Items), and every kind of review and correction is harvested: a finding of a design, code, stream or focused review as an entry of the item's `harvest.md`, and a programme review, a correction by the user or a failed step as a `- note` entry.

A new lesson (from a review finding, a correction by the user, or a step that failed in a way a rule would have prevented) is handled by your role, not by the skill you are reading:
- **A subagent** (a stream, a reviewer, any agent working from a brief) never writes a lesson file or runs `./zn new`. It puts the candidate (the rule, why, and the question that catches it) in its review or final report.
- **The lead of a prep or raft** writes it in `<skills folder>/<the skill the lesson improves>/lessons/<slug>.md` (the real folder: `z-nile/skills/` for z-nile's skills, `<project>/skills/` for a project's, never through a `.claude/skills/` link, which git can't add through; format: zz-rules skill, Items), and records where it came from in its own `harvest.md`: review findings through the harvest (z-design step 5.3, zz-execute Phase 4 step 5), and anything else (a subagent's candidate, a correction by the user, a failed step) as `- note <what happened> (erred <skill>): <lesson ids>`. It adds a note to an existing lesson when one fits, writes a new file only when none does, and commits both with its work.
- **Any other lead** (in the main checkout, a capture, or a metrics report) captures it: `./zn new issue c lesson-<slug> --project z-nile --filed-by "<source>" --desc "<skill>: <the rule>, because <what happened>; check: <the question>"` (z-ticket skill). Pass `--filed-by "<source>"` (quoted: it holds a space for a review finding; `review:<item id>/<review file> F<n>`, `lesson:<skill>/<slug>` or `agent:<item id>/<slug>`) only for a lesson that comes from a finding of yours; one from the user's correction carries their words, so capture it with the z-ticket skill without the flag. The prep that takes the issue writes the file.
