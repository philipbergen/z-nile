# Review 001: c0135 (design mode)
Inputs: prep-new-refuses-used-slug at 0c94a010 (c0135.md, check.sh, acceptance/slugs.spec.luau, prototype.patch); capture c533ca25; origin/impl-c0117's publish.luau/main.luau diff; `./zn lessons --when design --full`. Prototype applied in a scratch clone of 0c94a010: slugs.spec 11 passed, 0 failed.

Checked and holding: the read-only `listed` argument can't widen what the publisher writes (every returned change is still validated after `build` by `validateMoves` and `publish.allowed`, and `read` could already read any path at `base`); the inside-callback check is race-safe (each attempt re-fetches, rebuilds on the new `base` and pushes with `--force-with-lease=refs/heads/main:{base}`, so a capture that lost the lease re-runs the check against the winner's tree); ignoring one id in two folders is right (audit's `duplicate` reports it); c0117's broker only replaces the push and refuses a non-fast-forward, which `publish.commit` already rebuilds and retries, and c0117 does not touch `cmd.new` (its main.luau hunks: usage, guarded, flags, land, focus, commit, spend, board).

### F1 [medium] `new raft`'s local path has no case: deleting its refusal leaves slugs.spec green
Where: c0135.md Design "Refusals in `new`" third bullet ("`new raft`, publishing and local: the same"); Rules and mutants (no row); slugs.spec "the local path …" (runs only `new issue`).
Evidence: in the scratch clone with prototype.patch applied, I changed main.luau's raft-local check to `local takenHere = nil and audit.slugOwner(audit.sluggedLocal("."), "raft", slug)` and ran `lune run tests/run -- ../z-nile/.tracker/issues/c0135/acceptance/slugs.spec.luau`: `11 passed, 0 failed`. Every `new raft` case in the spec publishes.
Critique: a Design sentence with no case that fails without it (lesson z-design/spec-design-correspondence). The tempting fix is one more assertion in the issue-local case.
Consequences: the raft local path reaches the check only after its member and root checks (`the raft is made in …`), so the case must use a member that passes them (c0005) and assert the slug message, not just `ok = false`, or a member error passes it.
Recommendation: add M12 ("`new raft` local path unchecked", run) and a case: `PICKMAN_PUBLISH=0 new raft chore keeper c0005 --project pickman` fails naming `taken by R0004`, and the raft folder count is unchanged; also the retired one (`old-raft`, R0003), since `sluggedLocal` reaches `retired/` through `audit.scan`.
Lesson: z-design/spec-design-correspondence

### F2 [medium] `raft-plan --apply` builds `new raft` with its first issue's slug, which the new rule can now refuse halfway through a plan
Where: `z-nile/engine/raftplan.luau:321` (`args = { "new", "raft", op.type, slugOf[op.issues[1]] }`) and `cmd["raft-plan"]` in main.luau (runs each op in turn through `cmd[...]`, whose `fail` exits); not in c0135's Design or Touched modules.
Evidence: search for every producer of `new raft` arguments: `git grep -nE '"new", "raft"|"raft", op|cmd\.new\(' -- z-nile/engine z-nile/scripts zn` → `main.luau:1033 function cmd.new`, `raftplan.luau:321`. The real tree already holds the case: backlog raft R0040 (`slug: skill-lessons`, `issues: []`) kept the slug of c0111, whose work went into R0042; R0051 (`slug: touch-fire-and-hop`) holds f0110's slug today. Under G1 a raft that is emptied, retired or done keeps its slug, so when its first issue is rafted again by `raft-plan --apply`, that op fails after the earlier ops have published (reasoned from the code: I did not run a plan).
Critique: the rule adds a refusal to a command another command drives with a derived argument (lesson z-design/new-rules-migrate-existing-work: what fails on the day it lands). The tempting fix is to let the plan fail and tell the user to pick a slug.
Consequences: a partial `--apply` leaves rafts published and the rest unmade; any derived slug needs the same lookup as `new`, from the same function, and two ops in one plan must not pick the same derived slug.
Recommendation: `raftplan.commands` takes the taken raft slugs (from `audit.sluggedLocal`, the one rule) and gives a new raft its first issue's slug, or that slug with `-2`, `-3`, … when a raft has it, distinct within the plan; add `raftplan.luau` to Touched modules, a Rules row and a slugs.spec case (a plan whose first issue's slug a retired raft holds prints `new raft … <slug>-2 …`; mutant: the plain slug). Alternatively refuse the whole plan before anything runs, naming the clash; either way never a half-applied plan.

