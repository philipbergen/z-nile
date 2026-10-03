# Review 008: R0210 (design mode)
Inputs: prep worktree `4170b40`: R0210.md and R0210/check.sh; c0640.md and check.sh; c0650.md, check.sh and `adapt.spec`; c0660.md, check.sh and both specs; design-review/refute 006 and 007. Prototype `proto3-r0210` `53f8c70`: `scripts/tracker/main.luau` (`guarded()`, `publishing()`, `cmd.new`, `cmd.status`, `cmd.start`), `scripts/lib/fence.sh`, `tests/tooling/repo-fence.spec.luau` (`NAMES`, `ALLOWED`, `EXEMPT`) and the promoted c0510 specs. R0200's re-prep `prep-r0200-mktree` `db73d96`, read for context only: c0510's `check.sh` and specs.
Dropped from design-review-007: F1, F2, F3, F4 and most of F5. The refutations hold:
- F1: R0200's AC9 no longer spells the name. The `ALLOWED` entries for c0650's and c0660's promoted specs are in `proto3`. A banned-name grep of every prepared file in this raft and in c0510 finds only names that are allowlisted or exempt.
- F2: the spec now runs from a linked worktree, with valid slugs and a fixture identity. I re-ran it.
- F3: the decision now sits in `publishing()`. The guarded case asserts `ok`, that the stub exists, and that HEAD and origin are unchanged, so the two refusals review 007 named as wrong (fail the command; no-op success that loses the stub) are each killed. Their rows are still missing from the table (see F1).
- F4: the publisher no longer names a guard variable and has no entry.
- F5: the Rollout, Experiments, c0660 rule and Problem items are fixed. What is left is in F3.

Runs, all in `proto3-r0210`, one spec file at a time, with no other suite running (no lock directory, no `lune run tests/run` process):
- `tracker/issues/c0650/acceptance/adapt.spec.luau`: 6 passed, 0 failed.
- I ran the same spec once more with a mutant in `scripts/tracker/main.luau`: `not guarded()` removed from `publishing()`, and the guard added only at `cmd.new`'s issue call site (`if state == "backlog" and publishing() and not guarded() then`). Result: **6 passed, 0 failed** (see F1).
- I restored the file from a scratchpad copy. `git diff --quiet` is clean and `git status` is empty.
- Nothing printed `REPOSITORY CHANGED`. No git write ran in any worktree.

Summary:
- **c0640's guards:** still sound.
- **c0650's adaptation:** works on the combined prototype. Its one real gap: AC2 proves the refusal for `new issue` only. A refusal placed at that one call site passes every check, and it leaves `status` moves, `new raft` and `start`'s claim publishing to `origin/main` from a check.
- **The real repository and its remote:** with the designed implementation, no path remains by which a check changes them except the paths c0640 already names as caught only by review:
  - a `check.sh`'s own commands, including a direct `git push` or `gh`;
  - on Linux, writes to the checkout's index or files;
  - work handed to a process outside the jail.

  Any other path needs a wrong implementation that AC2 would accept (F1).
- **First attempt:** possible. The trap is the instruction to "merge" `proto3-r0210`, a local branch that carries R0200's prototype code and stale documents (F2).

