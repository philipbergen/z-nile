---
title: A raft's interface section names every prep that writes a file it takes from a dependency
when: design
tags: [raft, interfaces, dependencies]
from: R0072 design review 001 F1, F3
check: For each path in "From <dependency>", does a search of the non-done issue documents name another item that creates or changes it, and does the raft say what it needs from the file and what happens if the other writer lands first?
---
A raft that takes an interface from its dependency also takes whatever else lands on the same file before it runs.

**Why:** R0072 design review 001 F1: the first draft listed `z-nile/lib/bounded.pl` as c0191's, while c0181 (R0074) records that it writes the same path with another contract, and its landing order against R0072 was free.

**How to apply:** `git grep -l '<path>' -- '*/.tracker/**/*.md'` for each path; list the properties the raft's specs rely on and the stop-and-report rule when the landed file lacks one.
