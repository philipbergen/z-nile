# Review 001: c0302 (design mode)
Inputs: prep worktree `prep-layer-branch-breaks-clone-fixtures` at 9e8f3a5d8 (origin/main is now 71458a532, which adds only tracker files), with the uncommitted `c0302.md`, `check.sh`, `acceptance/{narrow.py,layer.sh,fixtures.spec.luau}` and `experiments/{narrow.patch,mutants.py}`; `./zn capture c0302` (b28f3689); `z-nile/engine/{layergit,compact}.luau`, `z-nile/tests/lib/{clone,trackerfix,cachepaths,slow}.luau`, `z-nile/tests/run.luau`, the seven specs, `c0060/retrofit.spec.luau`; the documents, checks and patches of c0178 (active, R0073), c0282, c0083, c0123, c0180, c0248, d0298 and R0096.
Probes: a `--no-hardlinks` clone of the worktree under `$TMPDIR`, with `narrow.patch` applied and committed on `R9999/1/c9999`. Every probe ran through `./zn run`.
- In the worktree, `fixtures.spec` gives 2 passed and 1 failed (the seven listed), as E4 says.
- In the patched clone: `fixtures.spec` passes 3/3, `narrow.py` exits 0, `./zn promote-check c0302` is OK, `layer.sh` gives 50 passed in 33 s, and AC3's run gives 50 passed in 32 s.
- `layer.sh` against the unfixed seven: 18 passed, 32 failed, 8 'no main branch'. This reproduces E4.
- `mutants.py` N2 and N4 to N10 turned red as recorded.
- The other results are cited in the findings below.

### F1 [high] Under `./zn dispatch`, AC2 and AC3 cannot pass, and d0298, which fixes the cause, depends on c0302
Where: `check.sh` AC2 and AC3; `acceptance/layer.sh:30`; Design, "The proof on a layer branch"; Implementation step 3. Nowhere does the document say which environment c0302 runs in.
Evidence: d0298 is prepared, in R0096, with `depends_on: [c0266, c0302, c0304]`. It records that on main, `c0008/done-order` fails 1 case in a dispatched step's environment (d0298.md:46, E1, E8: "could not push the binding commit to main ... git (z-nile wrapper): git push to main refused: could not fetch a fresh copy of main"). d0298's AC4 is the fix. c0302's check.sh runs AC3 and `layer.sh` in the caller's environment, and `layer.sh` hands that environment unchanged to the clone's runner. Probe: in the patched clone, I ran `c0008/done-order` with d0298's `dispatched` variables (`ZN_DISPATCH=1`, `ZN_HEADLESS=1`, the broker, token and state variables, `z-nile/bin` first on `PATH`). It gave 4 passed and 1 failed, case "marks the PR ready while origin still has the previous head, then pushes the done commit", with that same message. The same seven without those variables gave 50 passed. So a headless z-run of c0302 stops at `./zn finish` on a red that no edit to the seven can clear, because check.sh is sequestered. And z-ready refuses R0096 until c0302 is done. On the dispatched path the two items wait on each other.
Critique: On one of the two ways a raft is run, no implementation can meet these criteria. The tempting fix is to drop done-order from AC2 and AC3. That shrinks the proof of the captured outcome.
Consequences: To make the check independent of its environment, check.sh would have to unset the step's variables. That copies part of d0298's stepenv fix and has to stay in step with it, and it can't use `env -i`, which the repo-fence scan bans. To document "interactive only" instead, z-raft must carry the rule into the raft's Theme and prompt. A dispatched code reviewer that runs `./zn check c0302` sees the same red.
Recommendation: Pick one and record it, with the probe as a new Unknowns entry.
- (a) The Design, step 3 and the Unknowns say that c0302 is executed, and its `./zn check` run, outside a dispatched step: interactive z-work. State the reason and the d0298 cycle, so that z-raft puts the rule in the Theme and the prompt.
- (b) `layer.sh` and AC3 run the seven with the dispatched step's variables unset: the list in d0298 E1, with `z-nile/bin` removed from `PATH`. Add an experiment showing that `./zn check c0302` passes inside d0298's `dispatched` helper, and that without the unsetting it fails on done-order.

