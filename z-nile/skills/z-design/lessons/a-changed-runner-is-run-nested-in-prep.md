---
title: A change to how the net or a gate runs is tried with a spec nested inside it
when: design
tags: [net, gate, environment, prototype]
check: Which promoted specs run this command nested in a fixture, and what do they inherit from the outer run (a variable, a marker path outside `.cache`, a process the reaper sees)?
---
A command that starts the suite (the net, a gate, the runner) is also run by specs inside that suite, in fixtures. State the outer run passes down by the environment reaches every one of them. No gate shows this except one that runs inside the changed command.

**Why:** d0383's first prototype (2026-11-19) passed the kick's ready-marker path to the net in an environment variable. Every spec in the net's suite inherited it, and `c0278/readers.spec`, which runs a nested `./zn watch-net`, then wrote the outer kick's marker and failed in the jail: the net's first real run would have pushed a false repair to main (design review 001 F1). The same review found the detached net is an orphan the reaper stops (F2) and that the prototype's new `while` loop failed the two loop scans, which `--affected` does not select (F4).

**How to apply:** Pass such state as a flag, never an inherited variable (zz-test/runner-knobs-are-flags). In prep, run one promoted spec that nests the changed command inside a fixture started the new way, and run `./zn reap --dry-run` beside a detached helper. A prototype that adds a loop runs `tests/acceptance/c0193/tree.spec.luau` and `tests/meta/scanning-loops.spec.luau` by name.
