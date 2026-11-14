---
title: A fixture that re-finishes or restacks a layer reviews it again
when: build
tags: [fixtures, stack, review, restack]
check: Does every fixture that commits a layer review and then re-finishes or restacks that layer commit a new review (or a refute naming the new commit) before the next `start` or `done`, since the rewrite changes the finish commit the review's `Commit:` names?
---
A layer's review names the finish commit it reviewed. `./zn finish` squashes and `./zn restack` rebases, so either one gives the layer a new finish commit, and the earlier review is stale even though its file is still in the tree.

**Why:** c0248 prep (2026-11-12): the prototype's fixtures that finished, reviewed, then restacked failed `start` with a stale review until they reviewed again after the rebase.

**How to apply:** in a fixture, put the review step after the last finish or restack of that layer, or answer it in a refute that names the new commit.
