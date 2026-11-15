# Review 001: c0226 (design mode)
Inputs: prep commit 304a51ceb (base 6d8cd0ff0; origin/main is 7 commits ahead, none touching `z-nile/engine/{trail,history,ids}.luau` or the lesson). Files reviewed: `z-nile/.tracker/issues/c0226/{c0226.md,check.sh}`, `acceptance/{rule,cuts,docs}.spec.luau`, `experiments/{prototype.patch,mutants.py,mutants.out.txt}`. Also read: `z-nile/engine/{trail,history,ids}.luau`, `tests/lib/fixture.luau`, c0284's `board.spec.luau` trace case, d0355, and the zz-arch, zz-test and z-design lessons named below. I compared the capture (`./zn capture c0226`: the Problem only; the Solution idea comes from c0138's landed prep and only adds detail) and found no scope narrowed. Commands run: `./zn check c0226` on the prep tree gives 1/4 (AC4), as E2 says. The affected selector for each touched path matches the design's lists. Grepping `tests/acceptance` and every `.tracker/**/acceptance` for the changed texts found no override, so `Overrides: none` holds. I checked E3: 05b058ea's two blobs are the same (a5905e93), so it is a plain move. In a `mktemp` clone of the base with `prototype.patch` applied, the three specs pass 15/15. I also ran a blob-comparing variant and a final-newline repository, and a history/trail parity probe (F1). All runs used `./zn run` and the clone has been removed.

