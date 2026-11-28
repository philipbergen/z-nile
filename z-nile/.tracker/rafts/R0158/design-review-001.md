# Review 001: R0158 (design mode)
Inputs: f1bf68fd3811f35bd3345472d30adbfca09a28bc; z-nile/.tracker/rafts/R0158/R0158.md, z-nile/.tracker/rafts/R0158/check.sh, z-nile/.tracker/issues/c0394/c0394.md and acceptance/, z-nile/.tracker/issues/c0460/c0460.md and acceptance/, z-nile/.tracker/issues/c0458/c0458.md (and `./zn capture c0458`), z-nile/engine/main.luau (`cmd.finish`), z-nile/engine/readycheck.luau, z-nile/engine/work.luau
Grouped: [c0394@3e2a8cadcee8, c0460@8d36481f8e28]

Raft mode: only the Theme, Order & dependencies, Whole-raft design and raft coherence are judged. The members' own designs are not re-reviewed.

### F1 [high] The grouping makes c0458 land before c0394 is built, and c0458 removes the per-layer code review that c0394's high-finding rule and specs rely on
Where: R0158.md, Order & dependencies ("c0460 needs c0458 ... `./zn ready R0158` and `./zn work` order the rafts by these"); c0394.md section 3 (`added` answers), Theme bullet "the added issue goes in front of the layer whose review found it by default"; c0458.md Solution bullet 2
Evidence: `readycheck.luau:211` refuses to ready a raft while any member's `depends_on` is not done ("it must be done first"). c0460 has `depends_on: [c0458]`, so R0158 cannot start until c0458 has landed on main. c0458's captured Solution says: "The per-layer code review step is removed from `work.luau`, `dispatch.luau`, `main.luau`, `workgraph.luau` (its `review` action) and zz-execute, so every raft ... gets exactly one adversarial `final-review` on its whole stack", and `dispatch.REVIEW_MODES` drops `code`. c0394 is built on top of that main. Its design still assumes per-layer reviews:
- Section 3 accepts `added` for a high finding only when "`<id>` is in front of the reviewed layer (`before:` names the issue whose review this is; a layer's review is in its issue's folder, c0248)". It also says "A high finding of a **final** review (no single layer) needs the ruling."
- It edits zz-execute "Phase 4 step 6", which is the per-layer adversarial code review phase (`zz-execute/SKILL.md:61`) that c0458 removes.
- It edits `work.forRaft` beside the `review` action that c0458 removes.
- Its sequestered `acceptance/answers.spec.luau:346-359` builds a layer, finishes it and writes `{folder}/review-001.md` in the issue folder. AC11 ("a high added in front of its layer is accepted") is judged on that flow.
After c0458, every code review is a final review. So every high finding answered `added` needs a user ruling, and the user's decision "In front by default (Recommended)" can no longer be reached in delivery. The raft document notes only that c0460 needs c0458. It never asks what c0458 does to c0394.
Critique: this is a member-against-member disagreement that the grouping itself creates. Without c0460 in the raft, c0394 waits only for c0248, and the order between c0394 and c0458 is open. With c0460 in, that order is fixed in the worst direction. The tempting fix is a sentence telling c0394's executor to "adapt to c0458 when it lands". That rewrites a user-decided rule at build time, and it edits c0394's sequestered answers.spec, which execution may not do.
Consequences: taking c0460 out does not settle c0394 against c0458 on its own. Both are in flight, they disagree on the review flow, and nothing records which lands first. Whichever lands second has to be re-prepped. If c0458 goes first, the "In front by default" decision has to be put to the user again, because "the layer whose review found it" no longer exists. If c0460 stays in, c0394's design has to change (z-raft's rule: that member leaves the raft).
Recommendation: z-raft takes c0460 out of R0158. R0158 then holds c0394 alone and waits only on c0248, and c0460 is rafted after or with c0458, whose code-mode check list it extends. Separately, record a `depends_on` that fixes the order between c0394 and c0458. Best is c0458 `depends_on: [c0394]`, since c0458 is still in draft and its designer can carry the `added` high rule over to the single final review. Its prep puts the "In front by default" interaction to the user. The other way, c0394 is re-prepped against c0458 with that same question to the user. Re-run R0158's coherence review on the new `grouped:` record.
Lesson: z-design/design-the-execution-window
Erred: z-raft
Upstream: none

### F2 [medium] The Order says each outside dependency binds only its own member, but `ready` makes the whole raft wait for both chains
Where: R0158.md, Order & dependencies: "Dependencies outside this raft, both of which must be done before their member starts"
Evidence: `./zn ready` refuses the raft while any member's dependency is unfinished (`readycheck.luau:211`). So c0394 also waits for c0458 (design: draft, no raft), and c0458 waits for f0459 ("Agy session adapter and Gemini lineup", design: draft). In the other direction, c0460 waits for c0248, whose raft R0152 is still `design: draft`. The Theme's claim that "neither needs the other's code" is true, but the document never names the cost: each member waits for the other's chain. It also names no member to unfold if one chain lags.
Critique: a reader takes from "before their member starts" that c0394 can be delivered once c0248 lands. It cannot.
Consequences: if c0460 stays in after F1, the raft needs a stated fallback: which member to unfold, and when.
Recommendation: if F1's unfold is taken, this closes with it. Otherwise rewrite the sentence to say that the raft starts only when c0248, c0458 and f0459 are all done. List each member's waits the other does not share, and name the unfold fallback (take c0460 out if c0458 is not prepared when c0248 lands).
Lesson: z-raft/grouping-cost-checks-every-wait
Erred: z-raft
Upstream: none

