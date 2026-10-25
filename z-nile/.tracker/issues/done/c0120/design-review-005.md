# Review 005: c0120 (design mode)
Inputs: `origin/prep-c0120` at 870782a (`git log 9449b79..870782a`: `c0120.md`, `check.sh`, `rewrite-finished.luau`, `acceptance/*`, R0043.md), the prototype `proto2-c0120` at a4f4832 (cloned to a scratch folder outside the repository, remote removed; its c0120 specs, `check.sh` and rewrite tool are byte-identical to the prep's), `./zn capture c0120`, `./zn lessons --when design --full`, c0114's decided guesses (`z-nile/.tracker/issues/c0114/c0114.md`) and acceptance folder, and `origin/prep-c0115` (PR #103).
Dropped from review-004: F1 (fixed as refute-004 says).

Runs in the scratch clone:
- From `z-nile/`, all 14 c0120 spec files pass (94/94). From `pickman/`, pickman's suite passes (1068/1068). From `z-nile/`, z-nile's full suite passes (908/908).
- **Repository-safety attacks.** I used `ac.sh` with a probe `check.sh` under `pickman/.tracker`, both directly and through `./zn check`, and the runner from `pickman/` with a probe spec:
  - **Inherited `GIT_DIR`** (a decoy repository): `./zn check` refuses ("git's repository is … not this checkout's own"). The runner strips it, so the spec sees no `GIT_DIR` and `PICKMAN_FENCE_REAL_GIT` is the real repository.
  - **`GIT_COMMON_DIR`** (a decoy): stripped by `ac.sh` and the runner, and the real repository is protected.
  - **`GIT_CEILING_DIRECTORIES`** at the checkout root:
    - `./zn check` fails, because the check.sh's own header can't find the toplevel (exit 1, the same as before c0120).
    - The runner's protected-repository read is clean. Specs then find no repository, which fails closed.
    - A ceiling at `pickman/` or `pickman/.tracker` behaves the same way.
  - **Waiver on failure:**
    - With the root's `.cache` set to 555 and no markers: refuses.
    - With two of the three markers: refuses.
    - With all three markers faked outside a jail: waived. That is the accepted design, keyed on the markers, as decided in c0114 G6.
  - **`.cache` as a symlink:**
    - At the root or in `pickman/`, through `ac.sh`: refuses.
    - In `pickman/`, through the runner: refuses.
    - `pickman/.cache/.git` as a folder: refuses.
  - **The root fence from a home**, inside pickman's jail: a spec can't remove the root's sentinel or create `<top>/.cache/fx` ("Operation not permitted"). Every attack refuses or holds on macOS. F2 is the Linux gap, and F3 is the missing pin.

Scope (item 11): the capture (ab750c0) is confirmed and unmarked. Title, Problem and Solution have only gained detail and `Decided with the user` lines. Every captured outcome has a Design and a Checked criterion.

New guesses (G13–G16), judged:
- G13 (z-nile's gate checks the root tooling, and changes to it force every project's full run): reasonable. z-nile owns `zn` and the shims, and the alternative, a third gate with no project, adds a CI job for a few files.
- G14 (z-nile's `scripts/check.sh` runs z-nile's gate only): reasonable and symmetric with G7. CI's pickman job covers pickman. The R0040 label it leaves untrue is disclosed, and that file can't be edited.
- G15 (the root `.luaurc` keeps every alias): reasonable, and needed because of the worktree inheritance (U2, Guess 8). The nearest `.luaurc` still wins for each home's files.
- G16 (no `home` key; the home is `dirname(root)`): reasonable. It matches c0114's `projects.inDir`/`folderOf` rule, makes E4 moot and keeps one source of truth. The registry-home spec pins the parser's refusal of `home`.

### F1 [high] c0114's decided Guess 5 adds a promoted spec, `c0114/finished.spec`, that c0120 turns red, and the Overrides line doesn't name it
Where: Regression guard, Overrides, fourth bullet ("c0114's, promoted before c0120 runs … registry, classified, gate-cover, docs, roots-cli, window, as `c0114-overrides.patch` records"); Verification log, the z-nile list ("c0114/{classified,…,window}", and "the first revision's `c0114-overrides.patch` is replaced by these"); `z-nile/.tracker/issues/c0114/acceptance/finished.spec.luau`.
Evidence: c0114's reworked prep, decided G5, promotes `finished.spec` into `tests/acceptance/c0114`, which c0120 moves to `z-nile/tests/acceptance/c0114`.
- **The cwd change.** Its `tree()` walks `ROOTS = { "tracker", "z-nile/.tracker" }` relative to the cwd. Run from `z-nile/`, neither folder exists (`z-nile/tracker`, `z-nile/z-nile/.tracker`), so `files` is empty and `t.expect(#files > 100).toBe(true)` fails.
- **The second rewrite.** Even if the paths are fixed, its case "every finished item's check.sh … is already rewritten" asserts `rewrites.paths(text, moved) == text` over every finished file. c0120's rewrite then changes about 33 of those files a second time (`./zn` to `../zn`, `tracker/architecture.md` to `.tracker/architecture.md`), and pickman's finished items leave `tracker/` for `pickman/.tracker`, which is not in `ROOTS`.
- **Not named anywhere.** `finished.spec` appears in neither override list. The prototype stands on the simulated old c0114 tree, which has no G5, so the measurement could not see it.
- **The c0114 list contradicts itself.** One bullet names six specs "as the patch records", and the log names eleven and says the patch is replaced.
Critique: an unnamed override is high (item 4). The executor will hit a red spec it was never told it may change, and it is a promoted c0114 spec, so the change is a scope question in code review. The tempting fix is to add `c0114/finished` to the list. That leaves the contradiction, and it leaves the other specs c0114's rework added or changed, such as docs.spec's settings-pairing case, which reads `.claude/settings.json` relative to the cwd.
Consequences: the override has to say how the c0114 spec relates to c0120's rewrite:
- (a) The c0114 assertion holds on c0120's output. This is false today.
- (b) The c0114 spec asserts on files as of c0114's move only. c0120's AC18 already pins c0120's own rewrite, so this keeps one owner per rewrite.
Recommendation:
- Measure the c0114 overrides on c0114's reworked tree, not the simulated one. If that tree hasn't landed, measure on `prep-z-nile-home`'s acceptance folder applied to the prototype.
- Replace bullet 4 with the measured list, `finished.spec` included, and delete `c0114-overrides.patch` or mark it historical.
- For `finished.spec`, choose (b). Read `ROOTS` from the registry, relative to the toplevel. Assert idempotence of c0114's rewrite on c0120's output only where it holds, or say the second rewrite supersedes it.
- Add a Verification-log line: `c0114/finished.spec` red without the override and green with it.
Lesson: ticket-prep/restated-rules-move-together (the same list stated twice, and the two copies disagree)

### F2 [high] Run from a home, the runner leaves the toplevel's `.cache` unfenced. On Linux (CI), git in a fixture there finds the real repository
Where:
- §4 ("The fence runs with `here` = the home"), §3 "Every other guard tied to a folder is the home's".
- `z-nile/tests/lib/fence.luau` `enter()` (`pickman_fence "$1" specs` with `$1` = here only).
- `z-nile/check.sh` lines 117–118 (`mkdir -p .cache` at the root, with no sentinel).
Evidence: in the scratch clone, I forced `jail()` down its non-macOS branch (`none (not macOS: environment guards only)`, as CI's ubuntu job gets). With the root's `.cache` as the gate leaves it (a folder with no sentinel), I ran a probe spec from `pickman/`. It printed `CEIL=…/pickman/.cache`. In `$(git rev-parse --show-toplevel)/.cache/fx`, `git rev-parse --absolute-git-dir` answered the clone's own `.git`, and `git add -N ../../AGENTS.md` ran against the real index.
- Before c0120 the toplevel's `.cache` was the run's own `.cache`, under the ceiling and holding the sentinel. That location was the idiom 59 spec files used (U9).
- After c0120 it is in no spec run's ceiling, and the gate creates it without a sentinel.
- On macOS the jail refuses those writes, which I confirmed, so only Linux runs are open. The ref guard still refuses ref updates there, but not index or worktree writes.
- §3 already extends the tripwire to "any `.cache` of the checkout". The ceiling and the sentinel weren't extended the same way.
Critique: a guard that covered a folder before the move no longer covers it after (item 9: a weakening is high; lesson testing/guards-move-with-the-working-directory). The tempting fix is "every spec now writes its home's `.cache`" (U9's conversions). That holds only for specs converted today. It misses unconverted ones from preps in flight, such as c0115's, which was designed for the root, and any spec copied from an old promoted file.
Consequences: fencing the toplevel's `.cache` from a home run needs:
- the ceiling, which is environment only and can't fail;
- the sentinel, a write outside the jail's allowed folder. The runner must make it before it enters the jail. Under an outer sandbox, that sandbox must also let the root's `.cache` be written, which extends refute-004's requirement.
Recommendation:
- In `fence.enter()`, while still unjailed (where it already makes `.cache` and sweeps links), run `pickman_fence_ceiling`, `pickman_fence_refusals` and `pickman_fence_sentinel` for the checkout's toplevel when it differs from `here`. Inside the jail's `bash -c`, add `pickman_fence_ceiling <top>` before `pickman_fence "$1" specs`, so the ceiling names both. Also give the gate's root `mkdir -p .cache` the same refusals and sentinel, or have it call those functions.
- Extend the testing skill's outer-sandbox requirement to "the root's `.cache` and every home's".
- Add a runner-home case: a run from `pickman/` has `<top>/.cache` in `GIT_CEILING_DIRECTORIES`, and `<top>/.cache/.git` is the sentinel afterwards. The mutant to kill is "ceiling for `here` only".
- Add a Rules-and-mutants row.
Lesson: testing/guards-move-with-the-working-directory

### F3 [medium] Nothing pins the root fence's refusal in `ac.sh` (step 2): the mutant `pickman_home_fence "$(pwd -P)" || true` survives everything
Where: §3 step 2; `homes.spec` (every refusal case is `pickman/.cache`'s); the Rules-and-mutants row H7 (kills only the opposite mutant, `pickman_fence` at the root).
Evidence: in the scratch clone I changed `ac.sh`'s root line to `|| true`. These all still pass:
- `homes`, `check-paths`, `finished`, c0034's `locator` and `repo-fence` (39/39);
- z-nile's full suite (908/908).
With that mutant:
- a symlinked root `.cache` or a `.git` folder planted at `<root>/.cache/.git` no longer refuses;
- the root's ceiling is exported, but its env step and its sentinel are skipped.
On the prototype as shipped, the refusals hold: my A5 runs refused.
Critique: the lead asked for the root fence entered from a home to refuse, and it does, but only by code. Step 2 is new in this revision (the root used to be the run's own home, fenced by the runner). A refactor that tolerates its failure would pass every gate.
Consequences: none beyond the new cases.
Recommendation:
- Add two homes.spec cases, each with markers set explicitly:
  - With `NO_JAIL`, a symlinked root `.cache` refuses with "is not a plain folder" and writes nothing through it.
  - With the three markers, a `.git` folder at the root's `.cache/.git` refuses. That refusal is never waived.
- Add the row "the root fence's refusals are never waived" with the `|| true` mutant, run.

### F4 [medium] The Rules-and-mutants table dropped the first revision's 60 rows and has none for several new rules
Where: Test plan, Rules and mutants ("The first revision's rows hold … the table is regenerated in the prototype round"). Compare `git show 9449b79:…/c0120.md`.
Evidence: the table now has 9 rows (H1–H7 and two planted cases). The 60 rows for `busy`, compaction, the graph, the fence's order and waiver (W1–W7), the selector, CI dispatch, promotion and the prompt are only in history. Several spec case names they cite have since changed ("a home is the root or the project's own folder…"). New rules with no row:
- G13's `--luau-dirs z-nile` naming the root's `scripts/`;
- `affected`'s "the root's `scripts/`, `zn` and root configs force every project's full run";
- `new raft` filling `{{PROJECT}}`;
- `rewrites.premove` finding the base whether the PR is squashed or not;
- the rewriter's `./<file>` prefix and its glob rule;
- the `../zn` settings entries (F5);
- the root fence's refusal (F3);
- the toplevel ceiling (F2).
Critique: item 0 needs a row for every behavioural rule, and the code reviewer and executor audit against this table. "Regenerated in the prototype round" is a promise, but this document is the contract.
Consequences: none.
Recommendation: restore the rows that still hold, with their current case names. Rewrite the ones whose rule changed and mark each `run` or `reasoned`. Add the rows listed above, and record the new runs in the Verification log.

### F5 [medium] The `../zn` permission entries in `.claude/settings.json` exist only in a Guess 12 sub-bullet: no Touched path, no §13 line, no criterion
Where: Guess 12, c0114 Guess 2 bullet ("c0120 adds a `../zn` entry beside every `./zn` one"); Touched modules (only `.claude/skills`); §13; AC13.
Evidence: `.claude/settings.json` isn't a Touched module. No spec pins the pairing. c0114's `docs.spec` "the settings allow ./zn wherever they allowed scripts/tracker.sh" is the only settings spec, and it reads the file relative to the cwd, so from `z-nile/` it must be overridden (see F1).
Critique: an executor that reads §1 to §13 won't make this change, and JC1 would then fail it as an unlisted file if it did.
Consequences: adding `../zn` raises a choice:
- Pair every `./zn` entry with a `../zn` entry. Settings entries are prefix matches, so `../zn find:*` would also allow it from any folder one level down.
- Or allow only the forwarder `scripts/tracker.sh`, which already matches from a home and needs no new entry.
Recommendation: decide one of the two and write it in §3 or §13. If entries are added, list `.claude/settings.json` in Touched, add a docs.spec case pinning the pairing, and add a row.

### F6 [medium] c0115's approved prep (PR #103) assumes z-nile's home is the root, and §14/§15 say z-nile preps "merge cleanly"
Where: §12 (z-nile's c0115 to c0118 "run from `z-nile/` … resolve there"), §14 ("Prep branches for z-nile items … merge cleanly. Their preps grep the moved paths"), §15 c0115 bullet; `origin/prep-c0115:z-nile/.tracker/issues/c0115/check.sh`.
Evidence: c0115 depends on c0120, and its prep was approved today (design-review-009) against the first c0120. Its check.sh says "cds to the item's project home: the root". I ran c0120's own literal-path reader (`rewrites.literals`) over that file, resolved from the prototype's `z-nile/`:
- `./zn` misses (lines 35, 42 and 44, i.e. AC6, AC11 and AC12);
- `cd pickman` and `pickman/tests/…` miss (AC10);
- AC2 clones `"$PWD"`, which is `z-nile/`, a folder and not a repository.

If PR #103 lands before c0120 is readied:
- c0120's AC11 goes red on an unfinished sequestered file that c0120 may not edit;
- the executor stops and escalates;
- c0115's own checks then fail on c0120's tree.

The PR title says "needs rebase after c0114/c0120 rework". c0120's design doesn't say so.
Critique: this is an existing item that fails the new rule on the day it lands (lesson ticket-prep/new-rules-migrate-existing-work). The cwd change, not the moved paths, breaks it, so "their preps grep the moved paths" doesn't catch it.
Consequences: a ready-time condition reads origin/main as the ready check does. The check-paths reader can run read-only against it.
Recommendation:
- In §14, state that z-nile preps designed for a root home are re-prepped for `z-nile/` before they land or before c0120 is readied.
- Add to Phase 1: every unfinished item's check.sh on the ready tree resolves from its home (AC11's live loop, read-only), or stop.
- Name c0115 and PR #103 in §15.
Lesson: ticket-prep/new-rules-migrate-existing-work

### F7 [low] Size: still reviewable as one PR, but the reason given for one PR is not the user's decision
Where: Size ("The captured Solution asks for the move 'in one change', so this stays one PR"); ticket-prep Size rule ("Split larger groups into sequential rafts").
Evidence: about 5,740 non-rename changed lines. Most of that is mechanical and checks itself:
- 110 overrides, each marked `-- c0120 override:` and committed by group;
- 34 rewritten finished files, generated by one tool and verified by AC18;
- 778 renames, R100 in one commit (JC1).

The hand-written core is about 2,000 to 2,500 lines: `ac.sh`, `fence.sh`/`fence.luau`, the runner, the gate, graph/affected, the engine, CI and the documents. That alone is above the guide. "In one change" in the capture refers to the `git mv`, not to every edit.
Critique: I judge it reviewable as one PR if code review goes commit group by commit group. That choice, against the skill's split rule, belongs to the user.
Consequences: none for scope.
Recommendation: escalate to the user, and record a `Decided with the user` line. Both options keep all scope:
- (a) One PR as designed, reviewed commit group by commit group. It costs one long code review (the first revision needed three rounds) and the longest freeze.
- (b) Two sequential rafts:
  - **First raft:** the parts that don't depend on the layout, landed first and inert while every home is `.`: `busy`, `graph.aliases`, the gate's `--project` and `--plan`, `roots --projects`, the fence's split functions and the `rewrites` module.
  - **Second raft:** the move, the switch of homes, the overrides, the rewrite and the documents.
  - It costs a re-prep and a temporary rule that keeps homes at `.` until the move. It gives a shorter freeze and smaller reviews.

### F8 [low] Stale and inconsistent text
Where and Evidence:
- U1, U3 and U8 still say "To rerun" or "to recount", although the Verification log reports the results. U10 says "z-nile's N1 in M1" (an unfilled placeholder).
- The counts disagree:
  - finished files: Guess 3 says "84 in 29", §12 "33 of 123", Size "34";
  - fixture specs: Guess 11 says "25", Regression guard "37 + 3".
- The Test plan says `homeOf` is "nil at the root", and for "a project folder". §2 and registry-home say `"."`, including for `pickman/src/x.luau`.
- §3 and §4 name `tests/lib/fence.luau`, which is now `z-nile/tests/lib/fence.luau`.
- The Verification log repeats one sentence twice ("The first revision's results … superseded by this revision.").
- §3's forwarder table row gives `<home>/scripts/check.sh` as `../check.sh`, which for z-nile runs every project. Only the paragraph below corrects it.
Recommendation: fill or remove the placeholders, use one count each, align the Test plan with §2, update the paths, drop the duplicate sentence, and add a z-nile row to the forwarder table.

Lessons (item 10): F1, F2 and F6 repeat existing lessons (named on their lines). No lesson was added since round 4 (`harvest.md`'s last entry is design-review-004 F1, an existing lesson).

Candidate lesson for the lead (testing): "when a run moves into a subfolder, the folder it used to fence keeps its fence: list every folder a guard covered before the move, and check each is still covered after it, not just the new one". Check: which folders were under the ceiling, sentinel or jail before this change, and which spec proves each still is? (This could also be a note on testing/guards-move-with-the-working-directory.)

Verdict: changes
