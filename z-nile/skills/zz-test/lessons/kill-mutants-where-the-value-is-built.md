---
title: A "comes from X" mutant is killed where the value is built, not where it is passed in
when: design
tags: [mutants, call-sites, registry]
check: For each "comes from X" rule, does some case go through the caller that reads X, rather than a function the test hands the value to?
---
A case that calls `f(value)` with the value supplied by the test proves `f` uses its parameter, not that the caller builds that parameter from the right source. A hand list in the caller then passes every spec while the Rules table claims the kill.

**Why:** c0141 design review 003 F2: "homes come from the registry" was pinned only by `owned(…, homes)` with the test's own `homes`; `scan` building `{ "pickman", "z-nile" }` by hand passed everything. A fixture item naming a third registered project, run through `scan`, killed it. The reviewer's first suggested case was itself vacuous, because the word it used (`game2/new`) isn't read as a path at all: check that the case's input reaches the rule.

**How to apply:** put the mutant in the caller ("`scan` builds homes from a hand list") and kill it with an end-to-end case through that caller; run the mutant, don't infer the kill.

c0160 design review 001 (F1): a default read "from the running checkout's registry" passed as a hand list, because every in-process case ran in a checkout whose registry equals the old list. Only a child process in a different checkout (a `git init` fixture under `.cache` with another registry) shows it. Check: does the default's source ever hold a value different from the hand list it replaces?
