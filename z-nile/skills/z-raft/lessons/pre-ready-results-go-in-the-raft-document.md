---
title: A result owed before ready is written in the raft document, not a member's
when: design
tags: [raft, experiments, grouped, ready]
check: Does every experiment a member's design says runs before `ready` name who runs it and where its result is written, and is that place outside the grouped record (the raft document, not the member's)?
---
A raft records a hash of each member's design when it groups it. Any later edit to a member's document, a result line included, changes that hash, and `./zn ready` refuses the raft until the member is folded again and the coherence review rerun.

**Why:** R0094 design review 002 F2. f0148's live-place experiments (E6, E5) must run before `ready`; once f0148 was stacked into R0094 they held all four members, with nobody named to run them, no result and no fallback, and writing the result into f0148.md would have made `ready` refuse.

**How to apply:** in the raft document, name the person who runs each such experiment, put its result line under `## Experiments phase`, and state the fallback (usually `./zn unfold <R-id> <id>` and back to z-design when the member's own fallback changes a value its sequestered spec pins). Say which other members now wait on it.
