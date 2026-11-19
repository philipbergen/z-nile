---
title: A sequestered spec finds its sibling files from its own path
when: design
tags: [acceptance, sequestration, paths]
check: Does every file a sequestered spec loads from its own folder (a node test, a fixture, a data file) resolve from the backlog folder, from active/ and after promotion, and was it run from a copy at the active path?
---
`./zn ready` moves an item to `active/` and rewrites only the literal paths in `check.sh`; every other file is unchanged. A spec that builds its sibling's path from the backlog folder and the promoted folder alone fails for the whole execution, and the executor cannot edit it.

**Why:** c0257 design review 001 F1: `rules.spec.luau` tried `issues/c0257/acceptance/rules.test.mjs` and `tests/acceptance/c0257/rules.test.mjs`, so from ready until `./zn done` the node run got a missing file and AC3 stayed red. Prep's own proof passed because the item was still in the backlog folder.

**How to apply:** take the folder from the spec's own path (`string.match(debug.info(1, "s"), "^(.*)/[^/]+$")`, as `tests/run.luau` does), and in prep run the spec from a copy of the acceptance folder placed under `issues/active/<id>/acceptance/`.
