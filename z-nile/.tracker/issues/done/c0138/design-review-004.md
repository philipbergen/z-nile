# Review 004: c0138 (design mode)
Inputs: prep worktree `prep-trail-compaction-reset` (base c199e8de, uncommitted prep): `c0138.md`, `check.sh`, `acceptance/{renamed,kept,docs}.spec.luau`, `experiments/mutants.py`, `prototype.patch`, `design-review-00{1,2,3}.md`, `design-refute-00{1,2,3}.md`, `harvest.md`. Prototype `proto-c0138` (20eb19ac): `git diff -- z-nile/engine z-nile/skills` is byte-equal to `prototype.patch`, and its `check.sh`, three specs and `experiments/mutants.py` are byte-equal to the prep's. `./zn capture c0138` (7769d615). `z-nile/engine/{trail,ids,main}.luau` (`cmd.capture`, `cmd.compact`, `cmd.remap`), `scripts/tracker/trail.luau`. `origin/main` cc721984. `./zn lessons --when design --full`, `./zn lessons --skill zz-review --full`.
Dropped from design-review-003: none. Every answer is real (below). F1 is a new hole in the mechanism behind 003 F2: a runner the executor can run.

## What I verified
Every run was in a throwaway clone (`mktemp -d` under the scratchpad, origin removed). I checked out today's origin/main cc721984, applied `prototype.patch`, and copied in the prep's issue files. Each command ran under `bounded.pl`, and I ran only single spec files, a subset of the runner, `./zn check c0138` and `./zn promote-check c0138`. The clone is deleted, and the main checkout, the prep and the prototype are unchanged.

- **No base drift.** `git diff --stat 20eb19ac origin/main` (138 commits) is empty over `z-nile/engine`, `z-nile/skills/zz-rules`, `z-nile/tests/lib`, `z-nile/tests/run.luau`, `z-nile/lib`, `zn`, `tests/lib`, `z-nile/projects.toml` and the c0111, c0114, c0119 and c0120 acceptance folders. It is also empty over all 45 files that name the engine files, the skill, the lesson or the map (my `readers.txt` search).
- **The prototype passes on today's main.**
  - `renamed`, `kept` and `docs` pass 28/28.
  - The promoted c0111 `trail`, c0114 `trail-move`, c0119 `capture-cli` and c0120 `trail-home` pass 29/29.
  - `./zn check c0138` passes 4/4, run with the issue folder moved to `issues/active/c0138` the way `ready` moves it.
  - `./zn promote-check c0138` prints `promote-check OK`.
- **Round 3's answers are real.**
  - I ran `experiments/mutants.py MF M14b M7 M16` from the issue folder. All four die on the cases their rows name: MF on "…does not parse, first or last", M7 on 2 cases, M14b on 4, M16 on 1.
  - `read`'s comment carries "or whose map does not parse or can't be read", and `docs.spec` pins it (line 78).
  - The patch has 116 `+`/`-` lines minus 8 headers, which is 108.
  - `./zn lessons --uncovered c0138` reports every finding covered.
- **Scope (d), judged independently. Confirmed: the whole-map reading narrows nothing.**
  - `cmd.compact` overwrites the map (`fs.writeFile(idsLib.MAP_FILE, idsLib.formatMap(map, …))`, main.luau:2958) with `ids.plan` over every listed id. So a compaction commit's map holds only that compaction's pairs.
  - For an added or modified file, the `+` lines are a subset of the file as committed. A line that fails to parse fails the whole file too.
  - The whole map therefore resets a superset of what the literal `+`-line reading resets. The extra resets fall on pairs repeated word for word, and on c0119's `fix`, whose c0008 the literal reading would stop marking. Both are marked, conservative answers.
  - `cmd.remap` writes no map: its `tracker: remap ids` commit is not a cut, so remapped branches change nothing here.
  - The capture's two bullets (b37679dc), a kept item's capture and first review found and a reused done id stopping, have cases (c0010, c0020).
  - Title and Problem are unchanged.
- **Overrides: none. Confirmed.**
  - `lune run z-nile/affected -- z-nile/engine/trail.luau` prints `ALL`.
  - 16 promoted specs name `zz-rules`. The six the Design doesn't list pass on the prototype: c0081 `skill-doc`, c0107 `keep`, c0115 `docs`, c0116 `docs` (20/20), and c0115 `layout` and `prompt` (11/11). See F5.
  - `scripts/tracker/trail.luau` returns the engine module itself, so c0111 `trail` (which requires that path) sees the new functions.
