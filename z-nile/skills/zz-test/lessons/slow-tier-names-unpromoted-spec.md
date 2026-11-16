---
title: A slow-tier row may name a spec that done has not promoted yet
when: build
tags: [slow, acceptance, promotion]
check: When slow.tsv names tests/acceptance/<id>/<file> and that path is not in the tree yet, does the manifest spec accept the same file in the issue's sequestered acceptance folder, and is the pinned row count updated?
---
`z-nile/tests/slow.tsv` names the path a spec has after `./zn done` promotes it, so the default and full gates skip it. `./zn finish` runs the manifest spec before that move.

**Why:** c0193's finish failed `tests/tooling/slow-tier.spec.luau` after the promoted `finishes.spec` and `scanners.spec` were added: both files still lived under the issue's `acceptance/` folder, so the existence check was false. The sequestered specs and `check.sh` stay unedited.

**How to apply:** add the promoted path, one line in the existing `<seconds><tab><path>` form. Teach the manifest spec to accept that file or the same name under the issue's active, backlog or done acceptance folder, and update the pinned count in the same commit.
