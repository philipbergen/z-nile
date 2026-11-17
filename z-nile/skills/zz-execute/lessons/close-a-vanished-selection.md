---
title: A selection the design relied on that is gone is closed before finish
when: both
tags: [affected, selection, watch, deviations]
check: For every source this layer made a promoted spec depend on, does `lune run z-nile/affected -- <it>` list that spec today, and where it does not, did the layer add the selector (a tooling spec with its own watch) instead of leaning on an earlier layer's gate?
---
A design written weeks earlier can rest on a selection the gate no longer makes (a path that used to force `ALL`, a watch another raft rewrote). An executor who notices it and goes on leaves the dependency unselected: a change to the source merges green, and the specs that depend on it go red only at the full gate.

**Why:** R0068 review-001 F2 (c0156): the design said a change under `z-nile/tests/lib` selects every spec; on the day of execution it selected only c0156's own specs, and the executor logged that and finished, so c0103's and c0128's pins were unselected by a change to `pin.luau`.

**How to apply:** when a Verification log line says a selection the Design names is gone, run the selector on that source, and close it in the layer: a tooling spec with its own watch, in the spec's own project (lesson zz-test/specs-pin-only-their-own-project), and the log says which gate runs the rest.
