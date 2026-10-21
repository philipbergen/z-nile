---
name: launch-raft
description: Start executing a readied raft in this session ("launch R0001", "/launch-raft R0001"). Reads the raft's prompt.md, enters the raft's worktree and follows the prompt. Fails when the raft isn't readied or has no prompt (run /ready-raft). Use for "launch R0001", "/launch-raft".
---

# Launch a raft

Start the session in the main checkout, which stays on `main`. The skill takes a raft id `<R>`.

1. **Read the prompt.** Run `./zn prompt <R> --path`. If it fails, stop and report its message: the raft isn't readied (run `/ready-raft <R>`), or the prompt is missing (run `/ready-raft <R>` again to regenerate it). Never reconstruct a prompt by hand.
2. Read the whole file at that path with the Read tool, in chunks if needed. Don't print it through Bash: the output would be truncated.
3. **Enter the worktree.** The prompt's hard rule 2 says to run `cd "$(./zn worktree <R>)"` first. From then on, work only there, and give subagents absolute worktree paths. The hooks follow the session's current directory, so they act in the worktree.
4. **Follow the prompt** as your instructions, from its first line: the execute-raft protocol, through the merge.

Other agents (Grok, ...) get the same text from `./zn prompt <R>`.

## Lessons
Before you start, read this skill's lessons: `./zn lessons --skill launch-raft --full`. Each is a mistake made before, with the question that catches it.

A new lesson (from a review finding, a correction by the user, or a step that failed in a way a rule would have prevented) is handled by your role, not by the skill you are reading:
- **A subagent** (a stream, a reviewer, any agent working from a brief) never writes a lesson file or runs `./zn new`. It puts the candidate (the rule, why, and the question that catches it) in its review or final report.
- **The lead of a prep or raft** writes it in `.claude/skills/<the skill the lesson improves>/lessons/<slug>.md` (format: tracker skill, Items), and records where it came from in its own `harvest.md`: review findings through the harvest (ticket-prep step 5.3, execute-raft Phase 4 step 5), and anything else (a subagent's candidate, a correction by the user, a failed step) as `- note <what happened>: <lesson ids>`. It adds a note to an existing lesson when one fits, writes a new file only when none does, and commits both with its work.
- **Any other lead** (in the main checkout, a capture, or a metrics report) captures it: `./zn new issue c lesson-<slug> --desc "<skill>: <the rule>, because <what happened>; check: <the question>"` (make-issue skill). The prep that takes the issue writes the file.