### F3 [medium] The Whole-raft table says the main.luau changes share no function, but both members change `cmd.finish`, and it leaves the work.luau question to the reviewer
Where: R0158.md, Whole-raft design, the `engine/main.luau` and `engine/work.luau` rows
Evidence:
- **main.luau**: the row says "different commands (`done`, review answers vs `finish`); no shared function or signature". c0394's section 2 lists `cmd.finish` among the sites it rewrites (`issues[layer.position - 1]`, now `main.luau:4290-4302`): the `base` computation becomes `layergit.layerBelow(raft, issue)`. c0460 inserts `mutants.refusal` right after the `merge-base --is-ancestor` check that uses that `base`, and passes it `layergit.diffPaths(base)` (c0460 Design, Adapter). So the two edits are adjacent lines of one function, and c0460's input is the value c0394 redefines. They agree only if c0460 takes `base` as c0394 leaves it: the nearest unlanded member's layer in the added-issue order, or `origin/main`.
- **work.luau**: the row says "listed in c0460's Touched modules for the pick's text only" and "to confirm: the reviewer checks". c0460's design touches work.luau only to add `Mutants` to `work.CODE_CHECKS`, a constant c0458 adds. c0394 changes `work.forRaft`, `:194-199` and `:426`, and adds the `wait` action. Answer: no shared function. But the row describes c0460's change wrongly and leaves the coherence question open.
Critique: the table exists so the second layer's executor knows what it is rebasing onto. An executor who trusts "no shared function" can put the refusal before c0394's `layerBelow` block, or keep a `position - 1` base. Then the diff for a layer above a waiting added issue, or in front of a parked one, is taken from the wrong base.
Consequences: the fixed row creates a test obligation. c0460's `finish-mutants` cases use rafts with no added issue, where `layerBelow` equals the old base, so they cannot tell the two apart. A raft spec case is the only place a layer above a waiting added issue gets checked.
Recommendation: rewrite the main.luau row. Both members change `cmd.finish`. c0394 replaces the below-layer `base` with `layerBelow`. c0460's call goes after the merge-base check on that `base` and reads `diffPaths(base)`. Mark it as agreeing, with c0460 rebasing onto c0394's block. Rewrite the work.luau row with the answer above. If c0460 stays in the raft, add a raft check (or name the case for c0460's executor to write in `tests/`) in which a layer finished above an approved added issue owes `mutants.md` for its own paths only.
Erred: z-raft
Upstream: none

### F4 [medium] The raft never says when c0394's new finding rules take effect for its own later layer, and RC1 pins a membership that an emergent issue breaks
Where: R0158.md, Order & dependencies, Exit criteria and Risks; R0158/check.sh, RC1
Evidence:
- c0394 changes the rules the raft's own later work is judged by: the `dropped` and `added` answer kinds in `completion.reviewProblem` and `openlist`, the legacy `deferred` note in `done`, the zz-rules Findings section, and `new issue --raft --wait`. c0460 is built in the same raft worktree, on c0394's layer, so `./zn` there runs c0394's engine and skills. The raft document never says whether findings raised while building c0460, and the refutes of R0158's final review, follow the old Emergent issues rule or the new Findings rule.
- `check.sh`'s RC0 loop says "every issue naming this raft, including emergent ones". RC1 then requires `./zn members R0158` to be exactly `c0394 c0460 `. A must-fix emergent issue is still allowed by c0394's own end 1 and by today's zz-rules (`./zn new issue ... --raft R0158`), and an added issue under c0394's end 4 once its engine is live. Either one makes RC1 fail. `check.sh` is sequestered, so execution cannot fix it.
Critique: the first defect leaves the executor to guess which rule binds a finding mid-raft. The second blocks a raft that met a legitimate emergent issue from finishing.
Consequences: if the rule is "the new rules apply from c0394's layer up", then R0158's final review refute may use `added`, and RC1 has to let an added member exist. If the rule is "old rules until the raft lands", the skills c0394 ships will contradict what the raft does.
Recommendation: add a sentence to the Order or Risks section: from c0394's layer up, findings in this raft follow zz-rules Findings, and the final review's refute may answer `added` or `dropped`. Change RC1 to pin the rule, not the set: c0394 and c0460 are members, and every other member is `emergent: true` (and carries `waits:` once c0394 is live). Drop RC1 if `./zn members` already guarantees it.
Lesson: z-raft/plan-the-switch-over
Erred: z-raft
Upstream: none

### F5 [low] The Theme leaves out c0394's 2026-11-20 rulings that its shared skill edits depend on
Where: R0158.md, Theme, c0394 bullet
Evidence: c0394's Problem records two 2026-11-20 rulings. The first: "there is no R-vision raft". The second: "use best judgement, just make them consistent", meaning that c0293, c0316, c0372 and c0394 edit the shared Lessons section, and the one built second applies its edit on top. The Theme quotes only the 2026-11-16 decisions, including "build on c0248's `done --through`". The Lessons-section ruling bears on the raft's shared skill files: the Whole-raft table and Risks talk about skill text collisions, and c0316 is another of those writers.
Critique: a reader of the raft cannot see that the Lessons-section edits are coordinated with items outside the raft.
Consequences: none.
Recommendation: add the two 2026-11-20 rulings to the c0394 bullet of the Theme. Name c0293, c0316 and c0372 as the other Lessons-section writers in Risks.
Erred: z-raft
Upstream: none

Verdict: changes
