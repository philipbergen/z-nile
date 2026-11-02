# Review 006: c0189 (design mode)
Inputs: worktree `prep-fixture-identity-reprep` at 9e6b43ee plus its uncommitted re-prep (`git diff` of c0189.md, check.sh, acceptance/{repo-hook,wiring}.spec.luau, experiments/{prototype.patch,mutate.py}, and the untracked acceptance/replace-mode.spec.luau); c0194 at main 0dc30738 (`z-nile/.tracker/issues/active/c0194/`: c0194.md, acceptance/{callers,docs}.spec.luau, experiments/prototype.patch; identical to 9e6b43ee's copy apart from the move to `active/`); R0070 `design-review-001.md` and `design-refute-001.md` and R0070.md at main; zz-review, zz-test, z-design skills; `./zn capture c0189`; zz-review and zz-test lessons.
Rounds 001-005 were not re-litigated. G1 to G4 are untouched by the re-prep. The hook's first line is still `#!/bin/sh` (checked in the prototype), so c0123's override is unaffected.

Method. I made a throwaway clone of the worktree under `mktemp -d`, removed its origin and set the identity to `reviewer@normal.test`. Then:
- I applied the re-prep's `experiments/prototype.patch` and copied in the five acceptance specs.
- **c0189 alone:** `wiring` + `replace-mode`: 17 passed, 0 failed.
- **Stacked** (c0194's patch applied with `--3way`, the four skill conflicts settled by keeping both sides as E13 describes): `c0194/callers`, `c0194/docs`, `c0189/wiring`, `c0189/replace-mode`: 36 passed, 0 failed. `c0077/replace-file`: 14 passed. With the c0189 specs moved to `tests/acceptance/c0189/` (as at `done`), `tooling/repo-fence`: 10 passed.

So both of R0070's conflicts are fixed as text. The install calls no `mktemp`, and `callers.spec` is green beside it. The prototype rule names `.cache/.tmp/` and contains c0194's pinned "scratch clone (never a `git worktree add`)". The two findings that matter are about what the fixes left out: what one new spec can write, and what the text says when c0189 lands without c0194.

### F1 [high] `replace-mode.spec` runs `replace-file.pl` from the project home, so a helper that does not consume `--mode=` writes files named `--mode=…` into the checkout
Where: acceptance/replace-mode.spec.luau, `replace()` (`process.exec("sh", argv, { stdio = … })`, with no `cwd`); Implementation step 1 ("Run the new specs … 1 of 5 cases pass"); Rules row M4.

Evidence:
- Every `replace({ "--mode=…", <path> }, …)` call runs perl in the spec's working directory, which is the project home (`z-nile/`).
- Before step 3 exists, and under mutant M4 or any later regression in the option's parsing, `replace-file.pl` reads `--mode=<x>` as `<dest>` and the fixture path as `<src>`. It then writes the fixture's content to `./--mode=<x>`, in the home.
- I ran this in the clone. With the base `replace-file.pl` and outside any jail (as on Linux), `perl lib/replace-file.pl --mode=abc "$PWD/.cache/r6/f"` exited 0 and created `z-nile/--mode=abc` holding `keep`, the fixture file's content.
- The spec's own cases would do the same for `--mode=0755` (twice), `--mode=abc`, `0999`, `75555`, `-1`, `7 5`, `0755x` and the empty value.
- Under the macOS jail the writes are denied, and the jailed run left no such file (1 passed, 4 failed, as step 1 predicts). The jail is the only thing between this spec and the working tree.
- Implementation step 1 tells the executor to run exactly this spec before the code exists. On Linux, where runs are unjailed (AGENTS.md: "What it can't see (unjailed runs on Linux …), review must catch"), that run writes nine stray files into the raft worktree.

Critique: the spec trusts the code under test to parse its own new option before any write stays inside the fixture. The tempting fix is to put the paths after the option in a different order, or to rely on the jail. Neither helps when the option is not consumed at all, and the jail does not exist off macOS.

Consequences: run every `replace-file.pl` call with `cwd = <the case's fixture folder>`. A misparsed `--mode=…` then lands in the fixture, and the case can see it. This also gives M4 a direct kill: "no entry named `--mode=*` appeared". It adds no rule to the design. The `sh.writeReplacing` case already uses absolute paths, and an old `sh.luau` ignores the third argument, so it writes nothing stray.

Recommendation: in `replace-mode.spec`, `replace()` takes the fixture folder and passes it as `cwd`. Each case then asserts that `fs.readDir(dir)` holds no name beginning with `--mode`. Update the Rules row for M4 to name that assertion, and re-run M4 and the step-1 count ("1 of 5") in a clone.
Lesson: zz-test/new-commands-run-in-a-copy

### F2 [high] "The text is true in either landing order" is false: with c0189 alone, the skills contradict each other and send guard prototypes into the main checkout
Where: c0189.md "The rules in prose" (re-prep paragraph: "The text is true in either landing order"); Risks ("If this lands first, … a clone there does not hurt the gate …"; "Not made a dependency: the sentence is true either way"); `depends_on: []`.

Evidence (c0189's prototype alone in the clone, `grep -n -E 'TMPDIR|\.cache/\.tmp'` over the skills):
- zz-test line 122 (new): "A prototype or experiment lives in a scratch clone (never a `git worktree add`) under the main checkout's `.cache/.tmp/` (never the system temp folder or a harness's scratchpad) …"
- zz-test line 123 (unchanged until c0194): "**Running specs against unguarded code**: only in a clone under `$TMPDIR`, outside every repository (`git clone --no-hardlinks . "$(mktemp -d)/repo"`). That applies when prototyping the guards themselves … A broken fixture there can only reach the clone."
- z-design line 31 (new) gives the same `.cache/.tmp/` rule. Line 55 (unchanged until c0194) says: "Before the guards exist on your branch, or while prototyping them, run them only in a clone under `$TMPDIR`."
- `wiring.spec` passes on this tree (17/17 with replace-mode). Its `lacks` looks for "into `$TMPDIR`", and these lines say "in a clone under `$TMPDIR`".
- Which bullet wins matters. A guard prototype that follows c0189's rule puts unguarded code inside the main checkout before c0194's `./zn tmp jail`, its `.luaurc`/Rokit isolation and its closed jail rule exist. The reason the old bullet gives ("can only reach the clone") then no longer holds, because a relative path that climbs out of the clone reaches the real checkout. Today's jail (zz-test line 92) also lets a run write anywhere in "this checkout's `.cache`". c0194 design review 004 F2 rated exactly that high: a jailed spec can plant a file in an agent's clone that the agent later runs unjailed.

Critique: the re-prep chose no dependency because the sentence would be "true either way". It is true only if c0194 lands first. The tempting fix is a third sentence reconciling the two bullets. That would be another pinned text that c0194's edits then have to merge around, and it still leaves guard prototypes in the repository before the jail exists.

Consequences:
- (a) `depends_on: [c0194]`. c0194 is already readied (R0070, 54722a81), so z-ready refuses c0189 only until R0070 is done. The rule could then also name `./zn tmp new <kind>`, as R0070 F1 suggested. The Risks bullet "If this lands first" and the "true in either landing order" sentence go. E13 (stacked) becomes the only order to prove, and it is already proved.
- (b) No dependency. The rule then has to defer to the unguarded-code bullet in its own words (for example "… (code under test that has no guards yet: zz-test, Running specs against unguarded code)"). `wiring.spec` needs a case that, in a tree without c0194, no skill tells a guard prototype to go under `.cache/.tmp/`. The Risks bullet has to say what protects a clone in `.cache/.tmp/` from the pre-c0194 jail. That is more text and more pins, and c0194 would have to merge around them.

Recommendation: (a). Record it in the front matter, drop the "either order" sentences, and keep E13 as the proof. If the lead wants c0189 able to land first (it was captured as a fast chore), take (b) with its spec case, and restate the Risks claim against today's jail rule, quoted.

### F3 [medium] The gate-in-a-clone sentence tells agents to run the clone's own `./zn hooks` unjailed, and a hook installed first refuses the fixture-identity commit c0194's clone recipe makes
Where: c0189.md, the zz-test sentence pinned by `wiring.spec` ("A scratch clone has no hook of its own … run `./zn hooks` in the clone first, outside any spec jail …"); row W10; c0194's zz-test "Running specs against unguarded code" (in its prototype patch).

Evidence:
- c0194's bullet covers "every mutant of guard code: the runner, `fence.luau`, `fence.sh`, **the hooks**, the jail". It requires "every command through `./zn tmp jail`", and its recipe commits the copied prototype "under an `@example.invalid` identity" in the clone.
- `zn` does `cd "$top"` on its own folder, so `./zn hooks` in a clone always runs that clone's engine. For a hook or `cmd.hooks` prototype (this chore's own kind of work), the sentence has the prototype's code run outside the jail, against c0194's decided rule ("Jail the clone").
- I ran the order the sentence suggests in the stacked clone. `./zn hooks --check` gave "… is missing; run ./zn hooks" (exit 1). `./zn hooks` gave "installed" with mode 0755. Then `git -c user.email=proto@example.invalid commit --allow-empty` was refused: "fatal: in 'prepared' phase, update aborted by the reference-transaction hook", exit 128. The refusal text tells the agent to "git clone this checkout under the main checkout's .cache/.tmp/", which is where it already is.
- R0070 F6 had recommended "using main's code (not the prototype's)". The re-prep dropped that, presumably because main's `./zn` cannot reach a clone, but put nothing in its place.

Critique: the sentence fixes the gate's red stage and opens two traps for the clone c0194 is building recipes for. The tempting fix, "run it jailed", cannot work: the jail denies the clone's git directory, as the sentence itself says.

Consequences: the sentence has to say which clones it is for. It needs a rule for clones of reviewed code (the merge clone, a prototype of non-guard code): install the hook after any commit the clone makes under a fixture identity, or not at all. It also needs a rule for clones holding guard code under test: run spec files only, jailed; no gate, so no hook. The pinned text and row W10 change with it.

Recommendation: reword the pinned sentence to cover both cases: "A gate run in a scratch clone of reviewed code stops at … run `./zn hooks` there first, outside any spec jail, and after any commit the clone needs under a fixture identity (the hook refuses those); a clone holding unguarded code (zz-test, Running specs against unguarded code) runs spec files only, jailed, and needs no hook". Update `wiring.spec`'s pin and W10, and add a W10b mutant (the unguarded-code clause removed).

### F4 [low] The `--mode=` bound is tested only above it: a rule that accepts one or two digits survives
Where: replace-mode.spec "a mode that is not octal is refused before anything is written" (bad values `abc`, `0999`, ``, `75555`, `-1`, `7 5`, `0755x`); Design "`--mode=` takes three or four octal digits".

Evidence: I changed the prototype's `/\A[0-7]{3,4}\z/` to `{1,4}` in the clone, and `replace-mode.spec` passed 5 of 5. The four-digit form also accepts set-id and sticky bits (`--mode=4755`), and the Design neither allows nor refuses them in so many words.

Critique / Consequences: no current caller passes a short or special mode, so this matters only for a later caller. Refusing special bits would be a new rule with its own case.

Recommendation: add `7` and `75` to the bad list, and `0644` as an accepted four-digit value (it is the default). Then either state that the first of four digits may be any octal digit, or refuse a non-zero one with a case (`4755`).
Lesson: zz-test/refusals-tested-on-both-sides

### F5 [low] Two re-prep statements do not match the documents
Where: c0189.md Unknowns & experiments, "Re-prep (2026-11-01)"; Existing work, the c0194 bullet.

Evidence:
- (a) "the rule, the hook's message and the lesson wording now name `.cache/.tmp/`": the lesson's new wording (step 7, "in a scratch clone or worktree (z-design, Unknowns & experiments)") does not name it. It points at the rule, which is what R0070 F1 asked for.
- (b) The c0194 bullet does not say that c0194's Implementation step 8, run by R0070's executor, "add[s] … the dated notes under c0189.md and c0157.md (the scratch-clone definition)". After this re-prep that note restates what c0189 already says, and it is another raft editing this issue's document. Once c0189 is readied, the document's path moves to `active/`.

Recommendation: correct (a). In (b), name the note and say it is expected and harmless, or that R0070's lead may drop it (it is c0194's step, so it is R0070's call).

Candidate lesson (z-design, new): a design that names a sibling issue's outcome but takes no `depends_on` on it proves its text in both landing orders. Apply its prototype alone and read every sentence the sibling will later replace. Check: with only this patch applied, does any unchanged sentence still say the opposite of the new one?

Verdict: changes
