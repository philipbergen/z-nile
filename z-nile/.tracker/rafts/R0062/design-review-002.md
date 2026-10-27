# Review 002: R0062 (design mode, raft)
Inputs: raft-check-guards-regroup 00308711 (R0062.md against origin/main ac0be3b8; c0139 and c0141 on origin/main; 9f9a6ea3; design-review-001.md, design-refute-001.md)
Grouped: [c0139@34e640a5a104, c0141@dd1005f1e817]

Checked, with no finding:
- What changed in c0141 since the old record: `git diff 2bd65f50^..origin/main -- z-nile/.tracker/issues/c0141` is 9f9a6ea3's needle-from-parts edit to `acceptance/uses-module.spec.luau`, its Verification-log line, and `raft: R0062` (left out of the hash). `git diff 9f9a6ea3 origin/main` over both member folders shows only `raft:` lines and `spend.md`, which the record leaves out. So origin/main's c0141 is the text round 001 ran: the needle passed 1/1 against the prototype and still killed the `./checkpathz` mutant. No Touched path, interface, order input or criterion changed; c0139 changed only by its `raft:` line.
- Round 001 said 9f9a6ea3 "landed before ec4fb379 grouped c0141, so the `grouped:` hash covers it". That was wrong: `new raft` hashes origin/main, which didn't have the edit yet. This round's record fixes it, and round 001's conclusions about the spec's behaviour still hold.
- The record: I ran `raftplan.recordHash` over each folder's files, read with `git ls-tree`/`git show` the way `originFolderFiles` reads them. It gives c0139 `34e640a5a104` at origin/main, 2bd65f50^, 9f9a6ea3^ and 9f9a6ea3, and c0141 `6ee8bd7fadad` at 2bd65f50^ and 9f9a6ea3^ but `dd1005f1e817` at 9f9a6ea3 and origin/main. The new `grouped:` matches origin/main. It's the branch's only change (`git diff origin/main..HEAD`: one line in R0062.md).
- Theme, Whole-raft design, Order, exit criteria and Risks still hold for the members as they are on origin/main. The Risks line "fixed before rafting" is accurate. Neither c0141's folder nor R0062's folder has a conflict marker at the start of a line.

Verdict: approve
