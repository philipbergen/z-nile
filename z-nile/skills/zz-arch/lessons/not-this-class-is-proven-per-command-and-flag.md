---
title: "Not a ref" is proven per command and flag, not filed away
when: design
tags: [guards, sweep, scope]
check: For each command a sweep files under "not this class of write", which flag or form makes it one (`reflog … --updateref`, `stash drop`), was that form run, and does filing it as a Non-goal narrow a captured "every command" outcome without a Scope decision line?
---
A command can be outside a guarded class in one form and inside it in another. `git reflog delete` rewrites a reflog; with `--updateref` it also writes the ref, outside any transaction. `stash drop` and `pop` reach `refs/stash` the same way.

**Why:** c0195 design review 001 F5: the sweep ran `reflog delete`/`expire` without `--updateref` and `stash` only as a push, so two ref-writing routes were filed as "reflogs, not refs".

**How to apply:** for each command the sweep rules out, run its flags and subcommands that touch a ref, in a fixture that has what they act on (a stash), on every git; a route left out needs a `Scope decision (user, …)`, not a Non-goal.