- **New mutants.**
  - NC (an unparseable retired map is skipped): killed by the `badold` case.
  - NA (the `c.doc` guard dropped): survives (F2).
  - NB (a failed read of the retired map is skipped): survives (F3).
  - I also reasoned through these, and each is killed by an existing case or makes no difference to any result:
    - `resets` true for an empty set: `compact2`.
    - the pathspec dropped from `diff-tree`, so item documents are parsed as maps: c0010.
    - intersection instead of union in the join: `both`.
    - no `-r`, so a tree listing is parsed: c0010.
    - no memo, or a module-level memo: no observable difference.
- **Size 110.** 108 patch lines plus the header-sentence fix in F5. Experiments and specs are not counted.

### F1 [medium] The committed runner crashes where the executor runs it: once `ready` moves the folder to `issues/active/c0138`, `mutants.py` finds no acceptance folder, and step 1's path no longer exists
Where: `experiments/mutants.py` line 18 (`ACC = [d for d in (HOME/.tracker/issues/c0138/acceptance, HOME/tests/acceptance/c0138) if os.path.isdir(d)][0]`); Implementation steps 1 and 3 (`python3 z-nile/.tracker/issues/c0138/experiments/mutants.py`).
Evidence: in the clone I moved the issue folder to `z-nile/.tracker/issues/active/c0138`, the path `./zn find c0138` printed. Then:
```
$ python3 -I z-nile/.tracker/issues/active/c0138/experiments/mutants.py M4
  File ".../issues/active/c0138/experiments/mutants.py", line 18, in <module>
    ACC = [d for d in (...) if os.path.isdir(d)][0]
IndexError: list index out of range
$ python3 -I z-nile/.tracker/issues/c0138/experiments/mutants.py M4
... can't open file '.../z-nile/.tracker/issues/c0138/experiments/mutants.py': [Errno 2] No such file or directory
```
- `ready` rewrites paths only in `check.sh` (z-ready step 3), so neither the runner nor the steps follow the move. The runner works only before `ready` (backlog) and after `done` (promoted), and execution happens in neither.
- `check.sh` takes its folder from `$HERE` and passes from `active/` (4/4).
- The same hard-coded backlog path is in `pickman/.tracker/issues/active/c0153/experiments/mutants.py` (`A = ".tracker/issues/c0153/acceptance/"`), which is active now.

Critique: this is the second round in a row that finds a hole in "the executor can run the mutation check". Round 3 made the runner exist. It still doesn't run where execution happens. Steps 1 and 3 require it ("never skip it"). The executor must either edit an experiment file the Design says to run "as is", or skip a required step. The tempting fix is to add `issues/active/c0138/acceptance` to the list. That still hard-codes one more lifecycle folder, and a root move (c0114, c0120) breaks it again.

Consequences: a runner that finds its specs from its own location survives every move. It also brings a second risk that exists today. The user requires bounded commands, and the runner takes about 8 minutes. A bound shorter than that sends SIGTERM to Python. Python then exits without its `finally`, which leaves a mutant in the executor's uncommitted `trail.luau`. The runner prints the backup path only at the end, so the executor isn't told where the good copy is.

Recommendation:
- Make the runner find its acceptance folder from its own path: `os.path.join(os.path.dirname(os.path.abspath(__file__)), "..", "acceptance")`, falling back to `HOME/tests/acceptance/c0138` after `done`.
- Have it print the backup folder before the first mutant, and restore on SIGTERM and SIGINT (`signal.signal(..., lambda *_: (restore(), sys.exit(130)))`).
- In steps 1 and 3, name it as `python3 "$(./zn find c0138)/experiments/mutants.py"` (run from the repository root), with a bound of at least 900 s.
- Prove it in prep by running one mutant from a copy of the folder moved to `active/`, as above. Record that run in E5.
Lesson: z-design/instructions-runnable-where-they-run. Candidate for the lead: an experiment script finds its issue's files from its own location, because `ready` moves the folder and rewrites only `check.sh`. Check: run it from a copy under `active/`. Do the c0153 runner and every other `experiments/*.py` that hard-codes `.tracker/issues/<id>/` still run there?

### F2 [medium] Dropping the `c.doc` guard from the predicate this chore rewrites passes every spec, so a first-review lookup can be cut at a map commit that touched only the item's review
Where: Design, The rule ("…or at a later commit that changed a compaction map and the item's document (`since`)"); `prototype.patch`, `return c.doc and cutsId(c.sha)`; Rules and mutants (no row for "the document, not another file of the item"); the Problem ("capture and its first-review lookups").
Evidence: mutant NA replaces `return c.doc and cutsId(c.sha)` with `return cutsId(c.sha)`. Results:
- `kept`, c0111 `trail`, c0119 `capture-cli` and c0114 `trail-move`: 42 passed, 0 failed.
- Why it survives: `cmd.capture` calls `trail.read(kind, id, trailLib.isDoc, head)` (main.luau:5282). `keep` then admits only documents, so for every `capture` case `c.doc` is always true.
- Only a non-document reader is affected. kept.spec has one, the first-review case, and no cut commit there touches a review without the document.

