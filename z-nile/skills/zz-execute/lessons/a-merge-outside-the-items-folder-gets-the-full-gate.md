---
title: A merge that touches anything outside a ticket's folder gets the full gate first
when: build
tags: [merge, gate, documents]
check: Does this merge touch anything outside the ticket's own folder, documents included, and if so has the full gate run on it before the merge, not only the specs named for it?
from: merges of #721 and #707, 2026-11-21 (fixed by #731)
---
Specs pin document structure and scan every file, so a document edit can break specs no one named.

**Why:** 2026-11-21: `README.md` gained a paragraph before its diagram in #721, merged on six named specs, and main was red until #731. The same day #707 was merged on the affected gate and broke three scan-every-file specs.

**How to apply:** list the changed paths; any outside `<root>/issues/<id>/` means one full gate on the PR head before merging, whatever the PR changes.