### F3 [medium] each path checks only one of the two trees: an emergent issue never sees origin, a backlog capture never sees the checkout
Where: Design "Refusals in `new`" (publish path: `sluggedFromTree(listed …)`; local path: `sluggedLocal(".")`); main.luau `reserveOnOrigin` (the emergent path's own `publish.commit`).
Evidence (read from the prototype, not run): an emergent issue (`new issue c x --raft R…`, publishing) reaches `takenHere = audit.slugOwner(audit.sluggedLocal("."), …)` and then `reserveOnOrigin`, whose callback checks nothing; an issue captured on origin/main after the raft branch was cut with the same slug passes, and the raft's gate fails `slug-duplicate` only after it merges main. Conversely the backlog publish callback already folds `localIds("issue")` into the id choice, but not local slugs, so a capture made from a raft worktree misses that branch's emergent issue.
Critique: the capture's outcome is "refuses a slug that another item of the same kind already uses"; both items exist when `new` runs and `new` can see both. The tempting fix is to add the origin check to the emergent path only.
Consequences: checking the union costs about 0.1 s (`sluggedLocal`) on the publish paths, and on the emergent path the origin check belongs inside `reserveOnOrigin`'s callback (it needs `listed` too, and a slug parameter) for the same race reason as the backlog path; offline (`PICKMAN_PUBLISH=0`) stays local only, which the Design should say.
Recommendation: every publishing `new` (backlog issue, emergent issue, raft) checks `listed`'s items plus `sluggedLocal(".")`; offline checks the local tree. Rules rows and cases: an emergent issue whose slug only origin has is refused (fixture: publish an issue from a second worktree after the raft branch is cut), and a backlog capture whose slug only the local tree has is refused.

### F4 [low] the c0082 override's `slug: s-{id}` puts the id inside the slug, so `renumber` rewrites it and hides what renumbering now does to a same-slug duplicate
Where: prototype.patch, `cli.spec.luau` `doc()`; cli.spec "renumber <directory> moves only that copy …" (asserts `tr({ "audit" }).ok` after renumbering c0010's backlog copy).
Evidence: `rewriteUnder` (main.luau:2787) substitutes `%f[%w]c0010%f[^%w]`, which matches inside `s-c0010`, so the renumbered copy's slug becomes `s-c0021` and audit stays clean. With slugs that don't contain the id (the real tree's), the two copies of a duplicated id that share a slug (one item twice) keep the same slug after renumber, and audit now fails `slug-duplicate`; zz-rules' Duplicate ids bullet still says only "renumber the copy not in done/".
Critique: the override passes for a reason the Design doesn't state, and the documented duplicate-id procedure gains a new failure.
Consequences: whether a same-slug duplicate should be renumbered at all (it is the same work) is a rule, so it needs a sentence.
Recommendation: give the c0082 fixture items slugs without their ids (for example `slug: s-{body-derived word}` or a fixed table per id), and add to the zz-rules Slugs bullet: "Two copies of one id with one slug are one item twice: remove the stray copy rather than renumbering it." Pin that sentence in slugs.spec's skill case.

### F5 [low] the audit line differs from the capture's format, and the deviation is not recorded
Where: capture Problem "`slug-duplicate <kind> <slug>: <id>, <id>`"; Design Audit: `slug-duplicate <path> <kind> <slug>: <id>, <id> (choose a new slug for all but one)`.
Evidence: `audit.format` is `{level} {code} {path}: {message}`, so the line reads `error slug-duplicate z-nile/.tracker/issues/c0099: issue taken-done: c0099, f0001 (…)`; the spec checks only the substring `issue taken-done: c0099, f0001`.
Critique: adding the path follows audit's format and is detail, not a cut, but the document should say it chose it.
Consequences: none.
Recommendation: one sentence in the Design ("the capture's format, with audit's level and path in front, as every audit line has"), and the spec matches the whole line.

### F6 [low] the 2.5 s of reads sit between the fetch and the lease push, widening every capture's race window
Where: Design Scalability; G2.
Evidence: the reads run inside `build`, after `fetch` and before `push --force-with-lease`; a push to main in that window loses the lease and repeats the whole attempt (another 2.5 s), five tries at most. origin/main took 158 commits in the last 24 h, 2 of them within 3 s of the previous one: rare today, more with dispatched runs (c0117) publishing status.
Critique: G2 accepted the latency; the race window is a second cost of the same choice that the decision text doesn't mention.
Consequences: none if the user accepts it.
Recommendation: one sentence beside G2's decision naming the wider window and the retry; no design change.

Candidate lessons (for the lead):
- zz-arch (or z-design): "A new refusal in a command is checked against every caller that derives its arguments (`raft-plan` derives `new raft`'s slug), because a refusal halfway through a batch leaves it half applied; check: who else builds this command's arguments, and what do they do when it refuses?"
- zz-test: "An override's fixture values must not contain the identifiers a command under test rewrites (`slug: s-{id}` and `renumber`), because the rewrite then passes the case for a reason nobody stated; check: does any fixture value embed an id, path or name that the command rewrites?"

Verdict: changes
