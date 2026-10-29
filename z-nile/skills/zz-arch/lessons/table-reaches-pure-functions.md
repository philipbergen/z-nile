---
title: A table a pure function uses arrives as an argument
when: design
tags: [parsers, drift]
check: Does every pure function that reads this table receive it from the caller, so that its spec can pass its own table?
---

A pure function that closes over a table read at require time cannot be given a different table by its spec, so the spec ends up testing the live file. The caller that reads the file passes the parsed table in.

**Why:** A design that moved a table into a data file left the pure functions with no argument to receive it, so the only ways to satisfy the specs were a hidden read or a second copy of the table.

**How to apply:** When a table moves out of code, add it to the function's arguments and to the tree the loader returns. The spec builds a small table of its own. A case with two tables and one input must be able to disagree.
