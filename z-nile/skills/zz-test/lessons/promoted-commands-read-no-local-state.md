---
title: A command promoted specs run at the real checkout reads no machine-local state unless asked
when: both
tags: [specs, determinism, state]
check: Does any command a promoted spec runs against the real checkout (the selector, a planner, a report) read state that differs between machines or runs (a local db, a cache, a learned table), without an explicit flag?
---
A promoted spec that runs a real CLI at the checkout's top sees whatever that CLI reads there. If the CLI reads a machine-local store by default, one learned row turns the spec red on one machine while CI stays green, and the spec's result stops being a function of the committed tree.

**Why:** c0165 design review 001 F2. `z-nile/affected` was designed to merge the gate's learned rows from the local db, and `c0120/graph-homes.spec` runs it at the real checkout. One row made that spec fail at line 157 on the prototype.

**How to apply:** make local state opt-in (`--learned`), passed only by the tool that owns that state (the gate's own selection call). The bare command, which reviewers paste and specs run, gives the committed answer. Add a case where a bare call ignores a local row and the flagged call reads it.
