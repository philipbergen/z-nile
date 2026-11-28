# Review 005: c0178 (design mode)
Inputs: commit 0d0575356 (branch `c0178-design`): `z-nile/.tracker/issues/c0178/c0178.md`, `check.sh`, `guesses.md`, `acceptance/template.spec.luau`, `acceptance/volume.spec.luau`, `affected-specs.txt`; base 5e8f5eaa4 (`z-nile/tests/lib/{trackerfix,netfix,fixture,fence,engine,clone,seal,cachepaths}.luau`, `z-nile/tests/run.luau`, `z-nile/specs.luau`, `z-nile/check.sh`, `z-nile/lib/{fence.sh,ac.sh,replace-file.pl}`, `z-nile/engine/{main,reap}.luau`, `z-nile/tests/slow.tsv`); c0179's ticket and `z-nile/go/internal/fxtree` with its users (#791); R0061, R0070 and c0194's documents; `./zn capture c0178`; the old design at 5e8f5eaa4; the designer's raw outputs in `.worktree/c0178-design/.cache/exp/` (read only); the lessons searches the brief names. Two probes of my own in a detached worktree at 0d0575356, under `./zn run`, scratch under its `.cache`, no volume mounted, no gate and no spec run: P1 (a whole-tree `clonefileat` and the identity step on a small packed four-repository template) and P2 (`cp -R` into a folder inside its source). Not run: any volume step, any spec, the gate. The worktree and its scratch are removed; `mount` (13 lines) and `hdiutil info` (one image) read as the designer recorded them.

Numbering: the folder holds design reviews 001 to 004 of the removed design; this is the first review of the 2026-11-24 redesign.

### F1 [high] The spec's last case writes into the run's shared template, so every later fixture of that gate refuses
Where: `acceptance/template.spec.luau:183-200`; Design, Slice 1, "Never handed to a spec, and checked before each clone".
Evidence: the case takes `trackerfix.template(false)`, the run's own lessons template, writes `<tpl>/main/zn.c0178` and leaves it ("this case runs last: the run's template stays refused"). The Design makes that state refuse "every later fixture of this run". A run is one worker process per spec file, eight at a time (`z-nile/tests/run.luau:383-418`), and all of them clone that one template. Once the spec is promoted, every `trackerfix.new` without `noLessons` that starts after this case, in any spec file of the same gate, raises `template changed`. "Last" holds inside this file only.
Critique: the gate goes red by scheduling order. Nothing in this ticket shows it: AC1 runs the file alone, and AC3's suite does not hold the spec before `./zn done` promotes it. It first shows at `done`'s affected gate, the merge gate or the net. The tempting fix is to delete the poisoned file at the end of the case; a deleted file still changes the folder's times, so the check still fires.
Consequences: the case needs a template of its own, and the spec needs a way to make one without touching the run's.
Recommendation: the case builds a private template through the tooling seam (a private tooling copy gives a private key), writes into that one and expects the next clone from it to refuse. Add a closing assertion in the file that the run's own templates still pass the changed-check. State in the Design that no spec may write into a template it did not build, and that the seam exists for that.
Erred: zz-test
Upstream: z-design

### F2 [high] The tooling case copies the whole home, its `.cache` included, in every gate
Where: `acceptance/template.spec.luau:114-123`.
Evidence: `cp -R <TOOLING>/z-nile <home>/.cache/c0178-template-tooling/z-nile`. `trackerfix.TOOLING` must hold `zn`, `scripts` and `z-nile` (the three copies name them), so it is the checkout's top, and its `z-nile` is the home the spec runs in: the source holds the destination. P2 on this Mac: `cp -R` into a folder inside its source exits 0 and copies the tree once, the `.cache` level included. So the case copies `z-nile/.tracker`, `go`, `tests` and every fixture the run has made so far (E1: 714,809 entries and 3.0 GB in a gated worktree today), with other workers writing them at that moment (sockets, files that vanish), and no result is checked. The next run removes that copy entry by entry. GNU `cp` refuses a copy into itself, so on Linux the case fails.
Critique: one case can cost more file events than the ticket saves in a gate, it makes AC3's limit depend on when the case runs, and on a volume it doubles what the volume holds. It cannot be fixed during execution (sequestered).
Consequences: none beyond the fix.
Recommendation: build the private tooling with `engine.copy(fixture.physical(trackerfix.TOOLING), tooling)`, which leaves out `.cache`, `.tracker` and `tests`, and check its result.
Erred: zz-test
Upstream: z-design

