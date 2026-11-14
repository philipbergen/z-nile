# Review 002: c0264 (design mode)
Inputs: worktree HEAD d1c8363b (wip: prep c0264 round 1 answered); c0264.md, check.sh, legend.txt, acceptance/intent.spec.luau, experiments/README.draft.md, experiments/mutants.sh, design-review-001.md, design-refute-001.md, harvest.md, the z-design/status-labels-need-a-tracker-fact lesson note; z-nile/README.md; capture from `git show origin/capture-workers:z-nile/.tracker/issues/c0264/c0264.md`.
Dropped from design-review-001: F1, F2, F3, F4, F5, F6 (all fixed; see below).

Runs (PATH with `$HOME/.rokit/bin` first; README restored with `git checkout z-nile/README.md` after each; `git status --short` clean at the end):
- Problem section vs the capture (`diff` of `# c0264` .. `## Design`): identical.
- `./zn check c0264` on today's README: 1/9 (AC8 only; AC9 "diagram lacks: interview", so today's diagram is killed). With the draft copied over the README: 9/9.
- `zn run --time 1200 -- bash experiments/mutants.sh`: 16 killed, the correct variant passes; README restored, tree clean.
- Probe (mine): the draft with both "clear context" edges deleted and their words put in a floating node `note["raft merged: clear context; raft released: clear context"]`: 9/9, see F1.
- Tracker facts behind the `exists` labels: `./zn find c0117` is `done/c0117`; `.models.toml`, `z-nile/engine/dispatcher.luau`, `credential.luau` and quota outcomes in `adapters.luau` exist. `git worktree list`: no other prep worktree is open. c0247's and c0118's designs edit only the skills table row, The flow step 1, the opening picture and The five parts, all outside the two sections AC8 frees.

Round 1 answers:
- F1 fixed: AC9 now exists and kills today's diagram (my run of today's README). Its mechanism (words anywhere in the block) has a hole of its own: F1 below.
- F2 fixed: Autonomous delivery starts after the design approval; `grep -n -i 'no human\|human in the loop'` on the draft finds only that sentence; AC6 pins it; mutant killed.
- F3 fixed: The worker now says it never orchestrates on an expensive model and waits on the wait tier.
- F4 fixed: AC5 checks the parts in one bullet; the split mutant dies; the user-words variant passes (run).
- F5 fixed: "c0248 to c0254, c0260 to c0263 and c0265".
- F6 fixed: INT/TERM trap and the bounded run recorded.

Faithfulness and scope: every rule of the user's four messages is in the draft (re-read against the capture's verbatim ask); every Problem bullet has a sub-section, label and criterion; nothing moved into Non-goals.

### F1 [medium] AC9 passes a diagram in which no raft end returns to claiming: its words need not be edges
Where: check.sh `pictured` / AC9; c0264.md AC9 ("both ways a raft ends ... each clearing the worker's context").
Evidence: draft with `layer -->|"raft merged: clear context"| loop` and `esc -->|"raft released: clear context"| loop` removed and the words put in a floating node `note[...]`: `./zn check c0264` 9/9. The diagram then shows a worker that never goes back to claim after a raft ends, the exact outcome AC9 names.
Critique: round 1 F1 found the diagram unchecked; the fix checks words, which any node can carry, so the flow (the outcome) is still unchecked. The tempting fix, more words, has the same hole.
Consequences: pinning the two edge lines constrains node ids (`layer`, `esc`, `loop`); an executor who renames a node breaks AC9, so the ids must be stated in the Design as fixed (step 1 already copies the draft verbatim, so no honest delivery differs).
Recommendation: in check.sh, check the two return edges as edges: a line of the diagram matching `-->|"raft merged: clear context"| loop` whose source is the ticket node and one matching `-->|"raft released: clear context"| loop` whose source is the escalation node (or, simpler, the two whole edge lines with `grep -qxF`), and `stack --> loop`. Say in the Design that the diagram's node ids are part of the reviewed text. Add the floating-node mutant above to mutants.sh and E4 (killed by AC9).

### F2 [low] E4's "diagram put back to today's" mutant is not today's diagram
Where: c0264.md E4 table row and Rules and mutants row "today's diagram"; mutants.sh `old-diagram` (replaces the block with two empty subgraphs).
Evidence: the runner's substitution writes `flowchart LR` with empty `eng`/`wrk` subgraphs, not the 19-line block on `main`. Today's diagram is in fact killed (my run of today's README: "diagram lacks: interview"), so the claim holds, but not by the mutant recorded.
Recommendation: either rename the row to "an empty diagram", or make the mutant paste `main`'s block (`git show origin/main:z-nile/README.md`, extract the mermaid block under How it should work) so the record and the runner agree (z-design/mutant-ids-match-the-runner).
Lesson: z-design/mutant-ids-match-the-runner

Verdict: changes
