# Review 003: c0135 (design mode)
Inputs: prep `prep-new-refuses-used-slug` at d672ea9a (c0135.md, check.sh, acceptance/slugs.spec.luau, prototype.patch, design-review-002.md, design-refute-002.md, harvest.md, zz-test/lessons/seed-every-enumerated-case.md); z-nile/engine/main.luau (`raftBranch` and its callers). prototype.patch applied in a scratch clone of d672ea9a (origin a scratch bare copy): `lune run tests/run -- .tracker/issues/c0135/acceptance/slugs.spec.luau` → `15 passed, 0 failed, 1 spec files`.
Dropped from review-002: F1 (fixed: the one-op case with `same` and `same-2` taken expects `same-3`, and the one-step mutant fails it), F2 (fixed: the emergent-issue window is written down), F3 (fixed: the hint names the edit, and the case applies it and expects no `slug-duplicate`; but see F1 below on what the hint says about branches).

Checked and holding:
- `same-3`: the prototype's loop (`raftplan.luau:325-329`, `local slug, n = base, 2; while used[slug] do …`) gives `same-3` for the one-op plan, and the one-step suffix fails it (refute's M17).
- The emergent-slug note matches the code: `new issue … --raft` writes the issue on the raft branch, and `reserveOnOrigin` publishes only the counter. The rename belongs to the raft, and audit catches the clash when it merges main.
- The audit case's fix: renaming c0099's `slug:` to `renamed-by-hand` clears `slug-duplicate`. In the clone that second audit prints only `warning orphan-raft …` and `error next-missing …`, so it does run and the slug check is quiet for the right reason.

### F1 [low] The hint's "branch and worktree names need not follow" is false for rafts: a raft's branch name is `<id>-<slug>`, and the engine finds a raft by it
Where: Design "Audit" (`(edit slug: in all but one; branch and worktree names need not follow)` and "`prep-<slug>` branches and worktrees made from the old slug keep their names, which are names, not keys"); slugs.spec's pinned audit line.
Evidence: `z-nile/engine/main.luau:137` `local function raftBranch(raft) return `{raft.id}-{raft.slug}` end`. `currentRaft` (`main.luau:341`) picks "the active raft whose branch is the current branch" with `raftBranch(r) == branch`. `start` (`:3280`, `:3333`), `worktree R…` (`:3652`) and `stop` (`:4827`) also build the branch name from the slug. `git grep -nE 'prep-%s|"prep-" *\.\.|`prep-\{' -- z-nile/engine zn` finds nothing, so for issues the sentence is true. But for two rafts that share a slug, an agent who follows the hint and edits the slug of the one that is already started (on branch `R0040-old`) makes `currentRaft()` return nil on that branch, and `start` and `worktree` then look for `R0040-new`.
Critique: this is low because a raft clash in practice comes from a rafting PR, whose rafts are still in the backlog with no branch. But the audit line is what the agent will act on, and "all but one" lets it pick the started raft. The tempting fix is to delete the clause, which leaves the trap unmentioned.
Consequences: the hint gets longer or splits by kind. The pinned whole line in slugs.spec changes with it, as last round's did.
Recommendation: say it per kind, and pin it. For an issue, keep the clause. For a raft: "(edit slug: in all but one; for a raft, one with no `<id>-<slug>` branch yet)", or have audit name the raft without a branch when exactly one has one. Correct the Design sentence to say that a raft's branch name is derived from its slug and is a key.

### F2 [low] "a suffix a raft already has is skipped, per slug": "per slug" has no case. A counter shared across the plan, with the skip loop kept, passes every case
Where: Rules and mutants row "a suffix a raft already has is skipped, per slug" (M17 "or a counter shared across the plan"); design-refute-002 F1 ("both fail that case").
Evidence: in the clone I moved `n` out of the op loop (`local n = 2` before `for _, op in ops`, `local slug = base` inside) and kept `while used[slug]`. slugs.spec printed `15 passed, 0 failed`. The two-op case (`same`, `same` with `same` taken) gives `same-2`, `same-3` either way, and the one-op case gives `same-3` either way. Only a counter shared across the plan *without* the skip loop fails, which is what the refute ran.
Critique: the slugs the mutant produces are still free and distinct, so nothing is published wrongly; a second base gets `b-3` where `b-2` was free. But the row claims a mutant killed that isn't.
Consequences: none beyond one expectation.
Recommendation: add a two-op plan with different bases, both taken (`taken = { a = true, b = true }`), expecting `a-2` and `b-2`. Or drop "per slug" and the shared-counter half of M17 from the row. Either way, the refute's claim is corrected in the record.
Lesson: zz-test/seed-every-enumerated-case

### F3 [low] The fix-clears-the-error assertion would also pass if audit crashed
Where: slugs.spec audit case, `t.expect(has(fixed.stdout .. fixed.stderr, "slug-duplicate")).toBe(false)` (and the existing `clean` assertion of the same form).
Evidence: in this fixture audit exits non-zero anyway (`error next-missing z-nile/next`, `audit: 1 errors, 1 warnings`), so `fixed.ok` can't be asserted, and an audit that raised before its report would print no `slug-duplicate` either.
Critique: lesson zz-test/no-vacuous-pass: "not run" must differ from "clean". Low, because the case's first audit in the same fixture proves the scan runs.
Recommendation: also expect the summary line (`has(…, "audit: ")`), or assert the exact `error`/`warning` lines as the first audit does.
Lesson: zz-test/no-vacuous-pass

Scope: unchanged since round 002 (capture c533ca25, both outcomes with criteria, G1/G2 the user's). Nothing dropped.

Lessons added this round: the seed-every-enumerated-case addition ("seed a generated-name rule with its own first output already taken") is a rule another raft can fail. Fine.

Candidate lesson (for the lead): z-design or zz-rules: "a fix hint that says a derived name may stay stale is checked against every place that name is derived: `git grep` the format (`{raft.id}-{raft.slug}`) before writing it; check: is the 'name' in this hint a key anywhere in the engine?"

Verdict: approve
