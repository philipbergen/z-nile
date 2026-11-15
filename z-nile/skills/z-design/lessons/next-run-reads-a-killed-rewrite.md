---
title: The next run of a command reads the state a kill left, with no hand repair
when: design
tags: [git, rebase, interruption, specs]
check: For every state a kill can leave this rewrite in (the branch moved and origin not, or the reverse), what does the next run of the same command read from it, and does a spec run that next command with no hand repair? Does any ahead/behind test read a half-finished rewrite as divergence, when a rewritten commit is never an ancestor or a descendant of the one it replaces?
---
A design that promises "a kill leaves no ref on a bad state" has to say what the next run does with the state it does leave. A rewrite (a rebase, an amend, a squash) makes commits that are neither ancestors nor descendants of the ones they replace, so a test built on ancestry ("local is ahead of origin, push it") reads a branch moved before its push as diverged from origin, and the advice a divergence refusal gives (`git pull --rebase`) then copies the base's commits into the layer.

**Why:** c0300 design review 001 F1: restack moved the branch to the rebuilt layer, ran the check, then pushed; a kill during the check left the branch rebuilt and origin old. The design said "the next restack sees local ahead of origin and pushes it"; in fact it refused the layer as diverged, and following the refusal polluted origin. The spec put the branch back by hand before its next case, so it never ran the next restack.

**How to apply:** list each state a kill can leave, and give each one a spec case whose next step is the same command with no repair in between. Decide "same layer on two bases" from the commits each copy holds (subjects and changes), not from ancestry, and finish the interrupted step (the push) when the copy is already where it belongs.
