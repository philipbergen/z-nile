# Review 002: R0061 (design mode, raft coherence)
Inputs: branch `raft-r0061-r0073-regroup` at d27b26145 plus the uncommitted `R0061.md` (`git diff`), `R0061/check.sh`; the members `c0134`, `c0135`, `c0137`, `c0178` (documents, `check.sh`, `acceptance/`, c0135's `prototype.patch`); origin/main 5199ca1be; `origin/R0073/1/c0178` b4caf82fc; R0070, R0071, R0072, R0073 and R0099's documents.
Grouped: [c0134@f7930714033c, c0135@2fb059d96ee8, c0137@1226bfaf3701, c0178@f9d865d0d9ed]

Raft mode: coherence only. These held up when I checked them: no file is in two members' Touched modules. `./zn stack R0061` lists c0134, c0135, c0137, c0178 once each in that order. `./zn workstreams R0061` ends `parallel: yes (wave 1: c0134 c0135 c0137 c0178)`. R0099 is active on layer 1 of 5 (`./zn stack R0099`), and c0135 has `depends_on: [c0263, c0282]`. `swept.sweep` treats a folder that is already gone as removed, so c0135's own `fs.removeDir(f.base)` is safe. c0135's prototype puts `<id>-<slug>` only in `audit.luau`, and neither c0135's new text nor c0178's adds a phrase that c0044 AC9, c0067 AC10 or R0025 RC1 bans.

I tested this in a scratch clone (session scratchpad, `./zn run`-bounded): `origin/R0073/1/c0178` merged with origin/main 5199ca1be (one conflict in `fence.luau`'s launch string against d0298's 9fe4b132f, resolved by keeping main's string and adding `GIT_TEMPLATE_DIR="$3/git-templates"`), plus c0135's `prototype.patch` and its spec copied in. Results: `slugs.spec` 17 passed, 0 failed, on c0178's harness (`fixtures:` line printed). `./zn check c0137` 3/3. `tests/meta/scanning-loops.spec` and `c0193/tree.spec` were red (F2).

### F1 [medium] `./zn work` will offer `./zn ready R0061 --on R0099` before R0099 is done, and c0135's step 5 cannot run then
Where: R0061.md, Cross-raft waits ("`./zn ready R0061` refuses until then"; "c0134, c0137 and c0178 wait with c0135"); c0135.md Landing order ("z-raft puts it in a raft that starts after R0099 is done") and Implementation step 5.
Evidence: plain `ready` does refuse a `depends_on` that is not done (`cmd.ready`'s loop). But `work.luau` (tier 2, `readyOn` and `work.baseFor`) picks a prepared raft whose unmet dependencies all sit in one active raft with every layer finished, and returns `R0061 is prepared and depends on R0099, whose layers are finished. From the main checkout run ./zn ready R0061 --on R0099`. `f0399.readyOnMembers` accepts that, because c0135's two dependencies are R0099 members. R0061 would then be built on R0099's top layer while `tests/acceptance/c0263/record.spec.luau` and `c0282/record.spec.luau` do not exist yet: they exist only after R0099's `done`. So c0135's layer is finished without its step 5. Once R0099 lands, the restack onto main brings in promoted specs that c0135's audit rule turns red, and that is found only in R0061's full gate. R0099.md says nothing about R0061 or c0135.
Critique: the wait the document describes is one the engine's own worker routes around, and it contradicts c0135's statement that its raft starts after R0099 is done. The tempting fix is to change "ready refuses" to "ready (without `--on`) refuses". That still leaves the worker's offer in place.
Consequences: taking `--on` means c0135's step 5 runs after R0099's `done`: on layer 2 after the restack, then a re-finish of layer 2 and a restack of layers 3 and 4, before `./zn done R0061`. That is a different landing sequence from the one c0135's design states. Refusing `--on` is a rule that only people enforce, so it must be written where the worker reads it.
Recommendation: in Cross-raft waits, state that R0061 is readied only after R0099 is `done`, never `--on R0099`, with the reason (c0135 step 5 edits the promoted copies). State that `./zn work` will offer `--on` once R0099's layers are finished and that the offer is declined. Write the same line in R0099's document (lesson z-raft/cross-raft-order-written-in-both). If the user prefers to allow `--on`, the sequence in Consequences changes c0135's stated landing order, so it goes under `## Open to the human` as a choice between the two. It is not written as fact.
Lesson: z-raft/cross-raft-order-written-in-both
Erred: z-raft
Upstream: none

### F2 [medium] The R0070/R0071/R0072 line is copied from R0073 and is stale: R0072's loop lint is already on main and turns c0178's layer red
Where: R0061.md, Cross-raft waits, third bullet; Whole-raft design (c0178's path list).
Evidence: the bullet repeats R0073.md lines 22 and 27. R0072 is in `rafts/done/`, and its lint (c0193) is promoted. On the scratch tree with c0178's built layer, `tests/meta/scanning-loops.spec.luau` and `tests/acceptance/c0193/tree.spec.luau` both fail with `z-nile/tests/lib/images.luau:152: loop "while true do" does not provably advance and is not on loops.ALLOWED`. So "either order merges" is no longer true: c0178 is the second lander and must add an entry to `z-nile/tests/lib/loops.luau`. That file is not in c0178's Touched modules, not in the raft's path-by-path list, and not in its design. R0071 has `issues: []`: c0191 landed as R0079, so R0071 touches nothing. R0070 (active) does touch `fence.luau`, `fixture.luau` and `loops.luau`, but its document addresses "R0073 (c0178)" and records the assumption that c0178's `swept.register` relies on c0194's `.cache/.tmp`. R0061 leaves that assumption out.
Critique: an executor who trusts this bullet meets a red gate on c0178's layer with no instruction. The tempting fix is to delete the R0071/R0072 names. That leaves the `loops.luau` entry unassigned.
Consequences: the entry is an addition to a shared reviewed list. It must name why the poll ends (it returns on the image, gives up after `wait` (180 s) or stale `stale` (60 s)) and, since the loop reads no text, `sweep = false`. If R0070's c0194 or c0189 lands first and edits `loops.luau`, the two hunks are separate entries in different files' blocks.
Recommendation: rewrite the bullet from the tree. R0072 is done, so c0178's layer adds `images.luau`'s `while true do` to `loops.ALLOWED` (its own block in `z-nile/tests/lib/loops.luau`, with why it ends), recorded on that layer as a build deviation (an added Touched path), and `tests/meta/scanning-loops.spec` and `c0193/tree.spec` must pass there. R0071 is empty and shares nothing. For R0070, quote its assumption (`.cache/.tmp`, hidden first segments refused by `swept.register`) and note that its pointer still names R0073. Add `loops.luau` to the c0178 entry of the path-by-path list as a layer addition. Also tell the executor that the built branch conflicts with main in `fence.luau`'s launch string (d0298's `STEP_VARS` and `$7` PATH), and that the resolution keeps main's string and adds `GIT_TEMPLATE_DIR`.
Lesson: z-raft/copied-raft-text-is-reverified
Erred: z-raft
Upstream: none

### F3 [medium] The Order's reason is false: `./zn finish c0178` runs only c0178's check, not the other members'
Where: R0061.md, Order & dependencies ("so its finish and the raft's RC0 run the other members' checks on the new fixtures") and Whole-raft design, first coupling ("with c0178 stacked last, `./zn finish` of its layer runs on a tree that holds c0135").
Evidence: `cmd.finish` (main.luau:4021) calls `runCheck(issue)` for the one issue on the layer, then the affected specs with `--own-acceptance`. c0135's spec is sequestered, so neither of those runs it, and neither runs c0137's check on c0178's skill edits. Both couplings are first proved at RC0, at the end.
Critique: this repeats R0061 design review 001 F1 under layers: the stated reason is not what execution does. The tempting fix is to move c0178 to layer 1, so that c0135's and c0137's own finishes run on its fixtures. That puts the largest and riskiest layer under three others, and every later fix to it restacks all of them.
Consequences: keeping c0178 on top is sound (a fix to it restacks nothing), but only with an explicit step that proves the couplings before its finish. Without that step, a break is found only at RC0, after the final review has started.
Recommendation: keep the order. Restate the reason as: c0178 is the top layer so that a fix to it restacks nothing. Add a raft-level step on layer 4: before `./zn finish c0178`, run `./zn check c0135` and `./zn check c0137` on that layer. RC0 repeats both. Say in the Whole-raft design that the couplings are proved there and at RC0, not by `finish`.
Lesson: z-raft/order-reasons-survive-workstreams
Erred: z-raft
Upstream: none

### F4 [medium] The c0137 coupling leaves out what the three finished criteria read, and the raft's own harvested lessons are in that scope
Where: R0061.md, Whole-raft design, "c0135's text under c0137's checks"; c0137.md, Implementation step 1.
Evidence: the bullet names two criteria ("One bans `<id>-<slug>` …", "Another runs the 13-phrase scan"). AC3 runs three of them. R0025 RC1 bans `make-prompt` and `./zn launch`. c0067 AC10 also bans `pbcopy` and `clipboard`, requires `^name: z-ready$` and six keys in z-ready, `./zn ready` and `prompt.md` in zz-rules and `/z-ready` in z-design, and forbids a `make-prompt` folder. All of these are `grep -r` over `skills` and `../pickman/skills`, lessons included. This raft's lead writes lessons into `z-nile/skills/<skill>/lessons/` on the layers (zz-execute: candidate lessons are written as they arrive, plus the code-review harvest). There is a precedent: c0137's own prep found "straight to main" in the lesson zz-arch/guards-trust-only-origin. c0137's step 1 tells the executor that a red AC3 means "a later change to main" and to stop and report.
Critique: a lesson harvested on this raft's branch that quotes a banned phrase (for example from a review of c0135's slug messages) turns AC3 red at RC0, and c0137's own instruction sends the executor to blame main. The tempting fix is to say "lessons too". That still leaves out the positive pins and the third criterion.
Consequences: the executor needs to know which text it is writing falls under the scans: the members' skill edits and every lesson file of this raft. It also needs to know that a red AC3 caused by the raft's own text is fixed by rewording that text (not sequestered), never by editing a finished check.
Recommendation: list all three criteria and what each pins and bans (above), name the scope as both skills folders whole (lessons included) plus `engine/main.luau` for the 13 phrases, and add: "a red c0137 AC3 is first checked against this raft's own skill and lesson edits (`git diff origin/main...HEAD -- z-nile/skills pickman/skills z-nile/engine/main.luau`); text of this raft is reworded, and only a red that main alone produces is c0137 step 1's stop".
Erred: z-raft
Upstream: none

### F5 [low] Experiments says nothing is open, but the members were never run together
Where: R0061.md, Experiments phase.
Evidence: each member's results are listed only on its own tree. No combined run is recorded, and F2's red is exactly what such a run finds. The run described above (c0178's layer + main + c0135's prototype) gives `slugs.spec` 17/0 and `./zn check c0137` 3/3, so the combined claims hold apart from F2.
Critique: "None open at raft level" stands only once the combined run has been made. The tempting fix is to cite this review. A review is not the raft's record.
Consequences: none beyond writing the record. The run cannot hold c0135's step 5 (R0099 is not done), and the record should say so.
Recommendation: record the combined run in Experiments (base, the conflict and its resolution, the results above, the loop-lint red and its fix from F2), and note that step 5 is proved only after R0099 is done, at c0135's layer and at RC0.
Lesson: z-raft/run-sequestered-specs-on-all-prototypes-together
Erred: z-raft
Upstream: none

### F6 [low] Rollback and the path list overstate what they say
Where: R0061.md, Risks & rollback (Rollback bullet); Whole-raft design ("Compared path by path").
Evidence: `./zn done` lands the four layer commits plus a binding commit that holds every promotion (`tests/acceptance/c0134`, `c0135`, `c0137`, `c0178`) and every move to `done/`. Reverting one member's commit leaves its promoted specs in place and red (for c0178, nine spec files that require `images.luau` and `swept.luau`), so "reverting a member's commit leaves the others" is not a rollback of that member. The path list leaves out `z-nile/tests/acceptance/c0134` and `z-nile/tests/acceptance/c0135`, which both members list. Design review 001 F3 had this fixed for c0135, and the rewrite dropped it again (lesson z-raft/regroup-carries-earlier-coherence-findings).
Critique: the conclusion (no shared file) still holds, but a reader trusts the list as complete and the rollback as working.
Consequences: none.
Recommendation: say that a member's rollback reverts its layer commit and removes its promoted folder `tests/acceptance/<id>/` (and moves its item back out of `done/` by hand), and add the two folders to the path list.
Erred: z-raft
Upstream: none

Verdict: changes
