# Review 002: c0194 (design mode)
Inputs: prep worktree `prep-temp-trees-under-repo` at 7871c2f9 with the uncommitted `c0194.md`, `check.sh`, `acceptance/{tmp,shim,runner,callers,docs}.spec.luau` (byte-identical to the prototype's copies), `harvest.md`, `design-review-001.md`, `design-refute-001.md`; prototype `.worktree/proto-c0194` (base 02aae689, uncommitted tree, not edited); c0075's sequestered specs on origin/main fce1fba9; `./zn capture c0194` (capture 64239635, unmarked); `./zn lessons --when design --full`, `./zn lessons --skill zz-review --full`; the author's `scratchpad/c0194/{c0194-mut.py,mut-all.out,e13.sh}`.
Runs (all in my harness scratchpad, removed afterwards; the prototype and the repository were not written): `./zn check c0194` (AC1–AC5 fail for the missing modules, AC6 passes); `./zn promote-check c0194` (only missing-module and missing-key type errors); the prototype's `tmp.luau`/`tmpcli.luau` copied and run on stand-in checkouts (F1, F2, F7); a `--no-hardlinks` clone of the prototype with its uncommitted files committed in it, where I ran `runner.spec`, `tmp.spec`, `callers.spec` and mutants (F4, and the spot-checks below); a clone of the repository under a `./zn tmp jail` tree (F2).
Spot-checks of `run` rows: `mut-all.out` records M9, M26 and M35 as `SKIP: pattern missing`, while the table marks them `run`; I re-ran all three on the clone and each is killed by its named case (M9: 2 failed, M35: 2 failed, M26: 2 failed). M48 also killed (2 failed). The record should hold the rerun output (no finding).
Dropped from design-review-001 (fixed; I checked the change, its case and, where named, its mutant): F4, F5, F6, F7, F8, F10, F11, F12, F13, F14. Repeated or reopened below: F1 (as F4), F2 (as F2), F3 (as F3); F9 and F15 leave small residues (F6, F8).

Scope: the Problem and Solution are the capture's plus the two `Decided with the user (2026-11-01)` lines. Every captured outcome has a design; the merge clone's removal at its end has no criterion (F5). Both decisions are recorded, but neither is carried out yet: Merging's verify step fails as written (F1), the clone jail cannot run specs (F2), and c0075's hand-off misses most of the cases it changes (F3).

### F1 [high] Merging step 2 as written always stops: `./zn tmp verify "$dir"` checks the clone against the worktree's `.cache/.tmp`, but `./zn tmp new gate` put it in the main checkout's
Where: zz-rules Merging step 2 (prototype), "`dir=$(./zn tmp new gate)` … `./zn tmp verify "$dir"` must print `isolated` … any other answer is a stop"; `tmpcli.luau` `verify` → `tmp.verify(explicit or process.env.ZN_TOP or ".", rest[1])`; `tmp.verify` refuses a tree that is not under `{top}/.cache/.tmp`; `tmp.place` sends `new` to `TMPDIR`'s checkout. Also E2b.
Evidence: This is the normal merge. The session starts in the main checkout (`/z-run`), so the hook sets `TMPDIR=<main>/.cache/.tmp`. The merge runs from the raft worktree, and `zn` exports `ZN_TOP=<worktree>`. I ran the prototype's command line on stand-ins with `TMPDIR=<M>/.cache/.tmp` and `ZN_TOP=<M>/.worktree/wt`:
- `new gate` → `<M>/.cache/.tmp/gate.6PNOcI`;
- `verify "$dir"` → `not isolated: <M>/.cache/.tmp/gate.6PNOcI is not under <M>/.worktree/wt/.cache/.tmp`, exit 1;
- `verify "$dir" --dir <M>` → `isolated`.
The docs say any answer but `isolated` is a stop, so every raft's merge posts `BLOCKED:`. No case runs `verify` the way Merging does. tmp.spec's command-line case passes `--dir co` to both commands, and no case puts a session `TMPDIR` and a different `ZN_TOP` together. E2b ran without a session `TMPDIR`, so `new` and `verify` agreed by chance.
Critique: The obvious fix is adding `--dir "$(git rev-parse --git-common-dir)/.."` to the documented line. That leaves a second, hand-built path for the agent to get wrong, and the next caller of `verify` hits the same mismatch.
Consequences: The tree itself says where its root is. `verify` should take the folder that holds the tree, require it to be a `.tmp` inside a `.cache` (both plain, as `tmp.root` checks), and require the tree to be a direct child of it (the rule `jailArgv` already applies). `--dir` then has nothing left to decide. Either drop it, or refuse when it disagrees with the tree. A tree that sits deeper (`gate.X/repo`) must refuse rather than climb to some outer `.cache/.tmp`.
Recommendation: In `tmp.verify(tree)`, derive the root from the tree's physical parent, as above. Add tmp.spec command-line cases. (1) With `TMPDIR=<A>/.cache/.tmp` and the command run from stand-in B (`ZN_TOP=<B>`), `new gate` followed by `verify "$dir"` prints `isolated` once the tree has the tools' `rokit.toml`. This is the Merging sequence; the old code fails it. (2) `verify` of `<tree>/sub` and of a folder outside any `.cache/.tmp` refuses. Re-run E2b as Merging is written: in a worktree, with a session `TMPDIR` set to the main checkout's folder. Add the row "verify finds the tree's own root" with the mutant "root from `ZN_TOP`" (today's code).
Lesson: z-design/new-refusals-reach-every-caller, z-design/instructions-runnable-where-they-run

### F2 [high] The decided "Jail the clone" can't do its job: a suite run inside `./zn tmp jail` refuses to start, and the command runs in the checkout, not the tree (the fix of design-review-001 F2)
Where: zz-test "Running specs against unguarded code" (prototype, pinned by docs.spec: `` `./zn tmp jail "$tree" -- <command>...` ``); `tmpcli.luau` `jail` (no `cwd`); `tmp.jailArgv`/`jailProfile`; E12; Rules row "the jail really contains the command" (reasoned).
Evidence: I made a tree with the prototype's `new unguarded --dir <S>`, cloned the repository into `$tree/repo`, and removed its origin. Then, through the prototype's `jail`:
- `sh -c 'pwd'` printed `/Users/philipbergen/code/pickman/.worktree/proto-c0194`. The command runs where `./zn` ran (`zn` does `cd "$top"`), not in the tree, so `cd repo/z-nile` failed (`No such file or directory`). `./zn tmp jail "$tree" -- lune run tests/run` would run the checkout's own runner.
- With an absolute `cd`, `lune run tests/run -- tests/tooling/game-roots.spec.luau` printed `cannot jail this run (already inside a sandbox, and macOS can't nest them), and it could write the repository or reach past the jail ($tree/repo/z-nile, $tree/repo, $tree/repo/.git, …)`. The runner treats the tmp jail as an outer sandbox that leaves the clone writable, and it refuses. The prototype's runner refuses the same way, because `writable(here)`/`fixtureOfGuarded` are unchanged.
- With `PICKMAN_FENCE_REAL_GIT=<the real .git>` and `GIT_CEILING_DIRECTORIES=<S>/.cache` added to the environment, the same run printed `note: not jailed (…); this is a fixture of a guarded checkout` and `3 passed`.
E12 ran only `sh -c '…'`, never a suite. So the procedure zz-test prescribes, and docs.spec pins, can't run the specs it exists for: the mutation runs of a guard prototype, which the old rule covered. An agent who meets the refusal is pushed back to the unjailed run the user just ruled out.
Critique: The tempting fix is to set those two variables inside `jail`. That works for suites, but it brings a consequence the user did not hear when deciding.
Consequences:
- Inside the tmp jail the clone's runner is not jailed (sandboxes don't nest). Every case that needs the live spec jail (`needJail` cases, `repo-fence.spec`'s live probes, runner.spec's "write their own folder and nothing else", E5's checks) fails or skips there. Those are exactly the guard-prototyping cases.
- `tmp.jailProfile` has no signal rule. The spec jail confines signals to its own sandbox (`(deny signal)` then `(allow signal (target same-sandbox))`, c0076/c0078). Under the tmp jail, specs of unguarded code can signal any of the person's processes, the session included, and no sweeper runs.
- Setting `GIT_CEILING_DIRECTORIES` to the tree's `.cache` is what makes the runner accept the run. `jail` must compute that value from the tree (the `.cache` above its `.tmp`), never take it from the caller.
Recommendation:
- `jail` runs the command with `cwd` set to the tree. It appends the tree's `.cache` to `GIT_CEILING_DIRECTORIES` and this checkout's git common dir to `PICKMAN_FENCE_REAL_GIT`. The profile gains the spec jail's two signal rules.
- tmp.spec pins all three: the argv's `env` entries, the signal rules in `jailProfile`, and the cwd, through a `jailArgv` that returns it.
- Re-run E12 with a real spec file in a clone (expect `this is a fixture of a guarded checkout` and passes), and record it.
- zz-test's paragraph says the command runs in the tree.
- Escalate to the user: under "Jail the clone", the cases that need the live spec jail can't run in the clone. The options:
  - (a) run those cases only in the prototype worktree, under the prototype's own spec jail, as unguarded code in a worktree of the real repository (the risk the decision avoided);
  - (b) leave them unrun in prep and have the executor run them on the raft branch, whose guards are reviewed, before review (cost: guard mutants found later);
  - (c) keep a second, outside-the-repository clone just for those cases (narrows the decision).
  Keeping the full scope costs one of these. The design records the choice as a `Decided with the user` line.
Lesson: z-design/instructions-runnable-where-they-run, z-design/probe-free-cli-lines-in-prep

### F3 [high] The c0075 hand-off still breaks cases it doesn't name, gives a wrong count, and collides with code review's sequestration rule (repeat of design-review-001 F3)
Where: c0194.md Existing work (c0075), Regression guard's conditional Overrides line ("two cases … the `--ro-bind` count is 3"), Implementation step 8; c0075's `acceptance/jail-argv.spec.luau` and `linux-jail-script.spec.luau` on origin/main; zz-review Code mode item 2.
Evidence: The search I ran, `git grep -n -e 'ro-bind' -e '%-%-bind' -e '#argv' origin/main -- 'z-nile/.tracker/issues/c0075/acceptance/'`, found:
```
jail-argv.spec.luau:35:  "--ro-bind",                         (the exact policy)
jail-argv.spec.luau:64:  local root = indexOf(argv, "--ro-bind")
jail-argv.spec.luau:104: t.expect(count(argv, "--ro-bind")).toBe(1)
jail-argv.spec.luau:124: local ro = indexOf(argv, "--ro-bind", 3) -- the second one
jail-argv.spec.luau:128: t.expect(count(argv, "--ro-bind")).toBe(3)
jail-argv.spec.luau:141: t.expect(#argv).toBe(25)
linux-jail-script.spec.luau:17-18: TRIAL_PATTERN "^bwrap --ro-bind / / --tmpfs /run --tmpfs /tmp --bind (%S+) %1 --bind (%S+) %2 --remount-ro /run …$"
```
The carve (`--ro-bind <cache>/.tmp <cache>/.tmp` between the two `--bind`s) adds three arguments. By reading (c0075's code isn't on main, so nothing can run), it changes these cases:
- "is exactly the reviewed policy": named in the design.
- "opens nothing else for writing": the count goes from 1 to **2**. The design says "the `--ro-bind` count is 3", which is wrong here.
- "keeps a checkout that lives under /tmp or /run visible": 3 → 4. Not named.
- "passes the folders through as given": `#argv` 25 → 28, and `TEMP` moves from `argv[13]`/`[14]` to `[16]`/`[17]`. Not named.
- `linux-jail-script.spec`'s TRIAL_PATTERN: it requires the two `--bind`s adjacent. Not named.
There is a second problem. Code mode item 2 says any change under `*/.tracker/**/acceptance/**` other than an `R100` rename is **high**, and that a code-mode recommendation never asks to edit sequestered specs. c0194's raft PR will contain such a change. Nothing in the design tells the code reviewer that it is the decided exception, so the decided step is due to be reported as a high finding and reverted.
Critique: "Two cases" was again written without reading the other raft's specs whole. Lesson run-the-other-rafts-specs asks for exactly that, and harvest.md maps 001 F3 to it.
Consequences: The edit has to be written down in full now, because the executor can't run it (no c0075 code) and the code reviewer has to compare it with something. The exception to item 2 has to be visible where the code reviewer reads: the raft document and the issue's Overrides line, naming the two files.
Recommendation:
- Put the exact edited expectations in c0194.md: the full argv list for the exact-policy case; counts 2 and 4; `#argv` 28 with indices 16 and 17; a TRIAL_PATTERN with `%-%-ro%-bind %1/%.tmp %1/%.tmp ` between the two `--bind`s. Name all five cases and both files on the conditional Overrides line, with the exact-list case's new list written out.
- Implementation step 8 says the code reviewer is to check that diff against that text, and z-raft's Theme for c0194's raft quotes it as the declared exception to zz-review code-mode item 2.
- Also grep c0075's other five spec files and its `check.sh` for the run's temp folder lying under `/tmp`, and paste the result (`jail-argv.spec:72` says so in a comment; the case stays true for its literal `TEMP`).
Lesson: z-design/run-the-other-rafts-specs, zz-review/lists-paste-their-search

### F4 [high] The outer-sandbox rule's choice of folders has no case: probing only the home's folder (design-review-001 F1's defect) passes every spec (repeat of design-review-001 F1)
Where: `fence.luau` `jail()`, the four `consider(...)` calls (home, checkout root, main checkout via `--git-common-dir`, `TMPDIR`'s); runner.spec "an outer sandbox is accepted only while no .cache/.tmp folder is open" (pure `tmpLeaks` only); Rules rows "an outer sandbox is refused…" (M44) and "the outer-sandbox rule is applied to the folders the design uses" (E13); AC3.
Evidence: In my clone of the prototype I deleted the three `consider` calls for the root, the main checkout and `TMPDIR`, which is exactly round 1's home-only probe. `runner.spec`: `7 passed, 0 failed`. The pure case feeds `tmpLeaks` hand-made folders, so it cannot see which folders the edge collects or how it sets `ownHome` and `fixture`. E13 is the only evidence, and it covered one branch. Its fixture repository is its own main checkout (not a worktree), and its `TMPDIR` is not under a `.cache/.tmp`. So the main-checkout branch, the one that holds agents' clones, and the `TMPDIR` branch have never run, in the suite or out of it. E13 is also not in the gate, so after `done` nothing keeps the edge aimed.
Critique: AC3 ("accepted only while every `.cache/.tmp` of the checkout is closed") passes with the wrong implementation round 1 found. This is the second round to find a hole in this probe's aim, so the mechanism, not just this hole, needs fixing: the set of folders is computed inline from four git and environment reads and never written down as a rule.
Consequences: A pure function of the reads makes the set testable, and the edge then has one job: fill it in. `fixture` (under a ceiling `.cache`) and `ownHome` move into the same function, so each has a case. Two details move with it: the `TMPDIR` pattern's greedy `^(.*)/%.cache/%.tmp`, which takes the last `.cache/.tmp` in the path; and dedupe when the home and the root coincide.
Recommendation: Add `fence.tmpFolders(here, top, common, tmpdir, ceilings): { {path, ownHome, fixture} }` (pure). `jail()` probes writability and entries for each listed folder that exists, and `tmpLeaks` judges them. runner.spec gets a table case:
- a worktree run (`here=/m/.worktree/w/z-nile`, `top=/m/.worktree/w`, `common=/m/.git`, `tmpdir=/m/.cache/.tmp`) lists `/m/.worktree/w/z-nile/.cache/.tmp` (own), `/m/.worktree/w/.cache/.tmp` and `/m/.cache/.tmp` once each;
- a `TMPDIR` of `/x/.cache/.tmp/pickman-run.A` lists `/x/.cache/.tmp`;
- a ceiling `/m/.worktree/w/.cache` marks folders under it as fixtures.
Rows and mutants: each source dropped, `ownHome` true for the root, ceiling ignored. Extend E13 with a worktree fixture whose main checkout's `.cache/.tmp` holds a tree, and record it.
Lesson: zz-test/guard-needs-its-own-case, zz-test/guards-move-with-the-working-directory

### F5 [medium] The merge clone, the bulk of the 14 GB in the Problem, is still not removed at its end: the promised Landing step is not in the prototype and has no case
Where: c0194.md Merging ("The clone is removed with `rm -rf "$dir"` after step 3 and the merge (Landing step 4 gains it)"), Cleanup ("now said in AGENTS.md, z-design, zz-execute and Merging"); the prototype's zz-rules (Landing step 4 and Merging unchanged on removal); docs.spec (no case).
Evidence: `grep -n 'rm -rf "$dir"' z-nile/skills/zz-rules/SKILL.md` in the prototype finds nothing. Landing step 4 is today's chained `sync; worktree remove; branch -D`. The Problem's 34 clones with `repo/`, `gate.log` and `game.rbxl` are merge-gate clones. The day-old sweep (AC1) bounds them, but the captured "each one is removed when its run … ends" has no check for the one tree most likely to pile up.
Critique: Landing step 4 must be the last command, because it removes the session's own folder. The removal therefore can't simply be appended to that chain, and a BLOCKED merge (step 2 or 3 fails) leaves the clone in place.
Consequences: Say where the removal goes. Right after the merge and before Landing step 4 works (it is in the main checkout's folder, not the worktree). On a stop, the clone is left for the person to inspect, and the sweep takes it after a day. `rm -rf -- "$dir"` only when `$dir` is non-empty and under `.cache/.tmp/`.
Recommendation: Add the sentence to Merging (after the `gh pr merge` step) and to the BLOCKED path ("left for inspection; swept after a day"). docs.spec asserts both, which is a rule the change restores, so it belongs in the spec. Add the row with the mutant "removal sentence dropped".

### F6 [low] Restated lists still disagree about `jail` and about who writes the main checkout's `.cache/.tmp` (residue of design-review-001 F9)
Where: zz-rules command table row `| tmp | ./zn tmp new <kind> \| root \| verify <tree> \| sweep [--dry-run] \| leftovers …` (no `jail`); the `zn` comment `./zn tmp new|root|verify|sweep|leftovers`; tmpcli's header (no `jail`); AGENTS.md "agents' scratch trees under `.cache/.tmp/` are the one other write there" (pinned by docs.spec) against zz-rules' list (the hook's dot-files, every worktree's gate trees, remap).
Recommendation: Add `jail <tree> -- <command>…` to the table row, the `zn` comment and tmpcli's usage. Make AGENTS.md say "`./zn tmp`, the SessionStart hook and the gate's trees under `.cache/.tmp/` are the other writes there", and change docs.spec's pinned sentence to match.
Lesson: z-design/restated-rules-move-together

### F7 [low] `verify` counts a `rokit.toml` in `.cache/.tmp` itself as the clone's own, and an unknown root `.luaurc` key breaks every gate tree, not only the merge clone
Where: `tmp.verify` (`own` = manifests whose path starts with `root .. "/"`); `tmp.root` → `tmp.neutralizer` refusal; `tmp.place` → `tmp.root` for `par`, `check-build`, `globaltypes`.
Evidence: On a stand-in checkout with `[tools] lune, rojo` above and a clone naming only `lune`, `verify` said `not isolated: rokit.toml above names rojo…`. After `.cache/.tmp/rokit.toml` naming `rojo = "evil/rojo@9"` was added, `verify` said `isolated`, and Rokit merges that manifest into the clone's tools. Only an unjailed writer (Linux, an agent) can put it there, hence low. Separately, a `globals` or `lint` key added to the root `.luaurc` makes `tmp.root` refuse, so `pickman_tmp_new` and with it `par.sh` fail the whole gate with a message about isolation.
Recommendation: `own` = manifests strictly below the tree (`tree .. "/"`). `verify` refuses a `rokit.toml` or a `.luaurc` it didn't write at the folder level (tmp.spec case). Either the gate's trees use the folder without the neutralizer's refusal (only `verify` and `new gate` need it), or zz-rules says that a new `.luaurc` key needs `RESETTABLE` updated first. Pick one and pin it.

### F8 [low] `tmp.place` falls back to the current folder, not the checkout, and the "an hour after a dead owner" rule is a day whenever anything inside changed (residue of design-review-001 F15)
Where: `tmp.place` → `tmp.root(process.env.ZN_TOP or ".")`; "The folder" ("a home's folder holds that home's runs' folders and nothing else"); `newest()` (`find -mmin -1440` makes `newest = now`); AC1 ("an hour after a dead owner").
Evidence (reasoned from the code): `deploy-beta` run from `pickman/` with no session `TMPDIR` makes `pickman/.cache/.tmp/deploy-beta.X`. That is a home's folder, and an outer-sandboxed pickman run then refuses ("another temporary tree"). A command run from `z-nile/engine/` would make `z-nile/engine/.cache/.tmp`. For an owned tree whose owner died, any file changed in the last day sets `newest` to now, so it waits a day, not an hour.
Recommendation: The fallback is `git rev-parse --show-toplevel` of the current folder (refusing outside a checkout), with a tmp.spec case run from a subfolder of a `git init`'d stand-in. For the second point, either say "an hour after the tree's last change, at most a day" in AC1 and the table row, or make `newest` measure the real latest change for owned trees. Say which.

Candidate lesson (for the lead; I write none): **A wrapper meant to run X is proved by running X in it.** `./zn tmp jail` was proved with `sh -c`, but its purpose is running a suite, and the runner's own outer-sandbox probe refuses it. The same holds for `new gate` + `verify`: the pair was proved without the session `TMPDIR` the docs assume. Check: did the experiment run the real command the instructions name, in the environment and folder the instructions run it in (session `TMPDIR`, `ZN_TOP` of a worktree, the wrapper's own working directory)? (Extends z-design/probe-free-cli-lines-in-prep.)

Verdict: changes
