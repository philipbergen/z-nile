# Review 001: c0156 (design mode)
Inputs: prep worktree `prep-whole-file-pins-keep-newlines` at 0d4323b4 with the uncommitted prep files (`c0156.md` sha256 b7429c84…, `check.sh` 7cc5e46f…, `acceptance/{pin,consumers,docs,record}.spec.luau`, `experiments/{mutants.py,prototype.patch}`); `./zn capture c0156` (capture 3bf887d6); origin/main 04571dee (every base blob in the Design still matches it); R0045's records (`R0045.md` line 38, `review-002.md`, `refute-002.md`), which confirm the `Decided with the user (2026-10-25)` line. Prototype: the throwaway clone `…/tmp.fipPiC5Jjp/proto`. Every run below was made there, with `PICKMAN_FENCE_REAL_GIT` set and a time limit, and every edited file was restored afterwards (`git status` showed the same as before).
Runs: the four c0156 specs (23 passed) and both pins (7 passed); `mutants.py … collapse-newlines comma-rule-any-blank-run joined-second-occurrence join-f0024-perplayer-comment id-mask-any-letter crlf-f0024` (OK); 11 skill and lesson readers the Design did not list (72 passed, F8); a Luau lexer probe (F3); two `\v`/`\f` mutants (F3); the weak-pin runs (F1); the runner on the `active/` path (F2).

### F1 [high] check.sh passes with pins that pin nothing, so "a comment-join mutant is killed by each" has no Checked criterion
Where: c0156.md Acceptance criteria (AC2, AC3, "Observed: None. The kill … is proven in prep (E1, E6) and again by the executor's step 6"); `check.sh` AC3; Implementation step 6.
Evidence: on the prototype I made four edits at once:
- `narrowed.spec`'s "exactly the narrowed one" became `t.expect(#pin.digest(fs.readFile(FILE))).toBe(#DIGEST)`;
- `golden.spec`'s f0024 case became the same length compare;
- f0014's `t.expect(n >= 4).toBe(true)` was deleted (the `delete-f0014-assertion` mutant);
- f0024's comment line was joined (the `join-f0024-perplayer-comment` mutant).

Result: `narrowed.spec` and `golden.spec` gave `7 passed, 0 failed`, and `consumers.spec` gave `5 passed, 0 failed`. AC1, AC4 and AC5 never read the pins' assertions, and AC6 runs these same two pins, so `./zn check c0156` is 6/6 for this implementation. AC3 is also green on `main` (E8), where E1 shows the hole is open. So no check can tell a closed pin from an open one. The join cases don't fill the gap either:
- c0103's two join cases go red on a joined file only because `pin.joined` raises when its own header line is gone. They do not go red because the pin compares anything.
- golden's join cases compare `pin.digest(joined)` with `pin.digest(src)`, which tests the rule, not the pin.

