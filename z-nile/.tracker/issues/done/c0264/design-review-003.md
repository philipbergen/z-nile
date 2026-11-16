# Review 003: c0264 (design mode)
Inputs: worktree HEAD 177da861 (wip: prep c0264 round 2 answered); c0264.md, check.sh, legend.txt, acceptance/intent.spec.luau, experiments/README.draft.md, experiments/mutants.sh, design-review-001/002.md, design-refute-001/002.md, harvest.md, the lesson note added to z-design/status-labels-need-a-tracker-fact; z-nile/README.md; capture from `git show origin/capture-workers:z-nile/.tracker/issues/c0264/c0264.md`; the Problems of c0248, c0249, c0250, c0253, c0261, c0262, c0263 and c0265.
Dropped from design-review-002: F1, F2 (both fixed; see below).

Runs (PATH with `$HOME/.rokit/bin` first; README restored with `git checkout z-nile/README.md` after each; `git status --short` clean at the end):
- Problem section vs the capture (`diff` of `# c0264` .. `## Design`): identical.
- `./zn check c0264` on today's README: 1/9 (AC8 only). With the draft copied over the README: 9/9.
- `zn run --time 1500 -- experiments/mutants.sh`: all 18 mutants killed by their named criterion; the correct variant passes; README restored.
- Probe (mine): the draft with both clear-context edges turned into mermaid comments (`  %% layer -->|"raft merged: clear context"| loop`, the same for `esc`): 9/9, see F1.
- Tracker states: c0118 and c0247 `design: ready` (designed), c0117 in `done/` (exists), c0249, c0250, c0261, c0262, c0263 `design: draft` (captured). The draft agrees.
- Faithfulness: each sub-section's claims agree with its ticket's Problem (e.g. "A second off-course verdict blocks the ticket" is c0262's, "who set its rank, who rafted it" is c0263's, the Haiku/composer wait tier is c0261's).

Round 2 answers:
- F1 fixed: AC9 now greps the four edge lines; `ends-float` is killed (my run). The mechanism, a substring of the diagram block, has another hole: F1 below.
- F2 fixed: `skeleton-diagram` and `todays-diagram` are distinct mutants, and `todays-diagram` really pastes `origin/main`'s block (read in mutants.sh; killed in my run).

Scope: every Problem bullet has its sub-section, label and a criterion; nothing moved into Non-goals; every rule of the four verbatim messages is in the draft.

### F1 [medium] AC9 passes a diagram whose two raft-end edges are commented out (repeat of the mechanism in review 002 F1)
Where: check.sh `pictured` / AC9 (lines 94-95, 122-124).
Evidence: the probe above: both `layer -->|"raft merged: clear context"| loop` and `esc -->|"raft released: clear context"| loop` prefixed with `%% ` (mermaid comments, not drawn): `./zn check c0264` 9/9. The rendered diagram then has no way back from a finished or released raft to claiming, the outcome AC9 names. `grep -qF` also matches `stack --> loop` inside `stack --> loopX` or inside a node's label text.
Critique: round 2 found that words need not be edges; this round finds that edge text need not be an edge. Each fix pins one more substring and leaves the next spelling open. The tempting fix (exclude `%%` lines) closes this spelling only.
Consequences: the Design already fixes the node ids and implementation step 1 copies the draft's block as written, so the diagram has no legitimate freedom at delivery: no state label lives in it and AC7 never relabels it. Pinning it whole costs nothing at delivery; after `done` check.sh no longer runs, so later diagram changes are free.
Recommendation: question the mechanism: pin the mermaid block of How it should work word for word, as legend.txt pins the legend: a sequestered `diagram.txt` (the draft's block), and AC9 compares `diagram()` with it exactly (`diff`), keeping the words list only as the failure message if you like. Say in the Design that the diagram is reviewed text copied as is. Add the commented-edges probe to mutants.sh and E4 (killed by AC9), and keep `ends-float`, `todays-diagram` and `diagram-one-way-out`.

### F2 [medium] The draft says people act only at the idea and the design, and that rafting needs no human, yet its Order section has z-raft ask a person for rank
Where: draft, Intent bullet 1 ("Apart from resolving a block, those are the only two stages that ask a person for anything"); Autonomous delivery ("once a person has approved its design, an item is rafted, ... with no human in the loop"); Order ("z-raft asks for a raft's rank when it makes the raft, and unset is a valid answer"; the Omarchy app's drag and drop).
Evidence: three sentences of the same README: rafting is a worker step with no human, z-raft (rafting) asks for a rank, and no stage outside idea, design and blocks asks a person anything. A reader cannot tell who answers z-raft's question or whether a headless raft stops for it. Both rules are the user's (message 1: "move all human interaction up to the idea and design stages"; message 2: "when making rafts we should ask for rank, unset is valid"), so the README must reconcile them rather than state both flatly. Round 1 F2 was the same kind of contradiction (Autonomous delivery vs Intent).
Critique: a README whose job is to state the intent contradicts itself on where people act; c0249's and c0252's designs will each quote the half that suits them. The tempting fix, deleting "z-raft asks" or "only two stages", drops one of the user's rules.
Consequences: the reconciliation the user's own words allow: ranking is optional ("unset is valid"), so asking never blocks a worker. Stating that is a small interpretation, which c0249's design settles; the README should say it is open, not decide it.
Recommendation: in Intent bullet 1, except ordering the work too ("Apart from resolving a block and, optionally, ranking the work, ..."); in Order, say that z-raft asks for a rank when a person is present, that unset is valid so a raft made with no person goes on unset, and that c0249 settles it. Add the new words to AC6's list and a mutant that drops them (killed by AC6). If the author reads the user's words differently, escalate to the user: (a) rank is asked only of a person making a raft by hand, (b) rafting is moved to the engineer end, which changes Autonomous delivery and the diagram.

Verdict: changes
