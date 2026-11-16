---
title: A raft's interface section names every prep that writes a file it takes from a dependency
when: design
tags: [raft, interfaces, dependencies]
from: R0072 design review 001 F1, F3
check: For each shared path and each unlanded record a member relies on, does a search of the non-done issue documents (not only Touched bullets) name every other writer, and does the raft list the properties it needs and what happens if that writer lands a different file?
---
A raft that takes an interface from its dependency also takes whatever else lands on the same file before it runs.

**Why:** R0072 design review 001 F1: the first draft listed `z-nile/lib/bounded.pl` as c0191's, while c0181 (R0074) records that it writes the same path with another contract, and its landing order against R0072 was free.

**How to apply:** `git grep -l '<path>' -- '*/.tracker/**/*.md'` for each path; list the properties the raft's specs rely on and the stop-and-report rule when the landed file lacks one.

**Note** (R0110 design review 001 F3, F5): a draft has no Touched bullets yet, so the search is every non-done issue document, and the raft pastes that search. An unlanded record the raft relies on is listed property by property (fields, store names, attributes, a pass key and its lifetime), with a stop-and-report rule when the design that would be read differs. Comparing a draft capture that never held those lines is not that check.
