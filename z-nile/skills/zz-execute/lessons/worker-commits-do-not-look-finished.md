---
title: A layer's worker commits do not start with "<issue>: " while it is unfinished
when: build
tags: [layers, restack, commits]
check: Is the subject of the newest commit on this unfinished layer "<issue>: …"? Then a restack reads it as the finish commit and rebases it alone: has the layer been synced (a merge of origin/main) instead, or is the subject "R<raft>: …"?
---
`./zn restack` treats a tip whose subject starts with `<issue>: ` as the layer's finish commit and rebases only that commit. Phase 2 step 3 names worker commits `<issue>: <what>`, so an unfinished layer whose newest commit is a worker commit is restacked as if it were finished: the rebase drops its other commits and conflicts.

**Why:** R0125, 2026-11-17: `./zn finish c0202` refused because main had moved, and `./zn restack R0125` then rebased only the tip `c0202: verification log` and stopped on a conflict. The layer also had no `tracker: start` commit, since its stale first build had been reset to origin/main. `./zn sync` (a merge) made the layer current and finish went on. The restack rule itself is a tooling defect, reported to the lead.

**How to apply:** before a layer's finish, bring it up to main with `./zn sync`, not `./zn restack`; restack a layer only after it is finished. Name worker commits on an unfinished layer `R<raft>: …` (or anything not starting with the issue id and a colon). After resetting a stale layer branch to main, keep a `tracker: start` commit on it.
