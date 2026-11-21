---
name: z-nile-omarchy-arch
description: Structure rules for the omarchy board app (z-nile-omarchy/, an app project with no Luau) - pure Model.js versus QML that only renders, external programs as argument arrays, tracker text as untrusted, and the Qt 6.12 markdown rule. Read before designing or writing anything in z-nile-omarchy/.
---

# The omarchy board app's structure

`z-nile-omarchy/` is a registered project of the **app** kind (c0257): an omarchy-shell plugin, `znile.board/`, in QML, JavaScript and shell, with no Luau. Its home holds `check.sh`, its root `.tracker/`, these skills, the top `README.md` and the plugin. z-nile's own rules (zz-arch) do not apply here; these do.

## Pure model, thin QML
- Every rule lives in `Model.js` (`.pragma library`): normalizing the board model, blockers, columns and order, filters, the approval and guess counts, markdown neutralizing, pull-request matching, agent argv, cost and the chart. It reads no file and starts no process, so its node tests (`tests/model.test.mjs`) can pin every rule.
- The QML files render and wire processes. A rule written in QML has no test: move it into `Model.js` and test it there.
- Data comes only through `fetch.sh` (which reads only through `./zn`, never a second tracker parser), `prs.sh` and `agents.sh`. The app never writes tracker state itself.

## External programs
- Every external program starts from an argument array (`Process.command`, `Quickshell.execDetached`), one value per element. Never a shell string (`sh -c`, `bash -c`, `eval`) or a shell in an argument array (`"bash", "-c"`, `-lc`). c0257's AC5 scans every file for these.
- An AI CLI starts in its normal ask-first mode: no auto-approve flag in any agent's argv.

## Untrusted text
- Every title, body and id comes from tracker files anyone can edit. Titles render as plain text. Descriptions render only through `Model.safeMarkdown` (HTML and images neutralized). Ids are matched against `^[fdcR][0-9]{4}$` before any use. Links are built only from a `https://github.com/<owner>/<repo>/blob/main/` base or a github pull-request URL. A document path with `..` is dropped.

## Qt 6.12 markdown (d0389)
- Qt 6.12's scene graph crashes the whole shell (`QSGBatchRenderer::prepareAlphaBatches`) when it lays out again markdown that holds background-tinted spans or tables. The details popup therefore never draws a background colour in markdown (inline code is coloured monospace only) and shows a markdown table as a code block (`safeMarkdown`). Keep both until a Qt release that fixes it is the omarchy one, and test any markdown change in a standalone `qml` probe before it reaches the shell.

## Shell scripts
- `fetch.sh`, `prs.sh` and `agents.sh` start with a shebang and `set -euo pipefail`, are executable, and write only under the user's cache or state folders (`$XDG_CACHE_HOME/znile-board`, `~/.local/state/znile-board`).

## Lessons
Search with `./zn lessons <terms>` when you are about to do something a lesson might cover.

A new lesson (from a review finding, a correction by the user, or a step that failed in a way a rule would have prevented) is handled by your role, not by the skill you are reading:
- **A subagent** (a stream, a reviewer, any agent working from a brief) never writes a lesson file or runs `./zn new`. It puts the candidate (the rule, why, and the question that catches it) in its review or final report.
- **The lead of a prep or raft** writes it in `<skills folder>/<the skill the lesson improves>/lessons/<slug>.md` (the real folder: `z-nile/skills/` for z-nile's skills, `<project>/skills/` for a project's, never through a `.claude/skills/` link, which git can't add through; format: zz-rules skill, Items), and records where it came from in its own `harvest.md`: review findings through the harvest (z-design step 5.3, zz-execute Phase 4 step 5), and anything else (a subagent's candidate, a correction by the user, a failed step) as `- note <what happened>: <lesson ids>`. It adds a note to an existing lesson when one fits, writes a new file only when none does, and commits both with its work.
- **Any other lead** (in the main checkout, a capture, or a metrics report) captures it: `./zn new issue c lesson-<slug> --project z-nile --desc "<skill>: <the rule>, because <what happened>; check: <the question>"` (z-ticket skill). The prep that takes the issue writes the file.
