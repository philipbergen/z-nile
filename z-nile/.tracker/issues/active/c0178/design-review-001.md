# Review 001: c0178 (design mode)
Inputs: prep worktree `.worktree/prep-shared-fixture-images` at de3ad691 plus its uncommitted `c0178.md`, `check.sh`, `acceptance/*.spec.luau` and `experiments/` (E1-README.md, prototype.patch); the author's prototype clone at 4201337a (read, and cloned once with `git clone --no-hardlinks` into a `mktemp -d` folder for one mutant run, since deleted); `./zn capture c0178`; `./zn lessons --when design --full`; the zz-review, zz-test, zz-arch, zz-rules and z-design skills; in-flight preps c0117, c0165, c0180, c0189, c0194 read from their worktrees.

### F1 [high] Captured outcomes are fenced off as Non-goals or left to open questions without a Scope decision line
Where: c0178.md Non-goals (bullets 5 and 6), Design "fixture.check once per call" row, "Considered, not done", "Open questions for the user" 2 and 3
Evidence: The captured Problem says "What should happen: a fixture costs a few files and processes, not thousands", and the captured Solution says "`fixture.check` once per call, memoised per physical path in a spec process". The design leaves these out:
- The repository-cloning specs keep about 2,900 files per clone. The Design calls them "the largest single source of fixture files: 24,865 files in a run of 10 of them". They are fenced off by Non-goal 6 and open question 3 ("Say if you want it captured").
- The eleven hand-built four-repository specs are fenced off by Non-goal 5.
- The memo bullet is not done ("**No memo**"), pending open question 2.

The capture (`./zn capture c0178`) carries no `Scope decision` or `Decided with the user` line for any of these. z-design says "Non-goals fence only what the capture did not ask for" and "Only the user changes scope: ask them … then record the answer". The document was marked `design: reviewed` with all four questions still open. "Considered, not done" also says the hardlink deviation is in "the open questions", but none of the four questions names it.
Critique: The author will be tempted to keep the open questions as they are and let the user answer after review. Then the reviewed design is not the one that gets executed: AC9 "is removed if they drop it", and an answer to question 3 adds work no review has seen. Part of the memo is not a user decision at all. The Design concedes that memoising the home's physical path (`fixture.physical(".")`) "is blind only to a renamed ancestor folder, which the jail forbids". Where there is no jail, a renamed home makes the memoised prefix disagree with every live `here`, so the check refuses: it fails closed. That memo meets the bullet's words and keeps the guard, so the author should decide it. Only the whole-verdict memo, which stops catching a deleted `.git`, weakens a guard.
Consequences: Asking the user may add a per-spec sparse or `--no-checkout` design for the repository clones, with its own cases, or it may produce a split into new issues. Either way the Problem gains `Scope decision` lines, and check.sh and the Test plan change before the next round. Memoising the home path adds one per-process cache that the fixture-check counts must reflect: 3 processes a call instead of 4.
Recommendation: escalate to the user: before the next round, ask (AskUserQuestion) and record each answer as a `Scope decision (user, 2026-11-…)` line.
- (a) The repository clones' checkouts. Options: design `--no-checkout` plus the paths each of the eight specs reads, in this issue; or split it into a captured follow-up named in the Problem; or accept about 2,900 files per clone. Keeping the full scope costs about 8 spec edits and a per-spec path list.
- (b) The eleven hand-built fixtures: convert them, or accept them as they are.
- (c) F1 in-process: keep it or drop it.
- (d) The hardlink deviation: add it to the questions.

Separately, the author decides the home-path memo now: memoise `fixture.physical(".")` per process, keep `pwd -P` and `rev-parse` of `dir` live on every call, and add a fixture-check case that counts exactly one `pwd -P` for the home across two calls. Record the whole-verdict memo as refused under "Considered", with its reason.
Lesson: z-design/never-narrow-captured-scope