### F3 [high] Half the fixture specs, and the lock and fence proofs, are slow tier: no check line runs them
Where: Design, "The spec-facing interface" ("The safety net is that every such spec still runs in the merge's gate and this ticket's AC3"); the guard table (lock: "`c0058` lock cases in AC3"; fence: "`c0058/fence.spec` ... in AC3"); Regression guard ("All run in AC3's whole suite"); `check.sh` AC3.
Evidence: AC3 runs "one full fast-tier z-nile suite". Intersecting `z-nile/tests/slow.tsv` (104 files, 8,402 spec-seconds) with the files that call `trackerfix.new` or `netfix.world`: 44 promoted spec files are slow tier, among them `c0053/commands-*` (five), `c0114/finished`, `guards`, `publish-roots`, `window`, `c0116/claims`, `recombine`, `c0120/homes`, `c0369/approve-*`, `tooling/stack-land`, `trace-land`, `approve`. Both `c0058` specs (`lock`, `fence`) are slow tier, as are `c0076/sweeper`, `c0127/reuse`, `c0049/parallel-runner` and all ten slice 3 specs. No gate before the landing runs `--slow`; the net runs it after the landing and files a defect.
Critique: the experiments ran 3 of the 87 fixture spec files with clones. The design's answer for the other 84 is AC3, which reaches about half of them. A slow-tier spec that depends on a built fixture goes red on main after the merge.
Consequences: a slow run base against head costs about 18 minutes a side on eight lanes and one more gate's worth of kernel-zone growth each; it is run once.
Recommendation: a `check` line that runs the slow tier at the base and at the head and compares passed cases per case, as AC3 does (opt-in with `C0178_FULL=1`, never promoted); the guard table names, per guard, a spec that a check line of this ticket actually runs; the Regression guard says which tier each named spec is in.
Lesson: z-design/guards-name-slow-tier-specs
Erred: z-design
Upstream: none

### F4 [high] AC3 cannot pass: it starts a meter at a path that does not exist, and it was never run
Where: `check.sh:17` (`METER="scripts/fsevents-meter.sh"`), `check.sh:78-79` (`"$ZN_ROOT/$METER"`).
Evidence: `$ZN_ROOT` is the repository root; `scripts/fsevents-meter.sh` is not there (`ls`: no such file), the meter is `z-nile/scripts/fsevents-meter.sh`. `steady` and AC6 use `$METER` from the home, which resolves; `suite` prefixes the root. The perl wrapper's `exec` fails with 127, no `events` or `status` line is printed, and the head round is reported failed. Without `C0178_FULL=1` the function returns "not measured" before that line, so the wiring check never reached it.
Critique: the one criterion that covers the whole suite is red for every implementation, in a file the executor may not edit.
Consequences: fixing the path exposes F5 and F11 in the same function.
Recommendation: `"$ZN_ROOT/z-nile/$METER"`, and before the review settles run AC3's function once on unchanged main with a small file list in place of the suite (the event limit fails, everything else must work), recording that run in Unknowns & experiments.
Lesson: z-design/prove-specs-pass-on-a-prototype
Erred: zz-test
Upstream: z-design