Under NA, a map commit that names the id or does not parse, and that edits only the item's review, starts a life. A first-review lookup then loses the reviews before that commit. That is the cut the Problem asks to remove, on the path the Problem names.
Critique: the guard predates this chore and was never pinned. But this chore rewrites that very line and moves the decision into a closure whose comment reads "only for a commit that changed the item's document". An executor can easily believe the closure checks it. The tempting fix is a pure `since` case. It wouldn't see the closure in `read`.
Consequences: the case needs a cut commit that edits only a review of an item `read` is asked about with a review filter. Put it in `broken`: its nil answer resets anything the guard lets through. That is the intended kill, not a neighbour's, and it shifts no other row: M1 needs the document changed, and M5 and M8 leave `broken` naming nothing.

I built it in the clone's copy of `kept.spec`:
- in `broken`, add `` [`{P}/issues/c0010/design-review-001.md`] = "# Review 001\n\nit names c0300, edited\n" ``;
- in "finds a kept item's first review across the compaction", expect `` `{SHA.compact} M\n{SHA.broken} M\n{SHA.prep} A\nnotes 0\n` ``.

Results with that copy:
- the prototype passes 18/18;
- NA fails exactly that case;
- the runner's M1, M5, M6, M8 and M12 still die (9, 4, 12, 4 and 1 failures).
Recommendation:
- Make that fixture edit and update the expectation.
- Add a Rules row: "only a commit that changed the item's document starts a life; a cut that touches only another file of the item starts none | kept :: finds a kept item's first review… | M17 the `c.doc` guard dropped | run".
- Add M17 to `experiments/mutants.py` and rerun it once.
- In the first-review case's comment, say why `broken` edits the review.
Lesson: zz-test/pin-fail-safes-where-they-act. The guard acts only in `read` for a non-document filter, so it must be pinned there.

