---
title: A rule that branches on where the agent runs puts the most specific environment first and makes it exclusive
when: design
tags: [skills, instructions, headless]
check: For each CLI and mode the skill can run in (an interactive session, a CLI without the tool, a subagent, a dispatched `claude -p`, `grok -p` or `agent -p`), which branch does a literal reader take first, and does a headless run also match an earlier, more general branch ("in Claude Code", "without it")?
---
A dispatched run is also "in Claude Code" or "without the tool", so a general branch written first captures it and the specific one, written as a trailing clause, never wins. Open the sentence with the specific environment, state that it excludes the others, and pin the order.

**Why:** c0247 design review 003 F1: "under `./zn dispatch`, write it as the question in `questions.md`" came last in a sentence that began "In Claude Code, … `EnterPlanMode`", so a dispatched run would call plan mode with no user, or only print and leave no `questions.md` for the dispatcher to find.

**How to apply:** most specific first, with "on any CLI" and "never X, never Y". Pin every branch sentence and their order and adjacency in the promoted spec, and the paragraph's exact text in the issue's own check.sh: a sentence pin proves the words exist, not what "Otherwise" and "Without it" refer to in place (c0247 review 004 F1: five mutants kept every pinned sentence and changed the meaning).

c0247 design review 005 F1: pin the whole Markdown block, from the title (or the last unchanged line) through the step it gates, never one physical line: a sentence on the next line joins the same paragraph, a `<!-- -->` wrapper hides it, and step 0's tail can carry an exemption. Take unchanged neighbours from the merge base (so a raft mate's edit is not blocked), and record what the pin cannot see (a contradiction elsewhere in the file) as a `reasoned` row.
