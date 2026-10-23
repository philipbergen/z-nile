# Review 003: c0120 (code mode)
Inputs: `impl-c0120` at 7ca91ef (fix delta `c4e9c49..HEAD`: 4171346 the clean read and fail-closed, f703737 merge of prep's ce5420b, 7ca91ef refute and log), `git diff origin/prep-c0120...HEAD` (origin/prep-c0120 at ce5420b), review-001/002 and refute-001/002, c0120.md (Rules and mutants, Verification log), `./zn lessons --when build --full`. Runs: `z-nile/check.sh --full` GATE PASSED (pickman 1068/157, z-nile 835/120, 136.5 s). `bash z-nile/.tracker/issues/c0120/check.sh`: 14/17. Sequestration against origin/prep-c0120 over the item roots' `check.sh` and `acceptance/`: 103 files, all R100. Scratch reproductions in `/private/tmp/claude-501/-Users-philipbergen-code-pickman/de5efc35-2bcd-47ee-b2a5-bc31e5be44c7/scratchpad/code-review-c0120-003/` (clone of 7ca91ef; `probe.sh` from review 002; `fence-old.sh` = 429e248, `fence-r2.sh` = c4e9c49, `fence-new.sh` = 7ca91ef, `fence-x5.sh` = X5's mutant; `fake-empty/git`, `fake-wrap/git`, `nohooks/`, `gcfg`, `home/`, `xdg/`).
Dropped from review-002: F1, F2 (both fixed; verified below).

## Repository safety: the clean read, verified
`probe.sh <clone> <fence> <home>` fences from `<home>` in specs mode, prints `PICKMAN_FENCE_REAL_GIT`, then tries `git -C <clone> update-ref`.

| inherited | from | 429e248 | c4e9c49 | 7ca91ef |
|---|---|---|---|---|
| none | `pickman/` | clone, REFUSED | clone, REFUSED | clone, REFUSED |
| `GIT_DIR=.git` (round 1) | `pickman/` | `::`, **ESCAPED** | clone, REFUSED | clone, REFUSED |
| `GIT_DIR=<foreign>/.git` (round 1) | root | foreign, **ESCAPED** | clone, REFUSED | clone, REFUSED |
| `GIT_CEILING_DIRECTORIES=<clone>` (round 2) | `pickman/` | `::`, **ESCAPED** | `::`, **ESCAPED** | clone, REFUSED |
| `GIT_COMMON_DIR=<foreign>/.git` | `pickman/` | foreign, **ESCAPED** | clone, REFUSED | clone, REFUSED |
| ceiling and `GIT_DIR=.git` | `pickman/` | `::`, **ESCAPED** | `::`, **ESCAPED** | clone, REFUSED |

Both old escapes reproduce against their fences, and the new fence refuses both. Every other variable below was run against 7ca91ef from `pickman/` and from the root. Each recorded the clone and REFUSED:
- `GIT_DISCOVERY_ACROSS_FILESYSTEM` set to 0 or 1;
- `GIT_WORK_TREE=<foreign>`, alone and with `GIT_DIR=<foreign>/.git`;
- `GIT_INDEX_FILE`, `GIT_OBJECT_DIRECTORY=<foreign objects>` and `GIT_NAMESPACE`;
- `GIT_CONFIG_PARAMETERS` with `core.hooksPath=<permissive hooks>`, and with `core.worktree=<foreign>`;
- `GIT_CONFIG_COUNT=1` with `core.hooksPath`, and a stale `GIT_CONFIG_KEY_11` under `GIT_CONFIG_COUNT=12`;
- `GIT_CONFIG_GLOBAL`, `GIT_CONFIG_SYSTEM`, `HOME/.gitconfig` and `XDG_CONFIG_HOME/git/config`, each with `core.hooksPath=<permissive hooks>` and `safe.directory=*`. The fence's `GIT_CONFIG_COUNT` entries outrank every file;
- `GIT_EXEC_PATH=<empty folder>`. `rev-parse` and `update-ref` are builtins, and the hooks are found through `core.hooksPath`;
- a `git` wrapper first on PATH that passes through: REFUSED. A fake `git` that answers `rev-parse` with nothing and exit 0 makes the fence refuse ("is in no git repository"), in both places. That is the fail-closed rule working.

So the mechanism review 002 questioned now holds. There is one read, it is clean, and an empty answer refuses. The runner's side matches. `git()` in `tests/lib/fence.luau` drops the ceiling. `protectedPaths` and `fixtureOfGuarded` ignore an empty answer, and when the ceiling-free read reaches further, both get stricter, never looser. `fence.enter` refuses before the snapshot, and the shell fence would refuse after it anyway. Without the ceiling, the read from a fixture with no repository stops at the sentinel and fails. Where the jail refused the sentinel, it reaches the real checkout and protects it. Both are safe.

An inherited `PICKMAN_FENCE_HOOKS` that names a folder of permissive hooks still escapes, under every one of the three fences. That is c0114's unchanged "the first guard's hook stays in force" rule, already raised in review 002 for the lead to capture. No tool sets it except the fence itself. It is not a finding of this round.

### F1 [low] `pickman_guarded` now answers for a different repository from the one its caller's git changes when the caller sets `GIT_DIR` explicitly
Where: `z-nile/lib/fence.sh:189` (`_pickman_fence_git rev-parse …` in `pickman_guarded`); Rules row X6.
Evidence: in the scratch clone, fence the root (`PICKMAN_FENCE_REAL_GIT=<clone>/.git`), `cd .cache/fx` (its own repository), `export GIT_DIR=<clone>/.git`, then `pickman_guarded "$PWD"`.
- c4e9c49 prints `guarded`.
- 7ca91ef prints `unguarded`, while `git rev-parse --git-common-dir`, which is what the publisher's own git sees, is `<clone>/.git`.
So the tracker would publish, and its git would act on the protected repository. The reference-transaction hook still refuses the refs, and in a spec run pre-push and `protocol.allow` refuse the push. A `git add` or `git commit` could already have written that repository's index and objects, though.
Critique: review 002 found that `pickman_guarded` reading with the caller's environment was right, because the answer was then about the repository the publisher would change. The ceiling case never needed it changed: from the root git always searches the folder it starts in, and from `pickman/` a failed read returns 1, which is guarded. The fix delta swapped one blind spot for another. No inherited path reaches it: the fence unsets an inherited `GIT_DIR` before anything runs, so only a spec or check.sh that sets `GIT_DIR` itself gets there. That needs a repo-fence `ALLOWED` entry, and review would catch it. Hence low. The tempting fix is to revert to plain `git`, but X6 now pins the clean read.
Consequences: making both reads ask means "unguarded" needs two successful reads that each name an unprotected repository. A failed environment read (a ceiling at the root, entered from `pickman/`) then answers guarded. That is already the behaviour, and it is fail-closed. c0114's unguarded-fixture publish cases are unaffected, because both reads agree in a plain fixture.
Recommendation: in `pickman_guarded`, answer `guarded` when either the clean read or the caller's-environment read names a repository in `PICKMAN_FENCE_REAL_GIT`, return 1 when either read fails or is empty, and answer `unguarded` only otherwise. Add an unsequestered case to `fence-inherited-env`: a fixture repository under a fenced checkout, with `GIT_DIR=<checkout>/.git` set, must answer `guarded`. Its mutant is "clean read only", which is today's code.

### F2 [low] The "in every mode" case never runs checks mode, and X5 is called equivalent although a stub git kills it
Where: `tests/tooling/fence-inherited-env.spec.luau:151` ("a fence whose read finds no repository refuses, in every mode"); Rules rows X2 and X5.
Evidence:
- The case loops over `specs` and `checks`. It runs inside a spec run, so `PICKMAN_FENCE_SPECS=1` is inherited (fixture.exec merges the environment), and `pickman_fence_env` line 63 turns `checks` into `specs`. Both iterations test the same mode. Run by hand with `env -u PICKMAN_FENCE_SPECS`, checks mode refuses too. The code is right; only the case claims more than it runs.
- X5: with `fake-empty/git` first on PATH (it answers `rev-parse` with nothing and exit 0), the shipped `pickman_guarded` returns 1, which is guarded. `fence-x5.sh` prints `unguarded` with exit 0: `cd ""` is a no-op, so `pwd -P` gives the caller's folder. That is the one answer that publishes.
Critique: the X5 claim is true for a real git, which never answers `--git-common-dir` with an empty success, so the line can't be reached there. But it isn't an equivalent mutant. A PATH stub reaches the line, and that is cheap in a fixture shell. Since its removal flips the one explicit "no", it deserves a case rather than "reasoned".
Consequences: the case must clear `PICKMAN_FENCE_SPECS` (and `PICKMAN_TEST_FENCE`) for its checks-mode iteration, or the shell must `unset` them. A stub git on PATH needs no new repo-fence `ALLOWED` entry unless it names a fence variable.
Recommendation: in `fence-inherited-env`, run the checks-mode iteration with `PICKMAN_FENCE_SPECS` unset, and add a case where a stub `git` that prints nothing for `rev-parse` sits first on PATH: `pickman_guarded` must not print `unguarded`, and `pickman_fence` must refuse. Mark X5 `run: killed`.
Lesson: testing/specs-set-host-markers-explicitly

## Judged criteria (code mode only)
- JC1: pass.
  - `git show -M --name-status 1fec94f` is still 632 entries, all R100.
  - The fix commits have no renames: 4171346 (1 A `fence-inherited-env.spec.luau`, 4 M) and 7ca91ef (1 A `refute-002.md`, 1 M).
  - Against origin/prep-c0120, `git diff -M100% --name-status … | grep -v '^R100'` lists 104 paths. These are review-002's 102 plus the new spec and `refute-002.md`, both named in the log.

## The three expected reds
- AC11: the one failure is `z-nile/.tracker/issues/c0114/check.sh: z-nile/next (from .)`, because c0114 is unfinished, as claimed.
- AC16: `./zn busy tracker src tests` prints `raft R0034 is active`, and the AC lists other branches that change the old paths. This is the freeze, as claimed.
- AC17: `R0012 is at pickman/.tracker/rafts/R0012, not done`, as claimed.

## Candidate lesson (for the lead)
- testing: when a fix moves a guard's read into a clean environment, check each reader's purpose first. A guard that answers "is the repository I am about to change protected?" must read the way the changer's own git will, as well as the clean way, and protect when either names a protected repository. This is c0120 code review 003 F1, after review 002. Check: for each read moved into the clean environment, does its caller then act through git with the caller's own environment?

Verdict: approve
