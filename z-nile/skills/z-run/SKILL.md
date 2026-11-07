---
name: z-run
description: Launch a readied raft from the main checkout ("/z-run R0010") - read its prompt, enter its worktree, and hand off to the zz-execute protocol the prompt carries. Use for "launch R0010", "run R0010", "/z-run". Fails when the raft isn't readied or has no prompt (run /z-ready).
---

# Run a raft

Start the session in the main checkout, which stays on `main`. The skill takes a raft id `<R>`, readied by z-ready.

1. **Read the prompt.** Run `./zn prompt <R> --path`. If it fails, stop and report its message: the raft isn't readied (run `/z-ready <R>`), or the prompt is missing (run `/z-ready <R>` again to regenerate it). Never reconstruct a prompt by hand.
2. Read the whole file at that path with the Read tool, in chunks if needed. Don't print it through Bash: the output would be truncated.
3. **Enter the worktree.** The prompt's hard rule 2 says to run `cd "$(./zn worktree <R>)"` first. From then on, work only there, and give subagents absolute worktree paths. The hooks follow the session's current directory, so they act in the worktree.
4. **Hand off.** Follow the prompt as your instructions, from its first line: it carries the zz-execute skill, the protocol you follow through the merge. Other agents (Grok, ...) get the same text from `./zn prompt <R>`.

## Headless (under `./zn dispatch`)
When `ZN_DISPATCH=1` is set you run headless and unattended, with the agent's own GitHub credential, and nobody answers a question. Never decide what you would ask the user (a scope change, a final review round that goes to the user, a missing credential): write the questions to `$ZN_DISPATCH_DIR/questions.md`, one `## Q<n>` heading per question with the options and what each costs, and stop. The dispatcher stops the chain there until the user answers and runs `./zn dispatch retry <id>`. `./zn land`, `status`, `spend` and every other `./zn` command that publishes tracker state are allowed: the dispatcher pushes that tracker state to `main` for you. Never `git push` to `main` and never merge a pull request: the dispatcher merges at its gates, your credential can't, and `z-nile/bin/git` and `gh` refuse. Record your spend as this skill says, but without `--tokens` for your own session: the dispatcher records the session's tokens and model. Start every review with `./zn dispatch zz-review <id> --mode <design|raft|code|stream>` (zz-rules skill, Dispatch), and give that one command a two-hour timeout (in Claude Code, the Bash tool's `timeout` of 7200000 ms): a review takes minutes, and the dispatcher keeps it alive by its heartbeat.

## Lessons
Before you start, read this skill's lessons: `./zn lessons --skill z-run --full`. Each is a mistake made before, with the question that catches it.

A new lesson (from a review finding, a correction by the user, or a step that failed in a way a rule would have prevented) is handled by your role, not by the skill you are reading:
- **A subagent** (a stream, a reviewer, any agent working from a brief) never writes a lesson file or runs `./zn new`. It puts the candidate (the rule, why, and the question that catches it) in its review or final report.
- **The lead of a prep or raft** writes it in `<skills folder>/<the skill the lesson improves>/lessons/<slug>.md` (the real folder: `z-nile/skills/` for z-nile's skills, `<project>/skills/` for a project's, never through a `.claude/skills/` link, which git can't add through; format: zz-rules skill, Items), and records where it came from in its own `harvest.md`: review findings through the harvest (z-design step 5.3, zz-execute Phase 4 step 5), and anything else (a subagent's candidate, a correction by the user, a failed step) as `- note <what happened>: <lesson ids>`. It adds a note to an existing lesson when one fits, writes a new file only when none does, and commits both with its work.
- **Any other lead** (in the main checkout, a capture, or a metrics report) captures it: `./zn new issue c lesson-<slug> --project z-nile --desc "<skill>: <the rule>, because <what happened>; check: <the question>"` (z-ticket skill). The prep that takes the issue writes the file.