The captured outcome "a comment-join mutant is killed by each" (and the Solution's "killed on an assertion") therefore rests on a prep experiment and on a hand-run step whose result only the Verification log records. zz-test allows Observed only for Studio playtests, and this outcome is measurable.
Critique: the tempting fix is a source probe in `consumers.spec` for `.toBe(DIGEST)`. That pins a spelling, not the behaviour, and a pin that compares the wrong file or the wrong constant would still pass (zz-test/source-pins-name-what-the-design-names).
Consequences: a behavioural kill check needs the pins to run against mutated pinned files without touching the repository. The pins read their files by home-relative paths, and the runner runs only from a project home. A check that does this costs a fixture and some run time.
Recommendation: add a Checked criterion (say AC7, "each pin goes red on an assertion for its comment-join and deletion mutants, and stays green on the CRLF variant"), using one of these:
- **(a) Behavioural.** A sequestered spec (or a `check` command) clones the tree into a unique `pickman/.cache/<name>` through `@tests/lib/clone`, applies each mutant from R0045's record to the clone's pinned file, and runs the clone's runner on both pins from its pickman home. It expects a `FAIL` on the digest case, not on a `could not load` line. Make this a pass/fail experiment first: does a nested run from a `.cache` clone work, and how many seconds does it take?
- **(b) Fallback if (a) is too slow.** Restructure each promoted pin so that every verdict goes through one local function per pinned file, `exactly(text): boolean`, comparing `pin.digest(text)` with that file's constant. The "exactly" case asserts `exactly(file)`. The join and deletion cases assert `not exactly(<mutated file>)`, with the mutation built in memory. Then any weakening of the comparison turns a join case red, and AC3 kills the mutants on its own. Golden's join cases must stop comparing against `pin.digest(src)`, and f0024 needs a join case of its own (today only the digest case guards it).

Under either option, add the rows to Rules and mutants and re-run E6.

### F2 [medium] Step 6 cannot pass as written: c0156's `mutants.py` names the backlog path, which is gone once the issue is readied
Where: `experiments/mutants.py` line 30, `UNIT = ("z-nile", [".tracker/issues/c0156/acceptance/pin.spec.luau"])`; Implementation step 6 ("31 killed, 6 green").
Evidence: `./zn ready` moves the issue to `z-nile/.tracker/issues/active/c0156/` (as with `./zn find c0117` → `…/issues/active/c0117`). In the executor's clone, the runner fails the path the script names. Run on the prototype with the `active/` path: `FAIL .tracker/issues/active/c0156/acceptance/pin.spec.luau: could not load spec: … could not resolve child component "c0156"`. In the executor's clone it is the backlog path that is gone, so all 24 rule mutants report `load error`, and the step's expected "31 killed" can't be met. The executor is then tempted to edit the script, or to skip the step that F1 shows is today's only proof of the kills (z-design/instructions-runnable-where-they-run).
Critique: hard-coding `active/` instead breaks the prep-time run.
Consequences: none beyond the script.
Recommendation: resolve the spec path from the script's own location (`here.parent / "acceptance" / "pin.spec.luau"`, made relative to the clone's `z-nile/` by its position under `.tracker/issues/`), or try the backlog path and then `active/`. Refuse with a clear message when neither exists, before any mutant runs. Name both expected counts in step 6.

### F3 [medium] The `\v`/`\f` rule has no Rules and mutants row, and the Design's "not collapsed" sentence has a mutant that survives
Where: Design, "`\v` and `\f` are not collapsed (a Luau `--` comment runs through them, R0045 review 002)"; `pin.spec` "a join with a vertical tab or a form feed …"; Rules and mutants table; Unknowns.
Evidence: two mutants, run on the prototype against `pin.spec`:
- `"\r\n?"` → `"[\r\v\f]\n?"` (treating them as line breaks: the real hole) is killed by its own case. But it has no row and no runner id.
- `"[ \t]+"` → `"[ \t\v\f]+"` (collapsing them, which the Design says the rule does not do) gives `14 passed, 0 failed`.

The Luau fact the rule rests on is also not recorded as an experiment. I probed it with `luau.load("-- x" .. sep .. "error('code ran')")()`: LF and **CR** end the comment, and VT and FF are swallowed. So the normaliser's "a lone CR is a line break" and "`\v` and `\f` are not" are both correct, but nothing in the document proves either.
Critique: the tempting fix is to delete the "not collapsed" sentence. Collapsing `\v` into a space is semantically harmless outside strings, but the sentence is a stated rule, and AC1's "tolerates only" is then not true of the module.
Consequences: deciding the rule also decides what a pinned file with a `\v` inside a string may change. The pinned files have none today.
Recommendation: record the lexer probe as an experiment (CR ends a `--` comment, VT and FF do not; pass/fail, with the fallback "treat CR as text" if a future Luau changes it). Add the runner ids `vf-line-break` and `vf-collapsed`, with rows. Add a case `pin.normalise("a\vb") ~= pin.normalise("a b")` (and the same for `\f`), or, if the author prefers to tolerate them, change the Design and AC1's tolerated list to say so and add `vf-collapsed` as a correct variant instead.

