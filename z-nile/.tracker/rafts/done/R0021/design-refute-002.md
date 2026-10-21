# Answers to design review 002 (R0021)

The damage the review found (the shared `user.email=e2e@example.invalid`, `refs/heads/leaked`, two test commits on `prep-check-isolation`) was repaired at the user's go-ahead: the local identity was unset, `leaked` was deleted, and the prep branch was rebased without the two commits and re-authored. Its cause, my run of `fence.spec` against main's unguarded runner, is F1 below.

- F1: fixed:
  - **Specs guard themselves**. Every git call in both c0058 specs goes through `git(dir, …)`, which refuses unless `git rev-parse --show-toplevel` in `dir` is `dir` itself. Cleanup uses `gitTry`, which has the same check.
  - **Probes check first**: each probe file refuses to load unless its repository is the fixture.
  - **Setup gates every case**: every case refuses to run unless setup finished (`setUp()`). The fixture repositories have no local identity, and the line that leaked the identity (writing it back after a case) now unsets it in the checked fixture.
  - **Experiment E12**: both specs run against main's unguarded runner in a clone under `/tmp`. Every behaviour case failed on its own assertion, and the clone's config, refs, HEAD and status were byte-identical before and after. So even with no guards, the specs no longer write outside their fixtures.
  - **New rule** (testing and ticket-prep skills): specs run against code without the guards (prototyping them, or a branch from before them) run only in a clone under `$TMPDIR`, outside every repository.
  - **The repair** was done before any further run.
- F2: fixed:
  - A top-level run refuses to start when the repository's effective `user.email` is a fixture identity, naming it and the repair (`fence :: a repository whose git identity is a fixture's is refused before any spec runs`).
  - Fixture repositories in the c0058 specs no longer carry a local identity; they commit with `-c`.
  - Consequences: other specs' fixtures keep their local fixture identity, and that is fine. Their nested runs (`tracker.sh done` → `tests/run` inside a fixture) are guarded runs, which never make this check.
- F3: fixed, by design rather than by wording alone:
  - **The jail**: on macOS a top-level run now runs its specs under `sandbox-exec`, with every write to the checkout, the main checkout and the shared git directory denied by the kernel, except the checkout's `.cache`. Spiked first: commit, config, `reset --hard`, `checkout --detach`, `remote add`, branch, a plain file write and a write into `.git` were all denied; fixtures in `.cache` and `/tmp` worked; the full gate passes jailed (638 passed, 22.9 s).
  - **The gate spec proves it** with harmless probe writes, which must fail (`repo-fence :: on macOS this run can write nothing in the checkout outside .cache`).
  - **macOS can't nest sandboxes** (spiked: `sandbox_apply: Operation not permitted`). A run already inside one says so and continues under the outer sandbox and the environment guards (`fence :: a run inside a sandbox says it is not jailed again, and still runs guarded`).
  - **The wording**: the testing section now says exactly what the ref guard does (refuses the ref change; the index and files may already be rewritten). Its "Caught only by review" list names the remaining gaps: unjailed runs on Linux (`add`, `checkout`, `reset --hard`, `worktree remove`, `remote set-url`, plain writes), `check.sh` files' own commands, and runs inside another sandbox. AC8 pins the "Jail" and `$TMPDIR` text.
- F4: fixed: the ref guard allows a fetch (every updated ref under `refs/remotes/`, created or moved, none deleted), and still refuses deletions, which is what `remote rm` does. So `scripts/ci-verify.sh` in c0001's AC3 works. Case: `fence :: fetching into refs/remotes is allowed, deleting a remote ref is refused`. Consequences: an empty transaction is refused (mutation R3).
- F5: fixed: spec runs use `pickman_fence <checkout> specs`, which unsets `GH_TOKEN`, `GITHUB_TOKEN` and the enterprise variants, points `GH_CONFIG_DIR` at an empty `.cache/gh-none`, and makes `pre-push` refuse every network push. `check.sh` files keep both, because `ci-verify.sh` needs them. Cases: `fence :: specs get no GitHub credentials and can't push to a network remote` and `repo-fence :: specs have no GitHub credentials and push only into fixtures`. `GH_CONFIG_DIR` and `sandbox-exec` join the scan list.
- F6: fixed (each low):
  - **An unclaimed takeover**: a takeover mutex with no pid is removed after 2 s (`lock :: a takeover left by a waiter that died before claiming it is cleared`).
  - **A leaked marker**: the marker now counts only for its own checkout or a fixture under its `.cache`, never another checkout below it (`fence :: a marker leaked into another checkout below it is ignored`).
  - **The window before a killed run's child records its pid**: accepted and documented. It is milliseconds at start-up, and the worst case is two suites sharing fixtures, which the jail makes harmless.
  - **`promote-check`'s copies outside the lock**: they are written by `check.sh` flows, not by specs; documented as an allowed writer.
  - **R0021's stale numbers**: fixed.