### F2 [high] The rule "the repository image follows HEAD (and the code)" has no case that can fail; the salt-dropped mutant passes
Where: Rules and mutants rows "the image follows HEAD and the code | clone-image :: …of this HEAD (after HEAD moved) | salt dropped | run" and "the key option (salt) | clone-image :: …of this HEAD | salt ignored | run"; acceptance/clone-image.spec.luau
Evidence: clone-image.spec has four cases, and none of them moves HEAD: no case is named "…after HEAD moved". The prototype's "moves HEAD" commit (a8ed9b2f) was a hand step, not a spec case. I ran it: in a `--no-hardlinks` clone of the prototype, I changed `z-nile/tests/lib/clone.luau` line 24 to `salt = nil, -- MUTANT: salt dropped` and ran `lune run tests/run -- tests/acceptance/c0178/clone-image.spec.luau`. Result: `4 passed, 0 failed, 1 spec files`. The mutant cannot be killed this way, because `clone.luau` and `images.luau` are themselves `code` in the key: any mutation of them changes the key, builds a fresh image at the current HEAD, and every assertion holds. The images.spec cases cover `--also` and the other key parts, but never `salt`.
Critique: The tempting fix is a case that commits in the real checkout to move HEAD, which no spec may do. Another tempting fix is to trust that a stale images folder catches it, but a fresh worktree has none.
Consequences: Testing it needs a seam. The image of a given repository must be buildable from a fixture repository, so that a spec can commit there and build again. The seam adds a parameter that the six override specs must not use.
Recommendation: Add two spec cases, both in this issue's acceptance (they run in the gate after `done` and assert a rule):
1. `images.spec :: the salt decides the image`: same inputs, salt "a" and salt "b", two ids; the same salt twice, one id.
2. `clone-image.spec :: the image follows the repository's HEAD`: through a seam such as `clone.imageOf(root)` (used by `clone.image()` with `engine.TOP`). Build the image of a fixture repository, commit in the fixture, and get a new image whose HEAD is the new commit. With the code unchanged, a mutant that drops the salt then fails.

Name the seam in the Design (Modules) and in the Rules table. Re-run both mutants on the prototype and record the result.
Lesson: z-design/spec-design-correspondence

### F3 [high] AC4 passes when the fixture helpers count nothing
Where: Design row "the gate prints fixture files written and processes started"; AC4; harness.spec cases "the runner sweeps a passing file's folders…" and "the coordinator of a concurrent run…"; Rules row "tally counts | harness :: tally counts | exec not counted"
Evidence: The only spec that reads the tally is harness.spec: `grep -n tally acceptance/*.luau` finds nothing else except docs.spec's pinned words. Its nested spec bodies call `tally.files(7)` by hand. The coordinator case asserts `(tonumber(procs) :: number) >= 0`, which is true for any number. Take an implementation in which `trackerfix`, `engine`, `clone` and `fixture` call `process.exec` and never `tally.files`. It prints `fixtures: 14 files written, 0 processes started` in that case (or nothing in a real run), and every c0178 spec stays green. The Rules row kills only a mutant inside `tally.exec` itself.
Critique: The tempting fix is to tighten `>= 0` to `> 0`. That still lets the helpers count nothing while the nested body's own calls make it non-zero.
Consequences: An exact count ties the case to the helpers' process count, which F7's poll loop and the memo in F1 both change. So the case should compare the tally with what really ran, not with a constant.
Recommendation: Add a spec case, in the existing "a warm fixture runs no cp…" child of seed-fixture.spec or a sibling. The child prints `tally.read()` after `trackerfix.new` and `fixture.git(f.other, {"status"})`, with `git`, `cp`, `pwd` and `perl` shimmed on PATH. Assert that the processes counted equal the shim log's lines, and that the files counted equal `find <base> -type f | wc -l`. Do the same for `engine.copy` (tooling-image.spec) and `clone.isolated` (clone-image.spec). In harness.spec's coordinator case, have the nested bodies call `tally.exec("true")` a known number of times and assert that exact sum. Add a Rules row: "the helpers count what they start and write | … | a helper using process.exec / not calling tally.files".
Lesson: zz-test/no-vacuous-pass

