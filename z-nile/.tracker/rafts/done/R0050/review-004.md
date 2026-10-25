# Review 004: R0050 (code mode)
Inputs: impl-c0116 at 49d08e9a (PR #121); `git fetch origin main` (origin/main 3e98b45a, merge-base 5f3d8767); `git diff origin/main...HEAD`, and the fix delta `git diff f14bbb01..49d08e9a` (333d76da, 8474e6b2, the merge 0c006d1c, 49d08e9a); review-001..003, refute-001..003, harvest.md; R0050.md, c0116.md, c0116's `check.sh` and acceptance specs; `z-nile/tests/tooling/recombine-members.spec.luau`; `z-nile/tests/acceptance/c0082/audit.spec.luau`; `engine/publish.luau`; zz-review, zz-test, zz-rules, z-raft, z-stop; `./zn lessons --skill zz-review --full`, `./zn lessons --when build`.
Dropped from review-003: F1, F2, F3

Checks run in the worktree: `z-nile/check.sh --full`: GATE PASSED (pickman 1404/1404 in 206 files, z-nile 1150/1150 in 168 files). `./zn check c0116`: 10/10. `bash "$(./zn find R0050)/check.sh"`: 3/3. `./zn audit`: 0 errors, 1 warning (orphan R0040). Sequestration: `git diff --find-renames=100% --name-status origin/main...HEAD -- 'tracker/**/check.sh' 'tracker/**/acceptance/**' '*/.tracker/**/check.sh' '*/.tracker/**/acceptance/**'` lists nothing, and `git diff --summary origin/main...HEAD` has no `mode change`. The worktree was left clean.

Experiments ran in a scratch clone at 49d08e9a (`cr-r0050-004`), with probe cases appended to `recombine-members.spec.luau` there (run from `z-nile/` with `lune run tests/run -- tests/tooling/recombine-members.spec.luau`).

Rulings on refute-003:
- F1: right. Each audit error's named command works on the fixture, and so does the next lifecycle command:
  - `stop c0041` (missing raft) and `stop c0081` (empty `raft:`) publish the backlog move;
  - audit then names `unfold R0099 c0041`;
  - `unfold` in the rafting worktree clears it, and the commit lands;
  - audit is clean, and `status <id> preparing` succeeds for c0031, c0041 and c0081;
  - `stop c0061` (live raft) is refused;
  - `unfold R0099 c0041` is refused before the stop ("use ./zn stop c0041").

  `publish.luau` is unchanged on this branch (`git diff origin/main...HEAD -- z-nile/engine/publish.luau` is empty), so publishing accepts exactly what it accepted before, and nothing broader. The published commit is the move `ready`/`stop` already make (`validateMoves`: whole directory, backlog↔active, same root, document differing only in `status:`, `check.sh` through `paths.rewrite`). I read the commit `stop c0092` published on origin. It holds two renames, `issues/{active => }/c0092/{c0092.md,check.sh}`, and the one changed line is `status: active-… → prepared-…`. `stop` refuses a backlog issue (c0071), a done issue (c0051) and a non-id (`x`). Dropped.
- F2: right. `unfold R0098 c0051` is refused, publishes nothing, and leaves `raft: R0098`. Dropped.
- F3: right for `list`. For the bare `status` it doesn't hold: see F2 below. That half of review-003 F3's evidence was wrong, so this is a defect of review-003's claim, carried into the fix. Dropped as F3; the remainder is F2.

The `raftless-active` narrowing (an empty `raft:` line only). I find no real hole that would justify overriding c0082's promoted `audit.spec`:
- `git ls-files` over every issue document finds 0 issues without a `raft:` line;
- the issue template writes `raft: {{RAFT}}`;
- `land` may change only sections, `title` and `depends_on`.

The state is reachable only by a hand edit or a botched merge resolution. It is not stuck either. In the probe, an active c0092 with no `raft:` line is silent in `audit`, but `./zn stop c0092` gives it back (`raftId == ""`), and the publish is exactly the move above. Firing on a missing line would turn c0082's exact-list case `issues/active/c0010` red, so it would need a designed Override. The cost is not worth it for a hand-made state with a working command. No finding. F1 below covers the part of the same mechanism that is worth fixing.

### F1 [low] `stop <issue>` and `audit` decide "the raft is dead" with two different readers, so for some states the audit names `stop <id>` and `stop` refuses, or `stop` names `stop <R-id>` and that refuses too
Where: `z-nile/engine/main.luau` `stopIssue` (`if raftId ~= "" and store.find(raftId) then fail(… use ./zn stop {raftId})`); `z-nile/engine/audit.luau:298-331` (`raftAt` from the scan: any raft folder is "live", a retired one "retired", and anything else counts as missing)
Evidence: probe in the scratch clone, with these active issues seeded on origin after the spec's own cases:
- c0091, `raft: R0010` (a backlog raft): audit is silent. `stop c0091` fails with `c0091's raft R0010 is live: use ./zn stop R0010`, and `stop R0010` fails with `R0010 is prepared in …/rafts/R0010 on origin/main: only a readied or started raft is stopped`.
- c0094, `raft: R0070` (a done raft): audit is silent. `stop c0094` fails with `… R0070 is live: use ./zn stop R0070`, and `stop R0070` fails with `R0070 is done …: only a readied or started raft is stopped`.
- c0093, `raft: c0011` (an issue id): audit gives `error dead-raft …/active/c0093: c0093's raft c0011 does not exist: give it back with ./zn stop c0093`. `stop c0093` fails with `c0093's raft c0011 is live: use ./zn stop c0011`. That error stays in the audit, and an audit error fails the gate.

I found no engine route into these states:
- `ready` and `stop` move a raft together with the issues carrying its claim stamp;
- `done` takes `store.members`;
- `fold`, `unfold` and `recombine` refuse non-backlog rafts;
- emergent issues are made on the raft's branch.

So this is low. But it is the third round on the mechanism "which command owns each dead-raft state" (002 F1, 003 F1). The remaining gap is that the rule is written twice:
- audit's `raftAt` (missing means "no raft folder by that id");
- `stopIssue`'s `store.find` (live means "anything with that id, in backlog, active/ or done/, raft or issue").

Each refusal names a command whose own rule then refuses the item.
Critique: the tempting fix is to add backlog and done rafts to `stopIssue`'s "dead" set, or to make audit flag c0091 and c0094. Either fix patches one reader and leaves the next disagreement for a later round.
Consequences: a single predicate means deciding what "live" is for an active issue. The coherent answer: the issue belongs to `stop <R-id>` exactly when its raft is in `active/` with an `active-…` claim and the issue carries that stamp (`stop <R-id>`'s own selection). Every other active issue belongs to `stop <issue>`. That predicate also covers the issues `stop <R-id>` leaves behind with its "not claimed with it; left as they are" warning: they then have a route instead of being stranded beside a backlog raft. For a non-raft value (an issue id, garbage), `store.find` should not be called. Today `store.find("xyz")` raises `not a tracker id`.
Recommendation: put the rule "which command gives back this active issue" in one function, beside audit or in store, and call it from both `stopIssue` and audit. Audit errors on every active issue that `stop <R-id>` would not take, naming `./zn stop <id>`, and keeps the `dead-raft` and `raftless-active` texts as its cases. `stopIssue` refuses only the issues `stop <R-id>` would take. Spec cases in the tooling spec (not a sequestered file) on this fixture:
- an active issue naming a backlog raft and one naming a done raft are each an audit error, and `stop <id>` gives each back;
- an active issue whose `raft:` is an issue id gives the same;
- an active issue naming an active raft without carrying its stamp gives the same;
- c0061 (carries R0060's stamp) is still refused.

Lesson: zz-test/one-rule-one-function

### F2 [low] The bare `status`'s new `retired` branch is dead code: `publish.allowed` never accepts a `rafts/retired/` path, so a retired raft is not printed at all
Where: `z-nile/engine/main.luau:1580-1587` (`cmd.status` with no id: `… and publish.allowed(p, roots) and … then local shown = if string.find(p, "/rafts/retired/", 1, true) then "retired" …`); `z-nile/engine/publish.luau:50-80` (`itemPath` strips only `active/` and `done/`, so for `rafts/retired/R0030/R0030.md` the id is `retired`, which fails `^R%d%d%d%d$`); the comment at `main.luau:1988-1989` ("audit's scan, list and the bare status show it, as retired")
Evidence: in the probe, the bare `./zn status` on the fixture (R0030 in `rafts/retired/` on origin/main) prints c0061, c0011, c0021, c0022, c0031, c0041, c0071, c0081, R0010, R0020 and R0060, with no R0030 line, as either `retired` or `prepared`. The branch can't be reached. Review-003 F3 said the bare `status` listed R0030 as `prepared`. That was wrong: it never listed it. No spec covers the `status` half (the refute's spec case is `list` only), so the dead branch went unnoticed.
Critique: harmless at run time. But the comment and refute-003 claim a behaviour that doesn't exist, and the next reader may build on it.
Consequences: none if the branch is removed. Making `status` show retired rafts would mean widening `publish.allowed`, which is the publish whitelist. That trade is not worth making for a display.
Recommendation: remove the `retired` branch from the bare `status` and correct the comment at :1988 to "audit's scan and list show it, as retired; the bare status, which walks only publishable paths, never lists it". Optionally add a probe line that the bare `status` doesn't print R0030.

## Judged criteria (code mode only)
- JC1: pass. Given only z-raft and zz-rules, every step of the rubric's three cases is still placed, as ruled in review-001..003:
  - two prepared chores: worktree, `sync`, `raft-plan` / `new raft`, design sections, coherence review, `status prepared`, land;
  - a feature folded into a prepared feature raft: `fold` or the plan's `skip`, then a new round because the record changed;
  - a recombine: `./zn recombine`, retirement of an emptied raft, and a round for a keeper whose record changed.

  The `raft:` conflict steps are unchanged. The delta's new sentences agree with each other:
  - z-raft's `unfold` line: it refuses an active member, so give it back first with `./zn stop <id>`;
  - zz-rules **Rafting**: per state, `unfold` in the backlog, `stop <id>` and then `unfold` in `active/`, `stop <id>` for `raftless-active`;
  - z-stop step 1.

  They also agree with zz-rules' **Published or carried** bullet: the only published whole-directory moves are made by `ready` or `stop`, and `stop <issue>` is a `stop` move. The dead-raft states sit outside the rubric's three cases.

Candidate lesson (zz-review): a re-review re-runs the previous round's evidence for any claim that the fix rests on. Review-003 F3 reported the bare `status` showing a retired raft without running it, and the fix added a branch that can't be reached. Check: did I run each claim in my Evidence, or infer it from code I read?

Verdict: approve