### F4 [medium] Step 0 stops the raft for unrelated edits to the skill and the lesson, and Existing work misses the active raft that makes one
Where: Unknowns, "Base blobs" (`zz-test/SKILL.md` `14e8f252`, the lesson `ed43a849`); Implementation step 0; Chore checklist, **Existing work** ("touches neither `tests/lib/pin`, `c0103/`, `c0128/` nor the three pinned files").
Evidence: a search of every local and `origin/` branch with `git diff --name-only origin/main...<branch>` over the Touched modules found that `impl-c0117` (R0052, active), `impl-c0118` and `impl-c0121` each add a "Starting a model CLI" bullet to `z-nile/skills/zz-test/SKILL.md`. That is far from line 21, so the patch would still 3-way apply. When R0052 lands, the skill's blob moves, and step 0 ("If any differs, stop and escalate for a re-prep") halts c0156 for nothing. Step 0's second clause ("if only an unrelated file moved, rebase the patch") contradicts the first for exactly these files. The Existing work search did not include the skill or the lesson, though both are Touched modules.
Critique: the tempting fix is dropping the two documents from the blob list, but then a reworded line 21 would go unnoticed until `docs.spec` fails mid-raft.
Consequences: a split rule needs a clear test for "unrelated", which an executor can apply without judgement.
Recommendation: split the blob list.
- **Tied** (stop and re-prep when any blob moved): the three pinned files, the two pin specs, R0045's `mutants.py`.
- **Documents** (go on when each still contains the old text that `docs.spec` asserts is gone, and the 3-way apply is clean; stop otherwise): the skill and the lesson.

List R0052 (impl-c0117) and the c0118/c0121 branches under Existing work, with that outcome.

### F5 [medium] The R0045 record this change edits and step 6 runs has none of the guards the Design claims for "the mutation script"
Where: Chore checklist, **Guards** ("The mutation script refuses anything but a separate clone under the temp folder and kills its process group at the limit"); `pickman/.tracker/rafts/done/R0045/experiments/mutants.py` as the prototype patch leaves it; step 6 (`python3 -I <R0045 record>/mutants.py <clone>/pickman`).
Evidence: the record is still `root = pathlib.Path(sys.argv[1])` followed by `path.write_text(...)` on `root / rel`. It has no clone or temp check, so `mutants.py <main checkout>/pickman` rewrites the real checkout's tracked spec files. `finally` restores them, but a crash or SIGKILL between the write and the restore does not. The new `timeout=120` is `subprocess.run`'s: it kills only the direct `lune` child (its workers can outlive it), and the `TimeoutExpired` it raises is uncaught, so the run aborts with a traceback. It does not set `PICKMAN_FENCE_REAL_GIT`; step 6 relies on the caller's shell for that. The Guards sentence is true only of c0156's own script.
Critique: it isn't a check, so the runner's jail never sees it. Review is the only guard (zz-test, "Caught only by review": work handed to processes outside the jail).
Consequences: porting the guard changes the record's usage. The argument becomes the pickman home of a clone under the temp folder, and the "clone" test must accept a home path, not a root.
Recommendation: port c0156's preamble into the record:
- refuse unless the argument's parent is a clone under the temp folder with no `.worktree`;
- set `PICKMAN_FENCE_REAL_GIT` from the script's own repository;
- use `Popen(start_new_session=True)` and `killpg` at the limit;
- report a timeout as a failure line, not a traceback.

Then pin the refusal with the record's own spec (`record.spec`), behaviourally if cheap (run it with a `.cache` fixture path and expect the refusal exit), else as a probe for the refusal message the Design names. Fix the Guards sentence to name both scripts.

