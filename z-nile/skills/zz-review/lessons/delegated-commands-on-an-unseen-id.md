---
title: A page action that delegates to a command is judged on an id the command has never seen
when: both
tags: [actions, servers, security]
check: For each action a page or API can send, what does the delegated command do when the id has no state (no run, no folder), and is that a start, a create or a refusal?
---
A guard that refuses one action on an id with no state (stop) says nothing about the others. `./zn dispatch retry <id>` on an id it has never run creates a state and runs the item's whole headless chain: a start, from a button labelled Retry.

**Why:** R0084 (c0121) code review 001 F1 (high): the served board's Retry on a backlog ticket would have spent tokens and opened PRs; only Stop answered 409 for a card with nothing running, and sequestered specs pinned the passthrough, so the raft had to stop for a re-prep.

**How to apply:** in a design, list the actions and run each delegated command on an id with no state (in a scratch copy); give the page's plan the same refusal for every action whose command would create or start something. In a review, send each action to an id the command has never run.