### F2 [high] c0282's sequestered `lifecycle.spec` has the same unnamed fixture; the design does not handle it, and promoting it turns AC4 red
Where: Design, "Existing work" and "The rule, kept"; `acceptance/fixtures.spec.luau`, the population walk.
Evidence: c0282's `acceptance/lifecycle.spec.luau` has `clone.isolated(root, dir)` at line 92, `git({ "remote", "remove", "origin" })` at 93 and `tr({ "start", "R0010" })` at 157 and 206, with no `{ "checkout", "-q", "-B", "main" }`. Search: `grep -rlE 'clone\.isolated\(root|"--no-hardlinks", root' --include='*.spec.luau' z-nile/.tracker | grep -v /done/` finds c0282's `lifecycle.spec` and c0178's `overrides.spec`, which only names the needle as text. c0282 is prepared, has no raft and depends on c0263.
- Its check.sh runs that spec at lines 15 and 17, on c0282's own layer branch. There `start` is refused with 'no main branch', exactly as the seven are today. Its AC7 (check.sh:25) also runs `c0074/done-gate` and `c0001/tracker-lifecycle` on that branch.
- Probe: I copied the spec to `z-nile/tests/acceptance/c0282/lifecycle.spec.luau` in the patched clone, which is where c0282's `done` will put it. AC4's third case turned red: `expected "", got "z-nile/tests/acceptance/c0282/lifecycle.spec.luau"`.
- `fixtures.spec`'s watch list will hold what it requires (`tests/lib/t.luau`), so c0282's `done` does not select it. Main goes red at the next full gate or watch-net run.
Critique: The chore checklist's Existing work item asks which prepared items fail the new rule on the day it lands, and what each does then. The design does not answer it for c0282, the one prepared item that fails it. c0282 cannot pass its own check on a layer branch, with or without c0302. After c0302 lands, its spec is the one the new rule rejects.
Consequences: c0282's spec is sequestered, so it needs a re-prep. That is a change to another item, so this prep's lead captures it rather than editing c0282. c0282 also comes to depend on c0302 for its AC7. If the scan is widened to unfinished items' acceptance specs, so that the next such spec is red in its own prep PR, AC4 stays red until c0282's re-prep lands. That fixes the order of the two.
Recommendation:
- Name c0282 under Existing work and say what happens to it.
- Capture its re-prep in this prep through z-ticket: c0282's `lifecycle.spec` names its clone's branch `main`, and c0282 depends on c0302.
- Decide whether AC4 also walks `z-nile/.tracker/issues/**/acceptance/*.spec.luau` outside `done/`. If it does, add a planted case for a sequestered spec, a Rules row, and the order (c0282's re-prep lands first, or AC4 is red). If it does not, say that the next such fixture is found only after its own `done`.
- Paste the search into the Design.
Lesson: z-design/new-rules-migrate-existing-work

### F3 [medium] Existing work misses c0178 (active, R0073), which rewrites the clone set-up of all seven, and the items whose checks need c0302; the override list misses c0060/retrofit
Where: Design, "Existing work"; Regression guard, the override search.
Evidence:
- c0178 is active (R0073, readied in 16df8b98c). Its `acceptance/overrides.spec.luau:22-36` lists all seven. Its `experiments/prototype.patch` replaces each clone line with `clone.isolated(root, <dest>, { paths = … })` (c0001's hunk at 67, c0080's at 83), and makes `clone.isolated` clone from a bare image of the checkout.
- Probe: c0178's hunks pass `git apply --check` today for c0001, c0038, c0050, c0074 and c0120, and fail on all five once c0302's lines are in. c0008 and c0080 fail either way. A 3-way merge of those five hunks with c0302's commit is clean and keeps one naming line in each file.
- Four items' checks run some of the seven on their own layer branch, where they fail today: c0178's AC10 (c0001, c0008, c0038, c0120), c0123's AC6 (c0008, c0074; check.sh:28,30), c0248's AC15 (c0074, c0120; check.sh:50) and c0282's AC7 (c0001, c0074).
- Grepping the seven basenames over `z-nile/tests` also finds `z-nile/tests/acceptance/c0060/retrofit.spec.luau`, which lists c0001, c0008, c0038 and c0050 by path. The design's list leaves it out. It stays green: its scan matches `process.exec("git", …)`, and the new line goes through each spec's own `git` helper.
Critique: Lesson design-the-execution-window applies: an active raft rewrites the lines next to this one's. Neither the ordering advice (the raft rule, AC1's split message) nor the design names that raft. If R0073's executor adds the naming line itself to clear its AC10, c0302's AC1 refuses the base ("a base that already holds it") and c0302 needs a re-prep.
Consequences: Whichever of the two lands second has to merge 3-way, not with `git apply`. The rule against sharing a raft is not something `./zn raft-plan` reads. With c0302 marked prepared, a simulation in the clone folded it into R0069 with c0247 and c0112. Those touch none of the seven, so today's fold is fine only by luck.
Recommendation:
- Add c0178 to Existing work and say four things:
  - R0073 and c0302 merge 3-way, and the probe shows the merge is clean.
  - c0302's anchor and its `clone.isolated(root` needle survive c0178's rewrite.
  - R0073's AC10 is red on its layer branch until c0302 is done.
  - If R0073 lands first with the naming line already in, step 1 stops, and that is the likely cause.
- Name c0123, c0248, c0282 and c0178 as items that in practice depend on c0302, for z-raft and for their re-preps.
- Paste the Existing-work search and the override search with their hits. Add c0060/retrofit and say why it stays green.
- Say that the raft-mate rule is checked by z-raft's coherence review, not by `raft-plan`.
Lesson: z-design/design-the-execution-window; zz-review/lists-paste-their-search

### F4 [medium] The promoted scan misses a fixture whose checkout variable is named differently, and is fooled by a block comment or an earlier, unrelated naming
Where: `acceptance/fixtures.spec.luau:16` (CLONES), `:38-46` (`code`), `:63-67` (`named`); Design, "The rule, kept"; Maintainability.
Evidence: Each probe planted a `tests/tooling/*.spec.luau` in the patched clone that clones, removes origin and starts with no real naming. AC4 stayed at 3 passed for all three. A control planted with `clone.isolated(root, dir)` and no naming failed and named the file.
- (P2) `clone.isolated(TOP, dir)`. c0178's specs already call the checkout `TOP` or `engine.TOP` (`clone-image.spec.luau:68`, `overrides.spec.luau:11`).
- (P3) The naming line inside a `--[[ … ]]` block comment.
- (P4) The naming line in an earlier `git init` helper, with the clone fixture after it unnamed. `named` compares the file's first naming with the file's first start.
The spec's watch list will be `t.luau`, so a new offending spec does not select it in `--affected`. The full gate or the watch net finds it, after it has landed.
Critique: The Maintainability claim, "a scan that names any new fixture that forgets it", holds for one spelling only. The tempting fix is to add `TOP` to CLONES. That leaves P3, P4 and the next name.
Consequences: Wider matching must not pull in fixtures cloned from a fixture's origin. Today, `clone.isolated(` with any first argument, plus an origin removal, plus a start, still gives the same ten: c0006's `source`, c0122's `origin` and c0178's `TOP` never start. A spec that needs a lone layer branch on purpose (the case F5 suggests) then has to build its repository with `git init`, or the rule flags it.
Recommendation:
- CLONES matches `clone.isolated(` and `"--no-hardlinks", ` with any first argument.
- `code()` drops block comments (`--[[` or `--[=[` up to `]]` or `]=]`) and trailing `--` comments outside strings.
- `named()` requires, for each clone match, a naming after that clone and before the first start that follows it.
- Add each as a planted pure case (P2, P3, P4, and a trailing comment) with its Rules row, and keep the population assertion.
- Say in Maintainability where the rule is enforced: the full gate and the net, not the affected gate.
Lesson: zz-test/absence-scans-cover-every-form

### F5 [medium] Non-goal 1 is unguarded, and the spec cited for it does not exist
Where: Design, "No behaviour change" (`tests/tooling/stack-git.spec.luau`); Non-goals; Rules and mutants.
Evidence: `stack-git.spec.luau` does not exist and never did. `git log --all -- z-nile/tests/tooling/stack-git.spec.luau` prints nothing, and `tests/tooling` has only `stack`, `stack-fix` and `stack-land`. `git grep -nE 'no main branch|mainTip' -- z-nile/tests pickman/tests 'z-nile/.tracker/**/acceptance/**'` finds nothing outside c0302. The Design rejects one option: making `layergit.mainTip` return HEAD on a lone layer branch (`layergit.luau:71`). A mutant that does that on top of the two lines passes AC1 to AC4 and every promoted spec.
Critique: The design states a rule, that mainTip and `./zn start` still refuse, but gives it no Rules row, and no case fails for the rejected option. The tempting fix is to cite another spec, but none pins the refusal.
Consequences: A case built by cloning the checkout trips the new scan (F4), so it has to use a `git init` fixture.
Recommendation: Remove the false citation. Then do one of these:
- Add a fast case, in `fixtures.spec` or a new acceptance spec. In a `git init -b R0010/1/f0010` fixture under the spec's `.cache`, it gets 'no main branch' from mainTip, through `./zn start` or the module run in that folder. A second fixture with a `main` gets main's sha. Add the mutant row "mainTip falls back to HEAD on a layer branch".
- Or state that only the code review's diff guards Non-goal 1, and add a `reasoned` row that says so.
Lesson: z-design/spec-design-correspondence

### F6 [medium] AC2 and AC3 run the seven slow-tier specs twice at every finish, restack and done; the cost is understated, and during execution AC3 duplicates AC2
Where: `check.sh` AC2 and AC3; Design, "The proof on a layer branch" ("about 25 s").
Evidence: All seven are in `z-nile/tests/slow.tsv`. Timings in the patched clone:
- `layer.sh`: 33 s. That is one full clone of the repository plus a fixture clone of it for each of the seven.
- AC3: 32 s, with seven more clones.
- Together: about 65 s and 15 full clones of a 113 MB repository for each `./zn check c0302`.
During execution the checkout is on `R<NNNN>/<n>/c0302`, so AC3 runs the same layer-branch state as AC2. Nothing then runs the plain-branch half of the captured outcome ("the same results ... as on a plain branch name"). The fixed chore fold would put c0302 in a raft with two other issues (R0069), so every restack pays the cost again.
Critique: This repeats the lesson. The design cites the user's rule that real-work proofs live in check.sh, but not the lesson that rule conflicts with, and it states about a third of the measured time.
Consequences: Dropping AC3 leaves only the layer-branch run. Replacing AC3 with a plain-branch run in `layer.sh`'s own clone keeps both halves, for about the same 65 s, with no run in the checkout.
Recommendation: State the measured cost and the conflict with the lesson. Then do one of these:
- Make `layer.sh` the only real-work run, and have it run both states in its one clone: `R9999/1/c9999` with no `main`, then a plain branch. Drop AC3's run in the checkout.
- Or keep AC3, and say that it duplicates AC2 during execution and why 32 s is worth it.
Either way, correct the 25 s.
Lesson: zz-test/check-sh-never-runs-the-slow-tier

### F7 [medium] `layer.sh` builds a copy of the tree at a fixed name under `.cache` and runs it there, outside the jail
Where: `acceptance/layer.sh:9` and `:20-32`; Design, "It writes nothing outside that one `.cache` folder".
Evidence: The zz-test Writers rule: "A writer of a whole directory tree (a scratch worktree, say) never works at a fixed name under `.cache`: it uses a fresh `mktemp -d` outside it". `layer.sh` runs from check.sh, outside any jail. It clones into `z-nile/.cache/c0302-layer`, `cp`s seven files into the clone (cp writes through a link at the destination), and starts `lune run tests/run` there, whose top process is unjailed.
- The jail lets every spec of a concurrent run in the same worktree write anywhere under `z-nile/.cache`. So during AC2 such a spec can swap a destination for a link into the checkout, or edit the clone's `tests/run.luau` before it starts.
- The cachepaths scan skips both places `layer.sh` lives (`.tracker` and `z-nile/tests`), so only review can see this.
- Every early `exit 1` after the clone (lines 25 to 28), and an interrupted inner run, skip the final `rm -rf` and leave a full clone in `.cache`.
- Precedent: c0115's check.sh did the same (a fixed `.cache/c0115-ac2`). c0060's check.sh (line 41) uses `mktemp -d "${TMPDIR:-/tmp}/…"`.
Critique: Exploiting it needs a hostile spec running at the same time, so medium, not high. But it breaks a stated safety rule, and the fix is one line.
Consequences: A clone under `$TMPDIR` is the documented place for a copy of the tree to run its own specs, and the jail closes other temp folders to specs. It also takes about 2,600 files out of the worktree's `.cache`.
Recommendation: Set `dir="$(mktemp -d "${TMPDIR:-/tmp}/c0302-layer.XXXXXX")/repo"` and `trap 'rm -rf "${dir%/repo}"' EXIT`, keep the toplevel check, update the Design sentence, and rerun E4.

### F8 [low] `narrow.py` spells the seven paths in two parts, so after a compaction AC1 still points at the old ids
Where: `acceptance/narrow.py:10` and `:25-33`.
Evidence: `z-nile/engine/compact.luau:40`: a compaction rewrites ids in the `.md` and `.sh` files under a project root, and elsewhere rewrites only `tests/acceptance/<id>` paths. So check.sh's AC3 paths and `layer.sh` (both `.sh`), and `fixtures.spec`'s FIXED list (whole paths), follow a compaction. `narrow.py` builds its paths as `A + "c0001/…"`, so it does not. Its `git show` of a missing path then ends in a traceback (red) that the executor cannot fix.
Recommendation: Spell each FILES entry whole, as FIXED does (`"z-nile/tests/acceptance/c0001/tracker-lifecycle.spec.luau"`).

### F9 [low] Step 4 contradicts itself, and the experiments' bounded commands are not recorded
Where: Implementation step 4; Unknowns & experiments; `experiments/mutants.py:1`.
Evidence: Step 4 says a newly failing spec "gets the same two lines", then says "stop and report it rather than editing a file AC1 does not list". The Unknowns don't say that E1 to E5 ran through `./zn run`, and the usage line in `mutants.py` is a bare `python3 -I mutants.py`.
Recommendation: Reword step 4 to "stop and report it; do not edit it". Record the `./zn run --time …` command each experiment used, and use it in `mutants.py`'s usage line.

## Lesson candidates (for the prep's lead)
- zz-test: a script a check.sh runs that executes, or writes into, a copy of the tree builds it in a fresh `mktemp -d` outside the repository and removes it with a trap. It never uses a fixed name under `.cache`, because a concurrent jailed spec can write there and the copy's runner is unjailed (F7). Check: does any script a check.sh runs execute or write through files at a fixed path under `.cache`?
- z-design: a design that changes a rule about how fixtures are set up searches the sequestered acceptance specs of unfinished items for the old shape, not only the promoted specs. c0282's prepared spec had the exact defect (F2). Check: does the search for the old shape cover `*/.tracker/**/acceptance/` outside `done/`?
- z-design: when an item may run headless, a check.sh that runs promoted specs is also run in a dispatched step's environment (d0298's `dispatched` helper), and the design says which environments it passes in (F1). Check: do this item's checks pass under `ZN_DISPATCH=1` with `z-nile/bin` first on `PATH`, and is any spec they run known to be red there?

Verdict: changes
