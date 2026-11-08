# Review 008: c0264 (design mode)
Inputs: prep worktree at 81dded29, with the uncommitted c0264.md, check.sh, experiments/readme.patch and harvest.md, plus acceptance/intent-ac1..3.spec.luau and roadmap-unique.spec.luau. I also read design-review-005/006/007 and design-refute-005/006/007. origin/main is bd51e437. Against HEAD it changes no README, spec or lib file (`git diff --stat HEAD origin/main -- z-nile/README.md tests/acceptance z-nile/lib` is empty).

The capture is `git show origin/capture-workers:z-nile/.tracker/issues/c0264/c0264.md` (2e282833). That branch is still not an ancestor of origin/main: it is 52 commits behind, and `./zn find c0263` and `./zn find c0265` both fail on main. I read the captures of c0175, c0248, c0249, c0250, c0253, c0257, c0260, c0261, c0262, c0263 and c0265 from that branch, and c0251's from main, where the branch leaves it unchanged.

Prototype: `.cache/rev8-c0264`, a clone of the worktree with the issue folder copied in, readme.patch applied, and c0263.md and c0265.md copied from origin/capture-workers. Commits used `GIT_*` env identities (`rev@example.invalid`), with no local identity. Everything ran through `./zn run`, and the clone was removed afterwards. `./zn check c0264` gives 11/11.

