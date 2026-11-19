---
title: A line that records a user decision quotes the user's own words
when: design
tags: [authority, decisions, scope, agents]
check: For every line a command writes as a user decision (Decided, Scope decision, Ruled), which argument supplies its words when an agent runs the command, and is it the user's quoted message rather than text the agent typed? And can an unattended session reach that command at all?
---
Decided, Scope decision and Ruled lines carry scope and authority. If an agent's own argument becomes the quoted decision, the record says the user decided what the agent wrote, and an unattended worker can unblock itself.

**Why:** c0250 design review 001 F5 and F12: `resolve approve` quoted the agent's `--answer` in the Decided line while the user's words sat only in the note, and only `ZN_DISPATCH` marked a headless session, so an unattended z-work session could resolve its own block.

**How to apply:** take the words from the argument that carries the user's message (`--said`) and name the option beside them; refuse every headless marker and a resolve from the session that filed the block; say in the skills when an agent may run the command.

**Note (d0415 design review 001 F2):** a criterion that names a different report from the captured sentence (`dispatch status` for "a later `./zn` spend report") is a smaller outcome with no ruling. Put the captured words in the criterion and make the command they name show the result.
