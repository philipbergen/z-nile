---
title: A guard's "would start itself" case must loop by exec in one process, never by fork
when: design
tags: [guards, specs, processes]
check: Under each mutant of this guard's self-start test, does every iteration of the loop add a live process (a `$( … )` or a pipe around the re-entry), and does the case make the loop an `exec` in one process an alarm can end?
---
A wrapper whose real git can resolve to itself recurses. If the wrapper asks git a question inside `$( … )` before it acts, each level forks and waits, so the chain is alive all at once and an alarm on the first pid does not end it.

**Why:** c0195 design review 001 F6: `closed.spec`'s case ran the fence's git with itself as its real git and no builtin list, so its mutants (no `-ef "$0"` test) forked a chain that plausibly exhausted the user's per-user process limit.

**How to apply:** make the case use a command the wrapper execs at once (list it in the builtin variable), so the mutant is a one-process `exec` loop that an `alarm` ends; add a depth marker the wrapper sets only for its own question and refuses on; never run a mutation rerun of such a case unbounded.
