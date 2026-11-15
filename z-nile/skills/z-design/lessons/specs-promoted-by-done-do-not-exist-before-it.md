---
title: A check.sh that names another member's promoted spec path fails until done promotes it
when: design
tags: [check, promotion, stack, layers]
check: Does any member's check.sh run a spec under tests/acceptance/<other id>/ that exists only after ./zn done promotes it, and was the check run both with the specs sequestered and with them promoted?
---
A layer's check runs on the layer's tree, where an earlier member's specs are still in its issue folder. A path under `tests/acceptance/<id>/` does not exist until the whole raft is done, so the layer cannot finish and `done` fails before it merges and promotes.

**Why:** R0099 design review 002 F1: c0283's re-prep added `tests/acceptance/c0263/provenance.spec.luau` and `publish.spec.luau` to its AC5; the prototype stack carried promoted copies of every member's specs, so the check passed there and fails on the real branch ("could not resolve child component c0263").

**How to apply:** resolve another member's spec as `$PWD/$(zn find <id>)/acceptance/…` with a fallback to `tests/acceptance/<id>/…`, and run the check on a tree with the specs sequestered and on one with them promoted; a prototype stack that promotes specs hides the defect.
