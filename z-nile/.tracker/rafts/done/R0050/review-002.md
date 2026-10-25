# Review 002: R0050 (code mode)
Inputs: impl-c0116 at 48fdbad0 (PR #121); `git fetch origin main` (origin/main 477d50f5, merge-base 1869ebda, the PR #126 squash); `git diff origin/main...HEAD` and the fix delta `git diff f61ee3fc..48fdbad0` (ffa8709f, e9f24227, 2fdb83de, the merge cb59d82a, 48fdbad0); review-001.md, refute-001.md, harvest.md; R0050.md, c0116.md, c0116's `check.sh` and acceptance specs; the new `z-nile/tests/tooling/recombine-members.spec.luau`; zz-review, zz-test, zz-arch, zz-rules; `./zn lessons --skill zz-review --full`, `./zn lessons --when build`.
Dropped from review-001: F1, F2, F3

Checks run in the worktree: `z-nile/check.sh --full`: GATE PASSED (pickman 1404/1404 in 206 files, z-nile 1146/1146 in 168 files). `./zn check c0116`: 10/10. `bash "$(./zn find R0050)/check.sh"`: 3/3. `./zn audit`: 0 errors, 1 warning (orphan R0040). Sequestration: `git diff --find-renames=100% --name-status origin/main...HEAD -- 'tracker/**/check.sh' 'tracker/**/acceptance/**' '*/.tracker/**/check.sh' '*/.tracker/**/acceptance/**'` lists nothing (c0116 was already in `active/` on main, so not even an R100), and `git diff --summary origin/main...HEAD` has no `mode change`. c0115's `rewrite-finished --check` (run in a scratch clone): "0 of 147 finished check.sh files would be rewritten".

Rulings on refute-001:
- F1: right. The clause drop is on main (1869ebda, PR #126); `git diff origin/main...HEAD -- '*/done/*'` is empty, the sequestration listing is empty, and c0115's AC14 tool is green. Dropped.
- F2: right as far as `recombine` goes. A repeated id is refused before the claim is published (the spec checks origin's tip is unchanged), and retirement is decided per member. Dropping the refusal is killed: `moving` would then be `{c0021, c0021}`, the claim publishes and the tip moves. The new `dead-raft` audit error is reported below (F1, F2). Dropped.
- F3: right. §5 now defers to §4, and zz-rules names `remap`. Dropped.

Does the audit error fire on legitimate states? I checked every route that writes `raft:` or moves a raft folder. `new raft`, `fold` and `recombine` write members' `raft:` locally, and the move to `retired/` is carried in the same rafting PR, so main never holds a member naming a retired raft. `unfold` empties `raft:`. `ready`, `stop` and `done` move a raft together with its members, and raftAt is keyed by id whatever the state (backlog, active or done all count as "live"). `done` takes every member (`store.members`), so no live issue is left naming a done raft. Done issues are skipped. A released `new raft` is an orphan that no issue names. In the real tree every live `raft:` value is empty or a backlog or active raft (`git grep -h -E '^raft:'`, then `./zn find` on each). I found no false positive.

### F1 [medium] The `dead-raft` error's remedy, "move it with ./zn recombine or unfold", can't be carried out: every `./zn` route out of the state refuses
Where: `z-nile/engine/audit.luau:298-321` (the message at :315); `cmd.unfold`, `cmd.recombine`, `cmd.fold` and `status <id> preparing` in `z-nile/engine/main.luau`
Evidence: I ran the new spec's fixture in a scratch clone (it builds the audit state the spec builds: c0031 naming the retired R0030, and the active c0041 naming the missing R0099). `./zn audit` prints exactly the two `dead-raft` errors. Then, from a rafting worktree:
- `unfold R0030 c0031` fails with "no such tracker item: R0030";
- `recombine R0010 R0030 c0031` fails with "no such tracker item: R0030";
- `unfold R0099 c0041` fails with "no such tracker item: R0099";
- `fold R0010 c0031` fails with "c0031 already belongs to R0030";
- `status c0031 preparing` fails with "c0031 is in R0030 on origin/main: z-raft takes it out first (./zn unfold R0030 c0031)", which is the command that just failed.

`store.get` never looks in `retired/`, and a missing raft has no folder at all. zz-rules says "The only way to change tracker state is `./zn`", so the state can't be left. Meanwhile the gate runs `./zn audit` and fails on any error, and `compact`/`remap` refuse while the audit has errors. So a dead raft that reaches main (by a merge race, which is the case this audit exists to catch) turns every PR's gate red, and its message sends the user to two commands that refuse.
Critique: the tempting fix is to reword the message ("edit raft: by hand"). That breaks the only-`./zn` rule and leaves the gate red until someone hand-edits a tracker document.
Consequences: a real route has to accept a member whose raft is dead. If `unfold` accepts it, then:
- it is local and carried by a PR, like every other `raft:` edit;
- it must not try to claim or edit the retired raft (its document is history) or a raft that doesn't exist;
- it should still refuse an issue whose raft is live, unless that raft is named;
- z-design's claim message should name the same route.
Recommendation: let `./zn unfold <R-id> <id>` (or one named command) take an issue whose `raft:` names a retired or missing raft: empty its `raft:` without claiming or editing that raft, and make the audit message and z-design's claim refusal name exactly that command. Document `dead-raft` and its way out in z-raft §5 (beside Conflicts) or in zz-rules **Rafting**. Spec cases in the tooling spec:
- the retired fixture: `unfold R0030 c0031` succeeds, publishes nothing, and `audit` is then clean;
- the same for the missing R0099 and c0041;
- `unfold R0010 c0031` (a live raft the issue doesn't name) still refuses;
- the audit text contains the command it names.

### F2 [medium] The `dead-raft` fixture never puts a live issue's raft in `active/` or `done/`, so treating those rafts as missing goes unseen
Where: `z-nile/tests/tooling/recombine-members.spec.luau` (fixture: R0010 and R0020 in the backlog, R0030 retired, R0099 and R0098 missing); `audit.luau:301-304`
Evidence: the code walks issue states {backlog, active, done} × raft places {backlog, active, done, retired, missing}. The fixture covers these:
- a backlog issue → backlog raft (silent);
- a backlog issue → retired raft;
- an active issue → missing raft;
- a done issue → missing raft.

It has no live issue naming an active raft or a done raft. So a mutant that builds `raftAt` from backlog rafts only (or that sets `"live"` only when the path has no `/active/` and no `/done/`) passes this spec. Today the real-tree audit in the gate kills it only by accident, because c0116 names the active R0050. Once R0050 is done, nothing does. A live issue naming an active raft is the normal state of every readied raft, so that mutant would turn every gate red the moment a raft is readied.
Critique: this is the enumerated-case gap the lesson names. The tempting fix (one active case) still leaves the done raft out.
Consequences: none beyond the fixture.
Recommendation: seed `rafts/active/R0060` with `issues/active/c0061` (`raft: R0060`) and `rafts/done/R0070` with a backlog `c0071` (`raft: R0070`), and assert that `audit`'s output names neither c0061 nor c0071. Also check that its only errors are the two expected ones (count the `dead-raft` lines), so a stray error can't satisfy `r.ok == false`.
Lesson: zz-test/seed-every-enumerated-case

### F3 [low] `recombine`'s header comment still says the other raft's folder is "deleted"
Where: `z-nile/engine/main.luau:1826` ("the other raft is retired (its folder deleted in this branch, so in the rafting PR)")
Evidence: since review 001 of the design, retirement moves the folder to `<root>/rafts/retired/<R-id>` with `retired: <keeper>` (lines 1942-1951 and z-raft §2).
Critique: a reader of the header alone would think the reviews and `harvest.md` are lost.
Consequences: none.
Recommendation: "its folder moves to `<root>/rafts/retired/<R-id>` in this branch (so in the rafting PR)".

## Judged criteria (code mode only)
- JC1: pass. z-raft and zz-rules alone still place every step of the three cases, as ruled in review-001:
  - two prepared chores: worktree, `sync`, `raft-plan` / `new raft`, write the design sections, coherence review, `status prepared`, land;
  - a feature folded into a prepared feature raft: `fold`, or the plan's `skip`, then a new round because the record changed;
  - a recombine: `./zn recombine`, retirement of an emptied raft, a keeper whose record changed needing a round.

  §5's review condition now matches §4 and the engine (review-001 F3, fixed). The `raft:` conflict steps in §5 Conflicts agree with zz-rules **Rafting**, and nothing contradicts that bullet, which now names `remap` too. The new `dead-raft` audit state isn't one of the rubric's three cases. Its missing way out is F1, not a JC1 failure.

Verdict: changes
