# Review 003: R0050 (code mode)
Inputs: impl-c0116 at 7e6c8b39 (PR #121); `git fetch origin main` (origin/main 8a9bc612, which is also the merge-base); `git diff origin/main...HEAD`, and the fix delta `git diff 9bba9f57..7e6c8b39` (8bdc0e1e, c8c70745, and the merge 7e6c8b39, which brings only spend rows); review-001/002, refute-001/002, harvest.md; R0050.md, c0116.md, c0116's `check.sh` and acceptance specs; `z-nile/tests/tooling/recombine-members.spec.luau`; zz-review, zz-test, zz-rules, z-raft; `./zn lessons --skill zz-review --full`, `./zn lessons --when build`.
Dropped from review-002: F2, F3

Checks run in the worktree: `z-nile/check.sh --full`: GATE PASSED (pickman 1404/1404 in 206 files, z-nile 1147/1147 in 168 files). `./zn check c0116`: 10/10. `bash "$(./zn find R0050)/check.sh"`: 3/3. `./zn audit`: 0 errors, 1 warning (orphan R0040). Sequestration: `git diff --find-renames=100% --name-status origin/main...HEAD -- 'tracker/**/check.sh' 'tracker/**/acceptance/**' '*/.tracker/**/check.sh' '*/.tracker/**/acceptance/**'` lists nothing, and `git diff --summary origin/main...HEAD` has no `mode change`.

Experiments ran in a scratch clone at 7e6c8b39 (`cr-r0050-003`), with probe cases added to the end of `recombine-members.spec.luau` there (run from `z-nile/` with `lune run tests/run -- tests/tooling/recombine-members.spec.luau`).

Rulings on refute-002:
- F1: partly right. For a backlog issue, the named `unfold` now works. In the probe, `unfold R0030 c0031` succeeds and publishes nothing. Once that branch lands, `status c0031 preparing` from a worktree succeeds, which is z-design's route back. For an active issue, it does not work: see F1 below. The author flagged this consequence in refute-002, and it is a defect of this fix.
- F2: right. The fixture now seeds c0061 → active R0060 and c0071 → done R0070, and counts the `dead-raft` lines. Dropped.
- F3: right. Dropped.

Can the dead path clear a member of a live raft by mistake? I found no route.
- `raftingStart` merges origin/main before `store.find(raftId)`, so the local tree holds every raft that main holds.
- `store.find` looks in backlog, `active/` and `done/` in every root. A live raft never reaches the dead branch. An active or done raft goes down the old path, which refuses it ("unfold takes a backlog raft").
- The member check compares the issue's own `raft:` with the named id. A typo in the id, or an issue of another raft, is refused (`unfold R0099 c0011` and `unfold R0030 c0071` both refuse).
- Two terminals that clear the same line make the same edit, so their PRs merge cleanly.

### F1 [medium] For an active issue, the remedy that `dead-raft` names leaves it stuck in `active/`, and the audit no longer reports it
Where: `z-nile/engine/main.luau:1764-1797` (cmd.unfold's dead branch); `z-nile/engine/audit.luau:298-324`; the active member c0041 in `recombine-members.spec.luau`
Evidence: I ran the probe in the scratch clone after the spec's own `unfold R0099 c0041`. From the rafting worktree, before and after its commit lands on origin/main (pushed and merged, as the PR would be):
- `audit`: `0 errors, 0 warnings`;
- `status c0041 prepared`, `status c0041 preparing` and `status c0041 new` each fail with `c0041 is readied (in active/): use ./zn stop R0099`, and after the landing with `… use ./zn stop <R-id>`;
- `stop R0099` from the main checkout fails with `tracker stop: no such tracker item: R0099`;
- `unfold R0099 c0041` fails with `c0041 is not a member of R0099`;
- `find c0041` gives `pickman/.tracker/issues/active/c0041`.

The only commands that move an item out of `active/` are `stop` and `done`, and both work through the raft. So the issue can't go back to z-design or be readied again, and nothing reports it. Before this fix the state was at least a loud audit error. Now it is silent, and the audit message still sends the user, and the spec, down this path for an active issue (`c0041's raft R0099 does not exist: clear it with ./zn unfold R0099 c0041`). That fails the lesson's own test (zz-rules/audit-what-new-refuses: "does each audit error name the one command that clears it, proven by running that command on the audit's own fixture?"). The audit line goes away, but the item is not cleared.
Critique: the obvious fix would be an audit warning for "an active issue with no raft". It brings the noise back but still offers no way out. The other obvious fix, moving the folder back to the backlog inside the rafting PR, rewrites `check.sh` paths in a PR, which is the change the sequestration listing exists to refuse.
Consequences: a real way out of `active/` for an issue with no live raft is a whole-folder move with its `check.sh` paths rewritten. zz-rules allows such a move to be published only by `ready` or `stop`. So the route belongs in `stop`:
- it takes the issue rather than the raft;
- it has to check on origin/main that the issue's raft is retired, missing or empty;
- it publishes the same backlog move and `prepared` status that `stop` gives a member;
- `publish.allowed` must accept that one-issue move as a `stop` move.

The dead branch of `unfold` should then refuse an active issue (it is not the route), and the audit's message for an active issue should name `stop`. A raftless active issue (the state that already exists after this fix) needs an audit error naming the same command, so the state is never silent.
Recommendation: make one command take an active issue whose raft is dead back to the backlog, published as `stop`'s directory move is, and make audit's `dead-raft` text for an active issue name that command instead of `unfold`. `unfold`'s dead branch refuses an issue in `active/` ("use ./zn stop …"). Add an audit error for an issue in `active/` whose `raft:` is empty, naming the same command. Document both in zz-rules **Rafting** and z-raft's `unfold` line. Spec cases on this fixture:
- `stop` on c0041 publishes c0041's move to `issues/c0041` with status `prepared` and its `check.sh` paths rewritten, and `audit` is then clean;
- `unfold R0099 c0041` refuses;
- an active issue with an empty `raft:` is an audit error whose text names the command;
- that command refuses an active issue whose raft is live (c0061).

If the author judges that the route out of `active/` is outside c0116's scope, the alternative is to escalate it to the user rather than leave it to a later capture. The audit's own fixture would stay at "cleared but stuck".

### F2 [medium] `unfold`'s refusal of a done issue in the dead branch has no case: dropping it leaves every spec green
Where: `z-nile/engine/main.luau:1781-1783` (`fail(\`{issue.id} is done: its raft: is history\`)`); `recombine-members.spec.luau` (the dead-unfold case)
Evidence: in the scratch clone I deleted those three lines and ran `recombine-members.spec.luau`: 4 passed, 0 failed. `git grep -n "is done: its raft"` finds the string only in main.luau, so no other spec pins it. The fixture already has the case: c0051 is done and names the missing R0098. Without the check, `unfold R0098 c0051` rewrites a done issue's document in a rafting PR, which is the history the audit deliberately skips. Refute-002 lists the refusal as part of the fix, and its mutants list doesn't include it.
Critique: this is the one guard in the new branch with no case of its own (zz-test/guard-needs-its-own-case).
Consequences: none beyond the case.
Recommendation: in the dead-unfold case, assert that `unfold R0098 c0051` fails with `c0051 is done`, publishes nothing, and leaves c0051's `raft: R0098` as it was. If F1's fix makes the dead branch refuse active issues, give that refusal its own case too (`unfold R0099 c0041`).
Lesson: zz-test/guard-needs-its-own-case

### F3 [low] `list` and the bare `status` show a retired raft as a live backlog raft
Where: `z-nile/engine/audit.luau:18` (`STATES` now includes `retired/`, used by `audit.scan`); `stateOfPath` at `main.luau:283-288` (anything not `active/` or `done/` is "backlog"); `cmd.list` at `main.luau:2638-2672`; `cmd.status` with no id at `main.luau:1575-1584`; the comment at `main.luau:1977-1979` ("nothing that finds items (store, the board, the plan) looks there")
Evidence: in the probe, `./zn list` prints `R0030  backlog  chore            R0030` for `rafts/retired/R0030`. The bare `status` walks origin/main's paths through the same `stateOfPath`, so it lists R0030 with its old `prepared` status. `./zn ready R0030`, or any command that uses `store.get`, then says `no such tracker item: R0030`.
Critique: a user (or z-raft reading `list backlog`) is shown a raft no command can act on.
Consequences: `audit.scan`'s other callers (`localIds`, `keepRecords`, compact, remap) do need retired rafts, so the scan stays as it is. Only the displays and `stateOfPath` change.
Recommendation: have `stateOfPath` return a distinct `retired` for `/rafts/retired/`, or skip retired paths in `list` and the bare `status` (or show them as `retired`). Add one probe line to the spec: `list` doesn't call R0030 backlog. Correct the comment at main.luau:1977.

## Judged criteria (code mode only)
- JC1: pass. z-raft and zz-rules alone still place every step of the rubric's three cases, as ruled in review-001 and review-002:
  - two prepared chores: worktree, `sync`, `raft-plan` / `new raft`, design sections, coherence review, `status prepared`, land;
  - a feature folded into a prepared feature raft: `fold` or the plan's `skip`, then a new round because the record changed;
  - a recombine: `./zn recombine`, retirement of an emptied raft, and a new round for a keeper whose record changed.

  The new sentences (z-raft's `unfold` line, zz-rules **Rafting**: a dead raft's member is cleared with `unfold`, which claims nothing and rides in the rafting PR) agree with each other and with §4 ("an `unfold` alone needs none") and §5 (land with no `status prepared` when no raft is claimed). The `raft:` conflict steps are unchanged. The dead-raft route for an active issue (F1) is outside the rubric's three cases.

Verdict: changes
