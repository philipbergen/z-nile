# Review 004: c0264 (design mode)
Inputs: worktree HEAD 1bfc4bab (wip: prep c0264 round 3 answered); c0264.md, check.sh, legend.txt, diagram.txt, acceptance/intent.spec.luau, experiments/README.draft.md, experiments/mutants.sh, design-review-001..003.md, design-refute-001..003.md, harvest.md, the lesson notes added to z-design/status-labels-need-a-tracker-fact; z-nile/README.md; the capture (`git show origin/capture-workers:z-nile/.tracker/issues/c0264/c0264.md`); c0247, c0261 and c0265 documents.
Dropped from design-review-003: F1, F2 (both fixed; see below).

Runs (PATH with `$HOME/.rokit/bin` first; README restored with `git checkout z-nile/README.md`; `git status --short` clean at the end):
- Problem section vs the capture (`diff` of `# c0264` .. `## Design`): identical.
- `origin/main` has not changed `z-nile/README.md` since the merge base 33156793 (`git diff <base> origin/main -- z-nile/README.md`: empty).
- `./zn check c0264` on today's README: 1/9 (AC8 only). With the draft copied over the README: 9/9.
- `zn run --time 1800 -- experiments/mutants.sh`: all 22 mutants killed by their named criterion (including `edges-commented` and `node-renamed`); the correct variant passes; README restored.
- Tracker states on `origin/main`: c0117 in `done/`; c0118 and c0247 `design: ready`; c0142, c0175, c0248..c0254, c0257, c0258, c0260..c0262 `design: draft`; c0263 and c0265 exist only on `capture-workers`, which carries c0264 itself, so they land together. The draft's labels agree.
- `git grep -l -e 'How it should work' -e 'z-nile/README.md' origin/main -- '*/.tracker/**/*.md' | grep -v /done/`: c0161 (says the README is untouched), c0118, c0121 (opening picture and board line, E3), c0193 (README untouched), c0247 (skills table row and flow step 1), c0248..c0254 (captured). None but c0247 is prepared and new to the README's labels: F1.

Round 3 answers:
- F1 fixed: AC9 diffs the section's mermaid block with the sequestered `diagram.txt`; `edges-commented` and `node-renamed` die by AC9 (my run). No spelling of the diagram other than the reviewed one passes.
- F2 fixed: Intent excepts "giving a rank when a person wants one", Order says "with no one to answer, the rank stays unset", AC6 pins both, and both mutants die (my run). The reconciliation keeps both of the user's rules.

Scope: every Problem bullet has its sub-section or row, its label and a criterion; nothing moved into Non-goals; every rule of the four verbatim messages appears in the draft. Faithfulness spot-checked against c0261 (Sonnet/Opus for claude, the final rounds, spend by tier) and c0265 (stale heartbeat, lost first even when a person started it): the draft says what those tickets say.

### F1 [medium] The draft adds a *designed* (c0247) label and row that nothing will flip when c0247 lands after c0264
Where: draft, The idea stage ("on top of the confirmation of intent, *designed* (c0247)") and the roadmap row `| z-ticket confirms intent | c0247 | designed |`; c0264.md Existing work ("c0247 (preparing, another session) ...").
Evidence: c0247 is `design: ready`, status `prepared-brisk-marble-heron`, on `origin/main`. Its Design names two README edits only (the skills table row and flow step 1) and never mentions a roadmap row or a label: `git show origin/main:z-nile/.tracker/issues/c0247/c0247.md | grep -n -i -e roadmap -e label -e 'How it should'` hits only the step-label sentence at line 37 and AC6. The legend says "A feature's PR changes its own roadmap row and every label that names it", but no check enforces it after c0264's `done` (check.sh no longer runs; the c0259 and c0264 promoted specs pin shapes, not truth). So if c0264 lands first, c0247's delivery leaves two *designed* labels that are false (it then *exists*), which is the defect c0117's lagging label already shows today (E5). Only the other order is covered: AC7 forces *exists* if c0247 lands first. Existing work is also out of date: it calls c0247 and c0118 "preparing"; both are prepared.
Critique: the README now promises something to an issue whose reviewed design does not know about it (z-design/quote-other-preps-before-promising). The tempting fix, dropping the c0247 label, removes the c0260 sub-section's honest dependency and the roadmap row the Problem asks for ("The roadmap table and the diagram gain the new tickets").
Consequences: c0247 is prepared, so its sequestered files cannot change, but its document's Implementation steps can gain a line in a tracker PR, or c0247's executor can be told through its raft's Theme at z-raft. The same applies to c0118 (its row predates this issue, from c0259) only if c0118's design also lacks it, which is c0259's leftover, not this issue's.
Recommendation: fix the order rule in the Design, for both orders: (a) c0247 lands first: AC7 already forces *exists* (say so); (b) c0264 lands first: record in Existing work that c0247's delivery must flip its row and its label to *exists*, and carry that to c0247 in this prep's PR (a one-line addition to c0247.md's Implementation steps, outside its sequestered files) or by a captured chore (`./zn new issue c ...`) that z-raft puts beside c0247. Update "preparing" to "prepared" for c0247 and c0118. No new spec case: a check of c0247's delivery belongs to c0247.
Lesson: z-design/quote-other-preps-before-promising

### F2 [low] E4's and the Rules table's mutant names do not match the runner's ids
Where: c0264.md E4 table and Rules and mutants column 3; experiments/mutants.sh.
Evidence: E4 says "Intent renamed", "the economy bullet removed", "a node relabelled"; the runner names them `no-intent`, `intent-no-economy`, `node-renamed`. The runner takes no id, so a reviewer cannot run one row's mutant alone, and matching 22 prose rows to 22 runner lines is by hand.
Critique: round 2 F2 was harvested to this lesson; the rows are now distinct but still not keyed.
Consequences: none beyond editing the table.
Recommendation: put the runner id in each E4 row (and in the Rules table's mutant column), and let `mutants.sh <id>` run one mutant (skip the others when an argument is given).
Lesson: z-design/mutant-ids-match-the-runner

Verdict: changes
