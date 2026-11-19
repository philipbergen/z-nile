---
title: Recombine before fold, and one recombine per keeper per rafting
when: design
tags: [raft, recombine, fold, claim]
check: Does the plan run every `recombine` into a keeper before any `fold` into it, and does it need more than one recombine into the same keeper (then the rest go in a later rafting PR)?
---
`./zn recombine` takes only a keeper and another raft that are `prepared` or `new`, on origin/main and here, so it refuses a keeper this checkout already claimed with `fold` or an earlier `recombine` ("is preparing: recombine takes a prepared or new raft"). `fold` accepts a raft this checkout claimed.

**Why:** R0093's regrouping (2026-11-18) folded five chores into R0093 first, then could not retire the empty orphans R0106 and R0108; the claim had to be released, the branch reset, and the recombine run first. Only one orphan could be retired in that PR.

**How to apply:** run the one `recombine` into a keeper first, then `fold`; an orphan that needs a second recombine into the same keeper is retired by a recombine-only rafting PR after the first lands (it changes no grouped record, so it needs no coherence review).