Round 4 of the restarted count. Dropped from design-review-007: F1 (AC7 no longer reads a base, so a row that an earlier raft member added is kept and passes; the text it no longer pins is F2 below) and F2 (the Intent's step list now leaves "completion" to c0248). 007 F3 is repeated as F3.

Scope fidelity: the Problem equals the capture, plus one `Scope decision (user, 2026-11-07)` line and one `Decided with the user (2026-11-07)` line. The title gains only spelling, and the Solution is unchanged. The Intent's three points, the nine mechanisms, the roadmap and the diagram each have a Design text and a Checked criterion. Each sub-section still restates its capture as written today. I checked each one line by line:
- c0253: "A raft, not a step" and "clears itself whenever a raft ends".
- c0250: the block is at raft level.
- c0260: all five steps.
- c0261: the three tiers and the model names.
- c0262: the limited view and the second off-course verdict.
- c0249: the rank is optional, `./zn rank` can unset it, and lost work comes first.
- c0265: the takeover is recorded.
- c0263: the full list, and "explicit human step before `prepared`".
- c0257: the order and drag and drop.

None of the four listed conflicts is decided.

The in-flight sweep for added roadmap rows found only c0264's own rows and c0260's. The search was `grep -rhoE '^\+\| [^|]* \| [cdf][0-9]{4} \| [a-z]+ \|$' --include='*.patch' --include='*.diff' .worktree/*/z-nile/.tracker`. The new `proto-c0260-capture-interview` worktree adds the same c0260 row and rewords the Skills row and flow step 1, which c0264 does not pin. Outside `done/c0259`, no in-flight check reads `How it should work` (`grep -rnE 'How it should work' --include=check.sh --include='*.luau' .worktree`).

### F1 [medium] The Intent's reading rule lost "of the same ticket": it now overrides any older line, across tickets. The Design still says it is per ticket
Where: the Intent's last paragraph ("where an older line below and one of the sub-sections from The worker, z-work to The board app (added for the 2026-11-07 ask) differ, the sub-section follows the ticket's current capture"); the Design's Decided paragraph ("says an older line gives way to a newer sub-section of its ticket"); design-refute-005 F4 and design-refute-006 F5
Evidence: round 1's wording was "an older line and a newer sub-section of the same ticket". 006 F5's Recommendation kept it ("… that names the same ticket"). The adopted text dropped it, so "the ticket's" has no referent, and the rule now reaches lines of tickets that none of the nine sub-sections names. Searching the patched README (`grep -nE 'next item|next unblocked item|gets a .rank:|round one Opus|claim top item|no human in the loop' z-nile/README.md`) turns up two such older lines that differ from a new sub-section:
- line 75, c0254 (whose capture was not rewritten): "A worker claims an item … a lost race means taking the next item". This differs from The worker, z-work (c0253, "It picks up a raft").
- line 81, c0251 (whose capture is unchanged on capture-workers): "round one Opus through `claude` or `agent`". This differs from Model tiers (c0261), where middle rounds run cheap and only the final round runs sharp.

As written, the rule says c0253 overrides c0254, and c0261 overrides c0251. Neither appears in the Design's conflict list. The Design's follow-up list does not name c0251's line, and it names c0254 only for the `preparing` claim. The Design describes the rule as per ticket ("a newer sub-section of its ticket"), but the text the README carries is not.

Critique: this is the fourth hole found in the gloss mechanism: 004 F1 and F3, 005 F4, 006 F5, and now this one. The README must not settle a question between two tickets' captures. Here it does so implicitly, through a general rule a reader cannot scope. The tempting fix is to put "of the same ticket" back. That fixes this hole, but the mechanism stays: one global precedence sentence in the Intent, reinterpreting lines a reader has not reached yet, with its reach defined by a range of headings.

Consequences: with the same-ticket scope, line 75 (c0254) and line 81 (c0251) are left standing beside the new sub-sections, contradicting them with no reading rule. So either they join the conflict and follow-up lists, or the README says where the two compose: c0261's capture already says "the tiers say how sharp, c0251 says which family". Moving the precedence into each sub-section makes the global rule unnecessary. The Intent's second clause, about designs a worker drafts, is an option (b) decision, not a precedence rule, so it stays.

Recommendation: question the mechanism. Replace the global rule with a local pointer in each new sub-section that supersedes an older one. For example, The worker, z-work ends with "(this replaces the worker end in Two ends, one stack, and the item loop of the diagram)". Rank and lost work gets "(this replaces Order's mandatory rank)". Blocked gets "(this replaces The worker moves on, in Escalation)". Each pointer names only its own ticket's older text, and each is pinned by AC5's verbatim text, so it goes away with that ticket's own PR.

If the global rule stays instead, restore "that names the same ticket" in the Intent, the Design block, AC4's heredoc and the patch together.

Either way, add two items to the conflict list as (5), decided by no one here:
- c0254's item claim against c0253's raft claim;
- c0251's "round one Opus" against c0261's cheap middle rounds, quoting c0261's "the tiers say how sharp, c0251 says which family".

Add both to the follow-up list. Then rerun AC4 and AC5 and the mutants that pin them (M5, M12).
Lesson: z-design/restated-rules-move-together

### F2 [medium] (repeat of design-review-006 F2) No criterion holds the text of the seven roadmap rows, while the Design says every block below is "held word for word"
Where: Design paragraph 1 ("the texts below are the required texts, held word for word by `check.sh`"); Design "Roadmap rows"; Design "Siblings" ("it does not pin the row's text"); check.sh `roadmap_rows`; design-refute-007 F1 ("row text is unpinned (the rows are a convenience…)")
Evidence: in `.cache/rev8-c0264` I replaced two rows with `| TODO | c0261 | captured |` and `| x | c0262 | captured |`. `./zn check c0264`: `PASS AC7 …`, 11/11. JC1 and JC2 do not cover row text either: JC2 judges labels and claims of being built, not what a row says. The Rules and mutants table has no row for it.

Critique: the capture's outcome is that "the roadmap table … gain[s] the new tickets", and a row is how a reader learns what a ticket is. A README whose seven rows say "TODO" passes every check and every rubric. The Design also contradicts itself: paragraph 1 says the rows are held word for word, and Siblings says they are not. Rounds 005 F2, 006 F2 and 007 F1 each moved this mechanism. The latest move traded the text pin for tolerance of sibling rows and kept no proxy at all. The tempting fix, pinning the Design's text again, fails a correct c0264 when a raft-mate's row is already there, as 007 F1 showed.

Consequences: a proxy that tolerates siblings must accept every sibling row known today: c0260's `capture interview and idea review (`capture/`, `zz-review --mode idea`)` from both of its prep worktrees. It must also say what happens to a sibling row that lacks the proxy, so that the proxy does not fail a correct c0264.

Recommendation: make AC7 require that each row's piece column name its ticket by a key term taken from the ticket's title: c0260 "idea review", c0261 "tier", c0262 "full-force", c0263 "provenance", c0265 "heartbeat", c0257 "Omarchy", c0175 "deepseek". Also require that the column is not the Design's `STATE` placeholder. Spec cases, each run on the prototype and recorded in Rules and mutants:
- c0260's sibling row passes.
- `| TODO | c0261 | captured |` fails.
- `| x | c0262 | captured |` fails.

Alternatively, if the user prefers no pin, add a Judged criterion whose rubric covers row text ("each new row names its piece as its sub-section does"). In either case, correct paragraph 1 so that it says which blocks are held word for word (the Intent, the sub-sections, the diagram lines) and that the rows are held by key term (or are judged).
Lesson: z-design/spec-design-correspondence

### F3 [low] (repeat of design-review-007 F3) The harvest still maps 006 F2 to the wrong lesson, and the round candidates were dropped instead of written
Where: harvest.md (`design-review-006 F2: z-design/spec-design-correspondence`); design-refute-007 F3 ("the harvest mapping of 006 F1 and F2 corrected; the candidate lessons … are reported, not written, as this lead writes lessons only through the skills' lessons folders"); Unknowns & experiments
Evidence:
- 006 F2's `Lesson:` line is `z-design/exact-checks-compare-against-the-merge-base`, but harvest.md still names spec-design-correspondence.
- `git status --short z-nile/skills` is empty, so no lesson file or note was added. The skill says the opposite of the refute: "The lead of a prep or raft writes it in `<skills folder>/<the skill the lesson improves>/lessons/<slug>.md`". The two candidates (006: a "document has X" check also checks where X is; 007: an exact check takes its "already there" base from before this issue's own change, not the merge base) are therefore lost.
- Unknowns records rounds 1 and 2 but not round 3 (007).
- `./zn lessons --uncovered c0264` passes, so only review sees any of this.

Critique: the refute says the fix was made, but it was not. A lead that declines to write lessons breaks the harvest the skill requires.
Consequences: none for the README.
Recommendation:
- Map 006 F2 to exact-checks-compare-against-the-merge-base.
- Add the 006 candidate as a note on spec-design-correspondence, or as a new zz-test lesson.
- Add the 007 candidate as a note on exact-checks-compare-against-the-merge-base.
- Record both in harvest.md as `- note …` lines.
- Add the round 3 line to Unknowns.

Candidate lesson (for the lead to harvest): a document that adds a rule for reading other lines ("where X and Y differ, Y wins") names the scope of the rule in the text it carries, not only in the Design. Here the Design's "of its ticket" was lost from the README text, and the rule silently grew to cover lines of other tickets. Check: does the text that ships say which lines the rule covers, word for word as the Design describes it, and does the conflict list name every line it now overrides?

Verdict: changes