### F5 [high] AC3 runs a copy of the tree from a fixed folder under the home's `.cache`, unjailed, after the head's jailed suite could write it
Where: `check.sh:19` (`W="$PWD/.cache/c0178-check"`), `check.sh:93-101`, `:119`; Lessons pass ("AC3's base clone is under the check's own work folder and removed at its end").
Evidence: the base checkout is `<home>/.cache/c0178-check/base`. Round 1 runs the base, then the head suite in `<home>` (its jailed specs may write anywhere under `<home>/.cache`, the base clone's `zn`, `z-nile/lib/fence.sh` and `tests/run.luau` included), then round 2 starts the base clone's runner again: its top process, `fence.sh` and the gate-queue script run outside the jail. Every early `return 1` skips `rm -rf "$W"`, and there is no trap.
Critique: this is the defect of the lesson the design cites as followed. The lesson's rule is a fresh `mktemp -d` outside the repository with a trap, and a check that the copy is its own checkout before git names it.
Consequences: outside `.cache` the base clone is no longer covered by the home's fence ceiling, so the function must name the clone with `git -C` only after checking it is its own top.
Recommendation: `hold=$(mktemp -d "${TMPDIR:-/tmp}/c0178-base.XXXXXX")`, `trap 'rm -rf "$hold"' EXIT`, clone there, verify `git -C "$hold/base" rev-parse --show-toplevel` equals it, then run. The same trap detaches AC7's decoy (F22).
Lesson: zz-test/check-scripts-copy-trees-outside-the-repo
Erred: zz-test
Upstream: z-design

### F6 [high] Slices 3 and 4, the user's 2026-11-01 scope, have no criterion, no spec and no check line, and their overrides are not named
Where: Problem (the two `Scope decision (user, 2026-11-01)` lines); Design, "Slices 3 and 4"; Acceptance criteria (AC1 to AC7); Regression guard, `Overrides:`; Touched modules.
Evidence: AC1 to AC3 are slice 1 and AC4 to AC7 slice 2. Nothing fails when the ten hand-built fixtures are not converted or the repository-cloning specs still check out whole trees: `template.spec` never passes `copy` or `executable`, and `clone.template()` has no case. The `Overrides:` line says "none in slices 1 and 2" and defers slice 4's specs "when the user answers G6"; the thirteen are in neither the Overrides line nor Touched modules, and the ten are in Touched modules only. All ten are slow tier (F3), so "each edited spec run twice" is the only proof and it is a step, not a check. The Problem says the decisions are kept, "see 'How the decisions are kept'": no section of that name exists.
Critique: a captured outcome with a Design and no criterion can be dropped at execution with every check green. Slice 4 is one paragraph: it does not say what `origin` of a cloned whole checkout names (today's `clone.isolated` leaves the real repository as `origin`), which files name the template's path, or what the guard table says for a template that is cloned from the real repository ("nothing clones the real repository in slices 1 and 2" is the table's only sentence).
Consequences: converted specs are promoted acceptance specs, so each needs its own before-and-after proof that every case and assertion is kept.
Recommendation: one Checked criterion per decision. For slice 3: the ten specs run by name at base and head with equal passed-case sets, and an events bound for one of them. For slice 4: the same for the thirteen, a case that a cloned checkout's remotes and reflogs name no template, and a row in the guard table. Name all twenty-three on the `Overrides:` line now, and write the missing section or drop the pointer. If slices 3 and 4 are to wait for G6, escalate to the user: the options are to design them here now, or to move them to a new ticket by a Scope decision.
Lesson: z-design/never-narrow-captured-scope
Erred: z-design
Upstream: none

### F7 [high] The capture's "and processes" has no criterion, and the count the Design gives leaves out what today's 79 includes
Where: Problem ("to cut file churn and processes"; "a fixture costs a few files and processes"); Design, "After the clone" ("13 git processes and 2 `perl` (today 79 processes, the 2026-11-01 measure)").
Evidence: every command after the clone goes through `fixture.exec` (one `fixture.check`: two `pwd -P` and a `git rev-parse`, so 4 processes a call) or `fixture.git` (the check runs twice, `fixture.luau:88-89, 102-104`: 7 a call, as the removed design's own Problem said). Thirteen commands are 52 to 91 processes, plus the clone, the rewrite, the tooling key and the `find`. Today's 79 was a count of every process. The removed design cut this with one check per call, a decision the Problem still lists ("keep your choice" for the memo) with nothing in the new design behind it.
Critique: the process half of the captured outcome is about where it is today, the Design reads as if it fell by five times, and no criterion measures it.
Consequences: none.
Recommendation: count processes for one `trackerfix.new` on the prototype the same way the 2026-11-01 measure did and put the number in the Design. Then either give the outcome a criterion and a mechanism (one check per `fixture.git` call is about 40 lines in `fixture.luau`), or escalate to the user: keep "processes" in this ticket, or move it by a Scope decision.
Lesson: z-design/never-narrow-captured-scope
Erred: z-design
Upstream: none

### F8 [medium] Nothing checks a clone's remotes before its force-push; the rewrite guard runs only as a spec case
Where: Design, "The rewrite list", "After the clone", "The guard".
Evidence: `git push -q -f origin HEAD:main` in `<base>/main` goes wherever `main/.git/config` says. If one of the nine rewrites did not happen (a git that writes the path into a tenth file, a file missing from the list, a failed rename), `origin` still names the template's bare repository and the push lands in the template every later fixture copies; `other`'s fetch reads it back. The design's defence is `template.spec` (run when selected) and the changed-check before the next clone, which fires only if another clone follows and after the damage. E5 hit this class once and it was loud only because the folder was missing. #791's Go helpers run the same guard at every template build (`cmd/zn/init_test.go:147-158`).
Critique: the fix an author reaches for is another spec case; it has the same gap.
Consequences: a check at build needs one `grep -rlF` of the template (about 2,200 files, once per run); a check per clone must cost no process.
Recommendation: at template build, fail unless the files naming the build or final path are exactly `trackerfix.REWRITE`; after each clone's rewrite, read the nine files in-process and refuse if any still holds the template path, and compare `remote.origin.url` of `main` and `other` with `<base>/origin.git` before the first push. Rows and cases: a list short by one file; a rewrite that fails on one file.
Erred: z-design
Upstream: none

### F9 [medium] The shared template has four timing holes
Where: Design, Slice 1, "Who builds it, when", "Never handed to a spec, and checked before each clone", "`<run>`".
Evidence: (a) the stamp is written after the rename, so a third worker can find the template with no stamp; what `find -newer <missing>` then means is not stated. Two builders make it worse if stamp and rename are won by different ones: the published build has files newer than the stamp. (b) The check runs before the clone: a write between check and clone gives a poisoned fixture, and nothing fails if no clone follows in that run. (c) "The first `trackerfix.new` of a worker removes every template folder of another run": two workers removing one folder race, and `fs.removeDir` raises when entries vanish under it, failing an unrelated spec. The rule also needs the name grammar: `trackerfix.new("fixture-templates")` removes the folder, and a link swapped in at that name makes "every folder of another run" mean every fixture. (d) P1: `git status` in a template checkout rewrites its index and trips the check for the whole run; a clone does not (0 entries newer after two clones), which is the one result the check needed and the simulation never ran (the patch has no stamp, key or sweep).
Critique: each is rare and each fails a gate by timing.
Consequences: a stamp inside the tree is cloned into every fixture; decide whether the fixture keeps or removes it.
Recommendation: create the stamp last inside the build, before the rename, and check with `-mindepth 1` after the clone, not before; remove a stale template by renaming it to a unique name first, tolerating a lost rename, and only names of the template grammar under a `fixture-templates` that `lstat`s as a folder; refuse the reserved fixture names; give `fxclone.tree` a refusal for a source that is a link (P1: flags 0 follows it). Cases for each.
Erred: z-design
Upstream: none

### F10 [medium] `template.spec` has cases a correct implementation fails, and seams the Design does not define
Where: `acceptance/template.spec.luau:46, 67-72, 105, 120-124, 153`; Design, "The spec-facing interface"; Acceptance criteria ("AC1, AC4 and AC5 run everywhere").
Evidence: line 153 is `stat -f %Lp`, BSD only, in the criterion said to run on Linux, the first other host. Line 71 greps a whole fixture for the bare word `fixture-templates`: a fixture holds copies of `z-nile/skills` with their lessons and `z-nile/README.md`, the ticket adds a zz-test Speed bullet, and its own lesson candidates name the folder, so one sentence in a skill or lesson turns a promoted case red in another raft's gate. `trackerfix.build`, `trackerfix.forget` and the mutable `trackerfix.TOOLING` appear only in the spec.
Critique: the executor cannot edit the spec and cannot tell from the Design what the seams do.
Consequences: none.
Recommendation: `test -x` for the mode; grep for the template folder's absolute path, not the word; a Design sentence and signature for each seam, with what `TOOLING` changes (the copy and the key together).
Lesson: z-design/spec-design-correspondence
Erred: zz-test
Upstream: z-design

### F11 [medium] AC3's comparisons are unsound even with the path fixed
Where: `check.sh:87-121`; "Where the numbers come from".
Evidence: (a) both head rounds must be under 990,000 and nothing sets the home's `.cache` first: after slice 1 alone, round 1 removes whatever is there, and base-built leftovers are 714,809 entries, about that many events, before the head makes anything. (b) The base's first round is cold (a fresh clone, no removals) and the CPU rule compares the base's smaller round with the head's larger one, with no margin. (c) `BASE=5e8f5eaa4` is pinned in a sequestered file: a case main renames or removes before the merge counts as lost. (d) The base's status is never read, and missing base results make the lost-cases list empty. (e) 990,000 is the worst of three heavy files applied to 95% of the suite; by my estimate a fallback to plain copies everywhere still passes it (about 100 fixtures at about 4,700 events against 40). AC2 holds the mechanism, so (e) is acceptable if said.
Critique: the criterion can fail a correct slice 1 and gives no verdict on the suite's real ratio, which the simulation patch could have measured in prep.
Consequences: a warm-up round is one more suite (about 7 minutes and one more gate's kernel growth).
Recommendation: empty the fixtures of both homes before round 1 or add a warm-up and count the last round only; compare like with like for CPU, with the 4% spread c0179 measured as margin; take the base as `git merge-base HEAD origin/main` at run time; fail when the base's status is not 0 or its passed set is empty; state that the limit is an estimate and what the executor does when a correct build measures above it.
Lesson: zz-test/no-vacuous-pass
Erred: zz-test
Upstream: z-design

### F12 [medium] AC2 pins absolute limits on three spec files other rafts keep editing, under time limits the gate queue can use up
Where: `check.sh:20-23, 41-42, 59-64`; AC2; G8.
Evidence: the limits are today's simulation numbers times 1.15, with pass counts 23, 22 and 18 written in. `tooling/light-path` and `models-dispatch` belong to live features; three new cases with a fixture each use the margin. Each `lune run tests/run` queues behind every other gate on the machine (zz-test, Speed: up to 1,800 s), inside `./zn run --time 900`.
Critique: the ticket may wait weeks; the criterion then fails for a correct build, on the machine whose load is the reason for the ticket.
Consequences: a per-fixture bound needs a probe spec the check owns.
Recommendation: make the checked number the mechanism's: a check-only probe that makes N fixtures in one run and must stay under one template build plus N times a per-fixture budget, with and without `noLessons`. Keep the three files as a ratio against the base measured in the same check, and give every run a time limit that covers `ZN_GATE_WAIT`.
Lesson: z-design/measured-thresholds-name-their-load
Erred: zz-test
Upstream: z-design

### F13 [medium] The whole saving rests on a call Apple's manual discourages for folders, and that is not in the Unknowns
Where: Design, "The clone step"; Risks, "The syscall number".
Evidence: `man 2 clonefile` on this machine, LIMITATIONS: "Cloning directories with these functions is strongly discouraged. Use copyfile(3) to clone directories instead." `copyfile` clones file by file, which is the one-event-per-file cost c0179 measured for `cp -c`. The design lists the syscall number as a risk and nothing else. What a failed folder clone leaves at the destination (a full volume) is not stated; the copy path then finds the destination present and refuses, which is loud. A fallback to copy is silent in `trackerfix.new`; after this ticket only one small-tree assertion (`template.spec:156-157`) notices it, and that assertion fails on a Mac whose checkout is not on APFS.
Critique: #791 took the same call for the Go tests, so there is precedent, but neither ticket recorded the limitation or what was checked.
Consequences: none.
Recommendation: an Unknowns entry with what was tried (P1: source times untouched, links not kept, flags kept, `EEXIST` clean), a failed clone on a nearly full scratch volume tried once by the executor, a refusal that removes a partial destination, and one runner line when any fixture of a run was copied on macOS. 462 is the same number on Intel Macs and `fence.luau` already calls `syscall(202, …)` through perl, so the number itself is not the risk.
Erred: z-design
Upstream: none

### F14 [high] The stale-volume rule detaches a volume whose specs are still running, which breaks the lock a promoted spec pins
Where: Design, Slice 2, "Naming and stale volumes", "Who, when"; guard table, lock row.
Evidence: a volume is stale when its owner, the top process, is gone. `fence.luau:792-825`: the launcher and the specs survive a signal to the top process alone, and the lock holds because workers record their pids in it. Under the design those records are on the volume's copy; the disk's lock holds only the top's. So: the top dies, the next run force-detaches the volume, sees a disk lock whose only pid is dead, takes it over, and two suites share the home. `c0058/lock.spec.luau:264-285`, "a run whose top process was killed keeps the lock while its specs still run", pins the opposite; it is slow tier and nested, so no check line of this ticket runs it (F3). The copy itself has no case: a build with no lock copy passes AC3, AC6 and AC7, because none starts a second run during a volume run.
Critique: in the gate the window is short (`bounded.pl` kills the group, the gate queue holds the next gate), which is why it will not show in testing; with `ZN_GATE_QUEUE=off`, or a run started by hand beside a gate, it is open.
Consequences: a run that waits on a stale volume's lock must look again for the volume once the lock frees, before it mounts its own; a failed stale detach at start needs a stated outcome.
Recommendation: a volume is stale only when no record of the lock on it still holds (`anyHolder` over the volume's own lock), judged before any detach; otherwise the run waits as for any lock, then repeats the sweep. A stale volume that will not detach refuses the run. Check lines, outside the jail: a second run during a held volume run is refused; a run whose top was killed with a held spec still refuses the second run and its volume survives until the spec ends.
Lesson: zz-arch/lock-reads-live-state
Erred: z-design
Upstream: none

### F15 [high] The volume switch is an exported variable, so runs that specs start inside the jail make volumes too
Where: Design, Slice 2, "Who, when" (`PICKMAN_FIXTURE_VOLUME=1`, "which `z-nile/check.sh` exports"; "not a guarded (nested or worker) run"); `volume.spec.luau:95-108`.
Evidence: fourteen files start a top-level runner in a fixture copy by clearing only the marker (`PICKMAN_TEST_FENCE = ""`): `c0058/fence`, `c0058/lock`, `c0059/adapt`, `c0114/gate-cover`, `c0114/guards`, `c0120/runner-home`, `c0127/reuse`, `c0184/generic`, `c0191/runner-cpu`, `c0191/proof-limits`, `tooling/fence-cache-entry`, `fence-inherited-env`, `fence-leftovers`, `lock-start-ids` (six are fast tier). For them `guarded` is false and the variable is inherited, so `fxvolume.wanted` says yes inside the outer jail. The profile is `(allow default)` with `/dev` writable and the mount is done by a daemon outside it; E6 made its mounts outside the jail, so whether they succeed inside is unmeasured. If they do: 8 GiB RAM disks at `<fixture>/z-nile/.cache`, left behind by the cases that kill their run (`lock.spec:257, 271`), which no sweep finds (not this home's `.cache`). If they do not: `fixtures: volume not used (...)` in the output of runs whose output specs pin.
Critique: both outcomes are defects, they appear only in gate-driven runs, and the lesson names this exact mistake.
Consequences: a flag alone is not enough: a fixture copy of `z-nile/check.sh` passes the flag itself.
Recommendation: the gate passes a runner flag that the top process never forwards, and `fence.luau` (exempt from the gate scan's `PICKMAN_FENCE_` rule) refuses a volume in any process started inside a spec run, whatever the marker says, passing that as `guarded`. A `volume.spec` case for it, and one check that runs a fast-tier nested-run spec in a volume run and compares `hdiutil info` before and after.
Lesson: zz-test/runner-knobs-are-flags
Erred: z-design
Upstream: none

### F16 [high] R0070 moves the run's temp folder under the mount point; the design does not mention it
Where: Design, Slice 2, "Who, when" (stage at `<runTemp>/fx-stage`), "What is carried out" ("into the run temp"); Slice 1, "`<run>`"; Lessons pass.
Evidence: R0070 is active and c0194 is built on `R0070/1/c0194`. c0194.md:121: "the run's folder is `<home>/.cache/.tmp/pickman-run.X`; the profile adds `(deny file-write* (subpath <home>/.cache/.tmp))`". `fence.enter` makes the run temp before the lock (`fence.luau:962-968`), the design mounts over `<home>/.cache` after it. Once c0194 is on main the mount hides the specs' `TMPDIR`, the `mktemp` shim in it, the stage point and the copies carried "into the run temp" (which then vanish with the detach). R0061's document recorded this coupling for the old design; the redesign drops it.
Critique: either order of landing breaks every gate-driven run, and c0194 will land first.
Consequences: with the run temp on the volume, c0194's rule that nothing outside the jail runs from a spec-writable folder must be re-read for the files the top process stages.
Recommendation: read c0194's current design and specs and state slice 2's order for both worlds (where the run temp is made, where the stage and the carried files live), run c0194's `runner.spec` and `repo-fence` on a merged prototype, and name R0070 in the design.
Lesson: z-design/quote-other-preps-before-promising
Erred: z-design
Upstream: none

### F17 [high] Any interrupted gate leaves the worktree's `.cache` on a RAM disk, and only the next run in that home looks for it
Where: Design, Slice 2, "Detach", "Lifecycle", "Naming and stale volumes"; Touched modules (`z-nile/engine/reap.luau`).
Evidence: the detach is the top process's. Ctrl-C, a CLI's command timeout (zz-test: "a command the CLI killed while it waited is simply run again"), a `./zn run` limit and `bounded.pl`'s 3,600 s all end the top process first; the link sweep was moved into the launcher for that reason (`fence.luau:815-817`). The sweep finds mounts "exactly this home's physical `.cache`": at the root, where `./zn reap` runs, there is no home; a volume killed while staged (mounted at `<runTemp>/fx-stage`) or attached and not yet mounted is in `hdiutil info` only (E6's first script leaked two that way). Until someone finds it the worktree's `<home>/.cache` is RAM, and `git worktree remove` (`main.luau:4810`, and the hint at `:2938`) cannot remove a mount point, so it fails part-way (reasoned, not run). This checkout has about 270 worktrees.
Critique: the design calls this a crash case; it is the ordinary end of a gate a worker abandons.
Consequences: a process that detaches after the top dies is a helper that outlives its starter: it meets the reaper's orphan rule and `./zn run`'s group kill.
Recommendation: a lifeline, started before the mount, that waits on a pipe from the top process and detaches when it closes and the lock on the volume has no holder (F14); `./zn reap` finds every device whose volume is named `znfx-<pid>-<key>` with a dead owner, from `hdiutil info` and `diskutil`, wherever or whether it is mounted; the worktree-removal paths call the same sweep first. Cases in `volume.spec` for a staged and an unmounted volume; `./zn reap --dry-run` beside the lifeline in prep.
Lesson: zz-arch/children-need-a-lifeline
Erred: z-design
Upstream: none

### F18 [medium] `fxvolume` is placed where the engine cannot load it
Where: Touched modules (`z-nile/tests/lib/fxvolume.luau`, `z-nile/engine/reap.luau`); guard table, `cache-paths` row.
Evidence: `main.luau:32` requires `./reap` at load. `engine.copy` leaves `z-nile/tests` out of every fixture (`engine.STATE`). If `reap.luau` requires the harness module, no `./zn` command loads in any fixture; if it does not, the decision exists twice. The `.cache` lines the reaper gains are in `z-nile/engine`, which `cachepaths` covers: `z-nile/tests/lib/cachepaths.luau` needs entries and is not in Touched modules. What `reap --auto` does about volumes inside a check run, what `--dry-run` prints and the usage text are not stated.
Critique: the executor meets this on the first fixture spec and must deviate from a sequestered spec's require.
Consequences: `volume.spec` requires `@tests/lib/fxvolume`; moving the module changes that line now, before it is sequestered.
Recommendation: the pure module in `z-nile/lib/` (shared by runner and engine, copied into fixtures), the spec requiring `@znile/lib/fxvolume`, `cachepaths.luau` and the reaper's usage in Touched modules, and a sentence that `reap --auto` in a check run reads no mounts.
Erred: zz-arch
Upstream: z-design

### F19 [medium] The top process's volume steps have no time limit, and it copies files specs wrote without looking at them
Where: Design, Slice 2, "Who, when", "What is carried out", "Detach", "Fallback".
Evidence: E6 and E7 saw a 10.3 s detach, an 11.2 s staging unmount and one `Resource busy` in about 26 cycles. The fallback covers a step "failing"; a `diskutil` that hangs holds the home's lock and the machine's gate queue. How the volume's device is found after `newfs_apfs` is not stated (E6 parsed `diskutil list` text). The carry-out copies `spec-durations.tsv` and the results file from a folder specs write: a link below the top level, a FIFO or an 8 GiB file is copied by an unjailed process. Whether the second snapshot and the lock's removal come before or after the detach is not stated. The stale sweep is placed "before `takeLock`"; `fence.enter` checks and writes `.cache` earlier than that (`fence.luau:909-933`: the plain-folder check, the link sweep, every home's sentinel), so unless the sweep comes first those steps judge the stale volume and not the disk's folder.
Critique: each is a few lines once named; unnamed they are the code review's to find.
Consequences: a timed-out attach must still detach its device.
Recommendation: every `hdiutil`, `diskutil` and `newfs_apfs` call under a limit, with the fallback on a timeout before the mount and a refusal after it; the device read from a plist form; the carry-out copies only a regular file under a size limit, opened without following links; the order of detach, snapshot and lock removal written out.
Lesson: zz-arch/read-cache-as-untrusted-input
Erred: z-design
Upstream: none

### F20 [medium] Slice 2's guesses rest on one spec file and a wrong statement of which runs it reaches
Where: G4, G5; Design, Slice 2, "Who, when" ("so `./zn finish`, `done` and the merge gates"); E7; Usability.
Evidence: `./zn finish` runs its specs through `z-nile/specs.luau` (`main.luau:4329-4342`; `specs.luau:2-3`: "The gate itself ... starts `tests/run` directly"), not through `z-nile/check.sh`. So finish, `./zn check` and every run by hand get no volume, and the results file the design carries out is written only by a path that never asks for one. Which runs make the machine's file events was not measured. E7 ran one spec file of 410 on a volume, mounted by a wrapper before the runner started (`exp/e3b.sh`), so the designed sequence (lock copy, stage, carry, detach by the top process) has not run once. A failure that exists only on the volume (a rename from `TMPDIR` across devices, `noowners`) is not reproduced by the advice to run the spec by name. Slice 1 alone takes light-path from 225,599 to about 51,000; the volume takes it to 23,744.
Critique: slice 2 adds 12 points to slice 1's 77% on that file, for a subset of runs, with F14 to F19 as its price, on evidence from one file.
Consequences: deciding after slice 1 means slice 2 needs its own ticket and `check.sh`.
Recommendation: escalate to the user: (a) build slice 1 as its own ticket now, record one full gate and one slow run, and decide the volume as a separate ticket with those numbers; (b) keep the volume here, after F14 to F19 and a prototype run of the full suite and the nested-run specs on a real volume; (c) no volume, and cut removals on disk instead (for example `other` made on first use, which the removed design had). What full scope costs is (b). My recommendation is (a).
Erred: z-design
Upstream: none

### F21 [medium] "Each slice merges alone" has no mechanism, and the lead's steps leave out three things
Where: Implementation steps; "What the lead must change".
Evidence: one ticket is one layer and one `check.sh`; AC4 to AC7 fail until slice 2 exists, so `./zn finish` cannot pass after slice 1. Unfolding c0178 from R0061 reverses the user's grouping of 2026-11-19 ("all four, you're missing c178") and is listed as a step, not as a question. The built layer of the removed design (`R0073/1/c0178`, pull request #460) is not mentioned. The outcomes the owner approved on 2026-11-19 and the redesign no longer delivers (no sample hooks, one `fixture.check` per call, the gate's fixtures line, `c0116/claims`' worktrees) are not listed anywhere the owner will read before approving again.
Critique: the executor cannot follow the order as written, and the owner approves a smaller design without being told what left.
Consequences: a split is the user's call and adds tickets through z-idea.
Recommendation: escalate to the user: split into one ticket per slice (each with its own criteria), or keep one ticket that lands whole. Put the unfold, pull request #460 and the list of dropped outcomes under Open to the human.
Erred: z-design
Upstream: none

### F22 [medium] Rules and mutants: three rows cannot fail, five rules have no row, and no designed code has run
Where: Rules and mutants; Unknowns ("every row but three is `reasoned`").
Evidence: "a path is replaced as a whole path" names a case "with a fixture named after the template plus a suffix"; the case uses `c0178-template`, and after the pre-rename rewrite no file holds the template path as a prefix of a longer name, so a plain substring replace passes. "a sweep by name only" is said to be killed by AC7, whose decoy differs in name and place at once (`c0178-decoy` at `$W/decoy`); a sweep by name alone leaves it. "a clone never lands in an existing folder" takes the clone path on macOS, where the listed `cp -R` mutant is not reached. No row: the lock copy, the stale rule, the nested refusal (F14, F15), the changed-check's `-cnewer` half, the per-clone remote check (F8). AC7 also leaves its decoy attached when interrupted (no trap), and waits 60 s for a mount that a queued gate delays.
Critique: with 14 of 17 rows unrun, a wrong row is found at execution, where the spec cannot change.
Consequences: none.
Recommendation: fix the three rows (a fixture named `<template basename>-x`; a decoy named `znfx-<dead pid>-<key>` mounted elsewhere; `{ copy = true }` in the existing-folder case), add the five, and run the rows the simulation patch can carry before the review settles.
Lesson: z-design/reasoned-rows-claim-testable-reasons
Erred: z-design
Upstream: none

### F23 [low] Small corrections
Where: `check.sh:136, 140, 164` and `volume.spec.luau:2`; Risks, "What a gate hides"; G1; sizes.
Evidence: the volume is called "slice 3" in the check file and the spec header and slice 2 in the document. "the gate puts nothing there first": the static stage builds `<home>/.cache/check.rbxl` before the specs (hidden during them, harmless). `fxvolume.wanted` is said to need "`hdiutil` present" and takes no argument for it. G1's cost is stated per gate; a run with one fixture pays a template build and the last run's template removal, about what it pays today. Slice 2's 350 lines leave out the lifeline, the limits, the reaper's command line and the zz-test section on the lock and the jail.
Critique: clarity.
Consequences: none.
Recommendation: correct the four sentences and re-estimate slice 2 after F14 to F19.
Erred: none
Upstream: none

## Probe: what fixture specs read of a fixture's `.git`
Grepped the 151 files that call `trackerfix.new` or `netfix.world` (90 under `z-nile/tests`, 61 in unfinished items' acceptance folders) and the engine (`z-nile/engine`, `z-nile/lib`, `scripts`, `zn`) for paths under `.git/`, `packed-refs`, `ORIG_HEAD`, `FETCH_HEAD`, `objects/`, pack and index files, `gc`, `prune`, `fsck`, `repack`, `count-objects`, `pack-refs`, `reflog`, `unpackLimit`, `hash-object`, `cat-file`, `update-ref`, `for-each-ref`, `show-ref`, `ls-remote`, `rev-list`, `--all`, `--force-with-lease`, `alternates` and `seed`.
- Hooks written into a fixture: `c0053/commands-new` (`main/.git/hooks/pre-push`); unfinished `c0189/hooks-command`.
- `update-ref`: `c0114/finished` (`refs/remotes/origin/main`), `c0120/homes`; unfinished `d0434/restack-conflict`, `c0189/hooks-command` (also `hash-object -w`).
- `cat-file -e <ref>:<path>`: `c0114/publish-roots`, `roots-cli`, `window`, `c0183/capture`, `d0298/ready-order`, `tooling/approve-walk`, `ready-members`, `recombine-members`.
- `rev-list --count`, relative to a commit read earlier in the case: `c0053/commands-prep`, `commands-start`, `c0116/claims`, `recombine`, `c0369/approve-branch`, `approve-main`, `tooling/stack-land`.
- `ls-remote`, `for-each-ref`: `tooling/approve`, `approve-walk`, `gatequeue-net`, `light-path`, `rounds-work-next`.
- `--force-with-lease` from a worktree branch: `d0333/commit-land`, `tooling/stack-land`, `trace-land`. `worktree prune`: `d0383/watch-net-kick`. `FETCH_HEAD` after its own fetch: `tests/lib/fakecli.luau`.
- The index and `HEAD` as files: unfinished `c0139/conflicts` (overwrites `main/.git/index` and restores it, reads `.git/HEAD`, removes `.git/worktrees/wt`).
- None reads `refs/heads/main` or `packed-refs` as a file, names or counts anything under `objects/`, runs `gc`, `prune`, `fsck`, `repack` or `count-objects`, reads a reflog, expects `ORIG_HEAD` or `FETCH_HEAD` to be absent, checks a link count, or reads `<base>/seed` (`c0053/commands-sync` builds its own `<base>/outer/seed`). The engine reads none of these either.
- What a cloned fixture has that a built one lacks (P1): `FETCH_HEAD` and `ORIG_HEAD` in `other`; in `main` and `other` a `packed-refs` line for `origin/main` that still names the template's seed, shadowed by a loose ref; in `origin.git` one unreachable commit, the same id in every fixture of a run; one more reflog entry in `main` and `other`; packs for loose objects; no `seed`. Nothing found depends on any of them. The limit of this probe is the pattern list and the 3 of 87 files actually run.

## Checked and not raised
- The three identity commands cannot reach the real repository: each runs through `fixture.git` in `<home>/.cache/<name>/main` or `other`, which must be the top of its own repository, the template is built by `git init` and `engine.copy`, and the jail (macOS) or the push and ref hooks (elsewhere) refuse the rest. What can go wrong is a push into the template (F8). An empty `name` already empties the home's `.cache` today.
- The lock is a folder made by `mkdir` with pid records, not an `flock`, so copying it does not split a lock by inode. The hole is where the workers' records live (F14).
- The home's `.cache` holds the lock, the durations, a results file, the sentinel, `gh-none`, the gate's `check*.rbxl`, check files' work folders and fixtures. The board, `bin/znlive`, the Go build cache, the live, dispatch, work, approval and watch-net state and `measure.tsv` are in the root's `.cache`, which is no home and is not mounted over. On a fresh volume the jailed shell writes the sentinel and `gh-none` after the mount (`fence.luau:995`).
- Size: a gate's fixtures were 3.0 GB on disk before slice 1 (E1) and clones share blocks; the repository's pack is 53 MiB, so slice 4's template is small. 8 GiB is enough; a full volume is loud if the message is built.
- The changed-check costs stats only (about 2,200 a clone), no file events. The tooling key misses an edit that keeps size and mtime, as the design says.
- Kernel zone: AC3's margin of 4,580 is about one gate's own growth, so a doubling passes; c0179 E6 and this design's E6 found no growth from attach and detach.
- Spotlight: c0179 E3 showed `mdutil -i off` works without sudo on a user-mounted volume; E7's script discarded its output.
- Linux: slice 1 does not fall back to today's behaviour, it gives a packed template and one `cp -a` (about 2,200 entries against 7,983), keeping the pack's hard links inside a fixture as today's loose objects are. The system check is in the perl itself (`$^O`). The clone path cannot be tested there; F2 and F10 are what fails there.

## Slices and verdict
- Slice 1 is the right first build and is safe to merge alone once F1 to F5, F8 to F13 and F22 are answered and it has criteria of its own (F21). The clone itself held up under every probe: source times untouched by cloning, no shared inodes, refusal on an existing destination, and no spec or engine read of what differs.
- Slice 2 is not buildable as written: F14 to F17 are each a guard that stops holding or a checkout left on RAM, and F18 to F20 show the designed sequence has not run. Redesign it as its own ticket after slice 1's full-gate and slow-tier numbers exist, or not at all (F20).
- Slices 3 and 4 are not designed to a checkable state (F6).
- Blocks slice 1: F1, F2, F3, F4, F5, F7, F8, F9, F10, F11, F12, F13, F21, F22. Blocks slice 2 only: F14, F15, F16, F17, F18, F19, F20. Blocks slices 3 and 4: F6. F23 blocks nothing.

## Lesson candidates (for the lead)
- zz-test: a case that damages shared run state on purpose builds its own copy of that state. Why: F1. Check: does any case write into something every other spec file of the run reads, and what does the next worker see?
- z-design: a safety net stated as "the suite runs it" is counted against the tiers. Why: F3 (44 of 87 files, and both guard proofs, were slow tier). Check: how many of the files this change reaches does each check line actually run?
- z-design: a new resource a run mounts or attaches names who releases it when the top process is killed, and how it is found when it is not where it was meant to be. Why: F17. Check: what does `kill -9` at each step leave, and which command finds it by identity, not by place?

Verdict: changes
