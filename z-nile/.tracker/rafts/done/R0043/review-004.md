# Review 004: R0043 (code mode)
Inputs: `impl-r43` at 4509e58, after `git fetch origin`, diffed against `origin/prep-z-nile-home` (33684ef). Fix delta: `01855774..HEAD` (the commit that added review-003), with non-merge commits d72367f, 7d55fb9 and 4509e58, and merges 4ff0ba0 and 4065a3a of the prep. Also read: c0114.md (G2–G5, Overrides, §3 rewrites), R0043.md "Sequestration in this PR", design-review/refute-006, `rewrites.luau`, `finished.luau`, the PR #98 description, and `./zn lessons --when build`.
Dropped from review-003: none (it had no findings).

What I ran and checked:
- `z-nile/check.sh --full`: GATE PASSED (full). 1887 passed, 0 failed, 274 spec files, 82.6 s.
- `bash z-nile/.tracker/issues/c0114/check.sh`: 16/16. `bash z-nile/.tracker/rafts/R0043/check.sh`: 5/5.
- Sequestration with `':(exclude)*/done/*'` over the four item-root globs: 37 `R100` lines, plus the same 2 `D` that earlier rounds accepted (`tracker/templates/{issue,raft}/check.sh`; the templates moved to `z-nile/templates/`). Without the exclusion, all 122 non-`R100` lines are `done/` `check.sh` files: 48 `M` in pickman's root and 74 `A`/`D` pairs for the moved z-nile items.
- `finished.luau <merge-base> <c0114>`: 198 sequestered files, 122 finished ones rewritten, 0 wrong.
- Finished checks run by hand:
  - c0069: 6/6 (the SPECIAL edit).
  - c0044: 11/11.
  - c0077: 6/6.
  - f0020: 4/4.
  - c0002: 3/3.
  - c0058: 9/10. AC6 expects `7 passed` from repo-fence.spec, which has had 8 cases on origin/main too. c0114 §Verification already lists this failure as one that also fails on main, so it is not caused by the rewrite. Not a finding.
- Repository safety (item 8):
  - `ZN_CWD` is read only in `hereDir()`. That function trusts it only when `pwd -P` equals `ZN_TOP`; `zn` sets both from its own location and then `cd`s there. Its only consumer is `projects.inDir`, which picks a project out of the registry the engine has already loaded from `.`. It never becomes a path the engine reads or writes. A fixture that inherits the real checkout's `ZN_TOP` gets "" (roots-cli covers this, mutant R93). A fixture that sets its own `ZN_TOP` can only choose among its own registry's projects. Either way it can't point the engine at the real repository.
  - `.claude/settings.json` adds exactly seven `Bash(./zn <cmd>:*)` allow entries: list, find, members, check, metrics, worktree and worktree-prune. They mirror the existing `scripts/tracker.sh` entries one for one, and nothing broader is added.
  - With the registry missing, the following refuse:
    - `projects.load` raises;
    - `projects.at` returns nil and a reason;
    - `audit.scan` raises;
    - `audit.run` reports `error registry` and stops;
    - `sweepStale`, `worktree-prune`, `lessons.load`, `roots.luau` and `affected.luau` fail;
    - publish refuses an origin/main with no registry;
    - `claims.taken`, `publish.allowed` and `trail.dirs` no longer have a default.
  - `history.parse` and `LOG_ARGS` keep their legacy default, which is §2's listed exception (refute-006 F4). They are parsers of a log they are handed and are fed real roots by `history.load`.
  - I probed a git tree with no registry (in my scratchpad, outside the clone). `list`, `audit` and `new issue` (with `ZN_CWD` set) each refused with "no z-nile/projects.toml … refuses to guess". I found no fail-open path.
  - The delta touches no guard file (`tests/lib/fence.luau`, `z-nile/lib/fence.sh`, `git-hooks/`, the ac.sh fence). Its spec edits only add `--project pickman`, `engine.registry(dir)` (which writes into the fixture `dest` under `.cache`) and explicit roots.
- Behaviour of the fix delta:
  - `projectRoot` refuses at the root and in a folder no project holds.
  - `new issue --raft X --project Y` refuses when the raft's root differs.
  - `new raft` refuses members outside the wanted project, on both paths (publish and offline).
  - `list` follows "list shows all projects": 152 lines at the root and in `src/`, 89 in `z-nile/`, 63 with `--project pickman`.
  - `./zn new issue` outside a worktree still refuses first.
  - The Overrides line names every promoted spec the delta edits (61 in all, plus tests/tooling/claim-taken).
- Lessons (build):
  - exhaustive-lists: the usage text lists `--project` for `new raft` and `list`.
  - plain-find: `inDir` and the list filter use `string.sub` prefixes with `/`.
  - no-live-counts: the finished list is fixed (`rewrites.FINISHED`).
  - pin-call-site-arguments: `--project` and `ZN_CWD` are pinned by roots-cli and layout.
  - None is repeated.

### F1 [low] PR #98's description is stale after the user's 2026-10-21 decisions
Where: PR #98 body, "Needs user: guesses" and "Results"
Evidence:
- Guess 2 says "`.claude/settings.json` is not edited", but d72367f edits it.
- Guess 3 says "`new issue` without `--project` files in `tracker/`", but it now refuses at the root.
- Guess 4 says "A missing registry means the legacy single root and is never refused", but it now refuses.
- Guess 5 says finished `check.sh` files "are left as they are", but 7d55fb9 rewrites 122 of them.
- Results still say c0114 14/14 and sequestration "108 `R100` and nothing else". Today it is 16/16, and the sequestration result needs the `done/` exclusion.
Critique: the user confirms guesses from this description, and four of them state the opposite of what the code now does. The JC1 commit list is still correct, so JC1 is unaffected.
Consequences: none beyond the text.
Recommendation:
- Mark G2–G5 as decided, quoting the user's words.
- Update Results with 16/16, the `done/` exclusion and `finished.luau`'s "122 rewritten, 0 wrong".
- List d72367f, 7d55fb9 and 4509e58 under "Then:".

## Judged criteria (code mode only)
- JC1: pass.
  - The PR description lists the one `c0114: move` commit, 9e178c4, which is still 703 `R100` and nothing else.
  - Every non-merge commit since then shows only `M` or `A` under `git show -M --find-renames=100% --name-status`: d72367f is 51 M, 7d55fb9 is 122 M, 4509e58 is 11 M, and the review and refute commits are A/M.
  - So no other commit moves a file. The finished-file rewrites are edits at the files' new paths, made after the renames-only commit, as §3 requires.
  - The two merges bring only the prep's own A/M changes.

Verdict: approve
