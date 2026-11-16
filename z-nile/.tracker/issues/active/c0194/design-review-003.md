# Review 003: c0194 (design mode)
Inputs: prep worktree `prep-temp-trees-under-repo` at 7871c2f9 with the uncommitted `c0194.md`, `check.sh`, `acceptance/{tmp,shim,runner,callers,docs}.spec.luau` (byte-identical to the prototype's copies, `cmp`), `harvest.md`, `design-review-00{1,2}.md`, `design-refute-00{1,2}.md`; prototype `.worktree/proto-c0194` (base 02aae689, uncommitted, read only); c0075's specs on origin/main 0762c851; `./zn capture c0194` (capture 64239635, unmarked); `./zn lessons --when design --full`; `./zn lessons --skill zz-review --full`; the author's `scratchpad/c0194/{c0194-mut.py,mut-all.out,mut-r2a.out,mut-r2b.out,e13.sh}`.
Runs: `./zn promote-check c0194` (only the missing modules' type errors). Everything else ran on a copy outside the repository (main's rule for unguarded code): a `--no-hardlinks` clone of the prototype with its 27 changed and untracked files copied in and committed as `@example.invalid`, under my harness scratchpad, removed afterwards. On the copy: `tmp.spec` + `callers.spec` 34 passed; `runner.spec`, `repo-fence.spec`, `c0060/fixture.spec`, `fence-leftovers.spec` 30 passed; M68 re-run, killed (`mut-r2b.out` still records it SURVIVED: put the rerun's output in the record); my own mutants X1–X6 (F3, F4); `./zn tmp jail` of a clone of the copy (the new runner) running guard specs (F1, F6); `./zn tmp sweep` on stand-ins (F5, F7); `./zn tmp rm ""` and `verify <missing>` (F8).
Dropped from design-review-002 (fixed; change, case and mutant checked): F1 (`verify` takes its root from the tree; M60 killed), F3 (the c0075 edit is written out whole; I recounted it against origin/main's `jail-argv.spec`: 28 arguments, `argv[13]`/`[14]` the carve, `[16]`/`[17]` TEMP, counts 2 and 4, and the unnamed cases stay true), F4 (`fence.tmpFolders` with its table case; M68–M72 killed), F7. Partly fixed, with residues below: F2 (as F1, F2, F3, F6), F5 (as F8), F6 (as F8), F8 (as F7).

Scope: the Problem and Solution are the capture's plus the two `Decided with the user (2026-11-01)` lines; every captured outcome has a Design and a criterion. "c0194 first" is carried out (Overrides line, Implementation step 8). "Jail the clone" is carried out in the docs, but the open question it raised is put to the user on a wrong premise (F1), and the guess in force is pinned as a permanent rule (F2).

### F1 [high] The open question is put to the user on a wrong premise: far more guard cases fail in the jailed clone than the Design names, option (b) carries option (a)'s risk, and the prep has already taken (a)
Where: Design, "Open question for the user"; zz-test "Running specs against unguarded code" (prototype); E12b; Rules and mutants preamble ("the mutant was applied to the prototype"); `scratchpad/c0194/c0194-mut.py` (`P='…/.worktree/proto-c0194'`, runs `tests/run` with `cwd=Z`).
Evidence:
- **Which cases fail.** The Design and zz-test name "`needJail` cases, the gate spec's live probes, `runner.spec`'s jail cases". I made a tree with the copy's `./zn tmp new unguarded`, cloned the copy (with the **new** runner, `grep -c tmpFolders` = 2) into `$tree/repo`, and ran `./zn tmp jail "$tree" -- sh -c 'cd repo/z-nile && lune run tests/run -- …'`. The top-level run was accepted (`note: not jailed …; this is a fixture of a guarded checkout`). Then:
  - `runner.spec`: 9 passed, 2 failed. One is the `needJail` case. The other, "a run clears the run folders nothing owns and keeps a live run's", is not a `needJail` case: its nested runner refused with `runner.spec:272: cannot jail this run (already inside a sandbox …) … (…/repo/z-nile/.cache/c0194-stray/z-nile, …, …/repo/.git, …/repo)`.
  - `fence-leftovers.spec`: "a background process a spec leaves is stopped when the run ends" failed with the same refusal.
  - `lock-start-ids.spec`: two cases failed.
  - `c0060/fixture.spec`: passed.
  - Outside the tmp jail, the same copy passed all of them (30 passed).
  So every spec that runs a nested runner or reads start ids fails in the jailed clone. Those are the guard specs that prototyping the guards exists to run.
- **E12b proved less than it says.** It ran `git clone --no-hardlinks . "$tree/repo"` in the prototype, whose changes are uncommitted. That clones HEAD (main's base), so E12b ran **main's** runner, not the prototype's (see F6). It also ran `game-roots.spec`, which starts no nested runner. This is round 2's candidate lesson again: the wrapper was proved with a command that is not the one it exists for.
- **Option (b) is described wrongly.** It says "on the raft branch whose guards are reviewed, before code review (cost: a guard mutant is found later)". Before code review, the raft branch's guard code is no more reviewed than this prototype is now: it is new guard code running live in a worktree of the real repository. That is option (a)'s risk, moved to execution. The stated cost leaves this out.
- **(a) has already been taken, silently.** `c0194-mut.py` applies M19–M22, M44–M48 and M68–M72 (jail deny dropped, outer-sandbox rule widened, clearing disabled …) to `.worktree/proto-c0194` and runs the spec runner there. That is unguarded, mutated guard code run live in a worktree of the real repository. Main's rule today (zz-test on 0762c851) says unguarded code runs "only in a clone under `$TMPDIR`, outside every repository". Nothing records this, and the user is being asked whether to accept exactly this risk.
Critique: The tempting fix is to add "nested-runner cases" to the list in the Open question. That keeps a premise the user hasn't heard: under "Jail the clone", most of the guard suite cannot run where guard code is supposed to be tried. And (b) stays mislabelled as the safe option.
Consequences: The user's answer decides where guard mutants run, in this prep and in every guard raft after it. Any answer needs the list of failing cases to be measured, not guessed. A fourth option exists and has to be costed: make nested runners work inside the jailed clone. For example, the clone's runner, in "fixture of a guarded checkout" mode, could hand its own home's `.cache` and its own git directory to its specs, as the jailed runner does. That brings its own guard change, with a case.
Recommendation:
- Escalate to the user, with corrected options and what each costs:
  - (a) Prototype worktree under its own spec jail: the risk "Jail the clone" avoided. This prep has already run it about 60 times.
  - (b) Raft branch before code review: the same risk as (a), later, and every guard mutant is unrun in prep.
  - (c) A clone outside the repository for these runs: today's main rule, which narrows the captured "nothing builds a tree outside the repository".
  - (d) Make nested runners and start ids work in the jailed clone: a design change with its own cases, and no risk added.
- Re-run E12b with the prototype's own code in the clone (F6) and with the guard specs in AC6's list. Record which cases fail, by file and case, and put that list in the question and in zz-test.
- Record in Unknowns & experiments where the mutation runs actually ran.
Lesson: z-design/instructions-runnable-where-they-run, z-design/probe-free-cli-lines-in-prep, z-design/accepted-risks-checked-and-decided

### F2 [high] The guess in force is pinned as a permanent rule: a sequestered spec and AC5 assert option (b), zz-test states it as settled, and nothing keeps the prep from merging before the user answers
Where: `acceptance/docs.spec.luau:111` (`t.expect(has(text, "is not run there but on the raft branch")).toBe(true)`); AC5 ("the cases that need the live spec jail left to the raft branch"); check.sh AC5's label; zz-test paragraph (prototype); the Design: "if the user chooses otherwise, zz-test's paragraph and this Design change and nothing else".
Evidence: `grep -n 'raft branch' acceptance/docs.spec.luau` → line 111. The spec is sequestered, and `./zn done` promotes it into z-nile's gate. So the guess becomes a rule that every later gate enforces, and a different answer must change a sequestered spec and an acceptance criterion. The Design's "nothing else" is wrong. The zz-test sentence ("is not run there but on the raft branch, whose guards are reviewed") does not say it is a guess. The Design gives no rule on whether the prep PR may merge while the question is open. The user's standing rule is to put a guess on a branch and never merge it.
Critique: Rewording the Design's "nothing else" sentence leaves the pin in place. Dropping line 111 leaves zz-test free to say anything about where those cases run.
Consequences: Whatever the answer, zz-test needs some sentence about where the cases go, and it should be pinned. The pin can only be written once the answer is known, which ties the prep's merge to the user's answer.
Recommendation:
- Mark the guess as a guess where agents read it (zz-test: "(guess, pending the user's answer: …)") and in AC5.
- Take the clause out of `docs.spec`'s sequestered assertions until the user answers. Keep the pins that hold under every option: the jail command and running from the tree.
- State in the Design that the prep PR does not merge while the question is open. Pinning the answered sentence then is the step that follows the answer.
- List every file a different answer touches: zz-test, the Design, AC5, `docs.spec`, and check.sh's AC5 label.
Lesson: z-design/accepted-risks-checked-and-decided

### F3 [high] The command `./zn tmp jail` itself has no case: round 2 F2's defect (the command runs in the checkout) comes back and every spec stays green (the mechanism, again)
Where: `tmpcli.luau` `jail` branch: `process.exec(first, plan.argv, { cwd = plan.cwd, stdio = "forward" })`, `fs.writeDir(`{plan.cwd}/.jail-tmp`)`, the exit-code pass-through and the `git rev-parse --git-common-dir` that feeds `PICKMAN_FENCE_REAL_GIT`; Rules row M65 (mutates `jailPlan`'s returned `cwd`, not the command line's use of it); AC5 ("unguarded-code runs go through `./zn tmp jail` (from the tree, …)"); check.sh AC1's label "jails unguarded-code runs".
Evidence: On the copy, `tmp.spec` + `callers.spec`, each mutant alone:
- X1, `{ cwd = plan.cwd, stdio = "forward" }` → `{ stdio = "forward" }`, which is exactly round 2 F2's defect: **SURVIVED**, 34 passed.
- X2, the `.jail-tmp` `writeDir` dropped (the jailed command's `TMPDIR` doesn't exist): SURVIVED.
- X6, the exit code dropped (`process.exit(0)`): SURVIVED.
`grep -n '"jail"\|tmp jail' acceptance/*.luau` finds only docs.spec's text pin. No case runs the `jail` command, because a sandbox can't nest inside the spec jail. The suite pins the pure plan, but the defect round 2 found was in the edge that uses the plan.
Critique: Adding another `jailPlan` assertion doesn't reach the edge. Keeping the row `reasoned` repeats round 2's gap in a new place. This is the second round to find a hole in the jail's path, so the remedy is to change how that path is tested, not to add one more pin.
Consequences: The edge can be run without a real sandbox. Its first argument is `sandbox-exec`, resolved through `PATH`. A stand-in `sandbox-exec` first on `PATH` (it checks `-p <profile>` and execs the rest) lets a spec run the real command line inside the spec jail. Per the lesson, the stand-in answers only the arguments the design names, and refuses any other.
Recommendation:
- Add a `tmp.spec` case. It runs `./zn tmp jail "$tree" -- sh -c 'pwd; test -d "$TMPDIR" && echo "$TMPDIR"; echo "$GIT_CEILING_DIRECTORIES|$PICKMAN_FENCE_REAL_GIT"; exit 3'` from a stand-in checkout (`ZN_TOP` there, another folder as the current one), with a stand-in `sandbox-exec` on `PATH`.
- The case asserts: `pwd` is the tree; `TMPDIR` is `<tree>/.jail-tmp` and exists; the two lists end in the tree's `.cache` and the stand-in's git directory; exit code 3; and a refusal (`tmp: …`, exit 1) for a link or for the folder itself.
- Rows: X1, X2 and X6 as mutants, killed by that case. The row "the jail really contains the command" stays `reasoned` (E12).
- Fix check.sh AC1's label to say what tmp.spec checks.
Lesson: zz-test/guard-needs-its-own-case, z-design/spec-design-correspondence, zz-test/stand-ins-answer-only-named-arguments

### F4 [medium] What sweeps the main checkout's folder (where the 14 GB of clones go) and what keeps its isolation file fresh has no case
Where: `tmpcli.luau` `sweep` (adds `TMPDIR`'s folder); `scripts/hooks/session-tmp.sh` (the `sweep --dir "$top"` line); `tmp.place` (an exact `…/.cache/.tmp` `TMPDIR` goes through `tmp.root`, which refreshes the marker, sentinel and `.luaurc`); Cleanup ("It runs at the start of `z-nile/check.sh` (the checkout's folder and `TMPDIR`'s), at SessionStart …").
Evidence: On the copy, each alone, `tmp.spec` + `callers.spec`:
- X3: the `viaTmpdir` insertion made `if false`, so a worktree's gate no longer sweeps the session's folder. SURVIVED.
- X4: the hook's sweep line replaced by `true`. SURVIVED.
- X5: `tmp.place` returns an exact `.cache/.tmp` `TMPDIR` as it is, without `tmp.root`. SURVIVED.

The main checkout's folder is where agents' clones and merge clones live. A session started there gets it as `--dir`, and a worktree gate gets it only through `TMPDIR`. With X3 and X4 together, nothing ever sweeps it, and the suite stays green. With X5, `new gate` stops refreshing the isolation file after the main checkout's `.luaurc` changes, so `verify` refuses the merge.
Recommendation:
- `tmp.spec`: `sweep` with a `TMPDIR` of stand-in A and `--dir` stand-in B removes A's stale tree.
- `callers.spec`: the hook removes a stale tree in its project's folder (it already runs the hook in a stand-in project), and leaves a young one.
- `tmp.spec`: `new` through an exact-folder `TMPDIR` rewrites a stale `.luaurc` (the parent's `.luaurc` changed after the first `root`).
- Rows with X3, X4 and X5 as mutants.
Lesson: z-design/spec-design-correspondence

### F5 [medium] `.pickman-owner` has two writers with different start ids and one reader that knows only one: `./zn tmp sweep` takes a live run's folder for a dead one and removes it
Where: runner (`fence.luau`: `writeWhole(`{runTemp}/.pickman-owner`, `{myPid()}\t{ownId}`)`, where `ownId` is `fence.startOf`, the perl `sec.usec`); `tmp.new` (`{owner}\t{tmp.startOf(owner)}`, which is `ps -o lstart=` text); `tmp.sweep` (compares the record with `tmp.startOf` only); the CLI's `--dir <checkout or home>`; c0191's reaper "may call `./zn tmp sweep`".
Evidence: On a stand-in, both records name my live shell (`ps -o pid= -p $$` answered), and every mtime was set two hours back:
- `.cache/.tmp/pickman-run.A/.pickman-owner` = `<pid>\t<sec>.123456`, the runner's format;
- `.cache/.tmp/par.B/.pickman-owner` = `<pid>\t<ps lstart>`.
`./zn tmp sweep --dir <stand-in>` printed `tmp: removed …/pickman-run.A (idle 2 h)` and kept `par.B`. A live run's folder in a home's `.cache/.tmp` (the CLI accepts `--dir <home>`) is removed while the run uses it. The lock doesn't help: the specs' working directory is the home, so `lsof` doesn't count the folder as in use.
Critique: The tempting fix is to make `tmp.sweep` skip `pickman-run.*`. That leaves two formats under one file name for the next reader (the reaper).
Consequences: One format and one reader. The runner can't require `tmp.luau`, because fixtures copy the harness alone. So the shared part is either a pure parser that `runner.spec` pins equal to tmp's, as the shim is pinned, or `tmp` writes and reads the runner's start id, with `fence.startOf`'s perl text embedded the way `MKTEMP_SHIM` is.
Recommendation: Make both writers use the runner's start id (it already works for a reused pid and inside the jail), with tmp reading it, and pin the two texts equal in a spec. Add a `tmp.spec` case: a run folder whose record has the runner's format and a live pid survives a sweep two hours idle. Add the row with the mutant "start ids compared as `ps` text".
Lesson: zz-arch/one-reader-per-format, zz-arch/several-writers-check-the-subject

### F6 [medium] zz-test's clone procedure clones HEAD, so a guard prototype's uncommitted code never reaches the jailed clone, and its specs pass against the old code
Where: zz-test "Running specs against unguarded code" (prototype): `git clone --no-hardlinks . "$tree/repo"`; z-design's prototype practice (a throwaway, uncommitted prototype worktree, as here); E12b.
Evidence: `git -C .worktree/proto-c0194 status --short` lists 17 modified and 7 untracked paths, and HEAD is 02aae689 (main's). A `git clone .` of it holds none of them. E12b's clone therefore ran main's runner (F1). To run the new runner I had to copy the changed and untracked files in and commit them in the clone. The prescribed procedure gives no error: specs run green against main's guards, and every mutant applied in the prototype is "tested" against code that doesn't contain it.
Recommendation: zz-test's paragraph says how the working tree reaches the clone, for example: commit it in the clone (`git -C "$tree/repo" …` after copying `git diff --name-only` plus `git ls-files -o --exclude-standard` from the prototype), or commit on the prototype's own branch first. Pin the sentence in `docs.spec`. Re-run E12b that way (F1).
Lesson: z-design/instructions-runnable-where-they-run

### F7 [low] A home's `.cache/.tmp` is never swept, so the answer to round 2 F8 rests on a false claim (residue of design-review-002 F8)
Where: Design "`tmp.place`" ("its trees then sit in that home's `.cache/.tmp`, which the sweep and the outer-sandbox rule cover as a home's folder"); `check.sh` (`pickman_tmp_sweep "$(pwd -P)"` at the root); the hook (`--dir "$top"`); the runner clears only `pickman-run.*`.
Evidence: A stand-in with `pickman/.cache/.tmp/deploy-beta.X`, unowned and 106 h idle. `./zn tmp sweep --dir <stand-in>` removed nothing there. No caller passes a home. The outer-sandbox rule only refuses runs ("another temporary tree") and removes nothing. A crashed `deploy-beta` run from `pickman/` with no session `TMPDIR` leaves its tree there for good.
Recommendation: Either the gate's sweep also takes each picked project's home (it already loops over homes for `pickman_fence_all`), with a `callers.spec` case, or `tmp.place`'s fallback is the checkout root (`git rev-parse --show-toplevel`), as round 2 F8 offered. Say which, and correct the sentence.

### F8 [low] Landing's removal and the command line's refusals are fragile where agents run them (residue of design-review-002 F5 and F6)
Where: zz-rules Landing step 4 ("(remove the merge gate's clone first, with `./zn tmp rm "$dir"` …)"); Merging (no sentence for a stopped merge's clone); `tmp.removeTree`/`tmp.verify`/`tmp.jailPlan` → `physical(path)`; the header comments of `tmpcli.luau` and `tmp.luau`.
Evidence:
- The Bash tool does not keep shell variables between calls. By Landing step 4, `$dir` from Merging step 2 is gone, and `./zn tmp rm ""` printed `bad argument #3: runtime error: Invalid value for option 'cwd' - path does not exist` and a Lua stack, not a `tmp: <why>` refusal.
- `./zn tmp verify <missing tree>` crashes the same way instead of printing the `not isolated: the tree is missing` its code means to.
- A stopped merge (`BLOCKED:`) never reaches Landing, so its clone waits a day for the sweep, and nothing says so.
- The removal is a parenthetical, not part of the chained command.
- `tmpcli.luau`'s header lists no `jail`, and `tmp.luau`'s header still documents `new <dir> <kind>` and `verify <dir> <tree>`.
Recommendation:
- Landing and Merging say "the path `./zn tmp new gate` printed" (not `$dir`), put `./zn tmp rm <that path>;` at the head of the chain, and say a stopped merge leaves its clone for inspection, swept after a day.
- `physical` returns nil for a missing or empty path, so every command refuses with `tmp: …`. Add a `tmp.spec` case for `rm ""` and `verify <missing>`.
- Fix the two headers.

Candidate lesson (for the lead; I write none): **A guess the user hasn't answered is never a sequestered assertion.** c0194 pinned its guess (b) in `docs.spec` and AC5, so a different answer meant editing a sequestered spec, and promotion would have made the guess a gate rule. Check: does any sequestered spec, AC or label assert text that only holds under a guess in force?

Verdict: changes
