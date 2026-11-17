---
name: z-nile-omarchy-test
description: How the omarchy board app (z-nile-omarchy/) is tested - node tests of the pure model, run by the gate's node stage, and what only a person on an omarchy machine can check. Read before writing or running the app's tests.
---

# Testing the omarchy board app

- **Node tests.** `znile.board/tests/model.test.mjs` loads `Model.js` (a QML `.pragma library` script) with `new Function` and tests it with `node:test`. Run it with a file path, not a folder (a folder fails on node 22): `./zn run --time 60 -- node --test z-nile-omarchy/znile.board/tests/model.test.mjs` from the checkout's top. A test that reads node's summary asks for `--test-reporter=tap` (node 26 prints another summary by default).
- **The gate.** `z-nile-omarchy/check.sh` (`z-nile/check.sh --project z-nile-omarchy`) runs the app's node stage: `node --test` on every `*/tests/*.test.mjs` of the home, sorted. It fails when a test fails or when there are none, and it runs none of the Luau stages over the home (README, A project's home). `--full`, and `--affected` when a path under the home changed, run it too.
- **Write the test first.** Every rule a change adds or changes in `Model.js` gets a case in `tests/model.test.mjs` that fails without it.
- **Acceptance.** A ticket of this project has node tests and `check.sh` checks as its acceptance. An app home has no Lune runner, so it cannot promote Luau specs (`./zn done` would fail on them).
- **What only a person can check.** The QML (rendering, drag, the details popup, the terminal launch) runs only in omarchy-shell. Install by linking `znile.board/` into `~/.config/omarchy/plugins/`, then `./zn run --time 60 -- omarchy restart shell`. A crash of the shell leaves a report in `~/.cache/quickshell/crashes/`. Reproduce a rendering crash in a standalone `/usr/lib/qt6/bin/qml` probe before changing the app.
- **Probes** go through `./zn run --time <seconds> -- <command>`, like every other command you start yourself.

## Lessons
Search with `./zn lessons <terms>` when you are about to do something a lesson might cover.

A new lesson (from a review finding, a correction by the user, or a step that failed in a way a rule would have prevented) is handled by your role, not by the skill you are reading:
- **A subagent** (a stream, a reviewer, any agent working from a brief) never writes a lesson file or runs `./zn new`. It puts the candidate (the rule, why, and the question that catches it) in its review or final report.
- **The lead of a prep or raft** writes it in `<skills folder>/<the skill the lesson improves>/lessons/<slug>.md` (the real folder: `z-nile/skills/` for z-nile's skills, `<project>/skills/` for a project's, never through a `.claude/skills/` link, which git can't add through; format: zz-rules skill, Items), and records where it came from in its own `harvest.md`: review findings through the harvest (z-design step 5.3, zz-execute Phase 4 step 5), and anything else (a subagent's candidate, a correction by the user, a failed step) as `- note <what happened>: <lesson ids>`. It adds a note to an existing lesson when one fits, writes a new file only when none does, and commits both with its work.
- **Any other lead** (in the main checkout, a capture, or a metrics report) captures it: `./zn new issue c lesson-<slug> --project z-nile --desc "<skill>: <the rule>, because <what happened>; check: <the question>"` (z-ticket skill). The prep that takes the issue writes the file.
