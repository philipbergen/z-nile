# Review 002: c0135 (design mode)
Inputs: prep `prep-new-refuses-used-slug` at 7d92f2b6 (c0135.md, check.sh, acceptance/slugs.spec.luau, prototype.patch, design-review-001.md, design-refute-001.md, harvest.md); `./zn capture c0135`; `./zn lessons --when design`. prototype.patch applied in a scratch clone of 7d92f2b6 (origin a scratch bare copy): slugs.spec `15 passed, 0 failed, 1 spec files`.
Dropped from review-001: F1, F3, F4, F5, F6 (fixed as the refute says: the offline `new raft` case, `slugTaken` on every publishing path, id-free c0082 slugs and the zz-rules sentence, the whole audit line pinned, the window named beside G2). F2's mechanism holds; one edge is left (F1 below).

Checked and holding:
- The suffixing is deterministic: `raftplan.plan` sorts its ops (`raftplan.luau:289`) before `commands` walks them, `used` starts as a copy of `taken`, and `-n` is per base, so the printed plan and `--apply` give the same slugs.
- Every producer of `new` arguments was searched: `git grep -nE 'cmd\.new\(|cmd\["new"\]|"new", "raft"|"new", "issue"' -- z-nile/engine zn z-nile/scripts` → `main.luau:1067 function cmd.new`, `raftplan.luau:331`. `reserveOnOrigin`'s other caller (`main.luau:2911`, `renumber`) moves an item with its slug and passes no check, which is right.
- The race inside the callbacks: each check runs inside `publish.commit`'s `build`, which is re-run on the new `base` after a lost lease, and a returned reason fails the publish without a retry. `reserveOnOrigin`'s failure goes through `fail("could not reserve a number on origin/main: …")`, so the emergent path never falls back to the local counter after a refusal. `listed` is collected from the same `ls-tree` as `paths`, and nothing it adds is writable (every returned change is still validated).
- No double reservation on refusal: the emergent path's local check runs before `reserveOnOrigin`, and the origin check returns before `reserve` raises the counter.

### F1 [medium] raft-plan's suffix rule has no case for a taken `-2`: a one-step suffix passes every case and asks `new raft` for a slug a raft already has
Where: `raftplan.commands` (prototype.patch, the `while used[slug]` loop); slugs.spec "raft-plan's commands give a new raft a free slug …" (`taken = { same = true }`) and "raft-plan gives a planned raft a slug no raft has" (only `lone-chore` taken); Rules and mutants rows M13/M14.
Evidence: in the scratch clone I replaced the loop with a one-step suffix and a counter shared across the plan (`if used[slug] then slug = `{base}-{K}`; K += 1 end`, `K = 2` before the loop) and ran `lune run tests/run -- ../z-nile/.tracker/issues/c0135/acceptance/slugs.spec.luau`: `15 passed, 0 failed`. A probe, `raftplan.commands(ops, { c0001 = "same" }, …, { same = true, ["same-2"] = true })` with one op, printed `same-3` with the prototype and `same-2` with the mutant. So the mutant plans `new raft chore same-2 …` while a raft holds `same-2`, and `--apply` stops at that op after the earlier ops have published, the half-applied plan design review 001 F2 was about.
Critique: the design says "that slug with `-2`, `-3`, …", but the cases only reach `-2` through a plain slug that is taken, never one where `-2` itself is taken (lesson zz-test/seed-every-enumerated-case). The tempting fix is one more expectation in the pure case.
Consequences: the case has to tell "skip every taken suffix" apart from "count suffixes across the plan". `taken = { same = true, ["same-2"] = true }` with one op expects `same-3`, which kills both the one-step and the shared-counter mutants. A real `-2` raft on the CLI path is the same rule through `sluggedLocal`, so the pure case is enough.
Recommendation: in the pure case add a plan of one op with `taken = { same = true, ["same-2"] = true }` expecting `same-3`. Add a Rules row "a suffix a raft already has is skipped" with mutant M17 (one-step suffix / a counter shared across the plan), run, killed.
Lesson: zz-test/seed-every-enumerated-case

### F2 [low] an issue that exists only on a branch is invisible to every other terminal, and the Design doesn't say what happens when one turns up
Where: Design "Refusals in `new`" (emergent path) and "Existing work" ("a branch that adds a duplicate by hand is caught by the gate's audit").
Evidence (read from the prototype, not run): an emergent issue created with `new issue … --raft R…` is written to the raft branch only, and `reserveOnOrigin` pushes only the counter. A backlog capture published from another terminal before that raft lands checks origin/main plus its own checkout, so it can take the emergent issue's slug. The same goes for two streams' emergent issues (`ws-<issue>` worktrees) in one raft. The clash shows up only when the raft branch merges main (or the stream merges), as audit's `slug-duplicate`, which turns the raft's gate red.
Critique: this window can't be closed without publishing branch-only items, and closing it isn't what the capture asks for. But the Design names only the race between two captures on origin. The raft's executor meets a red gate caused by someone else's capture, with nothing in the documents saying which copy to rename.
Consequences: none for the code. One sentence, and a matching line in zz-rules' Slugs bullet or the emergent-issue procedure if the author wants agents to find it.
Recommendation: one Design sentence: "An emergent issue lives on its raft branch until the raft lands, so a capture on main meanwhile can take its slug. The gate's audit reports it when the branch merges main, and the raft renames its own emergent issue's `slug:`." Pinning it in a skill is optional.

### F3 [low] `slug-duplicate`'s fix names no command, and nothing proves it clears the error
Where: Design "Audit" (`(choose a new slug for all but one)`); slugs.spec audit case.
Evidence: lesson zz-rules/audit-what-new-refuses asks "does each audit error name the one command that clears it, proven by running that command on the audit's own fixture?" No command changes a slug: the fix is a hand edit of `slug:` in one document's frontmatter. The audit case removes the duplicate's folder instead of renaming its slug, so it never runs the stated fix.
Critique: the fix is simple, but an agent reading `choose a new slug` doesn't know that it means editing the frontmatter, or whether anything else (a `prep-<slug>` branch, a worktree name) has to follow.
Consequences: worktree and branch names that were made from the old slug keep it, which is harmless (they are names, not keys). The Design should say so in one sentence.
Recommendation: make the hint `(edit slug: in all but one)` or similar, and have the audit case rename c0099's `slug:` and expect a clean audit, rather than removing the folder. Add a sentence that existing branch and worktree names need not follow.
Lesson: zz-rules/audit-what-new-refuses

Scope: capture c533ca25. Both outcomes (`new issue` refuses and creates nothing; audit reports `slug-duplicate`) have a Design and AC1/AC3. The audit line keeps the capture's format behind audit's level and path (recorded). G1/G2 are user decisions. Nothing dropped.

Lessons added since round 001 (harvest.md): z-design/new-refusals-reach-every-caller and zz-test/fixture-values-embed-no-rewritten-ids both transfer to other rafts; fine.

Candidate lessons (for the lead): fold into zz-test/seed-every-enumerated-case: "a generated-name rule (`-2`, `-3`, …) is seeded with its own first output already taken; check: does any case start from a set where the rule's first candidate is itself taken?"

Verdict: changes
