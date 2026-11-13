---
name: z-work
description: The worker a person starts by opening an AI CLI and running z-work. The session takes the next raft, or the raft named, and carries it to landed. Use for "z-work", "./zn work", "work the next raft".
---

# Work a raft

You are the worker. A person opened this session and ran z-work. Stay with one raft until it lands or you release it, then stop. Do not start another raft in this session.

1. Run `./zn work next` (or `./zn work next <R>` when a raft was named, including every later call). The line it prints is the one next action. The ordering is that command's; this skill has none.
2. Say that line to the person before you do it, and why it is the next action.
3. Do that one action and nothing past it. A build follows `z-nile/skills/zz-execute/SKILL.md`. A review follows `z-nile/skills/zz-review/SKILL.md`. Tracker commands follow `z-nile/skills/zz-rules/SKILL.md`. Claiming is `z-nile/skills/z-ready/SKILL.md`. Giving the claim back is `z-nile/skills/z-stop/SKILL.md`. Read the skill the action names.
   One worker holds the raft and builds its layers one at a time, each complete (finished, green and reviewed in its own issue folder, the review stamped by the tool) before the next `./zn start`.
4. At each layer boundary, one line: the ticket, whether its specs are green, and the next `./zn work next` line.
5. Blocked means a human decision, or the same check failed after a real second attempt. Write `questions.md` in the raft folder, one plain question per heading. `./zn commit` it on the layer. From the main checkout run `./zn stop <R>`. Tell the person, then run `./zn work next <R>` again. A blocked layer stops the layers above it, and `./zn done <R> --through <issue>` lands the green layers below it. Never guess a human decision. Never narrow scope to get green.
6. When the line says end, say so and tell the person to start a fresh session (or `/clear`) and run z-work again.
7. `./zn work status` prints who holds which raft, which layer, and since when. `./zn finish` and `./zn done` read the session that is running the command and write that row. Claude Code counts each message id once, and only the file `CLAUDE_CODE_SESSION_ID` names in this checkout. Kimi counts a wire only when its `state.json` cwd is this checkout and the CLI named that session; a wire has no per-line time, so the whole file counts. If the session cannot be named, or Kimi's cwd cannot be told, that row says unmeasured. Grok is `~/.grok/sessions` and Cursor's agent is `~/.cursor/projects`; neither has a count on this row today. Do not type a number.
8. Left for later: rank is c0249 (the next raft is the lowest id). A blocked status is c0250 (`questions.md` is the only block signal). Heartbeats are c0265 (there is no beat). Several hosts are c0254 (the holder is the author of the ready commit). There is no headless `./zn work` loop.

## Lessons
Search with `./zn lessons <terms>` when you are about to do something a lesson might cover.

A new lesson (from a review finding, a correction by the user, or a step that failed in a way a rule would have prevented) is handled by your role, not by the skill you are reading:
- **A subagent** (a stream, a reviewer, any agent working from a brief) never writes a lesson file or runs `./zn new`. It puts the candidate (the rule, why, and the question that catches it) in its review or final report.
- **The lead of a prep or raft** writes it in `<skills folder>/<the skill the lesson improves>/lessons/<slug>.md` (the real folder: `z-nile/skills/` for z-nile's skills, `<project>/skills/` for a project's, never through a `.claude/skills/` link, which git can't add through; format: zz-rules skill, Items), and records where it came from in its own `harvest.md`: review findings through the harvest (z-design step 5.3, zz-execute Phase 4 step 5), and anything else (a subagent's candidate, a correction by the user, a failed step) as `- note <what happened>: <lesson ids>`. It adds a note to an existing lesson when one fits, writes a new file only when none does, and commits both with its work.
- **Any other lead** (in the main checkout, a capture, or a metrics report) captures it: `./zn new issue c lesson-<slug> --project z-nile --desc "<skill>: <the rule>, because <what happened>; check: <the question>"` (z-ticket skill). The prep that takes the issue writes the file.
