# Review 005: c0194 (design mode)
Inputs: prep worktree `prep-temp-trees-under-repo` at 7871c2f9 with the uncommitted `c0194.md`, `check.sh`, `acceptance/{tmp,shim,runner,callers,docs}.spec.luau` (`runner.spec` byte-identical to the prototype's, `cmp`), `harvest.md`, `experiments/proposed-lessons.md`, `design-review-00{1..4}.md`, `design-refute-00{1..4}.md`. Prototype `.worktree/proto-c0194` (base 02aae689; `tmp.luau`, `tmpcli.luau`, `fence.luau`, the skills' diff, `repo-fence.spec` diff), read only. Prepared c0075 (`z-nile/.tracker/issues/c0075/c0075.md`). `./zn capture c0194` (capture 64239635, unmarked). `./zn lessons --skill zz-review --full`, `./zn lessons --when design --full`. The author's `scratchpad/c0194/{mut-clone.py,mut-clone3.out,mut-clone4.out,r4-all.out,e12d.out}`.
Runs, all in my own jailed clone made as the brief and zz-test say (`./zn tmp new unguarded` from the prototype, `--no-hardlinks` clone, origin removed, the prototype's uncommitted files rsynced in and committed as `x@example.invalid`, every command through `./zn tmp jail`, tree removed with `./zn tmp rm`; files in `scratchpad/c0194-review5/`): round 4 F1's write probe again; a probe that replaces `.jail-tmp` with a link; a baseline of `runner.spec`, `tmp.spec`, `lock-start-ids.spec` (`base.out`: 46 passed, 1 failed, the `needJail` case); three mutants of round 4's new code (`mut.py`, `mut.out`). The tripwire did not fire. Overrides and Affected specs were not re-run: the Touched list is unchanged since round 3.
Dropped from design-review-004 (fixed; change, case and mutant checked): F1 (no allow rule is a pattern any more; my probe: `mkdir` at `repo/z-nile/tests/lib/.cache`, `repo/.git/hooks/.cache`, `repo/.git/refs/.cache`, `repo/scripts/.cache` denied; a nested fixture's `.cache` and the root's `.cache` written; the home `.cache` entry cannot be moved; no link at its top; N16 to N18 and N20 killed in `mut-clone3.out`), F3 (`mut-clone.py` judges against the baseline; P1 to P3 killed by the `profileFor` case), F4 (the restatements now describe the final jail; E12b line 221 quotes main's runner as history), F5 (the snippet exits 1 and 2; `tmp.startOf` maps them; N19 killed; three residues in F3 below). Round 4 F2 is fixed in the Design, but not in the skills or in one record line (F2 below).

Scope: the title, Problem and Solution are the capture's plus the three `Decided with the user (2026-11-01)` lines. Every captured outcome has a Design and a criterion. The jail decisions are carried out in the code and in zz-test. z-design's restatement of them is incomplete (F2).

The "Where the live-jail cases and every mutant run" statement agrees with AC3, AC6, row 321 and zz-test. The wiring risk (W1) is recorded as a `reasoned` row that the raft's gate catches. That design point is decided and I do not reopen it. The `.jail-tmp` probe found nothing: the jailed command can replace `$TMPDIR` with a link, but the kernel checks the resolved path, so a later run's write through it is refused (`Operation not permitted`). No unjailed tool reads that folder, and `rm` does not follow the link.

### F1 [medium] `runner.spec`'s live case fails instead of skipping wherever the run is not `sandbox-exec`, and c0075's Linux CI gate, which lands after this issue, is one of those runs
Where: `acceptance/runner.spec.luau:31-36` (`needJail()` calls `error("this case needs the macOS jail …")` whenever `PICKMAN_TEST_JAIL ~= "sandbox-exec"`) and `:53` (`the specs can write their own folder and nothing else under .cache/.tmp`). Design, "c0194 first" hand-off (Chore checklist, c0075 bullet; Overrides). c0075.md line 31 ("`PICKMAN_TEST_JAIL` says `bwrap` … CI runs it before the gate") and Observed ("the `gate` job of this PR's own CI run, which runs the whole suite under the jail on `ubuntu-latest`").
Evidence:
- My jailed-clone baseline (`base.out`), where the label is `outer sandbox (…)`: `FAIL … runner.spec.luau :: the specs can write their own folder and nothing else under .cache/.tmp … runner.spec:54: this case needs the macOS jail`. The author's `r4-all.out` shows the same.
- After `./zn done` this case is promoted and runs in every full gate. Under each label the runner sets, it fails as follows:
  - `none (…)` (Linux today): fails.
  - `outer sandbox (…)` (macOS, a mode the runner accepts): fails.
  - `bwrap` (c0075's Linux jail): fails.
  - Every future jailed clone, which the user's decision makes the place for guard prototypes: fails.
- c0075 is ordered after c0194 ("c0194 first"). Its own proof is a Linux CI run of the whole suite, so its gate goes red on a promoted spec that its Overrides do not name. `grep -n 'runner.spec\|c0194' c0075.md` finds nothing.
- The repository already has a pattern for this. Jailed cases return when unjailed (`c0076/sweeper.spec:81`, `c0078/jail-signals.spec:44`), and the item's `check.sh` asserts that they really ran on macOS (`done/c0076/check.sh:24-27`, `jailed_cases`, a marker file).
Critique: The `error` was chosen so that AC3 cannot pass without the jail. That holds for the sequestered check. But the same file becomes a promoted gate spec, and there it is permanently red off `sandbox-exec`. The obvious fix is to `return` when not jailed. Alone, that would let AC3 pass vacuously in an outer sandbox (lesson no-vacuous-pass). It would also skip the case on CI without a word, which specs-set-host-markers-explicitly warns against.
Consequences: The check moves to `check.sh` (the c0076 shape), which runs only for the item. The promoted spec then returns off-host. That is acceptable because the merge gate runs jailed on macOS, and the wiring (W1) is caught there and by `repo-fence.spec`'s probe (also edited by this issue). On Linux the case has no equivalent until c0075 writes one, so c0075 needs to be told.
Recommendation:
- In `runner.spec`'s live case, return when `PICKMAN_TEST_JAIL ~= "sandbox-exec"`. Under `none (…)`/`bwrap`/`outer sandbox (…)`, first assert the label it saw, as `repo-fence.spec`'s macOS case does. When it runs jailed, write a marker under its own `.cache/c0194-runner/`.
- AC3 in `check.sh` gains a `jailed_cases` step like c0076's: on Darwin the marker must exist, or AC3 fails with "run this check outside any other sandbox".
- The c0075 hand-off (the dated note under c0075.md, Implementation step 8) names the promoted `c0194/runner.spec` case: under `bwrap`, c0075 adds its own sibling or keeps the early return.
- With the `return`, the clone baseline has no failure, so `mut-clone.py`'s baseline set for `runner.spec` becomes empty. Re-run P1 to P3 once to show they are still killed.
- Cases: AC3 red on Darwin when the marker is missing (run it once with `PICKMAN_TEST_JAIL` relabelled); the spec green in the jailed clone.
Lesson: zz-test/specs-set-host-markers-explicitly, z-design/run-the-other-rafts-specs, zz-test/no-vacuous-pass

### F2 [medium] (repeat of design-review-004 F2) Where guard prototypes and their mutants run is still said three ways, and z-design, the skill a prep follows, leaves out the jail the user decided on
Where:
- z-design SKILL (prototype) line 54: "Before the guards exist on your branch, or while prototyping them, run them only in a clone under `.cache/.tmp/` (`./zn tmp new <kind>`; …), removed when the experiment ends". It says nothing about `./zn tmp jail`. `docs.spec:91` pins exactly this phrase.
- z-design SKILL line 56, the Mutation check, unchanged: "when you prototype the change in a scratch worktree, apply each row's mutant to the prototype and run the row's spec case".
- c0194.md line 224: "From round 4 on, every new or changed mutant runs in the jailed clone …; the two live-jail cases and their mutants (M20) are the only ones that need the worktree".
- Against these: the Problem's Decided lines ("those runs go through `./zn tmp jail`"; "from now on guard-prototype cases run in the jailed clone"), the Design's statement ("No mutant runs in a worktree"), and zz-test's "Running specs against unguarded code" (jailed).
Evidence:
- Round 4's refute says the Unknowns line "no longer says the worktree is needed". Line 224 still says it, in the present tense.
- A prep agent follows z-design's two bullets as written. It prototypes a guard change in a scratch worktree and runs each mutant there (what rounds 1 and 2 of this prep did, which line 224 itself calls the risk "Jail the clone" would have avoided). Or it runs a guard prototype in an unjailed clone under `.cache/.tmp/`, which is now four folders below the main checkout, so a climbing relative path reaches the checkout. Before this change such a clone was in `/var/folders`, far from it.
- Only zz-test says "jailed". z-design reaches it only through a section name ("Specs never touch the real repository") in the sentence before.
Critique: This is the third round that finds this rule stated differently in different places. Round 4 fixed the issue document's Design, but not the skill text where the rule acts. The tempting fix is to add "jailed" to line 54. That still leaves the Mutation check telling preps to mutate in a worktree, and a fourth copy of the rule.
Consequences: The rule needs one owner and pointers to it. zz-test's "Running specs against unguarded code" is the owner. It should say that a mutant of guard code (the runner, `fence.luau`, `fence.sh`, the hooks, `tmp.luau`'s jail) is unguarded code. z-design's two bullets point at it and add no detail. This touches z-design's Mutation check, which is not in the Restated rules list today.
Recommendation:
- z-design line 54 keeps its pinned phrase and adds ", jailed: every command through `./zn tmp jail` (zz-test, "Running specs against unguarded code")".
- The Mutation check gains one sentence: a mutant of guard code runs only in that jailed clone, never in a worktree; a case that needs the live spec jail is judged `reasoned` and runs unmutated in the raft's gate.
- zz-test's bullet names guard mutants explicitly.
- Line 224 loses "the two live-jail cases and their mutants (M20) are the only ones that need the worktree" (M20 is P1, killed in the clone).
- `docs.spec`'s z-design case also pins "`./zn tmp jail`" in z-design (mutant: the jail sentence removed). The Restated rules list names z-design's Mutation check.
Lesson: z-design/restated-rules-move-together

### F3 [low] Three plausible mutants of round 4's new code survive, and the Rules table has no row for them
Where: `tmp.startOf` (`return if r.code == 1 then "" else nil`); the start-record snippet shared by `fence.STARTED` and `tmp.STARTED` (`exit 2 unless syscall(202, …) == 0`); `tmp.prepareCaches` (`and process.exec("test", { "-e", "<checkout>/.git" }).ok`); Rules rows 314 and 322.
Evidence: `scratchpad/c0194-review5/mut.out`, each mutant applied to my jailed clone and `tmp.spec` run through `./zn tmp jail`:
```
B SURVIVED 34 passed, 0 failed   -- tmp.startOf: `r.code ~= 2` read as "no such process" (a perl that dies, exit 255, makes a live owner dead)
C SURVIVED 34 passed, 0 failed   -- the snippet, both copies: a failed sysctl exits 1 instead of 2 (round 4 F5's own "cannot tell" case, read as dead)
D SURVIVED 34 passed, 0 failed   -- prepareCaches: the `.git` test dropped (every folder at the tree's top gets a writable .cache)
```
The N19 case stubs `perl` to exit 2, so it pins how `tmp.startOf` maps exit codes. It does not pin that the snippet emits 2 for a kernel failure. The author's "live probe printed 0, 1 and 2" covers only the malformed-pid line, and `tmp.startOf` never sends a malformed pid. The `prepareCaches` case's tree has no folder without a `.git`, so D cannot fail it. Separately, `jailProfile`'s "unresolved spelling" branch is dead in use: `jailPlan` always passes `(at, at, …)`.
Recommendation:
- B: a stand-in `perl` that exits 255 keeps the tree (one line in the N19 case).
- D: add a `notes/` folder (no `.git`) to the `prepareCaches` fixture and assert it gets no `.cache`.
- C: record a `reasoned` row. A kernel refusal cannot be provoked here. The snippet's text is pinned equal in both readers, and its exit-2 lines can be read in one place.
- Either drop the `resolved` parameter from `jailProfile` or say why it stays.
Lesson: zz-test/pin-fail-safes-where-they-act

Candidate lesson (for the lead; I write none): **A case that needs the live jail returns off-host, and `check.sh` proves it ran.** A sequestered spec that `error`s off `sandbox-exec` keeps its own check honest, but once promoted it reddens every Linux, outer-sandbox and jailed-clone gate, including another raft's CI. Check: under each `PICKMAN_TEST_JAIL` value, what does each case of this spec do after promotion, and what in `check.sh` fails if the jailed branch never ran?

Verdict: changes