### F6 [medium] AC5's label claims the record "joins a line onto a comment in each pinned file"; its spec only finds names
Where: `check.sh` AC5; `acceptance/record.spec.luau`.
Evidence: the spec asserts that `('join-f0024-comment', ` (and three more names), `'tests/acceptance/c0128/' + f for f in` and `tests/acceptance/c0103/narrowed.spec.luau` appear in the script's text. An entry `('join-f0014-comment', K, 'x', 'x')`, a no-op, passes, and so does one whose anchor matches nothing (the script then reports `anchor found 0 times`, but AC5 never runs it). The needle `'tests/acceptance/c0128/' + f for f in` is Python spelling no Design sentence names (zz-test/source-pins-name-what-the-design-names), and the loop asserts that same needle three times (once per spec name).
Critique: the tempting fix is a regex over each tuple. That is still a probe of a Python file's text.
Consequences: if F1's option (a) runs the record's mutants, AC5 can become behavioural for free.
Recommendation: under F1 (a), AC5 becomes "each join entry of the record, applied to its pinned file, turns that file's pin red". Otherwise relabel AC5 to what it checks ("names a join mutant for each pinned file and runs the promoted specs"). In both cases, assert in-process that each named entry's old text occurs exactly once in its pinned file and ends in `\n` after a `--` comment, and that the new text is the old with that `\n` turned into a space. Drop the list-comprehension needle in favour of the paths the Design names.

### F7 [low] The Design and both headers cite a Non-goal that isn't there, and two tolerance lists are short
Where: Design ("spaces within a line (strings included, a Non-goal below)"); Maintainability ("keeping the spaces inside strings, a Non-goal"); `## Non-goals` (two bullets, neither about strings); `check.sh` AC1 label and `narrowed.spec`'s header ("only item ids, line endings, the spaces within a line and a trailing comma before `}` are tolerated"), which both omit trailing whitespace and the text's outer blank lines.
Evidence: the lesson's own check asks "can … changing the spaces inside a string change what the pinned file asserts while its normalised text stays the same?". The capture's Problem permits "collapse horizontal whitespace only", so tolerating spaces inside strings is in scope, not a cut. The document just doesn't say why it is safe for these files. I checked: none of the pinned files has a string with a run of spaces or a tab, and every negative probe (`banned` lists in f0024 and f0026, `os.date`, `WaitForChild("Board")` …) uses a needle with no space, so no probe can be made vacuous by spacing today.
Recommendation: replace "a Non-goal below" with that evidence, as an accepted risk under the capture's "collapse horizontal whitespace only". Make AC1's label and the header list the same tolerances as the module's doc comment.

### F8 [low] The Override search list is incomplete
Where: Affected specs, "The Override check …, for `zz-test/SKILL` the specs that read that skill (…)".
Evidence: `grep -rlF -e zz-test/SKILL -e zz-test/lessons -e lessons/ pickman/tests z-nile/tests` also finds `c0172/merge`, `c0115/absence`, `c0115/layout`, `c0115/prompt`, `c0114/docs`, `c0116/recombine`, `c0111/{harvest,skill-docs,lesson-format,metrics-lessons,prompt-lessons}`. I ran those 11 on the prototype with the edited skill and lesson: `72 passed, 0 failed, 11 spec files`. So the Overrides line holds, but the record of the search doesn't.
Recommendation: paste the search and its full hit list (zz-review/lists-paste-their-search), and add these 11 to E4.
Lesson: zz-review/lists-paste-their-search

Placement: `z-nile/tests/lib/pin.luau` with a re-export from pickman holds. c0156's sequestered specs live under z-nile and resolve `@tests` through `z-nile/.luaurc`, both before and after promotion, so a module only in `pickman/tests/lib` would be unreachable from them. `renamed.luau` sets the precedent. `--affected` selects `ALL` either way. No finding.

Lesson candidate (for the lead): "A whole-file pin's join and deletion cases go through the same comparison as its digest case; otherwise check.sh can't tell a pin from a no-op (c0156 design review 001 F1). Check: weaken the pin's compare: does any Checked case go red?"

Verdict: changes
