---
title: A rule wired in several places gets one mutant per place
when: design
tags: [mutants, wiring, specs]
check: For a parameter, setting or reader that the design threads through N call sites (a directory, a head, a flag), is there a mutant that drops it at each one, and does a spec case compare an output that depends on each site?
---
A mutant that drops the setting everywhere dies at the first site any case touches and says nothing about the rest: a spec that never reads the fourth site passes with it wrong.

**Why:** c0284 design review 001 F5: `dir` was threaded through five functions (`who.head`, `people`, `fronts`, `sideTrailers`, `trail.cuts`); mutant M7 replaced the board's argument once, and the reviewer's mutants "people read in the folder `./zn` runs in" and "the board reads HEAD" both survived, because the fixture's worktree never had unpublished commits and the cases compared three of eight items.

**How to apply:** list the sites, write one mutant for each, and give the fixture a state in which each wrong site changes an output (an unpublished commit in the worktree, a co-author who is a person); compare every item of the fixture, not a sample.
