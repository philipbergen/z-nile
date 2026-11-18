# Review 002: c0156 (design mode)
Inputs: prep worktree `prep-whole-file-pins-keep-newlines` at 0d4323b4 with the uncommitted prep files (sha256 prefixes: `c0156.md` f112306a, `check.sh` e199c2df, `acceptance/consumers.spec.luau` 65ad464d, `docs.spec.luau` ea499d63, `pin.spec.luau` b5258341, `record.spec.luau` 9e00a8fb, `experiments/mutants.py` d491de1e, `prototype.patch` 2eb7ac14, `E9-comment-ends.luau` 97ef8127), `design-review-001.md`, `design-refute-001.md`, `harvest.md`, and `./zn capture c0156` (capture 3bf887d6). origin/main is now e91f0cf5. All eight base blobs the Design lists are still the same there (`git rev-parse --short=8 origin/main:<path>` against 0d4323b4). The prototype is the throwaway clone `…/tmp.fipPiC5Jjp/proto`, whose tree holds `prototype.patch` and the acceptance folder. Every run below was made there, with `PICKMAN_FENCE_REAL_GIT` set and a time limit, and every edited file was restored afterwards (`cmp` with the saved copy; `git status --short` unchanged, 10 entries).
Runs: weakened-pin runs (F1); an in-process kill-check probe (F1); three guard-condition mutants and the guard removed, against `record.spec` (F2); `mutants.py … weak-compare-f0024 vf-collapsed delete-f0024-assertion crlf-f0024` (OK); an id-mask scan of the three pinned files (it masks only real item ids: no finding); the in-flight branch search over the Touched modules (only `impl-c0117`, `impl-c0118` and `impl-c0121`, each adding one line to `zz-test/SKILL.md`, as Existing work says); a search for spec readers added on main since the base (only `c0114/docs` and `c0120/docs`, already among the 18, and a comment in c0164's `walls.spec`).
Round 001 answers checked: F2, F3, F4, F6, F7 and F8 hold as fixed. F5 holds for the ported guards, but its new refusal case leaves each guard condition unpinned (F2 below). F1's fix closes c0103's pin but not golden's two files (F1 below).

### F1 [high] check.sh still passes a golden.spec that pins nothing for either of its files (repeat of design-review-001 F1)
Where: `acceptance/consumers.spec.luau` ("decides through one exactly function": `has(text, "local function exactly")` and `has(text, ")).toBe(false)")`, each satisfied once per spec file); `check.sh` AC2 and AC3; c0156.md Observed paragraph; Rules and mutants row "a pin's verdict goes through one comparison that its mutant cases also call".
Evidence: I made two edits to the prototype's `golden.spec`:
- `exactly24` became `return #pin.digest(text) == #D24`;
- the f0024 mutant case ("f0024: a line joined onto the comment above it, or a deleted assertion …") was deleted.

Then I deleted `t.expect(updates).toBe(6)` from `f0024/adapter.spec.luau`. Results:
- `golden.spec` and `narrowed.spec`: `8 passed, 0 failed`.
- `golden.spec` on the mutated f0024: `4 passed, 0 failed`.
- `consumers.spec` and `record.spec`: `10 passed, 0 failed`.

The f0026 half has the same hole: with `exactly26` weakened the same way, its mutant case deleted and `t.expect(#w.reads).toBe(0)` deleted from `f0026/adapters.spec.luau`, `golden.spec` gave `4 passed, 0 failed` and `consumers.spec` `5 passed, 0 failed`. In both cases `consumers.spec` stays green because the other file's case still supplies `)).toBe(false)`, `pin.joined(` and `local function exactly`. AC6 runs the same golden.spec. So `./zn check c0156` is 6/6 with an unpinned f0024 or f0026. "A comment-join mutant for each pinned file … killed on an assertion" (Solution), "killed by each" (Problem), is then again proven only by `mutants.py`, a prep run and step 6. c0103's pin is held: it has one file, and `consumers.spec` requires its `pin.joined(` call.
Critique: this is the second hole in one mechanism. The verdict lives in the executor-editable pin, and the check that it is wired is a text probe the spec satisfies as a whole. The tempting fix, a probe per file (`exactly24(pin.joined(`, `exactly26(pin.without(` …), still lets a case be wrapped in `if false then` or asserted on the wrong function. The Observed paragraph says the clone kill "is not a check (a check cannot edit the pinned files, and a nested clone run would not see the executor's uncommitted tree)". That reason does not hold for a check that serves the mutated file in memory.
Consequences: a behavioural check from outside the pin, as below, brings these:
- A rule on what the pins may require (it must supply each module).
- A rule on what counts as a kill: the digest verdict's own assertion, not a helper raise. Under the weakened golden, my join probe "failed" only because golden's CRLF case raised `no line ends in the comment`.
- It reads pickman's files from a z-nile item, so it goes in check.sh, not in a promoted spec (F3).

Recommendation: question the mechanism, not the hole. Add a Checked criterion (AC7, "each pin's own verdict rejects every join and deletion mutant of each of its pinned files, and accepts each file and its CRLF form"). Implement it as a check.sh-only script, `acceptance/kills.luau`, run by `check "AC7: …" lune run "$A/kills.luau"`. It is not a `*.spec.luau`, so the gate never runs it after `done`: the c0114 `finished.luau` pattern. The script:
- reads each promoted pin's source and loads it with `@lune/luau` `luau.load(src, { environment = { require = <map> } })`. The map serves `@tests/lib/pin`, `@tests/lib/renamed` and `@tests/lib/t`, plus an `@lune/fs` whose `readFile(path)` answers one pinned file mutated. Any other require raises `the pin requires <name>: kills.luau supplies only …`. I ran this shape on the prototype as a throwaway spec: on the real golden.spec it found 0 failing cases, and the f0024 deletion made 3 cases fail. On the weakened golden above, it went red.
- runs every case with `pcall`, for each of these mutants of each pinned file: the record's `--joins` entries (one for f0014, one for f0024, two for f0026) and the Design's three deletions. For each mutant it requires at least one failure whose message is `expected true, got false`. A `no line ends in the comment` or `no "…" to delete` raise does not count as a kill.
- runs the same cases on each file as it is and on its CRLF form, and requires that none fails.

Add Rules rows: `weak-compare-f0024-no-case`, `weak-compare-f0026-no-case` (the two edits above), and `kill-by-helper-raise` (a kills.luau that counts any failure). Each needs a case that kills it. Rewrite the Observed paragraph to say AC7 checks the kill, and that step 6's clone runs stay as a cross-check. This replaces the once-per-spec `consumers.spec` probes as the proof that the verdict is wired; `consumers.spec` keeps only "the rule lives once". If loading the pin spec this way proves impractical, the fallback is a check.sh rule-form `grep -qF` per file, which is weaker as said above. Each needle must be a name the Design gives: `return pin.digest(text) == D24` / `D26` / `DIGEST`, and `exactly24(pin.joined(`, `exactly24(pin.without(`, `exactly26(pin.joined(`, `exactly26(pin.without(`, `exactly(pin.joined(` and `exactly(pin.without(`, each with `)).toBe(false)`.
Lesson: zz-test/narrowing-pins-the-whole-file

### F2 [medium] The record's refusal case passes with any one of its guard conditions removed, and its `reasoned` reason is false
Where: R0045's `mutants.py` as the patch leaves it (`if root.name != 'pickman' or tmp not in clone.parents or not (clone / '.git').is_dir() or (clone / '.worktree').exists()`); `record.spec` "refuses a folder that is not the pickman home …"; Rules row "the record refuses a folder … | reasoned: … the script was not run unguarded (it would edit tracked files)".
Evidence: the case's only input is `<z-nile>/.cache/c0156-record/pickman`. That input is outside the temp folder and has no `.git`, so it fails two conditions at once. On the prototype I removed one condition at a time, then ran `record.spec`:
- `tmp not in clone.parents`: `5 passed, 0 failed`;
- `(clone / '.worktree').exists()`: `5 passed, 0 failed`;
- `not (clone / '.git').is_dir()`: `5 passed, 0 failed`.

Each condition alone is the one that refuses some real path. The temp check refuses a second plain clone outside the temp folder. The `.worktree` check refuses the main checkout under a `TMPDIR` that contains it. The `.git` check refuses a worktree under the temp folder. There is also no accept side: a guard that refuses everything passes the case. Removing the whole guard, which the row calls unrunnable, ran harmlessly against the fixture: the script fails to read the missing file and writes nothing, and the case went red (`expected true, got false`). So the row could have been `run`.
Critique: the tempting fix is a second refusal input. Every input under `.cache` fails the temp check first, so no such input can isolate the other conditions.
Consequences: isolating each condition needs a fixture that counts as "under the temp folder". That is a new piece of fixture state, and the accept side must not reach anything real.
Recommendation: run the record with `TMPDIR` set to a unique `z-nile/.cache/<name>/tmp` fixture (`tempfile.gettempdir()` honours it in the child), and add one case per condition plus an accept case:
- `<tmp>/a/pickman`, where `a` has a `.git` directory and a `.worktree`: refused;
- `<tmp>/b/pickman`, where `b/.git` is a file (a worktree): refused;
- `<tmp>/c/home`, named other than `pickman`: refused;
- the current outside-temp input: refused;
- `<tmp>/d/pickman`, where `d` has a `.git` directory and no `.worktree`: not refused. Its stderr lacks the refusal text, the script stops at its first missing file, and the fixture lists only what the case made.

Mark the guard rows `run` with the four condition mutants and a refuse-everything mutant. Per F3, these cases run from a check.sh script, not a promoted spec. The writes stay under `.cache`, and the review confirms that, since check.sh has no jail.
Lesson: zz-test/guard-needs-its-own-case, zz-test/refusals-tested-on-both-sides, z-design/reasoned-rows-claim-testable-reasons

### F3 [medium] Two of c0156's z-nile acceptance specs pin pickman's files, so a pickman-only change turns z-nile's gate red unselected
Where: `consumers.spec` reads `pickman/tests/lib/pin.luau` and both pickman pin specs; `record.spec` runs and reads `pickman/.tracker/rafts/done/R0045/experiments/mutants.py` and reads `pickman/tests/acceptance/{f0014,f0024,f0026}/…`. Both are promoted to `z-nile/tests/acceptance/c0156/`.
Evidence: the lesson `zz-test/specs-pin-only-their-own-project` landed on main in 04571dee, after this prep's base 0d4323b4, so the round's lessons pass could not see it. The executor's base will have it. Its check asks: "Does any sequestered spec read a file of another project …, so that an edit there turns this project's gate red without the selector picking it? Is that check in check.sh instead?" Here is the concrete failure:
- A later narrowing of f0024 or f0026 (Existing work names d0124's prep over those files) rewords the per-player or reads comment line.
- z-nile's promoted `record.spec` then fails `count(src, j.old) == 1`.
- The diff is pickman-only, so `--affected` selects no z-nile spec. The red first shows in the next full run. The fix is then a chore that edits a promoted z-nile spec or a done raft's record.

`consumers.spec` breaks the same way on any rewrite of the pickman pins, for example a renamed `exactly24`.
Critique: the tempting fix is to leave the specs and note the risk. The lesson's rule is the opposite, and pickman's own promoted pins hold the files after `done` anyway.
Consequences: moving the checks into check.sh means they run once, at `done`. They then run unjailed, as check.sh commands are, so they must only read, apart from F2's `.cache` fixture, and review must confirm that.
Recommendation: keep `pin.spec` and `docs.spec` as promoted specs; they read only z-nile's files. Turn `consumers.spec` and `record.spec` into check.sh-only scripts, `acceptance/consumers.luau` and `acceptance/record.luau`, each run as `lune run "$A/<name>.luau"` (the c0114 `finished.luau` pattern), together with F1's `kills.luau`. Keep AC2's and AC5's labels, and rerun `./zn promote-check c0156`. Rebase the prep onto current main (the base blobs still match at e91f0cf5) and rerun the lessons pass on it.
Lesson: zz-test/specs-pin-only-their-own-project

### F4 [low] Two implementation steps can't run as written
Where: step 2, `cd z-nile && lune run tests/run -- tests/acceptance/c0156/pin.spec.luau`; step 6, "In a throwaway clone … `git clone --no-hardlinks` …".
Evidence: before `./zn done` the spec is at `.tracker/issues/active/c0156/acceptance/pin.spec.luau`, and `tests/acceptance/c0156/` doesn't exist yet. A clone carries only committed work, and no step before 6 commits. With the patch uncommitted, the clone has no `z-nile/tests/lib/pin.luau`, and `mutants.py` stops with a traceback on its first read.
Recommendation: name the active path in step 2. Start step 6 with "commit (`./zn commit`), then clone the worktree's HEAD".
Lesson: z-design/instructions-runnable-where-they-run

### F5 [low] Two restatements of the tolerated list are off
Where: `pin.luau`'s doc comment in the patch ("tolerates exactly four things" followed by four bullets and a fifth item, the outer blank lines); c0156.md AC1 ("keeps every line break (blank lines, the breaks after comments, `\v`/`\f` joins included)").
Evidence: by E9 a vertical tab and a form feed are not line breaks. The rule keeps them as they are, so the parenthesis puts them on the wrong list. `check.sh`'s AC1 label doesn't mention them.
Recommendation: drop the count from the doc comment, or make it "five". Reword AC1 as "keeps every line break, and keeps `\v` and `\f` as they are (neither a space nor a break)", and keep the label and the doc comment in step.

### F6 [low] Round 001's F1 lesson was mapped, not learned
Where: `harvest.md` ("design-review-001 F1: zz-test/narrowing-pins-the-whole-file"); that lesson's `check`.
Evidence: round 001's F1 was "a pin whose comparison is weakened still passes check.sh", and its reviewer proposed the question "weaken the pin's compare: does any Checked case go red?". The lesson's `check` asks about joins, string spaces, a join mutant and raw reads, but never this, and the harvest added only a source. This round's F1 is the same defect, which that question per file would have caught. Any later whole-file pin (c0153's and c0159's exact pins too) can fail the same way.
Consequences: the lesson is one of this issue's *document* bases (`ed43a849`), and the patch edits its body. Sharpening its frontmatter in prep moves that blob.
Recommendation: add to the lesson's `check`: "For each pinned file, weaken its comparison and delete its own mutant case: does a check.sh check go red, through the pin's own verdict run from outside the pin?". Regenerate `prototype.patch` on the new lesson blob, and update the blob in Base blobs. `docs.spec`'s needles are body sentences and are unaffected.

Verdict: changes
