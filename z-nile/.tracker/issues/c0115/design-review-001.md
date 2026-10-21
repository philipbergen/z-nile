# Review 001: c0115 (design mode)
Inputs: `prep-c0115` at 0f79caf (`z-nile/.tracker/issues/c0115/{c0115.md,check.sh,acceptance/*,experiments/rename-lesson-ids.luau}`); capture (`./zn capture c0115`, fb7fd80) and its `Decided` lines from ab750c0 and 4c2b747 on main; the programme review `programme-review/c0115.md` (F1 to F12); `./zn lessons --when design --full` (27 lessons); c0120's design at prep-c0120 5a50a89 and its prototype `proto-c0120` (d6e36fa); the prototype `proto-c0115` at 46b4d8a (`z-nile/engine/skills.luau`, `main.luau`'s `cmd.skills`, `tests/lib/engine.luau`). Run: `z-nile/check.sh --full` on the prototype, GATE PASSED (pickman 1068, z-nile 982, 93.2 s, skills stage 0.5 s); `./zn check c0115` there, 11/12 (AC12 red for the right reason: R0034 active, and the stacked prep and prototype branches). Two probes in a scratch clone of the prototype under the scratchpad, never in the repository (F1, F2).

Scope (item 11): the title, Problem and Non-goals match the capture word for word. The Solution only gains a marked "(Added in prep)" block. Every Decided line (ab750c0, 4c2b747) has a Design section and a criterion. `z-raft` is drawn as planned, not made: c0116's capture says "Add `z-raft`", so this is c0116's scope, not a cut. No scope finding.
Guesses: G1 to G10 are reasonable, and none contradicts the capture or a decision. G1 is the decision's own example. G3 and G10 follow "zz-arch holds z-nile's tooling architecture rules (new …)". G4 agrees with the user's decision to re-prep R0030 and R0039. G9 leaves c0113 to the user.
Programme review: F1 to F12 each have an answer in the document's last section, and each answer is backed by the Design (checked against §1 to §10, the Overrides and AC1 to AC12).
Overrides (item 4): `affected` prints `ALL`. The 28 files the prototype changes under `tests/acceptance` and `pickman/tests/acceptance` match the 28 named in Overrides one for one, and the full gate is green with them.

### F1 [medium] An old lesson id left in skill text or a code comment passes every check, though §5 requires the new ids there
Where: §5 "Text" ("Skill text and lesson bodies that cite a lesson id use the new id"); `acceptance/absence.spec.luau` `scan`; `acceptance/lessons.spec.luau` "no harvest.md … and no lesson, names an old skill's id".
Evidence: in a scratch clone of the prototype I changed `publish.luau:362` back to `lesson architecture/guards-trust-only-origin` and appended `(lesson testing/no-vacuous-pass)` to `z-nile/skills/zz-test/SKILL.md`, then committed. `absence.spec` and `lessons.spec` passed (11 passed, 0 failed), and `./zn lessons --check` printed "ok". Why each check misses it:
- `scan` only matches the five ordinary words as `.claude/skills/<old>`, "`<old>` skill" or "<old> skill";
- `oldIds` only reads `harvest.md` files and lesson files;
- `lessons --check` doesn't read skill text or code.
The hyphenated old names (`ticket-prep/…`) are caught. `testing/`, `tracker/`, `review/`, `architecture/` and `metrics/` ids are not.
Critique: the tempting fix is to add `<old>/` to `scan`. That flags `tracker/next`, `tracker/compaction`, `scripts/tracker/…` and `tracker/issues`, which appear dozens of times in live code.
Consequences: the scan needs the rename script's own rule: a token counts as an old id only where `<new>/<slug>.md` exists. So the spec has to read the lesson folders first, and the scan stops being a pure text check.
Recommendation: add an absence case that collects every existing lesson `<new>/<slug>` from both skills folders. It then flags `<old>/<slug>` in any live file (`live()`, skills and `.md` included) wherever the mapped `<new>/<slug>` exists. The planted-text case must show it catches `architecture/guards-trust-only-origin` and `testing/no-vacuous-pass`, and leaves `tracker/next`, `tracker/compaction` and `scripts/tracker/x.luau` alone. Add a mutant row for it ("a skill keeps `testing/no-vacuous-pass`").
Lesson: ticket-prep/spec-design-correspondence

