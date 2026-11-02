# Review 002: c0178 (design mode)
Inputs: prep worktree `.worktree/prep-shared-fixture-images` at 3297d2b1 plus its uncommitted `c0178.md`, `check.sh`, `acceptance/*.spec.luau` (identical to the prototype's `tests/acceptance/c0178`), `experiments/`, `design-review-001.md`, `design-refute-001.md`, `harvest.md`; the author's prototype clone at 24098d4c (read; one `git clone --no-hardlinks` of it into a `mktemp -d` folder, used for the runs cited below and then deleted); `./zn lessons --when design --full`; the zz-review, zz-test, zz-arch skills; in-flight preps from `git worktree list` (c0180, c0194, c0123, c0132, c0157, c0162, c0165, c0168, c0181, c0191), read from their worktrees.
Dropped from design-review-001: F1 (the user decided the scope; the home-path memo is built and pinned), F2, F3, F4, F5, F6, F10, F11 (built, each with a case that can fail). F7, F8, F9 and F12 come back below with new evidence (F3, F1, F4 and F9 here).

### F1 [high] Prune deletes the real repository's image while the run is still using it: clone-image.spec goes red on its second run (repeat of design-review-001 F8)
Where: Modules `images.ensure` (the prune after every publish, ordered by the folder's mtime); `clone.imageOf`; clone-image.spec "the image follows the repository's HEAD"
Evidence: the HEAD case calls `clone.imageOf(subject)` twice on a fixture repository. Both images go into the real `images.dir()` with kind `repo`, the same kind as the image of this checkout. Every run makes new ones, because the fixture's commits get new shas. After each publish, prune keeps the newest 2 of the kind and removes the rest that are older than `minAge` (3600 s). It orders by the folder's mtime, which is the time the image was published, and using an image never updates it. So once this checkout's image is over an hour old, which happens whenever HEAD sits still for an hour (a prep worktree with uncommitted work, say), the fixture images make it the oldest and prune removes it.
I ran this in a scratch copy of the prototype. First I ran `lune run tests/run -- tests/acceptance/c0178/clone-image.spec.luau`: 9 passed, leaving three `repo-*` images. Then I backdated this HEAD's image (`touch -t 202611010700 repo-2109…`, inode 484856045) and ran the same spec again. The result was `clone-image.spec:131: expected 49, got 62` and `8 passed, 1 failed`. The image had been deleted and rebuilt (same name, new inode 485028289). The "paths" case then counted the 13 files of the rebuilt image as its own. In a full gate the same prune runs while the 13 cloning specs' workers are running `git clone` from that folder, and those clones fail.
Critique: round 1 asked for a last-use stamp or a per-checkout rule. The design chose "the images folder is per checkout", which does not help: the race is inside one checkout and one run. The tempting fix is to give the HEAD case its own `dir`. That fixes this spec, but it leaves the mechanism in place: any publish of a kind can still remove an image that another worker in the same run resolved a moment earlier (`fs.isDir(final)` and then `git clone`). The same applies to `seed` and `tooling` whenever the tooling changes during a run.
Consequences: prune must never run while another process in the run can be using an image. Whether a prune is safe then depends on the run, not on the image's age.
Recommendation: move prune out of `ensure`. The coordinator, or an in-process run, calls `images.prune()` once before any spec starts, under the run's lock, which already makes it the only run in this home. The 3600 s rule stays only for `.build.*` and `*.lock` litter. Give `clone.imageOf(root, options?)` the `dir` option and make clone-image's HEAD case build into its own folder, as images.spec does. Cases:
1. images.spec: `ensure` never removes another image, so after N publishes of one kind, every earlier image of that kind is still there.
2. harness.spec: a run prunes once, before the first spec, keeping the newest `keep`.
3. clone-image.spec: this checkout's image, backdated past `minAge`, survives the HEAD case.

Add the Rules row "nothing is pruned while a run can use it", with the mutant "prune inside ensure". Write the author's proposed lesson zz-arch/prune-by-last-use so that it covers a single checkout too.

### F2 [high] A sparse clone's commits keep the real repository's items: the "empty tracker" setup of eleven specs is no longer empty, and nothing checks the "same state" Non-goal
Where: Non-goals ("its setup is replaced by a cheaper setup that makes the same state"); Design "Per-spec clone paths"; Guards bullet; E11; `clone.isolated` (`noItems` given only by c0005 and c0045)
Evidence: in a sparse clone, the files outside the list are in the index as skip-worktree entries and are not on disk. `engine.empty` deletes the items from disk, but those were never on disk, so no deletion gets staged. I checked this in a scratch repository with a `--no-checkout` clone and `sparse-checkout set --no-cone /a/ /t/keep`. After an overlay, `git add -A --sparse` and a commit, `t/items/i1` (outside the set and absent from disk) was still in `HEAD`. Plain `git add -A` refuses the overlay instead.
On the prototype I disabled the sweep in my copy and ran `c0044/naming.spec` (11 passed). Afterwards `git ls-tree -r HEAD` of `.cache/naming-e2e/seed` held 230 item folders of the real repository (`z-nile/.tracker/issues/active/c0117/…` among them), and 10 item folders were on disk. In the old full clone, `engine.empty` followed by the first `git add -A` deleted them all.
The other specs without `noItems` (c0001, c0008, c0038, c0046, c0050, c0074, c0080, c0116/promote, c0120/promote-home, worktree-fetch) commit an "empty tracker" the same way, while c0001's own comment says "start from an empty tracker so ids are predictable regardless of the real backlog". The engine reads items through git, so the difference is reachable:
- `originTree`/`originIds` (main.luau:411);
- the stale-folder sweep's `ls-tree HEAD -- <dir>` (main.luau:486);
- `claims.carriers`'s `git grep` on a ref;
- `compact`'s `ls-files` walk, which skips files missing from disk (compact.luau:83).

The lists were found "by removing entries one at a time and re-running" (E11). That method keeps a spec green, but it cannot tell whether the spec still proves the same thing.
Critique: no case flips today, but the Non-goal as written is false. AC8 and AC10 pass while the state differs. The next command that reads `HEAD`'s tree in one of these fixtures will see 230 phantom items. The tempting fix is `noItems = true` in eleven more specs. That fixes the items but not the method, and the counter, `compaction.txt` and anything else `engine.empty` removes stay in the index too.
Consequences: the rule has to be "what a sparse fixture commits equals what the full clone committed". It needs one owner, so that a later `engine.empty` change carries over to the sparse case.
Recommendation: make `engine.empty(dir)` sparse-aware. When `dir` is a sparse checkout, it also runs `git rm -r -q --cached --sparse --ignore-unmatch` on every path it deletes (the roots' items, the counter, the compaction map). `noItems` then goes, or stays as a thin alias. Add a clone-image.spec case with one full clone and one sparse clone of the image: after `engine.empty`, the overlay and `git add -A --sparse`, the two commits' `ls-tree -r HEAD` are equal. Add a Rules row with the mutant "empty deletes from disk only". Change the Non-goal and E11 to say the lists were checked for the same committed tree, not only for a green run.

### F3 [medium] The takeover of a dead lock is not atomic: two waiters can both take it over, and the second removes the first one's live lock (repeat of design-review-001 F7)
Where: `images.ensure` loop (`ownerDead(lock)`, then `fs.move(lock, dead)`); Decisions "*The lock (F7)* … so exactly one builds"; AC1 "never one whose owner is alive before it is stale"; images.spec "a lock whose recorded owner is dead…"
Evidence: here is an interleaving with W1 and W2 waiting on a lock left by a dead builder:
1. Both read `owner` and judge it dead. `ownerDead` runs `fence.startOf` (perl) and `fence.alive`, so the window is the length of a few process starts, longer under load.
2. W1 renames the lock away, `continue`s, `mkdir`s a fresh lock, writes its own owner and builds.
3. W2, resuming from its earlier verdict, runs `fs.move(lock, …dead.<r>)` on W1's live lock, deletes it, then `mkdir`s and builds as well.
4. W1's final `pcall(fs.removeDir, lock)` then removes W2's lock.

This is the first run after a Ctrl-C during a build, with 8 workers waking on one lock. The dead-owner case has a single waiter, so it cannot see this. Round 1 asked for four waiters starting one build.
Critique: the result is only duplicate builds (the rename keeps the published image whole), but AC1's words and the "exactly one builds" decision are false. The mechanism checks one lock and then renames whatever lock is there at that moment. The tempting fix, comparing the record after the rename, still leaves a window in which to put a live lock back.
Consequences: an atomic takeover needs a second claim, and that claim can go stale too.
Recommendation: question the mechanism. Either serialise takeovers with `mkdir <id>.take`: re-read `owner` under it, rename only if the record is still the one judged dead, remove `.take`, and treat a `.take` older than a few seconds as stale. Or drop the takeover claim: a dead owner is treated like a stale lock (build, the rename decides), and AC1 and the Decisions say "at most a few duplicate builds". Either way, add an images.spec case with four children waiting on a dead-owner lock, plus a seam (`beforeTakeover`) that holds the first taker. Assert one build, or the bound the design states. Add the mutant "rename without re-check" to the Rules row.

### F4 [medium] `trackerfix.worktrees` never checks that the first name is fresh, yet every copy is made from the first one's tree; its refusals come after the first worktree exists (repeat of design-review-001 F9)
Where: Modules `trackerfix.worktrees`; Decisions "*`trackerfix.worktrees` (F9)*: … a name after the first …"; worktrees.spec "refuses a name … before making anything", "refuses a fresh-looking name that already exists…"
Evidence: the check of `refs/heads/<name>` and `refs/remotes/origin/<name>` runs only for `i > 1`. The first name goes to `./zn worktree`, which does three things a fresh name does not trigger:
- for an existing worktree at that path, it prints it and returns (main.luau `cmd.worktree`: `if w.path == path then print(path) return`);
- for a local branch, it resumes it;
- for `origin/<name>`, it tracks it.

Names 2 to n are then `--no-checkout -b <name> … origin/main`, with the first one's files copied in and `git reset -q`. Their working tree is the first one's branch while HEAD is `origin/main`, so they are dirty, and nothing reports it.
Names are also checked inside the loop. In the refusal cases, `{ "raft-ok-first", bad }` and `{ "raft-first-ok", taken }` make and then reuse `.worktree/raft-ok-first` before raising, and the case named "before making anything" asserts nothing about it.
Critique: the helper's contract ("fresh named worktrees") holds for 19 of 20 names. The tempting fix is to move the check to `i >= 1`. But `./zn worktree` reuses an existing worktree path, which no ref check catches.
Consequences: validating every name before any work means one `show-ref` per name plus a path check, all before the first `tracker.sh` run.
Recommendation: validate all names first, in one pass: shape, `refs/heads`, `refs/remotes/origin`, an existing `.worktree/<name>` path, and duplicates within the list. Only then make anything. Cases:
1. A first name that exists as a branch, as `origin/<name>` or as a worktree is refused, naming it.
2. After any refused call, `fs.isDir(<main>/.worktree/<first>)` is false.

Add the mutant "first name unchecked" to the Rules row.

### F5 [medium] `swept.register` accepts `<cache>/.`, `<cache>//images` and `<cache>/.git`: one sweep can empty the whole `.cache`, the fence sentinel and the run lock included
Where: `swept.register` (a text prefix test, `..` refused); `engine.copy`'s `registerFixture` (`^(.*/%.cache/[^/]+)`); harness.spec "swept refuses…"; Guards bullet ("`swept` and `images` refuse any path outside them")
Evidence: I ran a probe against the prototype's `swept`. `register` returned true for `<home>/.cache/.`, `<home>/.cache/./images` and `<home>/.cache//images`, and 3 were then pending. `registerFixture` produces `<cache>/.` from any `engine.copy` destination spelled `<cache>/./x`, because `[^/]+` matches `.`.
I also checked what `fs.removeDir("<dir>/.")` (the sweep's `removeTree`) does: in a scratch tree it deleted everything inside, including a `.git` folder, a lock file and `images/x`, and only then failed with `Invalid argument (os error 22)`. The register also takes the sentinel `<cache>/.git`, `tests-run.lock` and `spec-durations.tsv`, all strictly inside `.cache`. The harness case lists none of these.
Critique: the sentinel is what stops git started in `.cache` itself from finding the checkout (zz-test "Fence"), and the jail does not stop a spec deleting it. No helper produces these spellings today, but `swept` is presented as refusing everything outside fixture folders, and it does not.
Consequences: `register` should accept a single fixture name directly under `.cache` (or deeper), with no empty, `.` or `..` segment, and never the runner's own entries.
Recommendation: refuse any path with an empty, `.` or `..` segment. Refuse the first segment `.git`, `images`, `tests-run.lock`, `spec-durations.tsv` and anything starting with `.` (this also covers c0194's `.tmp`). Add each spelling above to harness.spec's refusal list, and add a `registerFixture` case for an `engine.copy` destination with `/./` in it.
Lesson: z-design/guards-move-with-the-working-directory

### F6 [medium] The read-only template folder makes a leftover run folder unremovable by plain removal, and c0194 moves run folders into `.cache/.tmp` and clears the stray ones
Where: Decisions "*Template folder (F10)*"; `fence.enter` (`chmod -R 555 <runTemp>/git-templates`); `removeRunTemp`; Existing work (c0194 named only for "moves the run's temp folder")
Evidence: with `mkdir -p run/git-templates/{hooks,info} && chmod -R 555 run/git-templates`, `rm -rf run` fails here with `Permission denied` for `hooks` and `info` and `Directory not empty` for `git-templates`. The removal only works after `chmod -R u+w`. Only `removeRunTemp` does that.
A run whose launcher is SIGKILLed skips its cleanup (zz-test, Sweeper), and leaves such a folder behind. Today it is in the user temp folder. c0194 (design: reviewed, Touched `fence.luau` and `fixture.luau`) moves every `pickman-run.*` into `<home>/.cache/.tmp/` and adds "stray clearing under the lock" and `./zn tmp sweep`, which remove those folders. A person's `rm -rf z-nile/.cache` hits the same wall.
Critique: the read-only folder fixes round 1's shared-state hole but adds permanent leftovers in the repository's `.cache` once c0194 lands. The tempting fix is to put `chmod` into each remover, which spreads a template detail into c0194's owner of temp trees.
Consequences: either every remover of run folders learns about it, or the template is guarded another way.
Recommendation: keep the template writable and check it instead. The launcher fails the run (`git template changed: <path>`) if `git-templates` holds anything but the empty `hooks/` and `info/` after the specs end. The same check, at the start of each spec file in a worker, catches a write before later files inherit it. A harness case: a spec that writes `$GIT_TEMPLATE_DIR/hooks/x` fails the run naming it. If the read-only folder stays instead, name c0194 in Existing work with the rule "removers of `pickman-run.*` restore write permission first", and add a case with a stale run folder holding the read-only template that the next run clears.

### F7 [medium] In-flight preps that change the same modules are not quoted: c0194 changes `fixture.check`, c0180 changes the same worker call in `runConcurrently`, and five more touch `run.luau` or `fence.luau`
Where: Design "Interface for c0179 and c0180"; Existing work
Evidence: `git worktree list`, then the Touched modules of each prep item that touch this issue's files:
- c0194 (`fixture.luau`, `fence.luau`; reviewed) adds `fixture.zone(physical, root)`, which `fixture.check` calls. It also adds a `z-nile/lib/tmp.luau` that `main.luau` requires (see F8).
- c0180 (`run.luau`) records traces "only in `runConcurrently`", the function where c0178 adds `env = { PICKMAN_WORKER, PICKMAN_TALLY }` to the worker `process.exec`.
- c0123 (`fence.luau`, `run.luau`), c0181 (`run.luau`, the lesson footer under a failing case), c0162 (`run.luau`, Lune version check), c0132, c0157 and c0168 (`fence.luau`) are not named at all.

The process counts the design states for `fixture.check` (3 a call) depend on c0194's `zone`, and the read-only template depends on c0194's clearing (F6).
Critique: whichever of these lands second merges by hand without a stated rule. c0194's specs and this issue's fixture-check counts can each turn the other's red.
Consequences: none beyond reading the documents and writing one line per prep.
Recommendation: rerun `git worktree list` this round. For each prep touching `fixture.luau`, `fence.luau` or `run.luau`, quote its current change and status, and say which side adapts. At least: `fixture.check` composes `zone` with the home memo, and the per-call count under both is stated; c0180's worker env and c0178's env merge in one table. Re-run fixture-check.spec on the prototype with c0194's `zone` applied.
Lesson: z-design/quote-other-preps-before-promising

### F8 [medium] Six specs list their tooling by hand, so a raft that adds a module the engine requires breaks them after a `git reset --hard`, and c0194 is such a raft
Where: Per-spec clone paths ("none (they list their tooling)" for c0008, c0074, c0080, c0038, c0116/promote, c0120/promote-home); "a raft that adds a folder a spec reads fails that spec loudly, naming the path `git add` refused"
Evidence: c0074 lists `z-nile/engine/`, `z-nile/lib/ac.sh`, `sh.luau`, `fence.sh` and `graph.luau`, `z-nile/roots.luau` and `z-nile/projects.toml`. E11 says `git reset --hard` (the spec's own, or `done`'s rollback) "deletes everything outside the list". c0194 (reviewed) makes `main.luau` call `tmpTrees.new` from a new `z-nile/lib/tmp.luau`. Once both land, that file is overlaid, committed, and deleted by the reset. The engine's require then fails in c0074, c0080 and c0008, as a load error, not as the `git add` refusal the design describes. Neither design names it as an override.
Critique: the specs where the user asked for fewer files carry a hand-kept copy of the engine's dependency set. The tempting fix is to add `z-nile/lib/` to the lists. That holds until a module lands outside `z-nile/lib/`.
Consequences: either the lists follow the engine automatically, or a check states that they cover it.
Recommendation: derive the tooling part of these six lists from the engine's static require closure. `z-nile/lib/graph.luau` already builds the graph, so make it `clone.isolated`'s `tooling = "engine"` (the closure of `zn`, `z-nile/engine/main.luau`, `z-nile/lib/ac.sh`, `fence.sh`, `roots.luau`, `projects.toml`) plus each spec's own extra entries. Or add an overrides.spec case: every file in that closure is covered by each of the six lists. Then name c0194 in Existing work with the edit whichever lands second makes.

### F9 [low] Stated numbers disagree with each other and with the prototype (repeat of design-review-001 F12)
Where: Scalability, Flow of one fixture, the "fixture.check once per call" table row, Decisions F1
Evidence: I measured a warm `trackerfix.new` on the prototype with `git`, `pwd`, `perl` and `cp` shimmed: 15 `git` (7 of them guard checks), 9 `pwd -P`, 1 `perl` and no `cp`, which is 25 processes, and the tally said 25. The design states "13 git processes (six of them guard checks) and 16 `pwd -P` (30 against 79 before)". The table row says a call is "4 (two `pwd -P`, one `rev-parse`, the command)", while Decisions F1 says "3 processes (4 on the first)". The interface paragraph says "every engine run a fixture spec makes still goes through" `tracker.sh` -> `zn`. c0180's own E2 names four specs that run `engine/main` directly (`c0052/new-spacing`, `c0052/renumber`, `c0114/registry`, `tooling/migrate-odd`).
Recommendation: replace the numbers with the measured ones and make the table row match Decisions F1. Narrow the c0180 sentence to "c0178 adds no other path; the four specs c0180 lists run `engine/main` directly, as before".

Verdict: changes
