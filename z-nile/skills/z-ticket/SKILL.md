---
name: z-ticket
description: Capture a new feature/defect/chore issue in the tracker backlog. Use when the user describes work to be done, a bug, or a chore ("add an issue", "we should", "bug:").
---

# Make an issue

0. **Open a capture worktree first**, before anything is created: `cd "$(./zn worktree capture-<slug>)"` (zz-rules skill, Worktrees). Everything below runs there, never in the main checkout. Then run `./zn sync`, so you see every item other terminals have created.
1. **Classify the work**:
   - **feature** (`f`): new player-facing or developer-facing capability.
   - **defect** (`d`): **game or product** behavior that's wrong compared with an issue that's already done or with an obvious expectation. This is rework, and it's counted against the 20% target, so classify honestly.
   - **chore** (`c`): tooling, refactors or infrastructure, with no change in behavior. **Anything related to CI or tests is always a chore, even when it's a bug**, for example:
     - a flaky or wrong spec, including a promoted acceptance spec;
     - a test-selector graph miss;
     - a broken gate script, `setup.sh`, hook or workflow;
     - tracker CLI bugs.
     These never count as rework.
2. **Create it**: `./zn new issue <f|d|c> <kebab-slug> --project <name> --desc "<one line>"`. The project is `--project`'s when given, else the one whose folder you run `./zn` in (`z-nile/` and below is z-nile's, `pickman/` and below pickman's, c0120); at the checkout's root, or in a folder no project holds, `./zn` refuses and asks for `--project`. Tooling work (the tracker, the gate, the guards, the skills, CI) is `--project z-nile`; the work of a game, the portal or the arcade library is its project's (`--project pickman`, `--project snake`, `--project portal`, `--project arcade`, …: a name in `z-nile/projects.toml`), or a capture run in that project's folder (`pickman/`, `snake/`, …) (zz-rules skill, Projects). The stub, with that line as its Problem, is pushed to `origin/main` at once, so other terminals see the id and the item. The slug is 2–5 words describing the outcome.
3. **Fill in the frontmatter**: `title`, and `depends_on` (IDs) if you already know them.
4. **Fill in only these sections**:
   - **Problem**: the user's words, sharpened. Who is affected, what happens now, and what should happen. Every outcome it names, and every idea the user gives under Solution, is the issue's scope: once it lands, prep may add detail but never narrows, defers or drops an outcome without the user (z-design, **Scope is what was captured**).
   - **Non-goals**: whatever came up and belongs elsewhere.
   - A few bullet-point ideas under Solution, if they came up.
   Everything else is left for `z-design`. Keep `design: draft`.
5. **Duplicates**: look for overlaps with `./zn list backlog`. If there's an overlap, say so and ask whether to merge.
6. **Land it.** Commit in the capture worktree (`git add -A && git commit -m "tracker: new <id> <title>"`), run `./zn land`, and before the worktree is removed record `./zn spend <id> --phase capture --time <minutes>`, then remove the worktree with the command it prints. No PR: land runs the gate locally and pushes to `main`. Under the dispatcher, land without asking (the user started it); the dispatcher pushes the capture for you. Report the ID and path.

## Headless (under `./zn dispatch`)
When `ZN_DISPATCH=1` is set you run headless and unattended, with the agent's own GitHub credential, and nobody answers a question. Never decide what you would ask the user (a scope change, a final review round that goes to the user, a missing credential): write the questions to `$ZN_DISPATCH_DIR/questions.md`, one `## Q<n>` heading per question with the options and what each costs, and stop. The dispatcher stops the chain there until the user answers and runs `./zn dispatch retry <id>`. `./zn land`, `status`, `spend` and every other `./zn` command that publishes tracker state are allowed: the dispatcher pushes that tracker state to `main` for you. Never `git push` to `main` and never merge a pull request: the dispatcher merges at its gates, your credential can't, and `z-nile/bin/git` and `gh` refuse. Record your spend as this skill says, but without `--tokens` for your own session: the dispatcher records the session's tokens and model. Start every review with `./zn dispatch zz-review <id> --mode <design|raft|code|stream>` (zz-rules skill, Dispatch), and give that one command a two-hour timeout (in Claude Code, the Bash tool's `timeout` of 7200000 ms): a review takes minutes, and the dispatcher keeps it alive by its heartbeat.

## Lessons
Before you start, read this skill's lessons: `./zn lessons --skill z-ticket --full`. Each is a mistake made before, with the question that catches it.

A new lesson (from a review finding, a correction by the user, or a step that failed in a way a rule would have prevented) is handled by your role, not by the skill you are reading:
- **A subagent** (a stream, a reviewer, any agent working from a brief) never writes a lesson file or runs `./zn new`. It puts the candidate (the rule, why, and the question that catches it) in its review or final report.
- **The lead of a prep or raft** writes it in `<skills folder>/<the skill the lesson improves>/lessons/<slug>.md` (the real folder: `z-nile/skills/` for z-nile's skills, `<project>/skills/` for a project's, never through a `.claude/skills/` link, which git can't add through; format: zz-rules skill, Items), and records where it came from in its own `harvest.md`: review findings through the harvest (z-design step 5.3, zz-execute Phase 4 step 5), and anything else (a subagent's candidate, a correction by the user, a failed step) as `- note <what happened>: <lesson ids>`. It adds a note to an existing lesson when one fits, writes a new file only when none does, and commits both with its work.
- **Any other lead** (in the main checkout, a capture, or a metrics report) captures it: `./zn new issue c lesson-<slug> --project z-nile --desc "<skill>: <the rule>, because <what happened>; check: <the question>"` (z-ticket skill). The prep that takes the issue writes the file.
