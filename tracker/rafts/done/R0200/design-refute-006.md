# Refutations 006: R0200 (design mode)

Verdict of round 6: approve, with two low findings.

- F1: fixed: the raft-move case now first runs `status <raft> prepared` while the raft's own design is a draft and expects a refusal naming the raft and `design: ready`; a version that skips the raft's own design (`t ~= id` in the check) is killed (`run`). Consequences: none.
- F2: fixed: the spec's read-only probe now includes `stamp` (a version that guards `stamp` fails `commands :: a tracker command in a directory that lost its .git refuses ...`, `run`); the garbled Repo-root guard sentence in c0510 is rewritten.
