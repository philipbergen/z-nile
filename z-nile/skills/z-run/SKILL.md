---
name: z-run
description: `/z-run <R>` is z-work with that raft named. Under `./zn dispatch` it is the headless run step. Use for "/z-run R0010". There is no separate run protocol.
---

# Run a raft

`/z-run <R>` is z-work with that raft named. Read `z-nile/skills/z-work/SKILL.md` and follow it, passing `<R>` to every `./zn work next <R>`. There is no separate run protocol.

The commands z-work uses when its line names them: `./zn prompt <R> --path` (if it fails, the raft isn't readied — run `/z-ready <R>`), then `cd "$(./zn worktree <R>)"`. **Hand off.** Follow the prompt as your instructions, from its first line: it names `z-nile/skills/zz-execute/SKILL.md` when the line says to build.

**Lost work and keeping the claim.** Without a raft named, z-work looks at `./zn lost` before a raft that is not yet started: lost work comes first. With a raft named (`/z-run <R-id>`), carry that raft and stop. A lost raft is taken over by `./zn stop <R-id>`, then `./zn ready <R-id>`; continue from the raft branch and its pull request where they exist (z-stop step 4) in a worktree that holds no claim of the old lead's. A worktree beats only a claim it holds, and `ready` made this one in the main checkout: run `./zn beat <R-id> --adopt` once in the raft's worktree to take it on. Keep your claim alive while you work: start `./zn run --time 3600 -- ./zn beat <id> --watch` in the background (it beats every 5 minutes and stops by itself; start it again when it reports its bound), or run `./zn beat <id>` yourself at least every 15 minutes.

## Headless (under `./zn dispatch`)
When `ZN_DISPATCH=1` is set you run headless and unattended, with the agent's own GitHub credential, and nobody answers a question. Never decide what you would ask the user, and never guess a ruling. A scope change or a missing credential: write the questions to `$ZN_DISPATCH_DIR/questions.md`, one `## Q<n>` heading per question with the options and what each costs, and stop. The dispatcher stops the chain there until the user answers and runs `./zn dispatch retry <id>`. A refutation or an unclosed high is written under `## Open to the human` in the item's document and you stop without ruling on it: the dispatcher stops the chain on that unruled list until the user rules in the document and runs `./zn dispatch retry <id>`. `./zn land`, `status`, `spend` and every other `./zn` command that publishes tracker state are allowed: the dispatcher pushes that tracker state to `main` for you. Never `git push` to `main` and never merge a pull request: the dispatcher merges at its gates, your credential can't, and `z-nile/bin/git` and `gh` refuse. Record your spend as this skill says. Do not pass `--time` or `--tokens`: the dispatcher records the session's wall, CPU, tokens and model. Start every review with `./zn dispatch zz-review <id> --mode <design|raft|code|stream>` (zz-rules skill, Dispatch), and give that one command a two-hour timeout (in Claude Code, the Bash tool's `timeout` of 7200000 ms): a review takes minutes, and the dispatcher keeps it alive by its heartbeat.

## Lessons
Search with `./zn lessons <terms>` when you are about to do something a lesson might cover.

A new lesson (from a review finding, a correction by the user, or a step that failed in a way a rule would have prevented) is handled by your role, not by the skill you are reading:
- **A subagent** (a stream, a reviewer, any agent working from a brief) never writes a lesson file or runs `./zn new`. It puts the candidate (the rule, why, and the question that catches it) in its review or final report.
- **The lead of a prep or raft** writes it in `<skills folder>/<the skill the lesson improves>/lessons/<slug>.md` (the real folder: `z-nile/skills/` for z-nile's skills, `<project>/skills/` for a project's, never through a `.claude/skills/` link, which git can't add through; format: zz-rules skill, Items), and records where it came from in its own `harvest.md`: review findings through the harvest (z-design step 5.3, zz-execute Phase 4 step 5), and anything else (a subagent's candidate, a correction by the user, a failed step) as `- note <what happened>: <lesson ids>`. It adds a note to an existing lesson when one fits, writes a new file only when none does, and commits both with its work.
- **Any other lead** (in the main checkout, a capture, or a metrics report) captures it: `./zn new issue c lesson-<slug> --project z-nile --desc "<skill>: <the rule>, because <what happened>; check: <the question>"` (z-ticket skill). The prep that takes the issue writes the file.
