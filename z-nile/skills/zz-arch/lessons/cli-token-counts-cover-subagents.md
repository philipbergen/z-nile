---
title: A new CLI's token count covers its subagents and side calls
when: design
tags: [cli, spend, tokens, caps]
check: For a new agent CLI, does the token count (and the `max_tokens` cap that reads it) include the CLI's subagent or child sessions and its side calls (a title call, a summary), or only the top session the stream prints?
---
An agent CLI can run work outside the session its stream reports: subagents in child sessions, a title or summary call. A count read from that one session under-reports the step, and a cap on it cannot stop a step whose cost sits in the children.

**Why:** c0175 design review 001 F1 (2026-11-15). `opencode run` prints only its own session, so `task` subagents and the per-session title call were missed. `opencode export` read only that session too. Whether agy's `invoke_subagent` usage reaches its stream had not been probed.

**How to apply:** probe the CLI with a prompt that starts a subagent, then compare the stream's count with the store's whole session tree. Read the tree when the stream misses it, and say how the cap behaves for what it cannot see live.
