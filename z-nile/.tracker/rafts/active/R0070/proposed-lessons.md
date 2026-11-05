# Proposed lessons (R0070, raft coherence review 001)
The rafting lead was a subagent and does not write lesson files; texts for the lead to write under `z-nile/skills/z-raft/lessons/`.

## z-raft/merged-text-read-against-captures
```
---
title: Two pinned sentences that both pass can still contradict each other
when: design
tags: [raft, pins, captures]
from: R0070 design review 001 F1
check: Does the merged paragraph deliver every member's captured outcome, or does it only satisfy both pins?
---
Specs pin fragments, so two members' fragments can stand side by side in a paragraph that contradicts itself.

**Why:** R0070 design review 001 F1: c0189's pinned prototype rule sent a clone "into `$TMPDIR` or the scratchpad" beside c0194's "under `.cache/.tmp/`, never the system temp folder"; every pin passed and c0194's captured outcome was dropped.

**How to apply:** after the specs pass on the combined text, read the combined paragraph against each member's captured Problem.
```

## z-raft/run-sequestered-specs-on-all-prototypes-together
```
---
title: Members' sequestered specs run on all members' prototype patches together
when: design
tags: [raft, specs, scans, prototype]
from: R0070 design review 001 F2, F7
check: Has each member's whole acceptance set (repository-wide scans and allow-lists above all) run on a tree with every member's prototype patch applied, and is each red case a declared Override or a named interface?
---
"Independent in code" is a claim about modules, but a scan reads every file.

**Why:** R0070 design review 001 F2: c0194's `callers.spec` scan flagged the `mktemp` in c0189's code once both prototypes were applied; neither design nor the raft listed it.

**How to apply:** apply the members' `prototype.patch` files to a scratch clone (under `.cache/.tmp` once c0194 lands), run every member's acceptance set, and write the interfaces the reds name.
```
