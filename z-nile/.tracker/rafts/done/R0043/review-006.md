# Review 006: R0043 (code mode)
Inputs: `impl-r43` at 528db73 (PR #98 head, base `main`, draft), after `git fetch origin`; `origin/main` is f6fd92c, which the branch does not yet hold (merge-base 5de93de). Fix delta `febae35..528db73`: 54f0226, 5fdf51e, 508522e (review/refute 005), 6c7a3f0, and the merges 6fbd3ec and 528db73. Also read: review-005, refute-005, c0114.md (§11, the Rules and mutants row R112, step 9, JC1), R0043.md's "Sequestration in this PR", `window-new-raft.spec.luau`, the PR #98 description, and `./zn lessons --when build`.
Dropped from review-005: none. F1, F2 and F3 are fixed as refute-005 says (checked below).

What I ran and checked:
- `z-nile/check.sh --full`: GATE PASSED (full). 2041 passed, 0 failed, 299 spec files, 126.9 s. Lint: 0 errors, 0 warnings, 0 parse errors. No repository tripwire fired in any run.
- c0114's `check.sh` (16 `check` lines): 16/16. R0043's `check.sh`: 5/5.
- `finished.luau`: `194 sequestered files, 130 finished ones rewritten, 0 wrong`, both against the merge-base 5de93de and against origin/main's tip f6fd92c.
- Sequestration, three-dot against origin/main over the four item-root globs:
  - With `':(exclude)*/done/*'`: 40 `R100` (37 before, plus c0122's, c0123's and c0127's `check.sh`), and the same 2 `D` earlier rounds accepted (`tracker/templates/{issue,raft}/check.sh`).
  - Without the exclusion: 74 `A`, 76 `D`, 56 `M` and 40 `R100`. Every non-`R100` line outside `done/` is one of the two template `D`s. The 56 `M` are the 54 before plus R0034's and f0065's.
- 6c7a3f0 is 2 `M`: path rewrites only (`scripts/lib/ac.sh` becomes `z-nile/lib/ac.sh`, `scripts/check.sh` becomes `z-nile/check.sh`, `scripts/tracker.sh` becomes `./zn`, and the comments follow).
  - By hand: R0034's non-gate lines give 4/4 (f0065's members check, promote-check, RC1 three times, RC2). f0065's `check.sh` gives 6/6.
- 54f0226 is 8 `R100` and nothing else.
- Merges:
  - 6fbd3ec has no hand-resolved file.
  - 528db73 resolved one conflict, `.claude/skills/ticket-prep/lessons/never-narrow-captured-scope.md`. It kept main's new R0044 paragraph and the branch's `./zn` wording. The remerge diff removes only the conflict markers and the old `scripts/tracker.sh` line.
- `.claude/settings.json`: the only change against origin/main is the 7 `./zn` entries (`list`, `find`, `members`, `check`, `metrics`, `worktree`, `worktree-prune`).
- Classification of what main captured since the prep:
  - c0122, c0123 and c0127 are tooling (the ref guard, the fence, the runner's lock) and are in `z-nile/.tracker/`.
  - c0128, c0129, c0130, d0124, f0125, f0126, R0044 and R0045 are game items and are in `tracker/`. c0130 ("R0035 remotes after lobby") was not in the brief's list, and is correctly the game's.
  - R0046 (c0129, game) and R0047 (c0127, tooling) are on origin/main after 528db73 and not yet on the branch: see F1.
- 5fdf51e (F1 and F2 of review-005):
  - `new raft` now calls `projectRoot`, then `refuseStale`, then `refuseInWindow`.
  - Offline, both `new issue` and `new raft` say "origin/main as last fetched…". Publishing, they keep the old text. `fail` is `never`, so the two calls cannot both run.
  - My mutants, in the clone, reverted:
    - Moving `refuseInWindow` back before `refuseStale` is killed: "right after the landing…" fails with "c0114 has not landed".
    - Dropping the offline branch is killed: the same case fails on the "as last fetched" needle.
  - The new spec's fixture is `.cache/window-new-raft`, and its identity is `@example.invalid`. It only reads `z-nile/projects.toml` from the repository.
- Repository safety: the delta touches no guard file (`tests/lib/fence.luau`, `scripts/lib/fence.sh`/`z-nile/lib/fence.sh`, git-hooks, ac.sh's fence, `repo-fence.spec`).
- Lessons (build):
  - seed-every-enumerated-case: holds now for `new issue`/`new raft` × offline/publishing.
  - plain-find: holds.
  - grep-preps-for-removed-names: R0045–R0047's new `check.sh` files name `scripts/…`, which forwards.
  - no-vacuous-pass: see F1.

### F1 [medium] R0047, a tooling raft on main for c0127, arrives in pickman's `tracker/` at the next merge, and nothing flags a raft whose member is in another project
Where:
- origin/main f6fd92c, `tracker/rafts/R0047/` ("Test lock pid reuse", `issues: [c0127]`, status `preparing-walrus-violet-lucky`).
- 54f0226 (c0127 moved to `z-nile/.tracker/issues/c0127/`).
- c0114 step 9.
- `z-nile/engine/audit.luau` (no check that a raft and its members share a root).
- `classified.spec.luau` (fixed slug lists).
Evidence: in the clone, on a throwaway branch, I merged origin/main into 528db73. The merge is clean, and then:
- `R0047` is at `tracker/rafts/R0047`, its member c0127 is at `z-nile/.tracker/issues/c0127` (main's status edit followed the rename), and c0114's AC10 cannot see it, because its lists are fixed slugs.
- `./zn audit` gives `0 errors, 1 warnings` (only the counter warning).
- With c0127's `raft: R0047` set, as R0047's prep will set it, `./zn members R0047` lists `z-nile/.tracker/issues/c0127` and audit is still 0 errors. So the pickman raft passes every member check while it sits in the wrong project.
- The engine refuses exactly this shape at `new raft` ("a raft holds issues of one project…", Rules and mutants R15). But a raft that arrives by merge, which is how every capture reaches this branch until c0114 lands (the main checkout's engine has no roots), is never checked.
Critique:
- This is the second round in which the step-9 classification depends on someone rereading `./zn list` after each merge (review-005 F3 was c0122, c0123 and c0127 themselves).
- The tempting fix is one more `c0114: move R0047` commit. It is needed, but it fixes this instance only. Every merge until landing can bring another tooling raft or issue, and so can R0047's own prep PR: it was started on main's engine and writes under `tracker/rafts/R0047/`.
Consequences:
- An audit rule that a raft and its members share a root must exempt R0001: it is finished and decided cross-project (c0114 §9: it "stays in `tracker/` with its game member").
- So the rule applies to unfinished rafts, or exempts `done/`. Either way it must read membership both from the raft's `issues:` and from each issue's `raft:` field (a prep raft has an empty `raft:` field, as R0047 has today).
- Moving R0047 also moves its `check.sh`, which names `scripts/lib/ac.sh` and `scripts/tracker.sh`. Both forward, so it is still an `R100` rename.
Recommendation:
- At the step-9 merge, move R0047 in a renames-only commit, `c0114: move R0047 into z-nile/.tracker/ (renames only)`, and list it under JC1.
- Tell R0047's prep, which is in flight, that c0127 and R0047 now live in `z-nile/.tracker/`, for example in the PR description or a note in R0047.md on main.
- Add an audit error, for example `raft-spans-projects <R-id>: <id> is in <root>, not <root>`, for an unfinished raft whose `issues:` or whose members' `raft:` name an item in another root. Pin it in a non-sequestered tooling spec under `.cache/<unique>` with these cases:
  - a backlog pickman raft with a z-nile member is an error;
  - the same with the link only in the issue's `raft:` field is an error;
  - a same-root raft is clean;
  - a `done/` raft spanning two roots (R0001's shape) is clean.
  Then the next merge that brings a misfiled item fails `./zn audit` (AC12, RC2) instead of relying on a reread.

### F2 [low] The offline window message calls `./zn sync` a fetch, but in a branch worktree it merges origin/main
Where: z-nile/engine/main.luau, `refuseInWindow`'s offline message ("fetch (./zn sync) if c0114 has landed"). `cmd.sync` (line 1246) calls `mergeOrigin()` unless `--fetch` is given.
Evidence:
- The message is printed only in a worktree, because the main checkout's engine predates the registry.
- Run there, `./zn sync` runs `git merge --no-edit origin/main` into the branch.
- If that merge fails, the user sees "published, but merging origin/main failed…", although nothing was published.
- `./zn sync --fetch` is the fetch-only form, and it is all `refuseInWindow` needs to see the landing.
Critique: an agent following the hint in the middle of work gets a merge commit it did not ask for (or a misleading error) when it wanted only a fresh `origin/main`.
Consequences: none beyond the string. window.spec's needle and window-new-raft's "fetch (./zn sync" needle would need the new text, and the latter is not sequestered.
Recommendation: say "fetch (`./zn sync --fetch`) if c0114 has landed". Update window-new-raft.spec's needle to match, and check that window.spec's sequestered needle ("capture from the main checkout until it does, never offline here") is still in the message.

## Judged criteria (code mode only)
- JC1: pass.
  - The PR description lists both `c0114: move` commits: 9e178c4 (703 `R100`, nothing else) and 54f0226 (8 `R100`, nothing else).
  - Every other non-merge PR commit since origin/main shows only `A`/`M` under `git show -M --find-renames=100% --name-status`. In the delta, 5fdf51e is 1 A and 1 M, 508522e is 2 A and 2 M, and 6c7a3f0 is 2 M.
  - The two merges in the delta move nothing of the PR's own. 528db73's one hand-resolved file is an edit in place.
  - F1's R0047 move is still to come and must be listed when it is made.

Verdict: changes