### F4 [medium] The sweep reaches about 37 of the fixture-building spec files; the claim "a passing one leaves none" is false
Where: Design row "a passing spec removes the fixtures its helpers registered"; Usability ("A failing spec keeps its fixtures, a passing one leaves none, so `.cache` no longer fills with 160k to 218k files"); Problem ("fixtures are never removed")
Evidence: Only `trackerfix.new` (its `base`) and `clone.isolated` (its `dest`) call `swept.register` (prototype `trackerfix.luau`, `clone.luau`). The search, from `z-nile/`: `grep -rlE '\.cache/' tests --include='*.spec.luau'` gives 127 files. 37 of them use `trackerfix.new` or `clone.isolated`. Of the other 90, 56 also call `engine.copy`, a raw `"init"` or a raw `"clone"` (`comm -23 … | xargs grep -lE 'engine\.copy|"init"|"clone"'`), so they build git fixtures that nothing ever removes. Among them are the eleven hand-built four-repository specs and `c0005/worktree`, `c0045/workstreams` and `c0046/launch`, which clone with `--no-hardlinks` by hand.
Critique: The captured bullet's words ("the fixtures its helpers registered") are met, but the Problem's accumulation is not, and the Usability claim overstates it. The tempting fix is to auto-register the top `.cache/<name>` of every path `fixture.check` accepts. That breaks nested runs: a nested runner started by a spec in the same home, such as harness.spec's, would sweep the outer spec's own folder when its inner file passes.
Consequences: Any automatic scheme must not sweep `images/`, the runner's own state (`tests-run.lock`, `spec-durations.tsv`), the root fence sentinel, or a folder that an outer spec in the same home is still using.
Recommendation: Do one of these, and pin it with a spec case:
- Register in `engine.copy` and in the fixture-making helpers that the hand-built specs already call, so the destination's fixture folder is swept.
- Have the runner sweep, after a passing file, every `.cache/<name>` literal that the file names, which the gate's unique-literal rule already maps to exactly one spec file. Exempt `images` and the runner's state, and skip the sweep in a nested run, which `PICKMAN_TEST_FENCE` already identifies.

Then correct the Usability sentence to what is swept, and add a harness case: a hand-built fixture under a passing file is gone, and an unswept name is listed.

### F5 [medium] A sweep that fails crashes the runner and turns a passing file red; detached fixture processes make that likely
Where: Modules (`z-nile/tests/run.luau`: "`swept.sweep()` when no case of the file failed"); prototype run.luau in-process loop; `cleanup.removeTree`
Evidence: `swept.sweep()` calls `cleanup.removeTree`. That function retries a "not empty" race for 3 s and then raises "could not remove <path> after <n> tries". The prototype calls `swept.sweep()` unprotected, after the file's cases are counted, so the raise kills the worker after its file passed. Fixture processes that outlive their case exist and are being specified:
- c0117's `control-cli` ("a detached process's late code push after a step is caught at the next run"), active;
- c0191 (No leaked processes), in prep.

The jail's sweeper stops such processes only after the whole run. Before this chore the same race existed only at the next run's `trackerfix.new`, outside any spec file's verdict.
Critique: The tempting fix is a `pcall` that ignores the error. That hides a leaked process writing into a fixture, which is the defect c0191 hunts.
Consequences: The outcome must be decided: a passing file whose sweep fails is reported, and either fails the run with the path and the leftovers named, or warns. A failed sweep also leaves the folder registered for nobody.
Recommendation: Decide it in the Design: a sweep failure prints `swept: could not remove <path>: <error>` and does not change the file's verdict, or it fails the run with that line. Add a harness.spec case: a nested spec body that registers a folder and leaves a background writer in it. Assert the runner's output and exit code as decided, and that the run does not crash. Name c0117 and c0191 under Existing work.

### F6 [medium] The deferred `other` is not the state the old setup made: it is cloned from origin as it is at first use
Where: Non-goals ("its setup is replaced by a cheaper setup that makes the same state"); Design `trackerfix.new` ("`other` waits, from the origin as it is"); Rules row "`other` waits, from the origin as it is, made once"; seed-fixture.spec "`other` is not on disk until…"
Evidence: Before this chore, `other` was cloned at `trackerfix.new`. Its `main` and `origin/main` stayed at the seed until it fetched, and it had no other remote-tracking refs. Now, if main pushes before `other` is first used, `other` starts already up to date, with every branch on origin as a remote-tracking ref. The case "`other` is not on disk until…" asserts exactly that (`toBe("later")`). I found no promoted spec that depends on the old staleness: each of the 13 files from `grep -rlE 'f\.other|\.other\b'` either pulls first or uses `other` right after `new`. But a "second terminal that is behind" is exactly what tracker race specs model. A future spec that commits in `other` without pulling, to test a rejected push or a rebase path, would silently test the fast path. The zz-test text in the prototype says only that it "is made when a fixture helper is first asked to work in it".
Critique: This is a semantic change that the Non-goal says does not happen.
Consequences: Restoring the old state costs two or three git processes, and only on first use.
Recommendation: Make the deferred clone reproduce the old state. `trackerfix.new` records the seed sha. The deferred `make` clones origin, then runs `git update-ref refs/remotes/origin/main <seed>`, `git reset -q --hard <seed>`, and deletes every other `refs/remotes/origin/*`. Change the seed-fixture case to assert that `other` is at the seed and behind `origin/main` after main pushed, and that a commit in `other` pushed without a pull is rejected. Change the Rules row's mutant to "cloned from the origin as it is".

