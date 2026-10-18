# Review 001: R0032 (code mode)
Inputs: 00301673d883090ddadd78cd3a9a58fa31a8ce0e (`git diff origin/main...HEAD`, origin/main at 309cb2f after `tracker.sh sync --fetch`); R0032.md and its check.sh; c0064.md, its check.sh and acceptance specs.

Checks run by the reviewer:
- `scripts/check.sh --full`: GATE PASSED (full). stylua clean; selene reported 0 errors, 0 warnings and 0 parse errors; both luau-lsp passes were clean; both Rojo builds succeeded; 1600 passed, 0 failed, 229 spec files.
- `scripts/tracker.sh check c0064`: 8/8 criteria passed.
- Sequestration: `git diff --find-renames=100% --name-status origin/main...HEAD -- 'tracker/**/check.sh' 'tracker/**/acceptance/**'` lists nothing.
- Design adherence: `git apply --check -R experiments/prototype.patch` succeeds, so the tree is exactly the prototype the three design reviews approved. The narrowed c0015 and c0003 cases match the Overrides list, and nothing else in those specs changed. The loosened c0015 secret guard (any step from the fifth whose `run` contains `lune run scripts/runtime-test -- `) is covered by `c0064/workflow.spec`, which pins all six steps, each runtime step's exact `run` and `env`, and exactly three mentions of the secret.
- Repository safety, against the testing skill's "Caught only by review" list:
  - Linux unjailed writes: none. No spec added here writes the checkout. `deploy-beta` writes only to `mktemp -d` and to `$GITHUB_OUTPUT`, and `c0064/deploy.spec` points `$GITHUB_OUTPUT` at a `.cache` fixture.
  - `check.sh` files' own commands: unchanged by this branch (sequestered). They run `tests/run`, `tracker.sh members/find/promote-check` and `git diff --quiet`, all read-only.
  - Handing work to a process outside the jail: none (no `open`, `osascript`, `launchctl` or daemon).
  - Leaving the process group: none (no `setsid` or double fork).
  - Signalling the runner: none.
  - Pids above 99999: not applicable.
  - Guard files (`tests/lib/fence.luau`, `scripts/lib/fence.sh`, `scripts/lib/git-hooks/`, `scripts/lib/ac.sh`, `tests/tooling/repo-fence.spec.luau`): untouched.

### F1 [low] The rewritten `$path`s and project paths contain `//`, because `process.cwd` ends in a slash
Where: scripts/deploy-beta.luau:34-42 (`root = process.cwd`, `` `{root}/{target.project}` ``, `Beta.project(..., root, ...)`); scripts/lib/beta.luau:95-100 (`absolute`)
Evidence: under Lune, `print(process.cwd)` in this worktree prints `/Users/philipbergen/code/pickman/.worktree/R0032/`, with a trailing slash. So `absolute(dir, "src/shared")` gives `.../R0032//src/shared`, and the source path is `.../R0032//default.project.json`. POSIX treats `//` inside a path as `/`, so both builds are correct, and the gate and `project.spec` (which compares the built places) pass. The doubled slash does show up in the project copy and in any Rojo error the deploy prints (`rojo build failed (<project>):` plus Rojo's output).
Critique: this is cosmetic today. The tempting fix is to strip the slash in `deploy-beta` only. That leaves `Beta.project`'s contract ("`dir` absolute") open to the same wart from any other caller, for example f0065 or a third place.
Consequences: normalizing inside `absolute` keeps existing absolute `$path`s unchanged and needs no spec change. `project.spec` compares built places, not path text, so it stays green.
Recommendation: in `scripts/lib/beta.luau`, trim one trailing `/` from `dir` before joining (for example `string.gsub(dir, "/$", "")` inside `absolute`, or once in `Beta.project`). In `deploy-beta`, build `source` from the same trimmed root. This doesn't block approval.

## Judged criteria (code mode only)
None.

Verdict: approve
