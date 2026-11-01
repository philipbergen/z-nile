---
title: A narrowed rule lists every way the code runs, not only the readers of its text
when: design
tags: [selection, tracing, coverage]
check: When a design narrows a forcing rule to a traced or recorded subset, which processes run this code without passing the point that records it (other programs that require it, a usage or fallback path, a probe, a copy that a script runs), and does each one either force, record, or declare?
---
A rule that replaces "any change here runs everything" with "a change here runs what the trace saw" is only as complete as the trace. Code also runs through entry points that never pass the tracing point: another program that requires the module, the command's own usage path, a copy of the tree that a gate runs. An audit of who reads the code as text misses all of them.

**Why:** c0180 design review 001 F1: the selector stopped forcing z-nile's run for engine changes and relied on a trace written by the CLI's dispatch. `z-nile/affected.luau` and `z-nile/roots.luau` require `engine/projects.luau` directly (the gate and the stop hook run them), and `./zn` with no command ran the usage path without tracing; a mutant in `projects.luau` turned `c0120/graph-homes` red while no recorded command selected it. The audit had searched for readers and copiers only.

**How to apply:** search for every way the code executes: `require` of the module from outside its folder, `lune run` and script entry points, usage and error paths before the tracing point, and specs that run a gate or a probe in a copy. Make each one force (a program rule), record (a reserved name), or declare its inputs, and add a case where that path alone changes.

c0180 design review 003 F1: the hand-built graph of `select.spec` had the edge the real graph lacked (a forwarder in `scripts/tracker/` was no graph root, so 40 specs' closures stopped there). When selection relies on a spec's own closure, run `graph.closure` on a real spec of each kind (direct require, forwarder, alias) and fail closed on an edge into a file the graph never built.
