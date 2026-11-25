# Review 001: c0178 (code mode)
Inputs: `origin/c0178-build` at 34d1700d6 against `origin/main` at 8be9b1075 (merge base 5e8f5eaa4): `z-nile/tests/lib/fxclone.luau`, `z-nile/tests/lib/trackerfix.luau`, `z-nile/tests/run.luau`, `z-nile/skills/zz-test/SKILL.md`, the 116 watch files, and the ticket's folder (`c0178.md`, `check.sh`, `acceptance/template.spec.luau`, `probe/`, `design-review-005.md`, `design-refute-005.md`, `guesses.md`, `affected-specs.txt`); main's `fixture.luau`, `engine.luau`, `seal.luau`, `netfix.luau`, `fakecli.luau`, `fence.luau`, `fence.sh`, `ac.sh`, `cachepaths.luau`, `slow.tsv`. Read only, no worktree. Seven probes of my own under `./zn run`, in a scratch folder outside the repository (no git repository of the project touched, no spec, no gate): P1 the change check's `find` rule; P2 `fxclone.tree` (the branch's file, copied) on small folders; P3 and P4 what a push starts in a pack-per-push bare repository (no finding: outside a run git 2.54 repacks such an origin in a detached process, 8 to 32 ms after the push returned in 12 of 12 tries; inside a run `z-nile/lib/fence.sh:103-105` sets `gc.auto=0` and `maintenance.auto=false`, so it does not); P5 the sweep's perl on a folder of assorted names; P6 the tooling key on copies of one tree; P7 `fxclone.tree` when its destination appears between its check and the clone. Not run: the acceptance spec, any of the 94 fixture specs, `check.sh`, the gate. The builder's numbers (cases, events, mutants) are quoted from the Verification log, not measured again. The file number is the lead's to set.

