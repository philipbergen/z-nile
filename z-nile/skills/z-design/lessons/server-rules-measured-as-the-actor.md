---
title: A server rule's effect is measured as the actor who will meet it, not inferred from the docs and the client's source
when: design
tags: [github, rulesets, admin, experiments, assumptions]
check: Has the rule's effect on the client that will meet it been measured as that actor (the admin, a bypass actor, the agent's token), and does the design name a fallback when it differs?
---
A rule a server enforces can look different to an actor who may bypass it: GitHub may report a ruleset-blocked pull request as mergeable to the repository admin, so a client that refuses a `BLOCKED` merge (gh's `blockedReason`) refuses nothing for that viewer. Docs and the client's source say what happens to someone; only a run as the actor says what happens to them.

**Why:** c0359's design rested "a hand merge is blocked while `static` fails" on gh's source and GitHub's docs, while every hand merge here runs with the admin's credential, the ruleset's one bypass actor; the 2026-11-15 incident's 28 merges were made that way. Its review found no experiment asked the question.

**How to apply:** make it a Phase-1 experiment run as that actor (read-only where possible: a scratch pull request and `gh pr view --json mergeStateStatus`), give it a fallback that goes to the user when the outcome depends on it, and make the rule itself not depend on the viewer where it can (`gh pr checks <pr> --required` reads the required checks, not the viewer's merge state).
