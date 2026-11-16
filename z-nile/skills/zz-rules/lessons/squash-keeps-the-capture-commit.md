---
title: A squash that lands a capture keeps its capture commit
when: both
tags: [git, squash, capture, merging, scope]
from: c0285 (lesson ticket, withdrawn 2026-11-16)
check: Does the squash subject of a capture PR start with 'tracker: new' and list every id its capture commit listed? And does no later commit of that PR change those documents, or does the capture commit reach `main` whole (a merge commit)?
---
A capture reaches `main` as a commit of its own: subject `tracker: new <ids> <title>`, its tree the captured text, because `./zn capture` and z-design's scope check read both. `./zn land` keeps it; a capture that rides in a pull request must keep it at the merge.

**Why:** PR #258 carried 2e282833 (`tracker: new c0260 … c0257 …`) and was squashed as `tracker: capture workers carry rafts to merge …`, so `./zn capture` gave c0260, c0261 and c0264 their one-line stubs and c0263 and c0265 their first add, and their preps checked scope against the wrong text. PRs #57, #178, #265 and #317 lost theirs the same way: 5 of the 26 merged PRs that carried a capture commit (2026-11-15).

**How to apply:** before `gh pr merge --squash`, list the PR's `tracker: new` commits. If no later commit changes their item documents (a spend commit changes none), squash with `--subject "tracker: new <every id they list> <title> (#<pr>)"`. If one does, a squash shows the later text: land the PR with `gh pr merge --merge`. Then `./zn capture <id>` names the capture commit, with no marker.
