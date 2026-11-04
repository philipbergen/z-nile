---
title: A raft's Order or Risks claim of "no code changes" or "only X changes" is pinned by an RC line
when: design
tags: [raft, rc, claims]
from: R0078 design review 001 F3, R0070 design review 001 F4
check: Does each factual claim the raft makes about what execution changes or proves have an RCn line that fails when the claim is false, and does that RC print something other than "nothing to judge" on the raft's own branch?
---
A claim no check backs is drift waiting to happen.

**Why:** R0078 F3: "no code is written" was backed by no check; R0070 F4: an RC whose empty state passed proved nothing.

**How to apply:** add an RC that diffs against the merge base for "only X changes"; run each RC on the raft's own branch and read what it prints.