### F1 [high] Three slow-tier specs that build these fixtures were never run on cloned ones: the list of "fixture spec files" misses a wrapper
Where: `z-nile/.tracker/issues/c0178/check.sh:89` (`git grep -lE 'trackerfix\.new\(|netfix\.world\('`); `c0178.md` Regression guard ("the 87 spec files ... 43 fast, 44 slow") and AC5; Verification log, "The 87 fixture spec files, base against head".
Evidence: `z-nile/tests/lib/fakecli.luau:151` is `local f = trackerfix.new(name, seed)` inside `fakecli.new`. `git grep -lE 'trackerfix\.new\(|netfix\.world\(|fakecli\.new\(' origin/main -- '*/tests/**/*.spec.luau'` lists 94 files, the check's pattern 87. The seven it misses reach `trackerfix.new` only through `fakecli.new`: `acceptance/c0117/control-cli` (slow, 827 s in `slow.tsv`), `tooling/dispatch-guards` (slow, 419 s), `acceptance/c0117/dispatch-cli` (slow, 406 s), and the fast `acceptance/d0415/dispatch`, `acceptance/d0416/nested-second-review`, `tooling/dispatch-review-fixes`, `tooling/rounds-dispatch`. The three slow ones are the three longest files of the slow tier (1,653 of its 8,403 recorded seconds). The builder's slow run was the 44 files of that pattern plus three guard proofs; `--affected` ran 176 files, which is the 270 affected minus the 94 slow ones. So no run at head included those three. The four fast ones ran once, in the full fast suite at head (0 failed). Also: main moved one commit (#792) since the comparison's base and added 89 lines of cases to four fixture specs (`tooling/stack-land` and `tooling/approve`, both slow, and `approve-walk`, `model-cmd`); none has run on cloned fixtures.
Critique: "all 87 fixture spec files pass the same cases" is true and is not the whole set. What is missing is every slow spec of `./zn dispatch`. If one depends on a built fixture, it goes red on main after the merge, where only the post-landing net runs the slow tier. The tempting answer is "the net will tell us".
Consequences: three more slow files per side are about 1,650 spec-seconds each; the counts in the Regression guard become 94 (47 fast, 47 slow); the fix to the check's pattern is a change to a sequestered file.
Recommendation: before any merge, rebase on `origin/main` and run by name at head, as one run with nothing else heavy on the machine: `tests/acceptance/c0117/control-cli.spec.luau tests/acceptance/c0117/dispatch-cli.spec.luau tests/tooling/dispatch-guards.spec.luau tests/tooling/stack-land.spec.luau tests/tooling/approve.spec.luau tests/tooling/approve-walk.spec.luau tests/tooling/model-cmd.spec.luau`; for any case that fails, run that file at the base before reading it as a difference. Record both in the Verification log. The pattern in `check.sh` and the counts in the document are design's: the author must escalate for that edit (the pattern gains `fakecli\.new\(`), and say in the Design how the list is found (every function that calls `trackerfix.new`, then its callers).
Lesson: z-design/guards-name-slow-tier-specs
Erred: z-design
Upstream: zz-review

### F2 [high] The branch replaces main's approved check file and acceptance specs with ones no design round has passed, and two build commits then edit the new spec
Where: `git diff --find-renames=100% --name-status origin/main...origin/c0178-build -- '*/.tracker/**/check.sh' '*/.tracker/**/acceptance/**'`; commits f11e477ff and 3929d32b8; `c0178.md` front matter; `approval.md`; `z-nile/.tracker/rafts/R0061/R0061.md`.
Evidence: the command lists nine `D` (the acceptance specs approved on 2026-11-19), one `A` (`template.spec.luau`) and `M check.sh`. `design-review-005.md` ends `Verdict: changes`; the folder holds no later design review, so the answers (3f33454ee) were never checked. After that commit, f11e477ff adds the case "a rewrite to a wrong path refuses before any push, by the remote check alone" and 3929d32b8 changes two type annotations in the spec (both disclosed in the Verification log). On the branch the ticket says `design: draft`; `approval.md` is unchanged and its hashes are of the removed design; R0061 still lists c0178 with `grouped: c0178@f9d865d0d9ed` and describes the removed design. The document itself says "the owner approves again" and records "slice 1 is built and merged as progress" as a guess (G10) whose alternative is "hold slice 1 until the owner answers".
Critique: by this skill's rule any such change is high. Here it is more than a rule: a merge would put an unreviewed check file and spec on main as the ticket's contract, with an approval record that no longer matches it, inside a raft whose record names another design. The added case is honest about what it kills (see F8 for what it does not prove). The tempting fix is to revert the two build edits; that brings back the survivor the case was added for.
Consequences: a design round on the answers has to read the added case and the two annotations too; R0061's record and the approval change with whatever the owner rules.
Recommendation: escalate to the user: (a) a design round on 3f33454ee plus the two spec edits, then the owner's approval, then the merge; (b) the owner rules that slice 1 merges now on G10, recorded as a `Decided with the user` line, with the design round still owed before `done`; (c) slice 1 stays on its branch until the four open questions are answered. In (a) and (b) the lead settles R0061's record and the stale `approval.md` in the same change. Cost of keeping everything as written: none in code; the merge waits for one design round and one approval.
Erred: zz-execute
Upstream: z-design

### F3 [medium] Two halves of AC4 were not measured, AC5 failed by its own rule, and after the merge neither can be measured again
Where: `check.sh:42` (`git -C "$ZN_ROOT" merge-base HEAD origin/main`), `:148-176`, `:179-192`; `c0178.md` Verification log; Solution 3 ("slice 1 is built and merged as progress and the ticket stays open").
Evidence: the log gives AC4's case comparison (368 and 368) and one metered suite at head (592,370 events, zone +6,685). It gives no base suite, so "at most 1.04 times the base's CPU-seconds" and "the base's zone rise plus 4,580" have no number to stand against. For AC5 it says `same_cases` refused ("the base run did not pass": one base case failed under load) and the comparison was done by hand. Once slice 1 is on main, `merge-base HEAD origin/main` of any branch cut from main holds slice 1: AC3's "at most half the base's file events" then compares the code with itself and fails, and AC4's and AC5's case comparisons pass whatever the code does.
Critique: the ticket's own check has not passed, which the log says plainly; what it does not say is that the merge removes the only base these three criteria can use. `./zn done` for this ticket then meets a check that cannot pass. The tempting fix is to pin the base sha in `check.sh`; that is a sequestered edit, and design review 005 F11 asked for the opposite.
Consequences: AC4 and AC5 in full are four fast suites and two slow-tier runs; they have to run alone on the machine, before the merge.
Recommendation: escalate to the user with two decisions. First, either run `C0178_FULL=1` once before the merge (one run, nothing else heavy; the zone reads 1,267,166 now, against the warning level of 5,000,000) and paste the output into the Verification log, or have the owner accept the log's hand comparison and the missing CPU and zone figures. Second, the design says how this ticket's check passes after slice 1 is on main (a base recorded by a reviewer, or the criteria marked as measured once before the merge): a design edit, not the executor's.
Erred: z-design
Upstream: zz-review

### F4 [medium] The check file writes two lists through fixed names at the top of the real home's `.cache`, unjailed
Where: `check.sh:89-90` (`... > "$1/.cache/c0178-fx.txt"`, `... > "$1/.cache/c0178-slow.txt"`), called with `$PWD` at `:158` and `:188`.
Evidence: both are shell redirections, so they write through whatever is at that name. The files stay after the check (nothing removes them), and the jail lets a spec swap a link in for an existing file at the top of `.cache` (zz-test, "Symlinks at the top of `.cache`"). A link there during a run in the same home sends the list of spec paths over the link's target, outside the jail. The runner unlinks such links when its run ends, so it needs a run in that home at the same moment; the check takes no lock for these two lines.
Critique: the document's Lessons pass cites this lesson as followed; it was followed for the base clone and not for these two files. `z-nile/tests/lib/cachepaths.luau` skips `.tracker`, so no gate sees them.
Consequences: none beyond the fix.
Recommendation: the lists go into the `mktemp -d` folder `make_base` already makes and removes (outside the repository), or through `z-nile/lib/replace-file.pl`. It is the design's file: the author must escalate for the edit; it can ride with F1's.
Lesson: zz-test/check-scripts-copy-trees-outside-the-repo
Erred: zz-test
Upstream: z-design

### F5 [medium] `--affected` does not select 24 of the 94 fixture specs when `trackerfix.luau` or `fxclone.luau` changes
Where: the 116 watch files of the diff; `affected-specs.txt`; Verification log ("`z-nile/check.sh --affected` (GATE PASSED, ... 176 z-nile spec files)").
Evidence: the diff's rule was "wherever a watch file names `trackerfix.luau`", and it is applied exactly: 116 files, one added line each, the same line, every file sorted under `LC_ALL=C`, no duplicate, and no watch file names `trackerfix.luau` without `fxclone.luau`. But 16 watch files cover specs that build these fixtures and name neither: `acceptance/c0136`, `c0138`, `c0278`, `c0369`, `d0297`, `d0298`, `d0333`, `d0383`, `d0406`, `d0415`, `f0399`, and `tooling/live-gate`, `raft-plan-deps`, `stack-fix`, `stack-land`, `trace-land`. `comm -23` of the 94 against `affected-specs.txt` gives 24 spec files, 18 of them fast, among them `f0399/land`, one of the three heaviest. The gap is older than this branch; the branch's rule copies it.
Critique: for this merge it means the `--affected` pass says nothing about those 18 (the builder's full fast suite did run them). For every later fix to the helper it means `--affected` stays green without them.
Consequences: 16 watch files gain two lines each, which is outside the 116 the Design names: a recorded deviation.
Recommendation: add `z-nile/tests/lib/fxclone.luau` and `z-nile/tests/lib/trackerfix.luau` to those 16 watch files in this change, sorted, and record it under "Different from the design"; check with `lune run z-nile/affected -- z-nile/tests/lib/fxclone.luau` that all 94 are listed. The merge's gate is `--full`, not `--affected`.
Lesson: zz-test/specs-read-sources-through-the-selector
Erred: zz-execute
Upstream: z-design

### F6 [low] Three failure paths leave or remove the wrong thing
Where: `z-nile/tests/lib/fxclone.luau:74-83`, `:57-62`; `z-nile/tests/lib/trackerfix.luau:400-417`.
Evidence: (a) `removePartial(dst)` runs before the exit code is read. P7, with the destination made between the Lua check and the clone call: `fxclone: clonefileat ... failed (exit 4):` and "the other process's folder still there: false, its file: false". Exit 4 means the destination existed; the helper removed a folder it did not make, against "refuses ... and leaves it alone". (b) P2: `fxclone.tree("<link to a folder>/", dst)` returns `clone`: with a trailing slash `test -L` and perl's `-l` both say no, so a linked source is cloned through. (c) In `trackerfix.new`, a failure of the rewrite (`replace`), of the stamp's removal or of the read of `main/.git/config` raises without removing `base`: the folder left behind is a clone whose remotes still name the template.
Critique: none is reachable from today's callers (fixture names are one spec file's, the template path has no trailing slash, a rewrite fails only on a full disk). Each is the helper's stated contract not holding.
Consequences: none.
Recommendation: remove a destination only when the clone call itself failed with something other than `EEXIST` (never on exits 2, 3, 4); strip trailing slashes before the link checks; wrap the steps from the clone to the remote comparison so any error removes `base`. One case each in a tooling spec of the build's own, not in the sequestered file.
Erred: zz-arch
Upstream: none

### F7 [low] A "private" template is private only because `cp -R` resets modification times
Where: `z-nile/tests/lib/trackerfix.luau:151-161` (the key: `chdir $root`, then relative path, mode, size, mtime); `c0178.md`, Seams (`TOOLING` "changes the copy source and the key together, so it gets private templates").
Evidence: P6: the key of a tree is `66101792...`, of its `cp -R` copy `1b8b7a4d...`, of its `cp -Rp` copy `66101792...` again, and still that after a same-size edit with the time put back. The tooling's root is not in the key. A private tooling made by any copy that keeps times (`cp -Rp`, a clone through `fxclone.tree`) resolves to the run's own template, and the spec's poisoning cases would then write into the template every other spec file of the gate clones.
Critique: nothing does this today (`engine.copy` uses `cp -R`); it is one optimisation of `engine.copy` away. Not worth a ticket: a hardening idea, and one line here.
Consequences: none (no two toolings share a template today).
Recommendation: put the physical root path into the digest.
Erred: zz-arch
Upstream: z-design

### F8 [low] Cases and check clauses that cannot fail, or prove less than they say
Where: `acceptance/template.spec.luau:148-160`, `:303-311`; `c0178.md` Rules and mutants; `check.sh:35`, `:173`; `trackerfix.luau:238-261`, `:321-325`.
Evidence: (a) "a clone that fails for another reason ... leaves no destination" uses `simulate`, which never calls the clone, so no destination can exist: the case passes with `removePartial` deleted. (b) The added case's wrong path does not exist, so a push there could never land, and the tip it compares is the template's, which nothing names after the rewrite: it kills "no comparison" (git's own message lacks "remote origin" and the folder stays) but does not show "before any push"; that needs a wrong path that is a live repository, whose tip is then compared. (c) The row "the index is refreshed" is marked `run (E5)`: that is the simulation's step from `pack` to `pack2`, which changed two things, not a mutant on the built code. (d) No case covers "a templates folder that is a link is refused" (`trackerfix.luau:323`), the ENOTSUP fallback, or the key's mtime and mode halves. (e) `kzone` prints nothing when `zprint` cannot be read; `$((hk1 - hk0))` is then 0 and AC4's zone clause passes. (f) P1: the change check does not see a removed top-level entry (`-mindepth 1`, and the root's own times are left out); the clone then fails later with a missing file or git's "does not appear to be a git repository", and the fixture folder stays.
Critique: not worth a ticket: "no spec covers X" and polish. Said here because the brief asked about each.
Consequences: none.
Recommendation: (a), (c), (d): cases in a tooling spec of the build's own where the lead wants them. (b) and (e) are the sequestered files': with F1's escalation or not at all. (f): check that `main`, `other` and `origin.git` exist after the clone, with the same message as a changed template.
Erred: zz-test
Upstream: z-design

### F9 [low] Once promoted, the ticket's own spec is probably among the heaviest fast-tier files
Where: `acceptance/template.spec.luau` (whole file); `c0178.md` E5, E9.
Evidence: arithmetic from the document's figures, not a measurement: the file builds five private or failing templates (E9: about 5,900 events and 1.9 s extra each), one fixture from scratch (8,941 events), three tooling copies and about 22 cloned fixtures (0.8 s each), most under one name, so each removes the one before (about 2,200 entries). That is roughly 30 s and 80,000 to 110,000 events in steady state, against 592,370 for the whole fast suite at head.
Critique: the ticket exists to make the gate cheaper. The log gives no time or event count for this file.
Consequences: a slow-tier spec is run by no gate before a landing, so moving it there needs a check line that runs it by name.
Recommendation: the lead meters the file once (the meter, one run, steady state) and writes the number in the Verification log; if it is what the arithmetic says, put the question of its tier to the owner before `done`.
Erred: z-design
Upstream: none

## Judged criteria (code mode only)
None (the ticket has no Judged criterion).

Verdict: changes
