---
name: ready-raft
description: Ready a raft for execution, which claims it, moves it and its issues to `active/` on origin/main with their `check.sh` paths rewritten, and writes the self-contained prompt to `<root>/rafts/active/<R-id>/prompt.md` (beside the raft, in its project root) for any agent (Opus, Grok, ...) to deliver as one PR. An issue with no raft goes back to ticket-prep first. Also used to regenerate the prompt. Use for "ready a raft", "ready R0010", "/ready-raft".
---

# Ready a raft

1. **Resolve the target.** Given an issue ID, the target is its raft. If the issue has no raft, stop: ticket-prep makes one (`--single` for a lone issue) in its prep worktree and merges it. A prompt for an undesigned issue defeats the purpose.
2. **Check readiness.** First, **scope**: each member's title, Problem and Solution ideas match its capture (`./zn capture <id>`; ticket-prep, **Scope is what was captured**) apart from added detail and decision lines, and a capture whose header carries any marker (`(no capture commit: …)`, `(ambiguous: …)` or `(history before … not followed: …)`) counts as not matching until the Problem has a `Scope decision (user, …)` line that confirms the item's scope. If one doesn't, stop and ask the user. Their answer lands as a `Scope decision` line through a pull request merged with the subject `tracker: scope <id> <what>` (a `tracker: new` subject would make the whole prepared document the new capture) before you ready the raft. If they restore the captured scope instead, the raft goes back to prep. `./zn ready` enforces every rule below except the acceptance specs one, and refuses with the reason, naming the item; read them so you can explain a refusal.
   - The raft and every member are `design: ready`.
   - Every issue has a `check.sh` with at least one `check`.
   - The acceptance specs that each `check.sh` names exist. `ready` doesn't check this one, so look before you run it.
   - `./zn status <R-id>` prints `prepared`: the prep PR has merged and main is current.
   - Every `depends_on` of a member issue that isn't a member of this raft names an item in `done/` (`./zn find <id>`), for example the chore that removes a promoted spec the issue overrides. If one isn't, stop and say which.
   - The executing agent starts from origin/main, so it must see the same files.
3. **Ready it.** In the main checkout, run `./zn sync` first, then `./zn ready <id>`. It checks the main checkout is on `main` and clean, claims the raft, and publishes one tracker-only commit that moves the raft and its issues to `active/` on `origin/main`, with every item path in their `check.sh` files rewritten. It then pulls the main checkout (a fast-forward) and writes `tracker/rafts/active/<R-id>/prompt.md`, which git ignores.
   - The prompt fills in `z-nile/templates/prompt.md` with the raft and issue documents, the `check.sh` files, the sequestered acceptance specs, the architecture map and the `execute-raft`, `tracker`, `architecture`, `testing` and `review` skills.
   - It also lists the build lessons (`./zn lessons --when build`): one line each, with the question to ask.
   - The design-review history isn't inlined. Its outcomes are already folded into the documents.
   - Running it again on an active raft regenerates the prompt from the current documents and makes no commit.
4. **Report** the character count and a 3-line outline: mission, issues, and the number of Checked criteria, plus the plan's last line (`parallel: yes` or `parallel: no`, from `./zn workstreams <R-id>`). The next step is `/launch-raft <R>` in a Claude session started in the main checkout, which enters the raft's worktree (`./zn worktree <R>`) itself.

To change what every prompt contains, edit `z-nile/templates/prompt.md` or the skills. Don't hand-edit individual prompts.

## Lessons
Before you start, read this skill's lessons: `./zn lessons --skill ready-raft --full`. Each is a mistake made before, with the question that catches it.

A new lesson (from a review finding, a correction by the user, or a step that failed in a way a rule would have prevented) is handled by your role, not by the skill you are reading:
- **A subagent** (a stream, a reviewer, any agent working from a brief) never writes a lesson file or runs `./zn new`. It puts the candidate (the rule, why, and the question that catches it) in its review or final report.
- **The lead of a prep or raft** writes it in `.claude/skills/<the skill the lesson improves>/lessons/<slug>.md` (format: tracker skill, Items), and records where it came from in its own `harvest.md`: review findings through the harvest (ticket-prep step 5.3, execute-raft Phase 4 step 5), and anything else (a subagent's candidate, a correction by the user, a failed step) as `- note <what happened>: <lesson ids>`. It adds a note to an existing lesson when one fits, writes a new file only when none does, and commits both with its work.
- **Any other lead** (in the main checkout, a capture, or a metrics report) captures it: `./zn new issue c lesson-<slug> --project z-nile --desc "<skill>: <the rule>, because <what happened>; check: <the question>"` (make-issue skill). The prep that takes the issue writes the file.