### F7 [medium] The image lock polls with one process every 0.2 s, bounds the wait in steps rather than seconds, and lets every waiter build once a lock is stale
Where: Modules `images.ensure` ("the caller polls every 0.2 s until … the lock is older than `stale` (60 s) or `wait` (180 s) has passed, then builds anyway"); prototype `images.luau` loop
Evidence: Each iteration runs `tally.exec("mkdir", { lock })`, a subprocess, then `task.wait(0.2)` and `waited += 0.2`. So 8 workers waiting on a cold build start about 40 `mkdir` processes a second. Under the load this issue measured (18 to 35), each iteration takes longer than 0.2 s, so `wait = 180` is a step count, not 180 s. A builder killed by Ctrl-C or the sweeper leaves its lock. The next run's workers all wait the full 60 s. They then break out without taking the lock (`mine = false`) and all build the same image at once. The lock records no owner, so liveness is judged only by age.
Critique: The tempting fix is to make `stale` shorter. That makes a slow, live build under load look dead, and multiplies the duplicate builds.
Consequences: An owner record brings a pid-reuse question, which the runner's `tests-run.lock` already answers with a pid and a start id read through perl, inside the jail too. A takeover must be atomic, so exactly one waiter wins.
Recommendation: In the loop, check `fs.isDir(final)` and `fs.isDir(lock)` in-process, and run `mkdir` only when the lock is gone. Measure `wait` and `stale` with `os.time()` (or `os.clock()`, which is wall time in Lune) against a start stamp. Write `pid` and the start id into the lock right after `mkdir`. A waiter that finds the owner dead renames the lock to `<id>.lock.dead.<random>` and retries `mkdir`, so one builds. Add images.spec cases:
1. A lock whose recorded owner is dead: four waiters start one build, at once, without waiting `stale`.
2. A held lock: the number of `mkdir` processes per second of waiting is bounded (count them with `tally.read()`).
3. `wait` is honoured in seconds when each poll is slowed.

Lesson: zz-test/count-calls-in-poll-loops

### F8 [medium] The interface promised to c0179 and c0180 does not hold: a shared images folder would prune live images, and c0180 is no longer an in-process driver
Where: Design "Interface for c0179 and c0180"
Evidence:
- Prune orders images by the folder's mtime. That is set at publish and never refreshed by use. In the "one shared images folder [that] serves every worktree" the interface offers c0179, worktree A's publish removes worktree B's image once two newer images of its kind exist and B's is over 3,600 s old. B's run may be cloning from it at that moment.
- c0179 as captured puts fixtures under `<volume>/<checkout id>/<home>/`, which is per checkout, not shared.
- c0180 was re-scoped on 2026-11-01 (its Problem's `Scope decision`: "keep ./zn as a subprocess; split main.luau into one module per command … let --affected run only specs that used a changed command") and dropped c0178 from `depends_on` (c0180.md line 234). The c0180 bullet here, "a driver that runs several spec files in one process must…", describes a design that no longer exists.

Critique: c0179's prep will read this section as a contract.
Consequences: Making sharing safe needs a last-use stamp, such as a `touch` of the image on each `ensure` hit (one fs call, no process), or a rule that a folder shared between checkouts is never pruned below the live runs' images.
Recommendation: Either state that the images folder is per checkout and must stay per checkout, or make prune order by a last-use stamp written on every hit, with an images.spec case: an old image used just now survives a prune with `keep = 0`. Rewrite the c0180 bullet from c0180's current document, or drop it, and name c0165 (which touches `run.luau` and `fence.luau`) and c0194 (which moves the run's temp folder under `.cache/.tmp`, where `GIT_TEMPLATE_DIR` and the tally folder then live) under Existing work.
Lesson: z-design/quote-other-preps-before-promising

