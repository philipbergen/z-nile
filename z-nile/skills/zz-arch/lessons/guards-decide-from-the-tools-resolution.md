---
title: A wrapper decides from the tool's own resolution
when: design
tags: [security, guards, wrapper]
check: Can an alias, a config key, a different spelling, an option's value or a plumbing command reach the action this guard refuses, and does the guard decide from what the tool itself resolves (a dry run) against state the guarded process can't rewrite?
---
A guard in front of a command-line tool that parses the arguments itself misses every spelling the tool accepts: aliases (`-c alias.p=push`), config refspecs (`remote.origin.push`, `push.default=matching`), DWIM short names (`heads/main`), wildcards, an option's value taken for the command (`--git-dir .git push`), and plumbing (`send-pack`). Ask the tool what it would do (`git push --dry-run --porcelain` with the same options and environment) and decide from its answer. Compare against a fresh copy of the remote's state the guarded process can't have rewritten (`git fetch <remote> +refs/heads/main:refs/<guard>/main`), never a tracking ref it owns.

**Why:** c0117 design review 001 F1: a hand-parsing git wrapper let 12 of 19 forms move `main` to a commit that adds code, and its base was the local `refs/remotes/origin/main`, which the agent could rewrite with `update-ref`. F2: a gh wrapper that matched `pr merge` as the first two words passed `gh -R o/r pr merge`, an alias and GraphQL mutations.

**How to apply:** route every invocation that could reach the action (the command word, any `-c`/`--config-env`, any alias, plumbing) to the decision; decide from the dry run; an allow-list of commands beats a deny-list of endpoints; spec one case per form, run for real in a fixture.
