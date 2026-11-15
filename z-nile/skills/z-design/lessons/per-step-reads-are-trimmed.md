---
title: A read a rule runs at every step names its trimmed form
when: design
tags: [cost, commands, github]
check: What does this per-step read (before every push, report or commit) print on the busiest real case, and is it trimmed to what the rule decides on?
---
A rule that makes an agent run a read before every push or report pays the read's whole output into the agent's context each time, and a dispatched step is killed when it passes `max_tokens`.

**Why:** c0271 design review 001 F5: the first draft's `gh pr view <n> --json state,comments` printed 13 to 35 KB on busy PRs (#49, #66, #329), once per push; a `--jq` filter that keeps the state, the head and the two newest comments printed 1 to 2.7 KB.

**How to apply:** measure the read on the busiest real case, and name in the rule a filter (`--jq`, a field list, a tail) that keeps only what the rule decides on.
