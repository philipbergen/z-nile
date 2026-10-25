# Review 013: c0115 (design mode)
Inputs: prep-c0115 at 1c22dc9a (`git diff 3a8c5ee6 1c22dc9a` of c0115's folder and the skills, read as 7a8412a1..1c22dc9a: §11 (q), check.sh, the three experiments, both patches, harvest.md, the ticket-prep lesson); impl-c0115 at ff9a1401 (d806b924, adf1973c, 859174cb), used only through a scratch clone whose origin is the real remote (fetched at main 754eb8ed); design-review-012.md and design-refute-012.md.
Dropped from design-review-012: none (it approved; its three lows are fixed as the refute says).

What holds:
- **Overrides commit 859174cb** is byte for byte `experiments/c0120-overrides.patch` (`git diff 859174cb^ 859174cb | diff - …patch`: identical). Every blob in check-paths' `RESTAMPED` matches the file at ff9a1401: c0083 2ed11243, R0044 f989acf1, d0124 3145713e, R0039 11a38337, c0075 6b776437.
- **The undone stacking skips.** `STACKED_ON` is empty, `rewrite-finished` requires `@tests/acceptance/c0120/rewrites`, and `backlog_clean` has no c0120 line. In the clone, `./zn check c0115` is 14/15. AC15 is the only red, for the expected reason ("c0115 has no raft yet").
- **The freeze specs.** `lune run tests/run -- <c0115 freeze.spec> tests/acceptance/c0120/freeze.spec.luau tests/tooling/busy-holds-move.spec.luau` passes (14 cases in those three files).
- **c0120's freeze is inert.** Its mark, `tracker/rafts/done/R0001/check.sh`, is gone from origin/main, so `freezesOn` never selects it and `c0120Move` is never called. Its specs still drive it through fixtures that seed the mark.
- **The mark in the rename-map block.** `skills.MOVE_MARK` is present on main and absent at impl HEAD, so the freeze turns off when c0115 lands. Moving the literal into the one block that absence.spec leaves out is legitimate: it is an old skill path, and it exists because of the rename. Leaving `prototype.patch` unregenerated is also acceptable, because `impl-c0115` supersedes it. The text that still says otherwise is F4.
- **The new lesson paragraph** ("run the whole item on every experimental patch") is a lesson that another raft could fail, not a restated finding, and the harvest note names it.

### F1 [high] c0115's history rule now counts c0120's squash-landed branches as "stacked on c0115", so any branch cut from them is silently ignored by AC12
Where: `z-nile/engine/main.luau` `ignoredBy`, the roots loop (d806b924); G14's third bullet ("any branch whose history holds a commit of `origin/prep-c0115` or `origin/impl-c0115` that main doesn't"); §11 (q).
Evidence: main took c0120 as a squash (c5b436ca). `impl-c0115` was cut from `impl2-c0120` and has now merged c0120's final branch, and `prep-c0115` holds c0120 commits too. Every unsquashed c0120 commit is therefore "a commit of origin/impl-c0115 that main doesn't", and always will be. Here is what that does in the scratch clone (real origin, fetched).
- Branch by branch:
  - `git merge-base origin/prep-c0120 origin/impl-c0115` = e8a34f3e (a c0120 prep commit), which is not on main.
  - `origin/impl-c0120` gives 9449b79a against both roots, which is not on main either.
- `./zn busy .claude/skills z-nile/skills pickman/skills` prints `ignored for c0115's freeze: origin/impl-c0120 (stacked on its implementation)` and `… origin/prep-c0120 (stacked on its implementation)`. Both branches change the skill paths, and neither is stacked on c0115.
- A branch `rogue-skill-edit`, cut from `origin/prep-c0120` and adding `.claude/skills/zz-rogue/SKILL.md`, gives `ignored for c0115's freeze: rogue-skill-edit (stacked on its implementation)`, and busy exits 0. AC12 passes.

c0115's freeze.spec can't see this: its fixture has no squash-landed stack under the roots.
Critique: the rule's premise was that the roots' commits not on main are c0115's own. The squash landing broke that premise for good. This is the breakage c0120 hit when #99 merged its prep (busy-holds-move.spec's header), and c0120's answer was `pinned` ("holds its move"). The port carries `pinned` but gives c0115 none. The tempting fix is to add a c0120 exclusion to the loop (for example "unless the merge-base is an ancestor of origin/impl-c0120"), but c0120's branches will be deleted and the next squash-landed base will break the rule again.
Consequences:
- c0115's entry gets `pinned` = c0115's own move commit (the renames-only commit AC13 finds on impl-c0115), recorded by sha the way c0120's is: in a reviewer-written record (review/sequestration-reference-not-a-ref), never found by searching history.
- The roots' history rule then either goes away for c0115, or counts only commits after that sha.
- Branches stacked only on `prep-c0115` and not named in `stacked` lose their exemption. That direction is safe: they block, and the user approves them by name.
- G14's third bullet changes. It narrows an exemption the user granted, so the change is recorded, not silent.
Recommendation:
- Give c0115's FREEZES entry `pinned` (its move commit, pinned in the record) and drop or bound the roots' history rule so that c0120's commits can't satisfy it.
- Rewrite G14's third bullet, its Rules and mutants row, and the freeze.spec header.
- Add a freeze.spec case. In the fixture, main takes a base branch `stack` as a squash, `impl-c0115` merges `stack`'s tip and then adds the move commit, and:
  - a branch cut from `stack` that edits the paths blocks;
  - a branch holding the move is ignored ("holds its move").
