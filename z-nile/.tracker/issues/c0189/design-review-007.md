# Review 007: c0189 (design mode)
Inputs: worktree `prep-fixture-identity-reprep` at 9e6b43ee plus its uncommitted re-prep (`git diff` of c0189.md, check.sh, harvest.md, acceptance/{repo-hook,wiring}.spec.luau, experiments/{prototype.patch,mutate.py}; untracked acceptance/replace-mode.spec.luau, design-review-006.md, design-refute-006.md, experiments/proposed-lessons.md); origin/main 8ab88a88: c0194 (`issues/active/c0194/`: c0194.md, acceptance/{callers,docs}.spec.luau, experiments/prototype.patch), R0070.md, c0123.md, c0157.md, c0229.md; z-raft, z-ready, zz-rules (grouped hashes, depends_on); zz-review lessons; `./zn lessons --when design`.
Rounds 001-005 and G1 to G4 not re-litigated. The hook's first line is still `#!/bin/sh` (prototype), so c0123's override of the `wiring` pin is unaffected.

Answers to 006, checked by running them. Throwaway clones under `mktemp -d`, origin removed, identity `reviewer@normal.test`:
- **F1 (spec runs in its fixture folder): right.** On c0189 alone, `wiring` + `replace-mode` gave 17 passed, 0 failed. With the base `replace-file.pl` and `sh.luau` restored, `replace-mode` gave 1 passed, 4 failed (step 1's count). The strays it made (`--mode=abc`, `--mode=0755` twice) were all under `.cache/c0189-replace-mode/*/`, and `ls -a z-nile | grep -- --mode` was empty. Mutants via `mutate.py <clone> bounded.pl M4 M9 W10 W10b M2`: M4 3 failed, M9 1 failed ("a mode that is not octal…"), W10 1 failed, W10b 1 failed, M2 2 failed. One remainder is F4 below.
- **F2 (`depends_on: [c0194]`): the text is right, but the consequences are not finished** (F1 and F2 below).
- **Stacked in the order the dependency now forces** (c0194's patch applied and committed first, then c0189's with `--3way`): z-design, zz-execute, zz-rules and zz-test conflicted. I settled them as E13 says. Then `c0189/wiring`, `c0189/replace-mode`, `c0194/callers` and `c0194/docs` gave 36 passed, 0 failed, and `c0055/setup-run` gave 8 passed. The stacked zz-test reads one way: the "Fixture identities" bullet, then c0194's unguarded-code bullet, then the tripwire bullet with the retry exception.
- **F3 (the sentence split by clone kind): right**, and it agrees with c0194's "every command through `./zn tmp jail`". One remainder is F6.
- **F4 and F5: right.**

### F1 [medium] `depends_on: [c0194]` settles an order that R0070 left to the user, and its stated cost leaves out R0078, c0123 and the user's "shipped ahead of c0157"
Where: front matter `depends_on: [c0194]`; Risks, "This chore waits for c0194" ("R0070 is readied and holds one issue … Reported to the lead, who may choose it instead"); Existing work, c0123 bullet; Problem, "Decided with the user (2026-10-31): 'New fast chore' … shipped ahead of c0157"; Guesses (none for this).
Evidence:
- R0070.md on origin/main, Risks: "the user decides the order of c0189 against R0070 (c0189 prepared again, then rafted after R0070 lands, is the simplest)". The document makes that choice and records no `Decided with the user` line and no Guess. "Reported to the lead" is not the user.
- R0070.md, Order & dependencies: "**R0070 also waits for R0078** (c0173 and c0174 …): R0078 must be merged before this raft's PR merges". So the real chain is R0078, then R0070 (c0194, size 850), then c0189, then c0123. c0123 is preparing on main (`depends_on: []` today) and the brief says it will depend on c0189. The Risks bullet names only "R0070 is readied and holds one issue". The c0123 bullet in Existing work does not say that c0123 now waits for c0194. That sentence is only in design-refute-006.md.
- The captured decision "shipped ahead of c0157" has no `depends_on` edge to enforce it. c0157.md on main: `depends_on: []`, status preparing (lesson z-ticket/carry-the-plan-order-into-depends-on). Before the re-prep, c0189 could land at once. Now it waits for two rafts, and nothing stops c0157 from landing first.
Critique: the dependency is the right technical answer to 006 F2. But it trades the user's "fast" against a contradiction in the skills, and R0070 explicitly left that trade to the user. The tempting fix is a sentence saying the lead agreed. That still leaves the c0157 order unenforced.
Consequences: whichever order the user picks, its edge has to exist in the tracker. If c0189 waits for c0194, then keeping "ahead of c0157" needs `depends_on: [c0189]` on c0157 (c0157 also names `$TMPDIR` for clones, per c0194.md line 155, so it waits for c0194 anyway). Otherwise the user drops "ahead of c0157". If c0189 lands first, 006 F2's option (b) applies, with its sentence, its spec case and its argument against today's jail.
Recommendation: escalate to the user, as a new Guess G5 (pending user), with the full chain and its costs:
- (a) Keep `depends_on: [c0194]`. The guard arrives after R0078 and R0070, and c0123 waits behind it. "Ahead of c0157" holds only with `depends_on: [c0189]` on c0157, or the user lets it go.
- (b) Land first under 006 F2 (b): a rule sentence that defers to the unguarded-code bullet, a `wiring` case that no skill sends a guard prototype under `.cache/.tmp/` in a tree without c0194, and the Risks argument against today's jail rule, quoted.
Recommend (a). Correct the Risks cost to name R0078. Add c0123's wait to its Existing-work bullet. Record the user's answer as a `Decided with the user` line.
Lesson: z-ticket/carry-the-plan-order-into-depends-on

### F2 [medium] R0070's step 8 will edit c0189.md while c0189 waits for it, which turns the `grouped:` record of any raft holding c0189 stale
Where: Existing work, c0194 bullet ("R0070's step 8 also adds a dated note under this document … whether to drop it is R0070's lead's call"); c0194.md Implementation step 8 and line 155 ("The executor adds a dated note under each draft's captured text … (they stay drafts; their own preps take it from there)").
Evidence:
- c0194's step 8 assumes c0189 is a draft. After this re-prep, c0189 is prepared (`design: reviewed`), and R0070 is readied with that step in its prompt.
- zz-rules, Rafting: "A raft's `grouped:` line records a hash of each prepared member's design (its document without `status:` and `raft:` …); the carried move and `ready` refuse a member whose design changed on `origin/main` since". z-raft §"Redesigned members" says the same.
- `depends_on` stops only `ready`, not rafting (z-ready line 14 checks it; z-raft does not). So z-raft can group c0189 now, for example with c0123. R0070's executor then writes the note into `c0189.md` and lands it. The later `./zn ready` of c0189's raft refuses with "c0189 (<recorded> → <now>): changed on origin/main since R… grouped it", which forces an unfold and refold (a new coherence round if the raft has several issues).
- If c0189's prep PR is still open when R0070 lands, the note is one more merge into this document.
- After the re-prep, the note only restates the rule (006 F5's own reading).
Critique: leaving it to "R0070's lead's call" puts a decision in a prompt that is already written and that the executor will follow. The tempting fix, telling R0070's lead to skip it, edits a readied raft's instructions from another issue's prep.
Consequences: the simplest rule that holds needs no edit to R0070. c0189 is rafted only after R0070 is done, which F1's (a) implies anyway. z-raft has to be able to read that from this document.
Recommendation: in Existing work (c0194 bullet) and Risks, say that c0189 is rafted only after R0070 is done, because R0070's step 8 edits this document and would invalidate an earlier `grouped:` hash. Say that the note is expected and harmless, and stays (it restates the rule). Drop "whether to drop it is R0070's lead's call". If the user picks F1 (b), say instead that R0070's lead skips c0189's note (c0189 is no longer a draft), and capture that as an issue against R0070's prompt.

### F3 [low] The steps and Existing work still read as if c0194 might land second, and the prototype no longer applies with plain `git apply`
Where: Implementation step 1 ("`git apply` on the branch from `origin/main`; `git diff 6e7fc1aa origin/main -- <Touched modules>` first: if it is not empty, merge, rebase the patch …"); step 7 ("c0194 if it landed"); Existing work, c0194 bullet ("whichever lands second merges those lines"); `experiments/mutate.py` (requires `<bounded.pl>`).
Evidence:
- With `depends_on`, origin/main will always hold c0194, which changes `main.luau`, `check.sh`, `setup.sh`, `repo-fence.spec` and four skills. So the diff in step 1 is never empty.
- I applied the patch on top of c0194's prototype. `git apply --3way` reported "Applied patch to 'z-nile/skills/{z-design,zz-execute,zz-rules,zz-test}/SKILL.md' with conflicts" (six conflict blocks), and a plain `git apply` refuses outright.
- The re-prep patch was made on 99913e40, not 6e7fc1aa.
- `mutate.py` takes a second argument, `bounded.pl`, which lives only in this prep session's scratchpad. An executor rerunning a row has no such file.
Recommendation:
- Step 1: base 99913e40; `git apply --3way`, then settle the four skill conflicts as E13 lists (the placements are already written there).
- Step 7: drop "if it landed".
- The c0194 bullet: "c0194 lands first; this chore merges its lines beside c0194's".
- `mutate.py`: make the runner argument optional (default: `perl -e 'alarm shift; exec @ARGV' 150`, as before), and note that after c0194 a mutant of guard code runs through `./zn tmp jail` (c0194's z-design mutation bullet).

### F4 [low] `replace-mode`'s `sh.writeReplacing` case still runs `replace-file.pl` from the project home, so a helper that does not consume `--mode=` makes a temporary file there
Where: acceptance/replace-mode.spec.luau, "sh.writeReplacing passes the mode on, and without one writes 0644"; Rules row M4 ("every call running in the case's fixture folder, so a misparse can never write into the checkout").
Evidence:
- `sh.writeReplacing` runs `perl replace-file.pl --mode=0755 <abs path>` in the Lune process's working directory, the home. `cwd` covers only the spec's own `replace()`.
- With M4 applied (`shift @ARGV` removed), run from a scratch working directory: `echo e | perl m4.pl --mode=0755 $T/fx/exec` printed `replace-file: --mode=0755: …/fx/exec: No such file or directory`, exit 1. So `<dest>` became `./--mode=0755`, and the helper creates its temporary sibling `./.--mode=0755.pickman-tmp.*` before it opens `<src>`, then removes it.
- That is a transient write in `z-nile/` on an unjailed run (Linux). Nothing is left behind, but the M4 row's "can never write into the checkout" is stronger than what the spec does.
Recommendation: make the row's words exact ("a misparse in `replace()` lands in the fixture; through `sh.writeReplacing` it can only create and remove a temporary file next to the working directory, denied by the jail on macOS"). Or run that case's three `sh.writeReplacing` calls in a child `lune` with `cwd` set to the fixture folder. The second removes the remainder; the first states it.

### F5 [low] The harvest gives 006 F2 a lesson about peers' scans, which is not what F2 found
Where: harvest.md, "design-review-006 F2: one-off: proposed new lesson z-design/peers-scans-run-on-the-prototype"; experiments/proposed-lessons.md.
Evidence: 006 F2 was "the text is true in either landing order" was false, and its candidate lesson was "a design that names a sibling issue's outcome but takes no `depends_on` on it proves its text in both landing orders … with only this patch applied, does any unchanged sentence still say the opposite of the new one?". The proposed lesson is about running a peer's repository-wide scan on the prototype, which is R0070 F2's defect. The landing-order rule is in neither proposal. The nearest existing lesson, z-design/restated-rules-move-together, already asks for a search for "either order", which this design had failed.
Recommendation: harvest 006 F2 as a new source on z-design/restated-rules-move-together (or as the candidate lesson, as its own file), and keep `peers-scans-run-on-the-prototype` as the harvest of R0070 F2.

### F6 [low] In a jailed clone the tool still says `run ./zn hooks`, which is the step the new sentence forbids there
Where: zz-test sentence ("A clone holding unguarded code … runs spec files only, jailed, and needs no hook"); `hooks.plan` problem "`hooks: <dest> is missing; run ./zn hooks`".
Evidence: the rule is prose only. An agent that runs `z-nile/check.sh` inside `./zn tmp jail` anyway (R0070 F6 expected exactly that) gets the stage's "missing; run ./zn hooks". Inside the jail, `./zn hooks` cannot write the clone's git directory. Run outside the jail, it executes the clone's unguarded `cmd.hooks`, which is 006 F3's trap.
Recommendation: accept it as a prose-only rule and say so in Risks (one line: "a gate run in a jailed clone stops at the hooks stage; zz-test says not to run one there"). Changing the message would change pinned strings, which this does not warrant.

Candidate lesson (z-design, for the lead): when a re-prep adds `depends_on` on an issue that sits in a readied raft, read that raft's Order and its executor's steps. The wait includes everything that raft waits for, and any step that edits this issue's document turns the `grouped:` hash of a raft holding it stale. Check: what does the dependency's raft wait for, and does its prompt edit my document?

Verdict: changes
