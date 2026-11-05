---
title: A project-selecting hook or wrapper asks the selector's forcing rules
when: both
tags: [selection, gates, hooks]
check: For each path class the selector forces (all projects, one project's tooling, old roots), which projects does this caller gate, and does it get the union from the same selector function rather than its own path table?
---
A hook that maps path prefixes to projects duplicates rules it does not own. Shared harness changes can force every project and old roots can force the tooling project, even when their path prefix suggests another home.

**Why:** c0165 design review 004 F1: a stop hook mapped `z-nile/lib/` to z-nile alone although the selector forces every project, and mapped old roots to pickman although they force z-nile's old-roots check. Its spec pinned both wrong mappings.

**How to apply:** expose a selector helper that returns the path homes plus every project its forcing rules name, in registry order. Call it from the hook and make one gate invocation with all returned projects; pin shared, tooling, old-root, combined-project and failure cases.