### F3 [low] The E5 join matrix leaves "can't be read, first" unseeded, and a mutant that skips only the retired map's failed read survives
Where: Unknowns E5 (the join matrix: "parses + can't be read, last (the submodule-entry commit)"); `kept.spec` gitlink commit.
Evidence: mutant NB, in `trail.renames`:
```luau
if not text then
	if file == ids.MAP_FILES[2] then
		continue
	end
	return nil
end
```
NB passes `kept`, c0111 `trail`, c0119 `capture-cli` and c0114 `trail-move` (42/42). The only unreadable file in the fixture is `z-nile/compaction.txt`, the current map, listed last. The decider-first-and-last lesson applies to the "unreadable" decider too.
Critique: NB is contrived, because it special-cases a file name. E5 names the matrix as the reference for future changes to the join, and this cell is missing from it. Reach on main is nil, because the two files never coexist.
Consequences: seeding the cell needs one more commit: a gitlink at `tracker/compaction.txt` beside a current map that parses, plus one `capture`, about 0.5 s. That is a fail-closed commit, so it goes after `dropped` and before nothing that pins "this commit's data alone".
Recommendation: either seed that commit and add its id to "restarts an item when a map file the commit changed can't be read" (add NB to the row's mutants), or mark the cell in E5 as reasoned: "unreachable on main since 05b058ea; M9c covers the skip in general". The second costs nothing and is honest.
Lesson: zz-test/any-rule-places-the-decider-first-and-last

### F4 [low] Step 1's drift trigger is not exhaustive: drift in `projects.luau`, in `main.luau` outside `cmd.capture`, or in both kinds at once falls in neither bullet
Where: Implementation steps, step 1 (the two bullets "`trail.luau`, `ids.luau`, `main.luau`'s `cmd.capture`, `z-nile/tests/lib` or one of the trail specs changed" and "**Only** `z-nile/skills/zz-rules` changed").
Evidence:
- `trail.read` calls `projects.at` and `projects.allRoots` (trail.luau, `read`), so `projects.luau` decides `read`'s roots. The diff command covers it (`z-nile/engine`), but no bullet names it.
- Most tooling issues edit `main.luau`. Drift there outside `cmd.capture`, plus the expected c0118 or c0121 rows in `zz-rules`, is neither "only zz-rules" nor bullet 1. The executor has to guess whether to apply the skill edits with `-3`.
Critique: z-design/instructions-runnable-where-they-run asks whether an executor can act without asking. The case is likely, because both siblings are in flight.
Consequences: none beyond the wording.
Recommendation:
- Make the bullets independent ("for each that applies").
- Add `z-nile/engine/projects.luau` to bullet 1.
- Add a third line: "any other drift: no rerun; the final `--full` covers it".
Lesson: z-design/instructions-runnable-where-they-run

### F5 [low] Lists typed from memory, stale counts and a header sentence the change makes less true
Where: Affected specs and E2 ("those that read `SKILL.md`: … ten …"); Regression guard ("`grep -rlF -e z-nile/engine/trail.luau …` and with the basename list only `c0114/layout.spec.luau` and the three above"); E6 and Scalability ("seventeen `capture` calls"); `kept.spec` header comment; the `trail.luau` header's last line ("Everything here is pure over texts except `read`, which runs git").
Evidence:
- `git grep -lE "zz-rules" origin/main -- z-nile/tests/acceptance` gives 16 files: c0048/board-docs, c0050/start-depends, c0052/skill-doc, c0057/open, c0081/skill-doc, c0082/cli, c0107/keep, c0111/skill-docs, c0114/docs, c0115/docs, c0115/layout, c0115/prompt, c0116/docs, c0119/scope-docs, c0120/docs and c0172/merge.
  - The Design's ten miss c0081/skill-doc, c0107/keep, c0115/docs, c0115/layout, c0115/prompt and c0116/docs. All six pass on the prototype (31/31), so nothing is overridden.
- `git grep -lF -e z-nile/engine/trail.luau` and `-e trail.luau` over both acceptance trees list nothing. The readers require `@znile/engine/trail` (c0114/layout) or `@scripts/tracker/trail` (c0111/trail, through the forwarder). The search as quoted does not produce the list it claims.
- `kept.spec` calls `capture(` 18 times (c0020 and c0004 twice each).
- Its header comment describes the fixture up to `again` only, and leaves out `broken`, `compact2`, `both`, `badold`, `badnew`, `dropped` and the gitlink commit.
- After the change, `trail.renames` runs git as well (and `trail.cuts` already did), so the header's "except `read`" is false twice.
Critique: z-design/lists-paste-their-search. The next prep that copies these lists starts short.
Consequences: the header sentence is in `trail.luau`. Changing it adds 1 line to the size, and `docs.spec` doesn't pin it.
Recommendation:
- Paste the two searches with their hits in Affected specs and the Regression guard.
- Fix the counts (eighteen `capture` calls).
- Extend `kept.spec`'s header comment to the whole fixture.
- Have the executor write the last header line as "Everything here is pure over texts except `cuts`, `renames` and `read`, which run git and only read" (add it to The new sentences).
Lesson: zz-review/lists-paste-their-search

### F6 [low] (repeat of design-review-003 F4) The sharpening of spec-design-correspondence's `check` is still not in the prep, and round 3 F1's candidate was not harvested where it was proposed
Where: `harvest.md` (002 F1 and 003 F4 → z-design/spec-design-correspondence; 003 F1 → zz-test/seed-every-enumerated-case only); `design-refute-003.md` F4 ("reported to the lead").
Evidence:
- `git status --short -- z-nile/skills` in the prep is empty.
- `z-nile/skills/z-design/lessons/spec-design-correspondence.md`'s `check` still asks only about "an older, stricter case", not a fail-closed neighbour commit.
- z-design step 5.3: "A finding that repeats a lesson the pass should have caught sharpens that lesson's `check`."
- Round 3's other candidate, "pin a join's fail-safe at the caller, per source position", was offered as a note on zz-test/pin-fail-safes-where-they-act. The harvest names a different lesson for 003 F1.
Critique: the refute moved the work to the lead, which is right for a subagent. But this harvest ships in the prep commit, and nothing yet holds the sharpening. Without it, the next linear fixture repeats 002 F1.
Consequences: none for the design.
Recommendation:
- Before the prep commit, the lead sharpens that `check` ("…not first by an older, stricter case or by a fail-closed neighbour commit in a shared fixture: remove the fail-closed commits; does each row's mutant still die?") with a c0138 design review 002 F1 note.
- Name zz-test/pin-fail-safes-where-they-act beside seed-every-enumerated-case for 003 F1.
- Then run `./zn lessons --check`.

## Lesson candidates (for the lead)
- **An experiment script finds its issue's files from its own path** (z-design/instructions-runnable-where-they-run, or a zz-test note). `ready` moves the folder to `active/` and rewrites paths only in `check.sh`. Check: does the runner run from a copy under `active/`? c0153's active runner has the same hard-coded backlog path (capture candidate).
- **A runner that edits tracked files restores them on SIGTERM** and prints its backup first, because the user's bounded wrappers kill long runs. Check: kill it mid-mutant: is the engine file restored?
- **A guard that only one kind of reader can reach is pinned through that reader** (a note on zz-test/pin-fail-safes-where-they-act). `capture` filters to documents, so the `c.doc` guard is visible only to a non-document lookup. Check: for each condition in a predicate, does some caller of the function reach both of its values?

Verdict: changes