### F2 [medium] `./zn skills` follows a symlinked `.claude` or `.claude/skills`: it removed and wrote links outside the repository, and `--check` passes a committed `.claude/skills` link
Where: §4 (`skills.load`, `skills.apply`, `skills.trackedNonLinks`); prototype `z-nile/engine/skills.luau`. Also `layout.spec` ".claude/skills tracks one relative link per skill folder".
Evidence: setup, in a worktree of the scratch clone: I replaced `.claude/skills` with a link to a folder outside the repository that held one foreign link (`someone-elses-skill`).
- `./zn skills` printed `removed .claude/skills/someone-elses-skill` and twelve `linked` lines, and exited 0. The foreign link was gone from the outside folder, and the twelve links were written there.
- I then committed `.claude/skills` itself as a link (mode 120000, absolute target). `./zn skills --check` printed `skills: 12 skills, one link each, ok`.
- Why: `trackedNonLinks` rejects only modes other than 120000, and `layout.spec`'s regex `^%.claude/skills/[^/]+$` ignores a tracked `.claude/skills` path. The same happens with `.claude` as a link. A developer's `~/.claude/skills` is the realistic target: the "extra link" rule would delete every plugin or personal skill link in it.

Item 9 holds as asked:
- No spec or check run can reach this path. AC2 and the gate stage run `--check` only, which only reads.
- `skills.spec` runs the write mode only in its trackerfix worktree under `.cache/c0115-skills`, through `fixture.exec`.
- `lessons.spec` writes only `.cache/c0115-lessons-load`. `layout`, `absence`, `docs` and `readme` only read (`docs` runs `bash zn`, which prints the usage).
- The rename script is the executor's migration, not a check.

