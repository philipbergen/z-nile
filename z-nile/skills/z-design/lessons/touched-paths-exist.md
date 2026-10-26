---
title: Touched modules are repository-relative paths that exist, re-spelled when the layout moves
when: design
tags: [touched, layout, paths]
check: Does every Touched modules path, or its parent folder, exist at the branch's tree (repository-relative, not relative to a project's home), and does the list name every folder the implementation changes?
---
Touched modules is read by machines: raft-plan's overlap and spend's line attribution match it by repository-relative prefix. A path in an old layout's form matches nothing, so two issues touching the same file show no overlap, and the item's own lines go unattributed.

**Why:** c0117 design review 006 F6: after c0115 moved the tooling's tests into `z-nile/tests/`, c0117's list still said `tests/lib/fakecli.luau` and five more `tests/…` paths (none exists), and it left out `z-nile/skills/zz-execute`, which the implementation changes. c0116's list has the same old form.

**How to apply:** after a layout move lands, re-spell every live design's Touched paths in the new form; before review, check each path or its parent exists on the branch and diff the list against the implementation's changed folders (`git diff --name-only <base>...HEAD`).
