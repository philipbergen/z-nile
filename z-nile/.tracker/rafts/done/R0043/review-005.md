# Review 005: R0043 (code mode)
Inputs: `impl-r43` at febae35 (PR #98 head), after `git fetch origin`, against `origin/prep-z-nile-home` (a9a491b, the PR base) and `origin/main` (f50a610). Fix delta: `4509e58..febae35`, which is merge c49de20 (the prep, which brought in main) plus the non-merge commits 4fd536e, f7144d6 and febae35. Also read: c0114.md (§9, §11's "execution window", the Rules and mutants row for R111), `window.spec.luau`, R0043.md's "Sequestration in this PR", review-004 and refute-004, the PR #98 description, and `./zn lessons --when build`.
Dropped from review-004: none (F1 is fixed: the PR description now marks G2–G5 as decided and its Results are current).

What I ran and checked:
- `z-nile/check.sh --full`: GATE PASSED (full). 1979 passed, 0 failed, 290 spec files, 130.5 s. Lint: 0 errors, 0 warnings, 0 parse errors.
- `bash z-nile/.tracker/issues/c0114/check.sh`: 16/16. `bash z-nile/.tracker/rafts/R0043/check.sh`: 5/5.
- `finished.luau f50a610 <c0114>`: `189 sequestered files, 128 finished ones rewritten, 0 wrong`.
- Sequestration, three-dot against the PR base, over the four item-root globs:
  - With `':(exclude)*/done/*'`: 37 `R100`, plus the same 2 `D` that earlier rounds accepted (`tracker/templates/{issue,raft}/check.sh`, whose templates moved to `z-nile/templates/`).
  - Without the exclusion, every other non-`R100` line is a `done/` file: 54 `M` (48 before, plus the six new ones) and the 74 `A`/`D` pairs of the moved z-nile items. This is what R0043.md's paragraph allows.
- The six newly finished checks, run by hand: R0012 7/7, R0041 3/3, c0106 3/3, f0027 5/5, f0028 3/3, f0029 5/5. c0069 is 6/6 after its label edit.
- f7144d6 changes only paths: `scripts/lib/ac.sh` becomes `z-nile/lib/ac.sh`, `scripts/check.sh` becomes `z-nile/check.sh`, and `scripts/tracker.sh` becomes `./zn`. c0069's change is a label only (AC6's text, not its commands).
- What the main merge brought (5bfb7f6..f50a610, outside `tracker/`):
  - Game code: `src/client/HudView`, `Main.client`, `Logic/Hud`, `Logic/Touch`.
  - Game specs: `tests/unit/{Hud,Touch}`, `tests/place/touch-adapters`, and the promoted `tests/acceptance/{c0106,d0105,f0027,f0028,f0029}`.
  - None of these names a tooling path, `scripts/`, `tracker/` or `z-nile/`. c0106's only "tracker" is a comment and a case title about id normalisation.
  - So no spec from main conflicts with c0114's overrides or with the new layout, and the full gate is green with all of them.
- `refuseInWindow`:
  - It fires only when origin exists, `origin/main` resolves locally, and `projects.at("origin/main")` reports exactly "has no z-nile/projects.toml".
  - After the landing, `projects.at` returns the registry (or a parse error, which does not contain that text), so it cannot misfire once the local `origin/main` holds the registry. The exception is a stale ref: see F2.
  - `PICKMAN_PUBLISH=0` does not skip it, and nothing else in the environment reaches it: it reads neither `PICKMAN_*`, `ZN_*` nor the fence.
  - Two ways it stays silent, judged not findings:
    - A tree with no origin remote, which is not the window: there is no main to collide with.
    - An origin whose `main` was never fetched. Every worktree of the real repository shares the main checkout's refs, so this never happens there.
  - A fixture under `.cache` with its own origin can only change its own numbers.
  - The publish path's hint is dropped only for the "has no registry" reason. Plain find (`1, true`) is used in both places.
- Mutant (my own, in the clone, reverted): I deleted `refuseInWindow("new raft")`.
  - With `PICKMAN_PUBLISH=0` in the window fixture, `new raft chore probe c0050 --project pickman` then succeeds and writes `tracker/rafts/R0011/R0011.md`, numbered from the local `tracker/next`.
  - The full suite stays green with it: 1979 passed, 0 failed, and window.spec has 4 passed. See F1.
- Stale-ref probe (in the clone, reverted): in the window fixture, origin gains the registry ("c0114 lands") and the worktree does not fetch. `new raft …` with publishing on, and `new issue …` with `PICKMAN_PUBLISH=0`, both refuse with "c0114 has not landed". See F2.
- JC1 and the delta's file kinds:
  - 9e178c4 is still 703 `R100` and nothing else.
  - The PR's commits since 4509e58 show only `A` and `M` under `git show -M --find-renames=100% --name-status`: 4fd536e is 2 M, f7144d6 is 7 M, febae35 is 2 A and 1 M, and the prep's a9a491b is 2 A and 5 M.
  - The commits from main that came in by merge are on origin/main, so they are not the PR's.
- Repository safety: the delta touches no guard file. 4fd536e only reads (`git rev-parse`, `git ls-tree` and `git show` through `projects.at`). My probes ran under `tests/run`, in `.cache` fixtures of the scratch clone.
- Lessons (build):
  - plain-find: holds.
  - one-reader-per-format: holds (`refuseInWindow` reuses `projects.at`).
  - testing/seed-every-enumerated-case: repeated (F1).