The finding is the command itself: a guard that fails open (zz-arch's own "**Guards fail closed.**").
Critique: the tempting fix is `fs.isDir` checks. Lune follows links, so `fs.isDir` can't tell a link from a directory (programme review F3).
Consequences: the refusal needs `readlink` (or `test -L`) on both `.claude` and `.claude/skills`. A tree with no `.claude/skills` yet must still work, because the fixture's first run creates it. `--check` also needs a new problem line.
Recommendation:
- `load` reports, and `apply` refuses with nothing written, when `.claude` or `.claude/skills` is a link.
- `trackedNonLinks` also reports a tracked `.claude/skills` or `.claude` entry of any mode, and any tracked path deeper than `.claude/skills/<name>`.
- Spec cases in `skills.spec`: a fixture whose `.claude/skills` links to a sibling folder under the same `.cache` fixture, holding a stray link. `skills` refuses there and the stray link survives, and `--check` fails on a committed `.claude/skills` link.
- Mutant rows for both cases.
Lesson: architecture/guard-no-is-explicit

### F3 [medium] AC12's freeze reads branches as of the last fetch, and nothing fetches first
Where: §9 "The freeze"; AC12; Implementation steps 1, 9 and 10.
Evidence: c0120 §8: "`busy` reads `origin/main` and the origin branches as of the last fetch (review 001 F8). It never fetches itself … So Implementation step 11 runs `./zn sync --fetch` just before `check.sh`, and AC16's label says it reads the last fetch." c0115 adopts the same command (G5: "the same rule as c0120's") but none of its steps fetches, and AC12's label claims "no branch or worktree changing them". Scenario: another session pushes a branch that edits `z-nile/skills/zz-rules/SKILL.md` after the executor's last fetch, and AC12 passes at `done`. The c0115 merge then conflicts with that branch, which is what the freeze exists to stop.
Critique: the tempting fix is to fetch inside AC12. c0120 found the ref guard refuses a fetch from a `check.sh` that has nothing new.
Consequences: none beyond c0120's: the fetch is a step, not a check.
Recommendation: steps 1, 9 and 10 run `./zn sync --fetch` just before `./zn busy` and `check.sh`. AC12's text and label say "as of the last fetch", as c0120's AC16 does.
Lesson: architecture/lock-reads-live-state

### F4 [medium] The design is measured on c0120 at 080d247, but c0120 has since changed the very files c0115 splits and overrides, and the document gives no rebase rule
Where: Design intro ("on c0120's prototype `proto-c0120` at 080d247"); §2; Overrides (c0120/docs, c0120/homes); E3; Size; Verification log.
Evidence: `git diff --stat 080d247 proto-c0120` (now d6e36fa, c0120's review 002 home fence) touches:
- `.claude/skills/testing/SKILL.md`: the Protected writers and a long new Fence bullet;
- `c0120/acceptance/docs.spec.luau`: four new pinned phrases in the testing skill;
- `homes.spec.luau` (+164 lines), `check-paths.spec.luau`, `layout.spec.luau` and `check.sh`;
- `ac.sh`, `fence.sh`, `tests/lib/fence.luau`, `cachepaths.luau` and `repo-fence.spec.luau`.

c0115's prototype has none of this. So these claims hold only for a c0120 that no longer exists:
- §2's byte-for-byte split;
- E3's "every pinned phrase is found by plain find in its new file";
- the c0120/docs and c0120/homes overrides;
- the measured size.

c0120 is still in review (review 003), so it may change again.
Critique: the tempting answer is "rebase later". With no list, the executor (or the next prep round) won't know which c0115 claims depend on c0120's open guesses.
Consequences: the list itself becomes something a rebase must keep up to date.
Recommendation: record the c0120 revision that c0115 was measured on, and add a "Rebase on c0120" step (Implementation step 1, and before the next review round) that rechecks:
- (a) the final testing-skill text against §2's split (the Fence bullet and the Protected writers go to `zz-test`);
- (b) the c0120/docs override, its phrases found in `zz-test`;
- (c) the c0120/homes override against the final `homes.spec`;
- (d) c0120 Guess 11 (fixtures keep `tracker/` as pickman's root through `engine.REGISTRY`), which `prompt.spec`'s pickman raft relies on;
- (e) c0120 Guess 7 (c0120's specs promote to the root), which the simulation and override paths rely on;
- (f) that `pickman/tests/meta/fence.spec.luau` exists (AC10), and c0120's check-paths exemptions (Touched modules, and R0030/R0039 by content);
- (g) `--plan`'s output and `par_start` stage syntax (AC2's exact lines);
- (h) `./zn busy`'s path and current-branch semantics (AC12);
- (i) the `projects` API that `skills.luau` and the specs call (`parse`, `legacy`, `projectOf`);
- (j) c0120's own edits to the tracker skill's lists, which §4 extends.

Then rerun M1 to M34 and the full gate, and regenerate the patch.

### F5 [low] `prototype.patch` is said to sit beside the document, but it doesn't, and two internal references are wrong
Where: Design intro; §1 table.
Evidence:
- "`prototype.patch` beside this document is `git diff -M proto-c0120` …": `git ls-files z-nile/.tracker/issues/c0115` lists no patch. The prototype is a local-only branch.
- "It has four kinds of commit:" lists three.
- §1's `ticket-prep` row says "`checklists/` (§6)"; the checklists are §7.
Recommendation: commit `prototype.patch` with the prep (or drop the sentence), say "three kinds", and fix the section reference.

### F6 [low] Rules-and-mutants rows are missing for four stated behaviours, and one of them has no spec case
Where: §4 (`--check` "only reads"; "a plan problem fails either form, writes nothing"; "A second run prints no `linked` or `removed` line"); §5 ("A lesson whose skill has no `SKILL.md` reports `<id>: no skill <s> (no <s>/SKILL.md in any skills folder)`"); Rules and mutants.
Evidence: `skills.spec` has cases for the first three, but the table has no rows for them (mutants: `--check` falls through to `apply`; `apply` despite problems; links re-made every run). The fourth message has no case in `lessons.spec` at all.
Recommendation: add the three rows, and a `lessons.spec` case for the new message with a row (mutant: the old `.claude/skills` wording).

### F7 [low] `readme.spec` checks only quoted `["…"]` labels, so a built-looking node in another mermaid shape escapes the planned rule
Where: `acceptance/readme.spec.luau` "every z- and zz- skill in the picture exists, or its node says planned". §7.
Evidence: the loop iterates `'%["([^"]+)"%]'`. A node `R[z-raft]` or `R(z-raft)` is never examined. The literal `z-raft (c0116, planned)` is still pinned elsewhere in the block, so a second, unlabelled `z-raft` node passes. `seen >= 10` doesn't stop it either.
Recommendation: either require every node line in the block to use the quoted form (one case), or scan every `z-…`/`zz-…` token in the whole block against the line it sits on.

### F8 [low] c0116, c0117 and c0118 must override c0115's promoted `readme.spec`, and §10 doesn't say so
Where: §10; `readme.spec` pins `z-raft (c0116, planned)`, `dispatcher (c0117, planned)`, `.models.toml (c0117, planned)`, `c0118, planned`.
Evidence: when c0116 adds `z-nile/skills/z-raft`, the pinned planned label goes stale. c0116 must then change `tests/acceptance/c0115/readme.spec.luau`. §10 names only "adds `z-nile/README.md` to its Touched modules".
Recommendation: §10 names the override for each of the three, so their `Overrides:` lines list `tests/acceptance/c0115/readme.spec.luau`. They are chores, so the override is theirs to make.

### F9 [low] JC1 is mechanical and could be a Checked criterion
Where: JC1.
Evidence: the rubric's every test is a git read: the move commit's subject; only `R100` lines under `git show -M --find-renames=100% --name-status`; no other commit moving a skill file. All of this can be computed over `origin/main..HEAD` before landing.
Recommendation: make it AC13, as a check line. It finds exactly one commit in `origin/main..HEAD` with that subject, asserts its `--name-status` lines are all `R100`, and asserts that no other commit in the range has an `R` entry under the skills folders. Keep the reviewer's judgment only for "reviewable".

## Lessons
Candidate (for the lead, not written by the reviewer). zz-test: an absence scan for renamed ids covers every form the id takes in live text, filtered by the new name's existence rather than by a word list. Why: F1, where `testing/<slug>` in a skill survived both scans. Check: "For each renamed identifier, does some spec fail when one old occurrence is left in each kind of live file (skill text, code comment, ledger), without flagging look-alike paths?"

Verdict: changes
