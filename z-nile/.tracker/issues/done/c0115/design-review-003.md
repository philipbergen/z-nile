# Review 003: c0115 (design mode)
Inputs: `prep-c0115` at 1baacaa; `design-review-002.md`, `design-refute-002.md`, round 001 skimmed, `harvest.md`; `c0115.md`, `check.sh`, `acceptance/*`, `experiments/rename-lesson-ids.luau`; `z-nile/engine/skills.luau` and `lessons.luau` on the prototype `proto-c0115` at b6f5caa (on `proto-c0120` b7e75b9); `./zn capture c0115` (fb7fd80); `./zn lessons --when design --full`. Everything ran in a scratch clone of the prototype under the scratchpad (`c0115-review003/ov`), never in the repository: the prototype's lessons removed, the prep tree's 34 lessons laid into their new folders, its five `harvest.md` ledgers and the review/refute files they cite copied in, the prep's issue folder copied in.
Dropped from review-002: F1 to F4 (fixed, checked below).

Re-review of round 002:
- F1: fixed as the refute says. `skills.oldLessonIds`, `renameLessonIds`, `oldNames` and `renameOldNames` are the one rule, called by the script, `absence.spec` and `lessons.spec`. On the overlay the script made 204 rewrites (exit 0), a second run 0. Then `./zn lessons --check`: "34 lessons, 179 harvest entries, ok"; `--uncovered R0040 R0042 c0115`: covered; `./zn skills --check`: "12 skills, one link each, ok"; AC3 (7 cases), AC4 (6) and AC5 (9) pass. The whole `check.sh` there: AC1 to AC10 and AC13 pass; AC12 is red for the known reason; AC11's red is my overlay's (c0120's review files copied into a backlog folder beside the simulation's `done/c0120`), not the design's.
- F2: fixed. AC2 clones with `git clone -q --no-hardlinks "$PWD"` into `$PWD/.cache/c0115-ac2` (ac.sh has cd'd to the root), runs `--check` and `--plan` in a subshell inside the clone, and asserts the ok line and a clean `git status`. The clone has its own `.git`, so nothing it runs resolves to the real checkout; a failed clone leaves no `.git`, and git's walk up stops at the fence's ceiling (`<root>/.cache`). The clone only reads its source. `ZN_ROOT`, which ac.sh exports, is read by nothing in `zn`, the engine or the gate. The fence's hooks and `GIT_CONFIG_*` reach the clone, and they guard the real repository, not the clone. Under M37 the write lands in the clone and fails the ok line.
- F3, F4: fixed (the stack in §11, the counts, the lesson reworded, §5's Text rule).
- Scope (item 11): the capture is unchanged; the title, Problem and Non-goals match; the Solution gains only the marked prep block and `Decided` lines. G1 to G11 are as before.
- Overrides (item 4): since 3854e30 only this item's folder and two testing lessons changed, so the count stands.

### F1 [medium] AC5 and the rename script treat a whole `harvest.md` as ids, so ordinary prose in a valid note or one-off turns the promoted AC5 red and makes the script exit 1
Where: `acceptance/lessons.spec.luau` case "no harvest.md under any root, and no lesson, names an old skill's id" (it calls `oldIds(fs.readFile(path), existing, ledger)` on the whole file); `rename-lesson-ids.luau` `fix(p, true)`; `skills.oldLessonIds` ledger mode; §5 ("In a ledger every token counts, since an entry is always an id").
Evidence: on the overlay clone I appended a valid entry, `- note c0115 prep: a spec wrote under review/x in the old layout: zz-test/no-vacuous-pass`.
- `./zn lessons --check`: "34 lessons, 180 harvest entries, ok". The format's own reader (`lessons.parseHarvest`) accepts it.
- AC5: `FAIL … old lesson ids: z-nile/.tracker/issues/c0115/harvest.md: review/x`.
- The script (`--dry-run`): "old ids with no lesson at the new place: review/x", exit 1.
- A one-off reason works the same way (`one-off: a stale review/round link` is reported). The premise "an entry is always an id" is false: a note's text and a one-off's reason are free prose, and leads write them every round. A prose path such as `tracker/rafts/R0010`, `testing/fixtures` or `review/x`, after a space or a backtick, is enough.
Critique: this is the third hole in the old-id mechanism (round 001 F1, round 002 F1). Each round has narrowed the regex instead of asking what an id is. The tempting fix is another exclusion for a following word, or a list of known look-alikes. That would be the fourth narrowing. The format already has one reader, which knows exactly which tokens are ids.
Consequences: ledgers get two parts. The parsed lesson ids (`parseHarvest`'s `entry.lessons`) are always ids, so every old one counts. The note text and the one-off reason are prose and take the prose rule. A line `parseHarvest` refuses is already a `lessons --check` failure (AC6), so the scan doesn't have to judge it. The script renames ids by span in the parsed id list and prose by the prose rule, and it reports only parsed ids.
Recommendation:
- Ledger mode applies only to the ids `lessons.parseHarvest` returns. `skills.oldLessonIds` in ledger mode takes the parsed entries (or the text and the entries), and prose mode runs over each note's text and one-off reason. The script, AC4 and AC5 keep calling that one function.
- Planted cases in `lessons.spec`: a ledger whose note text names `review/x` and `tracker/rafts/R0010`, with valid ids, passes AC5's rule and the script (exit 0, nothing rewritten); a one-off reason naming `testing/fixtures` passes; an entry whose id list holds `testing/gone` is reported; `testing/no-vacuous-pass` in a note's id list is renamed.
- Add a mutant row: ledger mode over the whole line again (killed by the note case).
- Rerun E4's overlay after the change.

Lesson: architecture/one-reader-per-format, testing/one-rule-one-function

### F2 [low] The script's new lesson-body name rename rewrites examples and half-renames prose, the defect round 002 F4 fixed only for ids
Where: `rename-lesson-ids.luau` (`skills.renameOldNames` on every lesson body); §5 "Text"; the overlay's diff.
Evidence (from the overlay run):
- `testing/lessons/plain-find-for-literals.md`: "`string.find(s, "make-issue")` do not match the text they name" becomes `"z-ticket"`. In Lune, `string.find("make-issue","make-issue")` is `nil`, but `string.find("z-ticket","z-ticket")` is `3 8`. The example now finds a match, the opposite of what it was chosen to show. AC4 forbids putting the old name back.
- `ticket-prep/lessons/instructions-runnable-where-they-run.md`: "a prep author reads ticket-prep and testing" becomes "reads z-design and testing". The hyphenated name is renamed, but the bare word isn't one of §8's forms.
Recommendation:
- Reword the plain-find lesson's example with a literal that names no skill (for example `"a-b.c"`).
- Fix "z-design and testing" by hand.
- Widen §5's Text rule from ids to names: a lesson body that quotes an old name as an example or as history says it in words.
- Implementation step 5 says to read the script's lesson-body diff line by line after every run, since lessons keep arriving.

Lesson: ticket-prep/bulk-renames-skip-ordinary-words

### F3 [low] The stack moved again after the measured base: `proto-c0120` is now 0c3b4f3, not b7e75b9
Where: Design intro ("`prototype.patch` … is `git diff -M proto-c0120`"); §11.
Evidence: `git log b7e75b9..proto-c0120` shows 0c3b4f3, a rewrite of c0120's edits commit. It changes `z-nile/lib/fence.sh`, `tests/tooling/repo-fence.spec.luau` and `tests/tooling/fence-inherited-env.spec.luau`. c0115 edits comments in the first two (§8). `prototype.patch` still matches `git diff -M b7e75b9` exactly, but the intro's literal command (`git diff -M proto-c0120`) now gives a different diff.
Recommendation: name the base by sha in the intro (`git diff -M b7e75b9`). Then either rebase onto 0c3b4f3 under §11 now, or leave it to Implementation step 1, which already reruns §11. Either way, say which.

Verdict: changes