### F9 [medium] `trackerfix.worktrees` says "as `./zn worktree` makes them" but always branches new from `origin/main`
Where: Modules (`trackerfix.worktrees(f, names)`); prototype `trackerfix.luau`; `z-nile/engine/main.luau` `cmd.worktree` (lines 3642-3705)
Evidence: `cmd.worktree` runs `git worktree prune` and `git fetch --prune`, then:
- reuses an existing local branch (`worktree add path branch`);
- tracks `origin/<name>` when that exists (`branch --track`, which gives the branch an upstream);
- otherwise branches with `--no-track -b` from `origin/main`.

For every name after the first, the helper always runs `worktree add --no-checkout --no-track -b name path origin/main` and copies the first tree in. For a name that exists on origin, that is a different branch and tree from what zn makes, with no error. For an existing local branch, `-b` fails with git's message and no rule. worktrees.spec refuses only bad name shapes. c0116/claims uses fresh names, so it is unaffected today.
Critique: The helper is a public one-liner that the next spec will reuse after pushing branches.
Consequences: None beyond one `show-ref` per name, which is cheap.
Recommendation: Refuse, naming the name, any name after the first whose `refs/heads/<name>` or `refs/remotes/origin/<name>` exists. Add a worktrees.spec case for each, with the message pinned, and narrow the docstring to "fresh named worktrees".

### F10 [low] The git template folder is shared and writable by every spec of the run
Where: Modules (`fence.luau`: "`GIT_TEMPLATE_DIR=<run temp>/git-templates`")
Evidence: The folder is in the run's temp folder, which the jail lets every spec write. A spec that writes `$GIT_TEMPLATE_DIR/hooks/post-checkout` puts that hook into every later `git init` and `git clone` of every other spec file in the run. That is mutable state shared across spec files, which zz-test's Speed rule forbids. The system template it replaces was not writable by specs.
Recommendation: After `fence.enter` creates `hooks/` and `info/`, make them and the folder read-only (`chmod 555`): git's template copy creates the destination folders itself, so specs' `.git/hooks` stay writable. Add to harness.spec's template case: writing into `$GIT_TEMPLATE_DIR/hooks` fails, while writing `.git/hooks/pre-push` in a fresh repository still works.

### F11 [low] `tally.exec` is a generic process runner in the harness that c0060's retrofit scan cannot see
Where: Modules (`tally.luau`); `tests/acceptance/c0060/retrofit.spec.luau`
Evidence: retrofit.spec keeps the twelve older fixture specs off raw git by matching `process%.exec%( ?"git"` and a `process.exec` of a computed command ("a generic runner would bypass the helper"). `tally.exec("git", { "commit" }, { cwd = … })` matches none of these patterns, so the scan does not see it.
Recommendation: Keep the counting inside the helpers (`tally.started(n)` next to their own `process.exec`), or add `tally%.exec%(` to retrofit's patterns in this chore's override list, with a case in overrides.spec.

### F12 [low] Numbers and labels that are not true as written
Where: Design and acceptance headers
Evidence:
- "7 processes a call become 3": fixture-check.spec counts one `rev-parse` plus the command, and the check also runs two `pwd -P`, so a call is 4.
- "The key costs one `perl` … (about 20 ms over ~900 files)": I ran the prototype's `image-key.pl` with the tooling image's inputs and skips over this worktree. It took 0.022 s and the walk covers 250 files (`find zn scripts z-nile` minus `.tracker`, `tests` and `.cache`).
- The header comment of docs.spec says "AC8" (it is AC10), and overrides.spec says "AC7" (it is AC8).
- AC11's list leaves out six of the seven overridden specs (only `c0008/done-order` is in it) and every reader of `f.other`; the full gate covers them, so the label's "stay green" is a sample.

Recommendation: Correct the two numbers. Fix the header comments. Add the six overridden specs and one `f.other` reader, such as `c0114/window`, to AC11, or label it as a sample.

Verdict: changes
