---
title: A prepared peer's repository-wide scan runs on the prototype before the design is called done
when: design
tags: [coordination, sequestered, scans, prototypes]
check: Which prepared or in-flight issues have a sequestered spec that scans the whole tooling or every skill (for a primitive such as mktemp, for a sentence, for a path), and has each been run on this prototype, stacked with that peer's own prototype.patch, with every red case either fixed here or a named interface?
---
A scan reads every file, so "independent in code" proves nothing about it. A design written while a peer was still a draft can add the one line the peer's finished scan forbids, and no member's own gate shows it.

**Why:** c0189's install called `mktemp` (design review 003 F4 had added it, correctly, for a unique name). c0194, prepared later, sequestered a scan of the tooling for `mktemp`; R0070's coherence review (F2) found c0194's `callers.spec` red on c0189's line, and the raft had to unfold c0189 for a re-prep. The same review found c0189's pinned prototype rule sending a clone "into $TMPDIR or the scratchpad" against c0194's decided `.cache/.tmp/` (F1): both pins passed, the combined text contradicted itself.

**How to apply:** `git worktree list` and `ls .tracker/issues/*/acceptance` for every prepared peer; apply this prototype and each peer's `experiments/prototype.patch` in one scratch clone (`git apply --3way`, keep both sides of a text conflict) and run the peers' scans and doc specs there. Read the merged paragraph against each peer's captured Problem, not only against the pins. Prefer removing the flagged primitive (here, by teaching the shared helper an option) to an allow-list entry in a peer's sequestered spec.