### F1 [medium] `new raft`'s window refusal has no spec: deleting it keeps the whole suite green
Where: z-nile/engine/main.luau:913. c0114.md, Rules and mutants row "no capture on the branch in the window, offline included" (R111 covers `new issue` only). window.spec.luau, case "in the window the branch publishes nothing…".
Evidence:
- With `refuseInWindow("new raft")` removed and `PICKMAN_PUBLISH=0`, `./zn new raft chore probe c0050 --project pickman` exits 0 and writes `tracker/rafts/R0011/R0011.md`.
- R0011 is the number `tracker/next` ("raft 11") gives main's next `new raft`: the collision §11 says cannot arise.
- `lune run tests/run` (all 290 files) stays 1979/0, and window.spec stays 4/4.
- window.spec drives only `new issue` (with and without publishing), `status` and `renumber`.
Critique: c0114 §11 makes `new issue` and `new raft` refuse in the window, offline included. Only one of the two call sites is pinned, so the other can be lost in a refactor (for example, folding the refusal into `projectRoot` for issues only) without any test going red. The tempting fix is to add a `new raft` line to window.spec, but that spec is sequestered.
Consequences:
- A new spec has to build the same pre-c0114 fixture (origin without the registry, a branch with it).
- It should also pin the order relative to `projectRoot`: at the root without `--project`, which refusal wins? Today it is the window's.
Recommendation:
- Add a non-sequestered spec, for example `tests/tooling/window-raft.spec.luau` under `.cache/<unique>`, reusing window.spec's setup.
- In the window, `new raft chore x c0050 --project pickman` refuses:
  - with `PICKMAN_PUBLISH=0`;
  - with publishing on.
- Both refusals carry "capture from the main checkout until it does, never offline here" and not "PICKMAN_PUBLISH=0 creates it locally". No `rafts/R0011` appears, and origin's `tracker/next` and tip are unchanged.
- Add the Rules and mutants row for `new raft` (call it R112) and run it.
Lesson: testing/seed-every-enumerated-case

### F2 [low] Right after the landing, `refuseInWindow` misfires on a stale `origin/main` and says "c0114 has not landed"
Where: z-nile/engine/main.luau:783–793 and 913–916, where `new raft` calls `refuseInWindow` before `refuseStale`, the only step that fetches.
Evidence: in the window fixture, origin gains `z-nile/projects.toml` and the worktree does not fetch. Then:
- `new raft chore probe c0050 --project pickman` with publishing on refuses with "origin/main has no z-nile/projects.toml (c0114 has not landed): capture from the main checkout…".
- `new issue c probe --project pickman` with `PICKMAN_PUBLISH=0` refuses the same way.
- `new issue` with publishing on is not affected, because `refuseStale` fetches before the check.
Critique:
- It fails closed and recovers after any fetch (`./zn sync`), so nothing is created wrongly.
- But in the publishing case the command never consults origin, although it is about to publish there.
- And the message points to a cause that is no longer true.
Consequences: fetching inside `refuseInWindow` would add a network call to the offline path, which by design makes none.
Recommendation:
- In `new raft`, call `refuseInWindow` after `refuseStale`, so a publishing run decides on a fresh ref. `projectRoot` still runs first, so its refusal at the root without `--project` is unchanged.
- Offline, keep the check and change the message to "origin/main as last fetched has no z-nile/projects.toml: fetch (./zn sync) if c0114 has landed, otherwise capture from the main checkout…".
- Add a spec case in F1's new spec: landing, no fetch, publishing `new raft` succeeds.

### F3 [low] Two tooling items captured since the prep are still in pickman's root and not named in the PR
Where: `tracker/issues/c0122/`, "Ref guard accepts a fetch with nothing new", and `tracker/issues/c0123/`, "Fence trusts only its own ref guard hooks". Both came in with c49de20. c0114 §9 and step 9.
Evidence:
- Both change the repository guards, which §9's rule makes z-nile's.
- The PR description does not mention them, and no `c0114: move` commit for them exists yet. AC10 passes only because it pins the prep's classification.
- f0125, f0126 and d0124, the other new captures, are game items and correctly stay.
Critique: step 9 places this move before `done`, so it is not yet late. But the moves will then land after the final review round, and JC1 requires every `c0114: move` commit to be listed.
Consequences: none beyond step 9's own rule. Each move is a renames-only commit, and their `check.sh` files keep `scripts/lib/ac.sh`, which forwards.
Recommendation:
- Record c0122 and c0123 in the PR description now, as tooling items to move.
- At step 9, move them in `c0114: move c0122 c0123 into z-nile/.tracker/ (renames only)`, list that commit under JC1, and confirm it with `git show -M --find-renames=100% --name-status`.

## Judged criteria (code mode only)
- JC1: pass.
  - The description lists the one `c0114: move` commit, 9e178c4, which is still 703 `R100` and nothing else.
  - Every other PR commit since then is `A`/`M` only, so none moves a file: 4fd536e is 2 M, f7144d6 is 7 M, febae35 is 2 A and 1 M, and a9a491b is 2 A and 5 M.
  - The finished-file rewrites are edits at the files' new paths.
  - F3's moves are still to come and must be listed when they are made.

Verdict: changes