### F1 [high] AC2 passes when the refusal guards only `new issue`: `status` moves, `new raft` and `start`'s claim still publish to `origin/main` from a check
Where: c0650 Design item 3 ("in `publishing()`"); AC2 ("a tracker command publishes nothing"); `adapt.spec` cases 3 and 4 (both run only `new issue c …`); Rules and mutants table (rows P1, P3, P4); `proto3` `main.luau` call sites of `publishing()` at lines 313, 316, 390 (`new raft`), 526 (`status`) and 869 (`start`)
Evidence:
- **Reproduced in `proto3`.** With the mutant described under Runs (no check in `publishing()`; `and not guarded()` only on `cmd.new`'s `state == "backlog"` line), `adapt.spec` passed 6 of 6.
- **What that mutant still does.** Under it:
  - `tracker.sh status <id> preparing` reaches `publish.commit` and pushes a claim to `origin/main`;
  - so do `new raft` and `start`'s claim;
  - all three can run from a check at the real root (or in any worktree of it).

  That is the remote-changing path c0650 exists to close. It is reachable only through a wrong implementation, but AC2 accepts that implementation.
- **Why it is plausible:**
  - `new` is the only command the spec drives;
  - review 007 F3 already showed an author putting the refusal at a single place (`publish.commit`);
  - an executor who sees `new`'s two `publishing()` calls may well guard at the call site.
- **Rows missing.** The table still lacks the rows review 007 F3 asked for: P5 "refuse by failing the command" and P6 "no-op success, the stub lost". The case's assertions kill both (`guarded.ok`, and the stub in `git status`), but they are not recorded.
Critique: the Design is right. The check proves it for one of four publishing commands. The tempting fix is a case for every command. That is heavy, because `start` needs a prepared raft with members on origin.
Consequences:
- **A second command in the guarded state.** Under `PICKMAN_PUBLISH=0`, `status` refuses outright (`status needs an origin remote (PICKMAN_PUBLISH=0 disables it)`). So the guarded `status` move fails, with exit 1. The case must therefore assert a refusal, not success.
- **The status message.** It then says `PICKMAN_PUBLISH=0` while the cause is the guard. Review 007 F3 asked for the message to name the guard, and it doesn't. The new case is the natural place to pin that wording.
- **The id.** case 4's `new` prints the stub's path, so its id is available. The case depends on case 4, so it must refuse to run when case 4 didn't finish (the existing `setUp()` pattern, with a second flag).
Recommendation:
- **New case** in `adapt.spec`, after case 4: `a check run publishes no status move either`. It takes probe-two's id from case 4's output (`tracker/issues/(c%d+)/`). It then runs `pickman_fence "$PWD" && bash scripts/tracker.sh status <id> preparing` in `wt`, and asserts:
  - origin's tip is unchanged;
  - HEAD is unchanged;
  - `not publishing` appears in the output.

  It kills the mutant above. Name it in AC2's `cases_pass` list in `c0650/check.sh`.
- **Optionally,** make `status`'s refusal name the guard when `guarded()` is true (`status needs to publish, and this repository is protected by the repository guards`), and assert that line.
- **Rows:**
  - P5 "refuse by failing the command" and P6 "no-op success (stub lost, origin merged)", killed by case 3;
  - P7 "refusal only at `new`'s call site", killed by the new case.

  Mark each `run`, by mutating `proto3` as above.

### F2 [medium] Phase 1 says `proto3-r0210` "may be merged as the starting point". Merged after R0200 really lands, it brings R0200's prototype code and stale documents into the raft branch
Where: R0210.md, Experiments phase ("`proto3-r0210` may be merged as the starting point, since it already holds c0640 and c0650") and Order & dependencies, Execution ("brings in the guard files from the prototype", without saying which prototype)
Evidence:
- **R0200 as a prototype.** `proto3` is `5f7868f` plus R0200's re-prepped *prototype*:
  - the prototype's `scripts/tracker/main.luau` and `publish.luau`;
  - c0510's three specs added under `tests/acceptance/c0510/`;
  - c0510 still in `tracker/issues/c0510/`, not in `done/`.

  When R0210 starts, `main` holds R0200's *real* implementation, with c0510 moved to `done/`. A merge then conflicts in the tracker sources, adds the same c0510 spec files on both sides, and touches the c0510 tree in both places.
- **Stale documents.** `proto3`'s `c0640.md`, `c0650.md` and `c0660.md` are older than the prep's. `diff -r` shows that E30, Design item 3 (still `publish.commit` with a `PICKMAN_FENCE_` entry), the Rules table (`reasoned`) and c0660's rule text all differ. A merge resolved with "theirs" reverts reviewed documents.
- **Silent regression.** Taking `proto3`'s side of `main.luau` replaces R0200's landed code with its prototype. The gate may still pass, so nothing flags it.
- **Local only.** The branch exists only on this machine (SETUP.md describes others).
Critique: the prototype is valuable, but only as a source of files and of one diff. The tempting fix is "merge it and resolve conflicts carefully". That leaves the executor to judge, without guidance, which side of R0200's code wins.
Consequences: listing the files is cheap, but it pins prototype commits (`47fbbb0`, `f20bc43`, `53f8c70`) in the documents. Those are local refs, and must not be deleted before R0210 lands.
Recommendation:
- **Replace "may be merged" with two steps:**
  1. Copy the guard files: `git checkout proto3-r0210 -- <c0640's Touched files>`, listed explicitly. Leave out `scripts/tracker/` and `tests/acceptance/c0510/`.
  2. Apply c0650 as a patch on top of the real R0200 code: `git diff f20bc43 53f8c70 -- scripts/ tests/ .claude/skills/testing/SKILL.md | git apply -3`.
- **Never take `proto3`'s tracker documents.**
- **Execution line:** say which prototype it means, and that the prototype refs must be kept until R0210 lands.
- **Off this machine:** say what to do when the branch is missing: implement from the documents, which are complete.

### F3 [low] Document gaps
Where and fix:
- **Stale "publisher's entry" wording:**
  - R0210.md's diagram says `scripts/tracker/publish.luau publishes nothing from a guarded repo`, and its Order section says c0650 "adds the publisher's entry";
  - c0640.md line 167 says the same ("c0650 narrows c0510's entries and adds the publisher's").
  - c0650 now places the refusal in `main.luau` `publishing()`, with no entry. An executor reading c0640 first may add one. Fix all three.
- **R0210.md Risks:** the bullet "c0510's specs under the guards are not proven in prep (its code doesn't exist yet)" contradicts E30, which was run on `proto3`. Say that they were proven on the prototype and are re-run in Phase 1.
- **c0650 Rules table:** row 3 names the case `adapt :: the publisher pushes nothing …`, but the spec and Test plan call it `a check run publishes nothing, says so, and still works`. Align them.
- **c0660 AC5:** it dropped the negative grep for `in new and edited specs`. Now the old bullet, left in place, passes as long as `c0510` appears anywhere in the skill. The new wording ("convert them when next edited") doesn't contain the old phrase, so restore the negative grep.

Verdict: changes
