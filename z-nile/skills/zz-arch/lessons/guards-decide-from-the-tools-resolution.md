---
title: A wrapper decides from the tool's own resolution
when: design
tags: [security, guards, wrapper]
check: Can an alias, a config key, a different spelling, an option's value or a plumbing command reach the action this guard refuses, and does the guard decide from what the tool itself resolves (a dry run) against state the guarded process can't rewrite?
---
A guard in front of a command-line tool that parses the arguments itself misses every spelling the tool accepts: aliases (`-c alias.p=push`), config refspecs (`remote.origin.push`, `push.default=matching`), DWIM short names (`heads/main`), wildcards, an option's value taken for the command (`--git-dir .git push`), and plumbing (`send-pack`). Ask the tool what it would do (`git push --dry-run --porcelain` with the same options and environment) and decide from its answer. Compare against a fresh copy of the remote's state the guarded process can't have rewritten (`git fetch <remote> +refs/heads/main:refs/<guard>/main`), never a tracking ref it owns.

**Why:** c0117 design review 001 F1: a hand-parsing git wrapper let 12 of 19 forms move `main` to a commit that adds code, and its base was the local `refs/remotes/origin/main`, which the agent could rewrite with `update-ref`. F2: a gh wrapper that matched `pr merge` as the first two words passed `gh -R o/r pr merge`, an alias and GraphQL mutations.

**How to apply:** route every invocation that could reach the action (the command word, any `-c`/`--config-env`, any alias, plumbing) to the decision; decide from the dry run; an allow-list of commands beats a deny-list of endpoints; spec one case per form, run for real in a fixture.

c0170 design review 001 F2: a tier rule judged require spellings, so `../../lib/plain` and `@Tests/lib/plain` loaded the helper past it. A rule about what a file loads judges the resolved target (the graph's own resolver), never the spelling.

c0170 design review 003 F3: the same rule judged only a spec's own requires, so a unit spec reached a helper through a fixture or a sibling module. A rule about what a file loads also judges what it reaches through the files the rule exempts.

c0170 design review 004 F1, F2: "resolved" must mean the canonical file (graph.build kept `../pickman/tests/lib/plain.luau` for a file inside the home, a second name past a `tests/lib/` prefix test), and a walk written to collect one forbidden kind re-opened the indirection for every other kind. Return every file the walk reaches and judge each by the rule for a direct load, outside files included.

c0170 design review 005 F1: on a case-insensitive disk a miscased path (`tests/Lib/plain.luau`) opened the helper while every name test missed it. A guard over file names checks them against the real listing and fails closed on a name the listing does not hold.
