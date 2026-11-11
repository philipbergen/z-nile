---
name: z-ready
description: Ready a raft for execution, which claims it, moves it and its issues to `active/` on origin/main with their `check.sh` paths rewritten, and writes the self-contained prompt to `<root>/rafts/active/<R-id>/prompt.md` (beside the raft, in its project root) for any agent (Opus, Grok, ...) to deliver one layer per ticket. An issue with no raft goes to z-raft first. Also used to regenerate the prompt. Use for "ready a raft", "ready R0010", "/z-ready".
---

# Ready a raft

1. **Resolve the target.** Given an issue ID, the target is its raft. If the issue has no raft, stop: z-raft makes one (`./zn raft-plan`, or `./zn new raft … <id> --project <name>`) in its rafting worktree and merges it. A prompt for an undesigned issue defeats the purpose.
2. **Check readiness.** First, **scope**: each member's title, Problem and Solution ideas match its capture (`./zn capture <id>`; z-design, **Scope is what was captured**) apart from added detail and decision lines, and a capture whose header carries any marker (`(no capture commit: …)`, `(ambiguous: …)` or `(history before … not followed: …)`) counts as not matching until the Problem has a `Scope decision (user, …)` line that confirms the item's scope. If one doesn't, stop and ask the user. Their answer lands as a `Scope decision` line through a pull request merged with the subject `tracker: scope <id> <what>` (a `tracker: new` subject would make the whole prepared document the new capture) before you ready the raft. If they restore the captured scope instead, the raft goes back to prep. `./zn ready` enforces every rule below except the acceptance specs one, and refuses with the reason, naming the item; read them so you can explain a refusal.
   - The raft and every member are `design: ready`.
   - Every member has an approval (`./zn approve <id>`, run by the human in the prep worktree) whose contract still matches. An item prepared before approval has none: `./zn ready` asks for that one-time step and stops.
   - Every issue has a `check.sh` with at least one `check`.
   - The acceptance specs that each `check.sh` names exist. `ready` doesn't check this one, so look before you run it.
   - `./zn status <R-id>` prints `prepared`: the prep PR has merged and main is current.
   - Every `depends_on` of a member issue that isn't a member of this raft names an item in `done/` (`./zn find <id>`), for example the chore that removes a promoted spec the issue overrides. If one isn't, stop and say which.
   - The executing agent starts from origin/main, so it must see the same files.
3. **Ready it.** In the main checkout, run `./zn sync` first, then `./zn ready <id>`. It checks the main checkout is on `main` and clean, claims the raft, and publishes one tracker-only commit that moves the raft and its issues to `active/` on `origin/main`, with every item path in their `check.sh` files rewritten. It then pulls the main checkout (a fast-forward) and writes `<root>/rafts/active/<R-id>/prompt.md` beside the raft, which git ignores.
   - The prompt fills in `z-nile/templates/prompt.md` with this raft's theme, order and interfaces, and names every other file by path: the raft document, each issue's document, its `check.sh` and its `acceptance/` directory, the architecture map, and the skills the executor follows. Those skills are z-nile's `zz-execute`, `zz-rules`, `zz-arch`, `zz-test` and `zz-review`, then every skill of the raft's own project (`pickman/skills/*` for a pickman raft; none more for a z-nile raft), each from its real folder, with when to read it. None of their text is pasted.
   - Lessons are not listed. Search with `./zn lessons <terms>` when you are about to do something a lesson might cover.
   - The design-review history isn't included. Its outcomes are already folded into the documents.
   - Running it again on an active raft regenerates the prompt from the current documents and makes no commit.
4. **Report** the character count and a 3-line outline: mission, issues, and the number of Checked criteria, plus the plan's last line (`parallel: yes` or `parallel: no`, from `./zn workstreams <R-id>`). The next step is `/z-run <R>` in a Claude session started in the main checkout, which enters the raft's worktree (`./zn worktree <R>`) itself.

To change what every prompt contains, edit `z-nile/templates/prompt.md` or the skills. Don't hand-edit individual prompts.

## Lessons
Search with `./zn lessons <terms>` when you are about to do something a lesson might cover.

A new lesson (from a review finding, a correction by the user, or a step that failed in a way a rule would have prevented) is handled by your role, not by the skill you are reading:
- **A subagent** (a stream, a reviewer, any agent working from a brief) never writes a lesson file or runs `./zn new`. It puts the candidate (the rule, why, and the question that catches it) in its review or final report.
- **The lead of a prep or raft** writes it in `<skills folder>/<the skill the lesson improves>/lessons/<slug>.md` (the real folder: `z-nile/skills/` for z-nile's skills, `<project>/skills/` for a project's, never through a `.claude/skills/` link, which git can't add through; format: zz-rules skill, Items), and records where it came from in its own `harvest.md`: review findings through the harvest (z-design step 5.3, zz-execute Phase 4 step 5), and anything else (a subagent's candidate, a correction by the user, a failed step) as `- note <what happened>: <lesson ids>`. It adds a note to an existing lesson when one fits, writes a new file only when none does, and commits both with its work.
- **Any other lead** (in the main checkout, a capture, or a metrics report) captures it: `./zn new issue c lesson-<slug> --project z-nile --desc "<skill>: <the rule>, because <what happened>; check: <the question>"` (z-ticket skill). The prep that takes the issue writes the file.
