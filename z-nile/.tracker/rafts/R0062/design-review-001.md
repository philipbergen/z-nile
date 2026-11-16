# Review 001: R0062 (design mode, raft)
Inputs: raft-check-guards fb759af9 (R0062.md, R0062 check.sh; c0139 and c0141 documents, check.sh and acceptance; the rafting commits 9f9a6ea3, ec4fb379, fb759af9 against origin/main)
Grouped: [c0139@34e640a5a104, c0141@6ee8bd7fadad]

Checked, with no finding:
- No shared Touched path: c0139's list (`z-nile/engine/{conflicts,main,audit}.luau`, c0115's two experiment scripts, `z-nile/tests/tooling/repo-fence.spec.luau`, `z-nile/tests/acceptance/c0139`) and c0141's (`z-nile/tests/acceptance/c0120/{checkpaths.luau,check-paths.spec.luau}`, `z-nile/skills/z-design/SKILL.md`, `z-nile/tests/acceptance/c0141`) are disjoint. Only c0139 adds repo-fence `ALLOWED` entries; c0141's module names no git variable (`git show 46f7d115:z-nile/tests/acceptance/c0120/checkpaths.luau | grep -nE 'GIT_|<<<<<<<'`: no hits).
- check-paths over c0139's check.sh: no c0141 prototype base holds c0139's prep (`git merge-base --is-ancestor b5b33a42 46f7d115`: no), so the raft's claim that c0139's check.sh passes c0141's rule had not been run. I ran it. I exported HEAD to a scratch repository and overlaid 46f7d115's `checkpaths.luau` and `check-paths.spec.luau`, then ran `lune run tests/run -- tests/acceptance/c0120/check-paths.spec.luau` from `z-nile/`, and got `4 passed, 0 failed`, with the live scan over both members' check.sh files. c0139's literal `tests/acceptance/c0139` folds to `z-nile/tests/acceptance/c0139`, which its Touched list names (all entries start with `z-nile/`, so they are read from the top).
- Audit and refusal scope: c0139's conflict-marker scan reads root and skills folders. Neither member's folder, R0062's folder or c0141's skill edit has a marker at a line start: `grep -rnE '^(<<<<<<<|>>>>>>>|=======)'` over the three folders gives no hits.
- 9f9a6ea3's edit to c0141's `uses-module.spec.luau` builds the same needle (`"req" .. "uire" .. '("./checkpaths")'`). Against the prototype it passes 1/1 and `touched-from-home.spec` passes 4/4. With the spec's require renamed to `./checkpathz` it fails (`expected true, got false`), so it still kills that mutant. It landed before `ec4fb379` grouped c0141, so the `grouped:` hash covers it.
- Order and exit criteria: neither member depends on the other, and RC0 runs both members' check.sh files, the full z-nile gate and promote-check. No raft-level RC is needed for disjoint surfaces.

### F1 [low] The Order cites c0160 as a reason, but c0160's record has no dependency on c0141
Where: R0062.md, Order & dependencies, item 1
Evidence: c0160.md has `depends_on: []`, `raft: ` (empty) and `design: draft`. Both members land in one PR, so their order inside the raft can't affect when c0160 can start. Separately, "both check.sh files already pass … c0141's prototype rule" was not backed by a recorded run (see above).
Critique: An agent executing the raft reads the reason as a constraint that doesn't exist. The real reason, landing the check-paths fix before c0139's new paths are scanned, is in the closing sentence.
Consequences: none.
Recommendation: Say that c0160's prep will depend on c0141, or drop the reason. Record this review's run as the evidence that c0139's check.sh passes c0141's rule on fb759af9.

Verdict: approve