### F1 [high] AC1 and AC2 pass a `trail.cuts` that does not judge by `ids.cutFile`, and that disagrees with history
Where: `acceptance/cuts.spec.luau` (fixture at lines 61-82, table case at 94-106); Design, "Why one rule, and why the patch log"; AC1, AC2.
Evidence: In the scratch clone (prototype applied, 15/15 green), I replaced `trail.cutsArgs` and `trail.parseCuts` with a blob-id comparison that never calls `ids.cutFile`: `git log --no-renames --diff-filter=AMDT --raw --no-abbrev --format=@@%H`, where a commit is a cut when it has an `M`, or an `A` whose blob no `D` in the same commit had. `rule.spec` 7/7 and `cuts.spec` 5/5 still pass. Then I built a two-commit repository whose second commit `git mv`s `tracker/compaction.txt` to `z-nile/compaction.txt` and drops only the final newline. On it the prototype's `trail.cuts` lists 1 commit, and `history.parse` counts 1 compaction (its `readMap` is called for one sha). The blob variant lists 2. So the two readers disagree again, which is the defect this issue exists to close. The Design names this exact case as its reason for reading the patch ("it differs from history's line-joined comparison when only a final newline changes; reading the same patch lines makes the two agree by construction"), but no case pins it. Nothing checks that `trail.cuts` and history count the same commits: AC1's "the one rule history and trail.cuts judge compactions by" is only checked against `ids.cutFile` alone.
Critique: The tempting fix is a newline case in `rule.spec`. But `rule.spec` works on ready-made `MapDiff`s and cannot see how a reader builds them. The gap is in how `trail.cuts` reads the log, so the case has to run over a real log.
Consequences: A fixture commit with no final newline leaves `\ No newline at end of file` in the patch. The parse must treat it as no content line. The prototype does, as history does, because the line starts with `\`, but the Design's parse sentence doesn't say so. A parity case needs history's set of compactions without relying on its warning text. `history.parse` calls `readMap(sha, path)` for the non-deleted maps of every commit it counts as a compaction, and never for any other commit (`renamedIds`). So a `readMap` that records the sha and returns nil gives exactly that set.
Recommendation:
1. In `cuts.spec`'s fixture, after `readd`, add a commit `nlmove` that `git mv`s `z-nile/compaction.txt` to `tracker/compaction.txt` and rewrites it as the same map without its final newline. It stays out of both expected tables.
2. Add a `cuts.spec` case, "AC2: history counts as compactions exactly the commits trail.cuts lists, over the same repository":
   - `local log = fixture.git(repo, history.logArgs({ "z-nile/.tracker" }))`;
   - `history.parse(log, { "z-nile/.tracker" }, function(sha) seen[sha] = true; return nil end)`;
   - expect the key set of `seen` to equal the key set of `trail.cuts("HEAD", repo)`.

   I ran this on the prototype: the cuts fixture gives 5 and 5, the same set, and the newline repository gives 1 and 1.
3. AC2, and its `check.sh` label word for word, gain: "and exactly the commits history counts as compactions; a move that only drops the map's final newline is none". The Design's parse sentence gains: "`\ No newline at end of file` is no content line, as in history".
4. Add two rows to the Rules table, both run with `mutants.py`:
   - "Contents are compared as the patch's lines, not as blob ids": cases `cuts :: lists every` (the `nlmove` commit) and the parity case; mutant M19, "cuts compares blob ids (`--raw`)".
   - "trail.cuts and history count the same commits": the parity case; mutant M20, "parseCuts judges with its own copy of the rule that treats every add beside a deletion as a move".
Lesson: zz-test/one-rule-one-function (give every copy the same planted cases, look-alikes included); z-design/spec-design-correspondence

### F2 [medium] `trail.parseCuts` is a second reader of the map-patch format
Where: Design → Code, `trail.parseCuts`; Maintainability ("`trail.parseCuts` mirrors history's map-patch reading line for line … Merging the two patch readers … not done"); `prototype.patch` `parseCuts` compared with `history.luau:344-363`.
Evidence: zz-arch rule 5: "Each file format has one reader, and every command uses it: … `ids.luau` for the counter and the compaction map." The prototype's `parseCuts` copies history's reading of one map file's patch: the four add/delete markers and the `+++ `/`--- ` exclusions. The design moves the rule into one function (`ids.cutFile`) but leaves its input built by two readers. The defect being fixed is two readers giving two answers to one question, and two readers of one format are how that comes back.
Critique: The tempting answer is to keep the copy with its "mirrors history's" comment. Then a later fix to one reader leaves the other: a `\` line rule, a header change, a prefix setting. With only the comment, F1's parity case is the only thing that would notice.
Consequences: Sharing the reader changes `history.parse`'s map branch, and c0118's specs (history, model, metrics, page, view, real) must stay green. History still reads the add/delete markers for item files itself, because its `cur.added`/`cur.deleted` drive item arrivals. M8 and M9 move into the shared function, and both `cuts.spec` and c0118 `history.spec` must kill them.
Recommendation: Put the line-level reading in `ids.luau` beside `MapDiff`, as a pure `ids.mapPatchLine(m: MapDiff, line: string)`. It applies one line of a map file's patch to `m`:
- `new file mode` or `--- /dev/null` marks it added;
- `deleted file mode` or `+++ /dev/null` marks it deleted;
- a `+`/`-` line that is not a `+++ `/`--- ` header is content;
- every other line (`index`, hunk headers, mode lines, `\ No newline at end of file`) is ignored.

`history.parse` calls it for a map file's lines. Its `flushFile` copy of `added`/`deleted` onto the map then goes, and item files keep their own marker check. `trail.parseCuts` calls it for each line of its current diff, and keeps only the commit and file framing.

Then add a `rule.spec` case that feeds it a deletion's header lines, an add's header lines, content and a `\ No newline` line. Point M8 and M9 at `ids.luau` and require both `cuts.spec` and c0118 `history.spec` to kill them. Touched modules stay as they are.

If the author keeps two readers instead, the lesson's other branch applies: F1's parity case is the shared planted case, and M8 and M9 must also run against history's copy and be killed by that case, with Maintainability saying why the copy stays.
Lesson: zz-test/one-rule-one-function

### F3 [high] Implementation step 5 tells the executor to remove the dispatched step's guards in its own worktree, and the recipe does nothing in the step's shell
Where: Implementation steps, step 5; E4; `experiments/mutants.py` (docstring lines 9-10, `TOP` at line 17, `git clone` at line 102).
Evidence: Step 5 says: "run them with the step's variables dropped: `for v in $(compgen -e | grep -E '^(ZN_|GIT_CONFIG_)'); do unset "$v"; done; unset GH_CONFIG_DIR; PATH=…`, then `lune run tests/run -- <those specs>` from `z-nile/`". That runs in the executor's own worktree, whose origin is the real repository. In this dispatched step, the 22 variables it targets are:
- `GIT_CONFIG_KEY_0..3 = credential.helper`, the step's resets of the user's git credential;
- `GH_CONFIG_DIR`, the step's GitHub credential;
- `ZN_PUBLISH_BROKER`, `ZN_PUBLISH_TOKEN`, `ZN_REAL_GIT`, `ZN_AGENT_GH_TOKEN` and the rest.

Taking `z-nile/bin` off `PATH` removes the wrapper that makes a step's `git` refuse pushes to main. So the recipe brings back the user's real git and gh credentials and drops the push refusal, for specs that push. Lesson z-design/clone-experiments-drop-the-step-environment allows dropping these only in a throwaway clone, with a guard that refuses unless the clone's `origin` is under its temporary folder.

The recipe also doesn't do what it says. The step's shell is zsh: here `type compgen` prints "compgen not found", so the loop unsets nothing and only `GH_CONFIG_DIR` and `PATH` change.

`mutants.py` says to run it "with the step's variables dropped". It clones with hardlinks, and leaves the clone's `origin` at the real repository's git directory (`TOP`).
Critique: The tempting fix is `bash -c '…'`. That would make the guard stripping actually work, which is worse. The runner's fence and the macOS jail still protect the repository while the specs run, but an implementation step must not prescribe removing the dispatcher's credential isolation in a real worktree (zz-review item 9: any weakening of the guards is high).
Consequences: Without the recipe, these three specs fail in a dispatched step at their fixture's first push on main, as they do on origin/main (E4's control; d0355 owns it). The `--affected` gate selects `c0114/trail-move` (affected by `trail.luau`), so it is red in a dispatched step for that reason. The executor has to be able to tell that apart from a regression.
Recommendation:
- Delete the recipe from step 5. Step 5 says instead: in a dispatched step, `c0114/trail-move`, `c0119/capture-cli` and `c0120/trail-home` fail at their fixture's first push on main on origin/main too (E4's control, d0355). Record each failing line in the Verification log; the merge's local full gate runs them outside a step. If zz-execute cannot finish with them red, that is its stop condition and goes to the human, never a stripped environment.
- If the author wants them run inside the step, it must be a bash script that makes a `git clone --no-hardlinks` under `mktemp -d`, runs `git remote remove origin` (so nothing in it can reach the real repository) and has the lesson's guard. The step names that script.
- In `mutants.py`, drop the "with the step's variables dropped" sentence, clone with `--no-hardlinks`, and run `git -C clone remote remove origin` right after the clone.
- Make E4's record match: it says how the three specs were run, and that step 5 no longer asks for it.
Lesson: z-design/clone-experiments-drop-the-step-environment

### F4 [low] The Rules and mutants table misses two plausible mutants
Where: Rules and mutants.
Evidence:
- (a) "The parse never marks a deletion" (`m.deleted = true` becomes `false`): a plain move's deleted side reads as a change in place, so c0114's move becomes a cut. `cuts :: lists every` kills it.
- (b) "A moved and changed map is named by the file it left" (return the deleted diff's path): `rule :: a map moved and changed` kills it.

Row 4's M1 tests the counting, not the naming, and neither (a) nor (b) is listed.
Recommendation: Add both rows and run them with `mutants.py`. With F2's shared reader, (a) is a mutant of `ids.mapPatchLine`, and both `cuts.spec` and c0118 `history.spec` must kill it.
Lesson: z-design/spec-design-correspondence

## Lesson candidates (for the lead to file)
- **New:** a shell recipe an agent is told to type names its shell when it uses a bash builtin. The Bash tool runs the user's shell (zsh here), where `compgen` is not found, so `for v in $(compgen -e …)` silently loops over nothing. Check: does every inline recipe in a step or experiment run under the shell it was written for (`bash -c '…'`, or a script with a bash shebang)? z-design/clone-experiments-drop-the-step-environment's own "How to apply" gives `compgen -e` inline.
- **Note on z-design/clone-experiments-drop-the-step-environment:** an implementation step never tells an executor to drop the step's environment in its own worktree. A spec a dispatched step cannot run is named with its control and left to the gate outside the step (c0226 design review 001 F3).

Verdict: changes
