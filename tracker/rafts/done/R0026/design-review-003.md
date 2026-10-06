# Review 003: R0026 (design mode)
Inputs: prep worktree `prep-guards-and-numbering` at e7d6e21 (round 2's changes: `git diff HEAD~1 -- tracker/`): `tracker/rafts/R0026/{R0026.md,check.sh}`, `design-review-00{1,2}.md`, `design-refute-00{1,2}.md`; c0074, c0075, c0076, c0077, c0078, c0079 and c0080 (each `<id>.md`, `check.sh`, `acceptance/*.spec.luau`); the review, testing, tracker, ticket-prep and execute-raft skills; the prototype `.worktree/proto-r0260` (`tests/lib/fixture.luau` `SHIM`, `tests/lib/fence.luau`, `tests/tooling/repo-fence.spec.luau`), read only.
Dropped from design-review-002: F1, F2, F3, F4, F5, F6. Their fixes hold:
- F1: `doneGate` is pure, and AC6 pins the call. A `cmd.done` that read `PICKMAN_FENCE_SPECS` itself would fail `repo-fence` in the gate, since `scripts/` is scanned and only `gate.luau` is allowed to name it.
- F3: every write is now aimed at the stand-in. The two `status` probes in the real tree's direction write only the fixture's index.
- F5: the `unset` is on the one `bash -c` line, which both jailed and unjailed runs use. The new case fails without it in both kinds of run.
- F2's bound is new behaviour, so it is judged below (F1–F3).

Runs: no specs. In a scratch folder under `$TMPDIR` (since removed), with no other sandbox, I generated the prototype's shim from `SHIM` with a stand-in cache. I set `GIT_CEILING_DIRECTORIES` to that cache, as the runner does, and ran the shim against a stand-in "victim" repository outside the cache, with git 2.54. Nothing printed `REPOSITORY CHANGED`. The prototype was not modified.

### F1 [high] The bounded rule doesn't hold: a fixture's git dir can name a common dir outside `.cache` (`commondir`), and its config can move the work tree (`config.worktree`, or a key on the section line), and the shim lets all three through. AC1 passes anyway
Where: c0075 Design, "The shim" (the "finite list", fast path step 6, slow path step 7); prototype `SHIM` lines 179–216; c0075 AC1 ("however it names one: … the repository's own `core.worktree` …"); c0078's new guards-list sentence ("The shim checks every path that names a repository or work tree").
Evidence: each was run against the stand-in shim:
- **`commondir`, fast path.** `cache/cd/.git/` holds only `HEAD` and a `commondir` file naming `victim/.git`.
  - The fast path checks that `cache/cd` and its `.git` are under the cache. It then reads `cache/cd/.git/config`, which doesn't exist, and runs the real git.
  - `git add z` gave rc 0. `git config user.foo bar` gave rc 0, and `victim/.git/config` gained `foo = bar`. `git rev-parse --git-common-dir` printed `victim/.git`.
  - Objects, the config and refs all live in the common dir. The config change is exactly what the runner's tripwire fails the run for, after the fact.
- **`commondir`, slow path.** `cache/wt/.git` is a gitfile pointing at `cache/gd`, which holds a `commondir` naming `victim/.git`. This is the normal layout of a linked worktree, which fixture worktrees use.
  - The slow path's `rev-parse --absolute-git-dir --show-toplevel` gives `cache/gd` and `cache/wt`, both under the cache, so the call is allowed.
  - `git status` listed the victim's files. `git config user.bar baz` wrote `bar = baz` into `victim/.git/config`.
- **`config.worktree`.** A clone under the cache ran `git config extensions.worktreeConfig true`, and its `.git/config.worktree` said `[core] worktree = <victim>`.
  - The trigger `^\s*(worktree\s*=|\[include)` doesn't match `worktreeConfig = true`, so the call takes the fast path.
  - `rev-parse --show-toplevel` printed the victim. After `rm victim/a`, `git checkout -- a` through the shim gave rc 0 and wrote `victim/a` back. That is the Problem's own class: a working-file write with no ref update.
- **A key on the section line.** A clone's config ending in `[core] worktree = <victim>` (and also `[core]worktree=<victim>`) is valid git: `rev-parse --show-toplevel` printed the victim. The line starts with `[core]`, so the anchored trigger misses it. `git checkout -- .` through the shim restored the victim's deleted file.
- **No spec case covers any of these.** The config case writes the key with `git config`, which puts it on a line of its own.

`--show-toplevel` honours both config forms, so the slow path would catch them. Only the fast path's lexical guess misses them. Nothing catches `commondir` on either path, because the shim never asks for the common dir. The design names `GIT_COMMON_DIR` (the variable) but not the file that does the same thing.
Critique: there are two tempting fixes, and both are poor:
- Add the three forms to the list. That repeats the case-by-case modelling the bound was meant to end, and the next git feature reopens it.
- Call these "written to escape" and leave them as Non-goals. But AC1 and c0078's skill sentence promise "every path that names a repository or work tree". `commondir` is such a path, and `config.worktree` is set by an ordinary `git config --worktree`.
Consequences: the honest way to bound the rule is to make git itself the authority, and to make the fast path a narrow, provable shortcut:
- The fast path is taken only for a plain repository: `.git` is a directory, it has no `commondir` and no `config.worktree`, and no config line contains `worktree` followed by optional space and `=`, or a `[include`, anywhere on the line (not anchored). That's two `-e` tests and a looser match, still with no new process, so E6's cost is unchanged.
  - A remote URL containing `.worktree/` still doesn't match, since `/` follows.
  - `worktreeConfig = true` sends the call to the slow path through the `config.worktree` test, or through its `extensions.worktreeConfig`, whichever is simpler.
- The slow path asks for the common dir too: `rev-parse --path-format=absolute --git-dir --git-common-dir --show-toplevel` (git 2.31 or later; the bare form changes the same way) and `target`s all three.
- The rule's statement changes from a list of ways to name a repository to: "the git dir, the common dir and the work tree that git itself resolves must be under `.cache`; the fast path is a shortcut taken only when the repository is plain".
- A new edge: `--path-format` needs git 2.31 or later. Either state the minimum version in SETUP and the testing skill, or make `rev-parse --git-common-dir` relative-safe by resolving it against the git dir.
Recommendation:
- Make the fast-path and slow-path changes above, and reword the c0075 rule and c0078's guards-list sentence to match.
- Add cases to `shell-git.spec`, each aimed at a stand-in in the run's temp folder, never the real checkout, and each requiring the stand-in's config (and, where relevant, a deleted file) to be unchanged:
  - "a git dir whose commondir names a repository outside .cache is refused": both the `.git`-directory form and the gitfile form, with `git config` as the probe;
  - "a work tree moved by config.worktree is refused";
  - "a core.worktree key on its section's line is refused".
- Add three Rules rows, whose mutants are today's fast path (two rows) and today's slow path without the common dir. Re-time E1.

### F2 [medium] Half of the bound's list has no case: `GIT_COMMON_DIR`, `GIT_INDEX_FILE`, `GIT_OBJECT_DIRECTORY`, `worktree move` and `--template` can be dropped from the shim and every check stays green
Where: c0075 Design, the shim's list and steps 2–4; Rules and mutants (rows "repository variables are checked for every command", "`worktree add` targets are checked"); `shell-git.spec.luau` (no `move`, `template`, `GIT_COMMON_DIR`, `GIT_INDEX_FILE` or `GIT_OBJECT_DIRECTORY` anywhere: grep).
Evidence:
- The variable cases set only `GIT_DIR` and `GIT_WORK_TREE`, and E6's mutant removes the whole variable loop. A loop over just those two passes every case.
- `GIT_INDEX_FILE` is the dangerous one. Any variable set skips the fast path, and the slow path checks only the git dir and the work tree. So with `GIT_INDEX_FILE` dropped from the loop, `GIT_INDEX_FILE=<real>/.git/index git read-tree HEAD`, run from a fixture, would overwrite the real checkout's index with the fixture's tree. That is a working-state change with no ref update, which the tripwire doesn't look at.
- `worktree move` is in the Design (step 4) and the code, but in no AC, row or case.
- `--template` names a folder that `init` only *reads*, so `target`ing it is an over-refusal, not part of "paths that name a repository". It doesn't hurt, but it isn't the rule either.
Critique: the tempting fix is one case per item. That is right here, because the list is now the rule's finite surface: an item that no case pins can quietly go missing.
Consequences: once F1 makes git's own resolution the authority, `GIT_COMMON_DIR` is also covered by the slow path's common-dir check. `GIT_INDEX_FILE` and `GIT_OBJECT_DIRECTORY` still aren't, because `rev-parse` doesn't report them, so they keep their own `target` and need their own cases. Dropping `--template` from the shim narrows it to the rule.
Recommendation:
- Add refusal cases aimed at the stand-in: `GIT_INDEX_FILE=<stand-in>/.git/index git read-tree HEAD` (the stand-in's index is unchanged), `GIT_OBJECT_DIRECTORY=<stand-in>/.git/objects git hash-object -w <file>` (no new object), `GIT_COMMON_DIR=<stand-in>/.git git config x.y z` (the config is unchanged), and `git worktree move <fixture wt> <temp folder path>` (refused, and the work tree is still in place).
- Add a row per variable with "this variable not `target`ed" as the mutant, and a row for `worktree move`.
- Either drop `--template` from the shim, or keep it and say in the Design that it is a deliberate over-refusal.

### F3 [low] Commands git itself starts find the real git before the shim. The bound and c0078's sentence don't say so
Where: c0075 Non-goals (absolute-path git, other programs' git libraries); c0078's guards-list sentence.
Evidence:
- Through the stand-in shim, `git -c alias.w='!command -v git' w` printed `…/libexec/git-core/git`, and the child's `PATH` began with git's exec-path. Git puts its exec-path ahead of `PATH` for everything it starts: `!` aliases, hooks, `rebase --exec`, `submodule foreach`, `bisect run`, `core.fsmonitor`, credential helpers.
- `git -c alias.e='!cd <victim> && git status --short' e` gave rc 0 and listed the victim's files.
- So the Problem's own scenario (`cd` elsewhere, then git) gets past the shim one level down: a `reset --hard` there would write to the victim.
Recommendation: no new mechanism, since this falls in the same "review's to catch" class as absolute-path git. Add one line to c0075's Non-goals and to c0078's skill sentence: "commands git itself runs (hooks, `!` aliases, `rebase --exec`, `submodule foreach`) find the real git first, since git puts its exec-path ahead of `PATH`". No spec case is needed.

Verdict: changes