- Add the mutant "history rule kept unbounded", which that case kills.
- Tell the user in the prep PR that G14's "same rule" now includes `pinned`, as c0120's did, for the same reason.

### F2 [high] The own-raft exemption, now applied to c0115, has no G14 line, no Rules and mutants row and no spec case: two mutants survive all three freeze specs
Where: `cmd.busy`'s raft loop (`for _, fr in freezes … string.find(members, ",{fr.item},")`); G14's ignored list (it doesn't mention it); c0115.md's G14 row (line 420); `acceptance/freeze.spec.luau`.
Evidence: in the scratch clone at ff9a1401 I ran each mutant of that `if` against the three freeze specs:
- (A) `if fr.item == "c0120" and string.find(…)`, so c0115's own raft blocks: 14 passed, 0 failed.
- (B) `if fr.item == "c0115" or string.find(…)`, so every active raft is ignored while c0115's freeze is on: 14 passed, 0 failed.

Mutant B makes AC12 ("no other raft active") pass while another raft is active, which is the freeze's main purpose (§9, "c0115 is readied only when no other raft is active"). The only cases for this rule are c0120's (busy-holds-move, "c0120's own raft … another active raft is listed"), and c0115's freeze is off in that fixture. On the decision: the user said "Yes, same rule" when c0120's rule had no own-raft or `pinned` part. §11 (q) adds both as "parts of the one rule", but G14's decided list, which the spec header copies, still lists four ignored kinds.
Critique: a rule in the engine with no row and no case (lesson ticket-prep/spec-design-correspondence). The tempting fix is to add a row that says "reasoned: same code as c0120's". But the per-freeze loop is exactly what a generalization gets wrong (mutants A and B).
Consequences: the case needs an active raft on origin/main in c0115's fixture, both while the mark is present and after it is removed. With F1's `pinned`, G14's list grows to six kinds, and the spec header must match it.
Recommendation:
- Add the own-raft rule (and, with F1, `pinned`) to G14's ignored list, and to the Rules and mutants table with mutants A and B, run against the port.
- Add a freeze.spec case. While c0115's mark is on main:
  - an active raft whose `issues:` lists c0115 is named on stderr (`ignored for c0115's freeze: raft R… (c0115's own)`);
  - an active raft that doesn't list it prints `raft R… is active` and exits 1.
- Once the mark is gone, both block.
- Record in G14 that "same rule" was applied to the parts c0120 added after the decision, so the user sees it in the PR.
Lesson: ticket-prep/spec-design-correspondence

### F3 [medium] zz-rules' `busy` row still says the freeze is c0120's alone
Where: `z-nile/skills/zz-rules/SKILL.md:77` at ff9a1401 (the row in the renamed tracker skill).
Evidence: "For that freeze alone (paths given, and only while `origin/main` lacks c0120's move), the branches stacked on c0120's prep and the ones the user approved by name … (`ignored for c0120's freeze: ...`)". c0120 has landed, so that freeze can never be on, and the only freeze that can now be on is c0115's, which the row never mentions. The row also omits the own-raft rule (F2) and the history rule (F1). `git grep -n "freeze alone"` over `z-nile/tests` finds nothing, so no spec pins the stale text. Neither §6 (Skill text) nor Implementation step 6 lists this row.
Critique: an agent whose `./zn busy` prints a dozen `ignored for c0115's freeze` lines finds no rule in the skill that explains them (lesson ticket-prep/restated-rules-move-together, c0120 code review 011 F1's "the tracker skill's busy row was false"). The tempting fix is to swap "c0120" for "c0115", which leaves the row naming one item again for the next move.
Consequences: the row describes the general rule (FREEZES: a move's mark, roots, stacked and approved names, `pinned`, the own raft) and names c0115 as the current entry. If c0115's docs.spec pins a phrase, the next move must override it.
Recommendation: rewrite the row as the general rule, add it to §6's list and to Implementation step 6, and add a docs.spec case that the row names `ignored for <item>'s freeze` and c0115's mark.
Lesson: ticket-prep/restated-rules-move-together

### F4 [low] §11 and the Design intro still say `prototype.patch` is regenerated and is where the executor may start, while (q) says it is not
Where: c0115.md §11 last bullet ("…and `prototype.patch` regenerated"); the Design intro ("the executor may start from the prototype"); Implementation step 1 ("Rebase rule §11 if the stack under c0115 changed after 757a5fa1"); the G14 row's Outcome column ("run (against c0120's latest implementation with the engine change)"); (q)'s date "2026-10-25" (c5b436ca and 1c22dc9a are 2026-10-24 -0700).
Evidence: (q) reads "`prototype.patch` stays as recorded at 757a5fa1". The patch is cut against impl2-c0120. It carries the simulated c0120 promotion, the pre-port freeze and the `STACKED_ON` skips, so an executor who applies it to today's main would reintroduce all three.
Critique: keeping the patch is fine, since impl-c0115 supersedes it. The contradiction is the problem, together with step 1's trigger, which is now always true.
Consequences: none beyond the wording.
Recommendation:
- Say once, in the Design intro and in §11's last bullet, that the prototype is the historical record at 757a5fa1 and that the raft continues on `impl-c0115` (ff9a1401, on main c5b436ca).
- Rebase step 1 on that base.
- Update the G14 row's outcome to "run against the port (d806b924, adf1973c)".
- Fix the date.

### F5 [low] The freeze's exemptions apply to every path set, so `./zn busy tracker` also hides c0115's stack and its raft
Where: `freezesOn` (it is on for any non-empty `pos`); the FREEZES comment ("one rule for every move").
Evidence: in the clone, `./zn busy tracker` prints `ignored for c0115's freeze: origin/prep-c0116 (stacked on its prep)` and eight more, though the call has nothing to do with the skill paths. With one freeze per move in one list, any move's readiness call applies every other live move's exemptions.
Critique: c0120 accepted "paths given" as the call boundary when it was the only freeze (architecture/item-rules-scoped-to-their-call). Turned into a general list, the boundary no longer tells one move's call from another's. There is no second caller today, which is why this is low.
Consequences: a `paths` field per Freeze, with the freeze on only when the given paths are exactly its own set. Compaction's no-path call is unchanged. One more case and one mutant.
Recommendation: give each Freeze its paths (c0120's `tracker src tests`, c0115's three skill paths). Add a case: `busy tracker`, with c0115's mark on, lists `prep-c0116`. Or record in G14 that every path set is covered, as an accepted choice.
Lesson: architecture/item-rules-scoped-to-their-call

Candidate lesson (for the lead): a rule that reads "a commit of X that main doesn't have" breaks for good once main lands anything under X as a squash. The squashed base's commits never reach main, so every branch cut from that base matches. Check: "does each 'not on main' history test survive a squash landing of the branch it was stacked on, and is there a case where main squashes the base?" (from F1; it extends c0120's `pinned` reason, which was a prep merge).

Verdict: changes
