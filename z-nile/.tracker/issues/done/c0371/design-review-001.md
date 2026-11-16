# Review 001: c0371 (design mode)
Inputs: prep worktree `prep-check-paths-homes` at 6b10cbf27 with its uncommitted c0371 files (c0371.md, check.sh, acceptance/check-paths-homes.spec.luau, experiments/E1-literals.luau, experiments/prototype.patch); `./zn capture c0371` (efa610174), idea-review-001.md and idea-refute-001.md; `z-nile/tests/acceptance/c0120/check-paths.spec.luau`; c0141 (prepared, raft R0062) and its sequestered specs; the live check.sh files of every project. I applied the prototype in two scratch clones (remote URLs pointed at nothing): one of 6b10cbf27 and one of origin/main a949a2bf. On both, c0120's check-paths spec passes 4/4 and c0371's spec passes 5/5. Main's unchanged spec on a949a2bf fails with the same five lines the Problem names. The probe on unpinned forms is `/private/tmp/claude-501/-Users-philipbergen-code-pickman/3fbf9326-e053-49c8-ab1e-bfbc221fe8f4/scratchpad/c0371-review-probe.luau`, using the fixture of c0371's spec. Every probe ran under `./zn run --time`. The worktree's c0371 folder passes `stylua --check` and `selene --quiet`. `./zn check c0371` fails AC1, AC2 and AC4 for the right reasons.

### F1 [high] c0371 does the same work as prepared c0141 and contradicts it: same spec, same moved functions, a different module and API, and the opposite Touched reading
Where: c0371.md Design, Moves (line 41) and rule 2 (line 45); acceptance case 1 (the mixed list); `z-nile/.tracker/issues/c0141/` (raft R0062).
Evidence:
- c0141 ("Check paths touched from home": prepared, design ready, size 680, in backlog raft R0062 with c0139) moves the same scanner out of c0120's check-paths spec into `z-nile/tests/acceptance/c0120/checkpaths.luau`. Its API is `scan(base, skip)`, `repoPath` and `owned`, and RESTAMPED stays in the spec.
  - Its sequestered `uses-module.spec.luau` pins three things: c0120's spec requires `"./checkpaths"`, its `scanFrom` returns `checkpaths.scan(base, …)`, and it defines no `literals`, `present`, `touched`, `under`, `items`, `scan` or `patternWords`.
  - Its `touched-from-home.spec.luau` calls `checkpaths.scan(fx, skip)`, `checkpaths.owned` and `checkpaths.repoPath`.
- c0141's rule reads Touched entries one convention per document: if any entry starts with a registered home, every entry is read from the top. Its Rules table lists **N1 "both readings"** as a mutant its cases kill. c0371's rule 2 is N1. c0371's case 1 also pins a mixed list (`{ "pickman/src/shared/Logic/New/init.luau", "tests/unit/New" }` covers `test -d tests/unit/New`), which c0141's rule reports.
- c0371's Problem bullet 2 is c0141's captured Problem: compare the path's repository-relative form (home plus path) with the entries.
- c0141 appears nowhere in c0371's `depends_on`, Existing work, Overrides or Non-goals. Whichever item lands second has specs that can't pass, and neither raft can edit the other's promoted or sequestered specs (c0141's Overrides names only c0120's spec).
- Reading every entry both ways hides real misreadings on the live tree:
  - c0193's AC (`for f in z-nile/engine/scan.luau z-nile/tests/lib/loops.luau z-nile/tests/lib/scanners.luau z-nile/tests/lib/hostile.luau; do case "$E" in *"$f"*`) uses prose words that the scan reads from z-nile/ as `z-nile/z-nile/…`. They pass only because c0193's repo-form Touched entries match the same text. I changed the prototype so that a `<home>/` entry is a repo path only, and c0120's live case went red on exactly those four words.
  - Probe D: a z-nile check with `test -f pickman/src/new` and Touched `pickman/src/new` is silent, though `z-nile/pickman/src/new` is missing.
  - Probe E: a home-form entry `tests/new.luau` covers the root literal `(cd "$ZN_ROOT" && test -f tests/new.luau)`.
  - The Design's claim "an entry for `pickman/src/server` does not cover z-nile's" holds only for the stripped text.

Critique: two prepared designs for one promoted spec disagree on the module name, the API and the rule. Renaming c0371's module to `checkpaths.luau` is the tempting fix, but it reconciles neither the API nor the reading.

Consequences: each reading has a cost.
- With c0141's per-document reading, c0193's check turns red (it needs a prose rule for a `for … in` list whose variable reaches only `case`, or a user-approved edit of a sequestered file), and c0371's mixed-list case goes.
- Keeping both readings means re-prepping c0141 (its N1 case inverted).

Which item delivers Solution bullet 1 moves an outcome between issues, so it is the user's call. Raft membership is z-raft's (`./zn unfold R0062 c0141`).

Recommendation: escalate to the user, with these options:
- **(a) c0371 takes over c0141.** Unfold c0141 from R0062, then fold it into c0371 or supersede it. c0371 adopts c0141's module, API and per-document reading, puts rules 1, 3 and 4 on top, and drops the mixed-list case. It adds a case: z-nile's `test -f pickman/src/new` with entry `pickman/src/new` is reported. It settles c0193's four words. Then c0141's two specs and c0371's run on one prototype on current main.
- **(b) c0371 depends on c0141** and builds rules 1, 3 and 4 on `checkpaths.luau`. Cost: main stays red until R0062 (c0139 and c0141) is done.
- **(c) c0371 lands as designed and c0141 is re-prepped**, with its module, API and N1 rule inverted. Cost: c0141's four review rounds and the per-document decision are undone.

Record the choice as a `Scope decision (user, YYYY-MM-DD)` line in both documents.

Question: which Touched reading does the repository keep, and which item delivers it?

Lesson: z-design/one-reading-per-value

### F2 [high] The root reading ends at the end of the line, though the capture says "in the same command list or subshell", so later lines of a `bash -c` script after `cd "$ZN_ROOT"` are read from the home and missing paths go unreported
Where: rule 1 (line 44: "on the same line … or the line ends"); Solution bullets 2 and 4 (lines 32, 34); E6 (line 91).
Evidence: the probe ran these cases on the prototype, each in a z-nile item with no Touched entries. Every one is a missed report.
- `check "AC1: x" bash -c 'cd "$ZN_ROOT" || exit 1` followed by `  test -f tests/run.luau'` on the next line: silent. Bash runs line 2 at the root, where `tests/run.luau` is missing. The scan reads it from z-nile/, where it exists.
- A top-level `cd "$ZN_ROOT"` line, then `check "AC1" test -f tests/run.luau`: silent.
- E6 is wrong both ways:
  - `(cd "$ZN_ROOT" && test "$x" != ")" && test -f tests/run.luau)` is silent: the `)` in quotes ends the root reading early.
  - `(cd "$ZN_ROOT" && test "$x" != "(" ); test -d scripts/hooks` is silent: the root reading runs past the real close, and the root has `scripts/hooks`.
  - So "a false report at worst, never a missed one" is false.
- `cd "$ZN_ROOT" && cd pickman && test -d scripts/hooks` is read from the root (silent): a literal cd is ignored while the root reading is on.
- `check "AC1" bash -c 'cd "$ZN_ROOT" && true' && test -d scripts/hooks` is silent: the reading doesn't end at the script's closing quote.
- Live checks already use the multi-line shape. They pass only because no later line holds a word the scan reads as a path:
  - c0292 AC7: `bash -c 'cd "$ZN_ROOT" || exit 1`, then `d=$(./zn find c0292)`.
  - R0100 RC2: `cd "$ZN_ROOT/z-nile/engine" || exit 1`, then several lines.
  - The diff RCs of c0173, c0174, R0078, R0080 and R0100 RC4, and c0371's own AC3: `bash -c 'cd "$ZN_ROOT" && base=…`, then `git diff … -- …` on the next line.

Critique: bullet 2 asks for the whole command list or subshell. Bullet 4 asks for a report whenever a path is missing from where its command runs. The line limit narrows both, with no Scope decision line. The zz-test sentence ("until its subshell closes") would also overstate the code.

Consequences: carrying state across lines needs a quote-aware pass that handles:
- single quotes;
- double quotes with `\` escapes;
- the `'"'"'` idiom (c0292 line 30);
- `\` continuations.

That same pass gives the paren depth and the end of a `bash -c` script. c0120's literal-reader case and the live scan must still read the same afterwards.

Recommendation:
- Keep `rootDir` and the depth across lines while the `bash -c` quote, `( … )` or `{ … }` that holds the cd is open. For a top-level cd, keep them to the end of the file.
- Count parens only outside quotes.
- End the reading at the script's closing quote.
- Let a literal `cd <dir>` after a root cd mean `<dir>/` from the root.
- Add the six cases above, each reported, plus Rules rows for them, and correct E6.

Otherwise escalate: keep the line limit with a `Scope decision` line, and make zz-test say a root cd counts only on its own line.

Question: what does the scan read on line 2 of `bash -c 'cd "$ZN_ROOT" || exit 1` and its following line, and is that where bash runs it?

### F3 [high] Rule 3 narrows Solution bullet 3 ("quoted text passed to a check's own search helper") to an escaped-backtick code span, with no scope decision
Where: Solution bullet 3 (line 33), rule 3 (line 46), Decision on 3 (line 49), E3 (line 88).
Evidence:
- The Decision says the rule "leaves an unquoted/plain quoted literal given to a helper (`has "$L" "tests/gone.md"`) read as a path, as before". Plain quoted text passed to a search helper is exactly what bullet 3 names.
- E3 surveyed only unfinished checks. The done c0264 (2026-11-15, its check.sh line 180) passes its search helper `words` single-quoted text that holds unescaped backtick spans: a single-quoted argument that starts with a backtick, then `./zn who <id>`, a closing backtick and " prints a ticket's history". Rule 3 doesn't cover that form. In an unfinished check, a single-quoted argument made of a backtick, `tests/run`, a backtick and " passes" would be read as `tests/run` and reported.
- The live search helpers are few, and each is a function in the same check.sh whose body runs `grep -qF` on its text arguments:
  - `g() { grep -qF -e "$1" "$2" …}`;
  - c0256's `has() { grep -qF -- "$2" "$1" …}`;
  - c0292's `has`, which loops `for w in "$@"` after a `shift`;
  - c0264's `words`, `has_all` and `keeps`.

Critique: the Decision cuts scope on the designer's judgement. Its argument against generalising (it would blind `typecheck src/x`) applies to "any helper", not to "a search helper", which is what the capture names.

Consequences: a rule with the full scope must:
- find `name() {` … `}` definitions, on one line or several;
- tell search helpers by their body (an argument goes to grep or rg as the pattern);
- treat a call's quoted arguments as text across `\` continuations (c0292's call spans three lines; this shares F2's quote-aware pass);
- keep reading unquoted file arguments.

A quoted literal file argument (`has "skills/x.md" "text"`) then goes unread unless the rule maps positions (`$1` against `$2`).

Recommendation: escalate to the user, with these options:
- **(a) The full scope as above.** Cases: `has` (file first), `g` (pattern first), c0264's single-quoted form, a multi-line call, and a non-search helper (`typecheck src/gone`) still reported. Cost: about 60 to 100 lines plus the reader shared with F2.
- **(b) Keep the narrow rule** with a `Scope decision (user, YYYY-MM-DD)` line in the Problem. It must still cover c0264's single-quoted, unescaped-backtick form and the whole span (F5).

Question: does `has "$L" "tests/run"`, which is quoted text passed to a check's own search helper, pass?

### F4 [high] Rule 4 fires on the word `echo` inside quoted text, so a missing file after it stops being reported (a regression)
Where: the prototype's `patternWords` (`for k, w in raw do if w == "echo"`); rule 4 (line 47); Non-goal 2.
Evidence: `raw` holds every word on the line, quoted ones included. In the probe, `grep -qF "echo" tests/gone.md` and `has "$f" "run echo" tests/gone.md` in a z-nile check are both silent. Main's scan reports `tests/gone.md (from z-nile)` for the first, because its grep rule marks only `echo`. Non-goal 2 says "c0120 AC11 keeps reporting every case it reports today". Neither echo row in the Rules table (rule removed; mark runs to the end of the line) catches this.

Critique: the mark belongs to the `echo` command, not to the word.

Consequences:
- "Command position" means an unquoted word after the start of the line, `;`, `&&`, `||`, `|`, `{`, `(`, `then`, `do` or `else`. `quoted` counts double quotes only, so c0292's echo inside `bash -c '…'` (line 67) still qualifies.
- The grep rule has the same pre-existing flaw: a quoted word `grep` marks the next word. Fix both in one place, or say why not.

Recommendation:
- Mark an echo's argument only when `echo` is an unquoted word in command position.
- Add `grep -qF "echo" tests/gone.md` and `has "$f" "run echo" tests/gone.md`, both reported, to the echo case.
- Add a row "a quoted word `echo` is not a command" whose mutant is "the rule matches any word".
- Either cover `printf`'s format string (probe L: `printf "z-nile/roots is gone\n"` is reported) or say why only echo.

Question: does `grep -qF "echo" tests/gone.md` still report `tests/gone.md`?

### F5 [medium] The code-span rule skips only the word right after the opening `\``, while zz-test and AC4 will say "a word inside a code span … is prose"
Where: rule 3 (line 46); Restated rules (line 51); AC4.
Evidence:
- The probe reports `has "$L" "\`git diff -- src/server\`"` as `src/server (from z-nile)`.
- The code doesn't check that the span is inside quotes, although rule 3 says so: `test -f \`src/gone.luau` is silent.
- The case pins only first words (`\`tests/run\``, `\`src/nothing\``).

Critique: an author who follows the skill sentence and writes a span with a path in second place gets a red gate. The rule as stated and the code differ.

Recommendation: either mark every word between the opening `\`` and its closing `\`` inside double quotes, and add two cases (a span whose second word is a path is prose; a `\`` outside quotes is still read), or reword the Design and the skill sentence to "the first word of a code span" and change AC4's phrase to match. Settle it together with F3 (b).

### F6 [medium] After the move, a change to the scan module selects c0371's fixture spec but never c0120's live scan
Where: Moves (line 41); Affected specs (line 68).
Evidence:
- In a clone with the module in place, `lune run z-nile/affected -- z-nile/tests/acceptance/c0120/check-paths-scan.luau` prints nothing.
- By contrast, `… -- z-nile/tests/acceptance/c0120/rewrites.luau` selects c0120's check-paths spec among about 150, because c0120's `watch.txt` lists `rewrites.luau`.
- `./zn finish` writes only c0371's `acceptance/watch.txt`, and zz-test says it is the only writer. That file will name the module, so a later edit of the module runs c0371's five fixture cases and never the live scan of every unfinished check.sh, which is the case that turns main red. Only a `--full` at a merge would see it.

Critique: the move takes the scan out from under the watch that protected it.

Consequences: a live case in c0371's spec reads the whole tree. It needs an inputs.tsv line like c0120's: `tests/acceptance/c0371/check-paths-homes.spec.luau<TAB>*` (lesson z-design/declare-what-full-runs-covered). It costs about 0.1 s.

Recommendation: add a case to c0371's spec, "the live tree passes" (`scanner.scan(scanner.TOP).bad` is empty and `checked == found`), with its inputs.tsv line. Or name another way a module change selects c0120's spec; a hand edit of c0120's `watch.txt` doesn't count. Also name the module on the Overrides line: it is a new file in c0120's promoted folder.

Question: which gate runs the live scan when only `check-paths-scan.luau` changes?

### F7 [medium] AC2 passes with c0120's spec keeping its own scanner
Where: check.sh AC2 (lines 15-18); AC2 (line 122).
Evidence: AC2 checks three things: c0120's spec passes, `grep -qF "check-paths-scan"` matches in it, and the module exists. A comment naming check-paths-scan plus an unused module satisfies all three while c0120's spec keeps, and the gate runs, its own `literals` and `scan`. AC1 tests only the module. c0141's `uses-module.spec` exists for exactly this case (its mutants U1, a local scan kept, and U2, the call only in a comment).

Recommendation: write AC2 as a case in c0371's spec. The case:
- reads c0120's spec with comments stripped;
- requires the require call (needle built from parts, as c0141 found that a literal require text in a promoted spec trips the architecture spec) and the call to the module's scan;
- refuses `literals`, `scan`, `patternWords`, `present`, `touched`, `under` and `items` in every spelling (`local function x(`, `local x = function`, `x = function`), and `PREFIXES`, `FILES` and `FOLDERS =`.

If F1 settles on c0141's module, this case is c0141's `uses-module` spec.

Lesson: zz-test/moved-rules-pin-the-old-caller

### F8 [medium] finished.spec reads check.sh files with the same misreadings, and the design doesn't say what happens when c0292 is done
Where: Regression guard (lines 95-96); Existing work (line 51).
Evidence:
- `lune run tests/run -- tests/acceptance/c0120/finished.spec.luau` in this worktree is red today on c0264's single-quoted code spans (`z-nile/.tracker/issues/done/c0264/check.sh: ./zn (from z-nile)` five times). It is in the slow tier, so the full gate doesn't run it.
- In a clone of a949a2bf with c0292 and f0201 moved to `done/`, it adds:
  - `c0292/check.sh: ./zn` four times (the `cd "$ZN_ROOT" && ./zn …` lines);
  - `z-nile/.tracker` and `z-nile/roots` (from the echo);
  - nothing for f0201.

Critique: the lesson asks for every scanner to be run on the check.sh with the item moved to done. This chore turns check-paths green and leaves `rewrites.luau`'s reader red now, redder at c0292's done (the net opens `slow-tier-red`). The design doesn't say so.

Consequences: `rewrites.luau` also drives c0120's AC18 (`finished.luau`), so changing its reader here is riskier than doing it in its own item.

Recommendation: name finished.spec and these lines under Existing work. Then have the lead capture an issue for its reader (c0264 now, c0292 at done), or ask the user to widen this chore's scope. Don't change `rewrites.luau` silently.

Lesson: zz-test/sentences-in-checks-are-grep-patterns

### F9 [medium] The frontmatter has no `size:`
Where: frontmatter (lines 1-13).
Evidence: z-design step 3, "Size and solo", asks for `size: <n>`. z-raft says "an issue with no `size:` is skipped and named: send it back to z-design" (`raftplan.luau` line 140). For an urgent fix to a red gate, that skip stalls the item.
Recommendation: add `size:` once F1 to F4 settle what gets built. For scale, c0141 estimated 680 lines for the comparable move and rule.

### F10 [low] Affected specs is not the selector's output, and the list of specs that read zz-test is incomplete
Where: Affected specs (line 68).
Evidence: the pasted command prints one line (c0120's check-paths spec). The other ten lines are grep hits for zz-test/SKILL.md. That grep actually finds 20 specs; the design leaves out:
- c0081/skill-doc, c0115/absence, c0115/docs, c0165/select, c0184/docs, c0191/docs and c0239/docs;
- tests/tooling lessons-hidden, select-scope and watch.

I added one sentence holding AC4's four phrases to zz-test line 78 in a clone and ran all 20 specs: all pass.
Recommendation: paste the selector's line as it is, then a separate "read zz-test as text (grep)" list with all 20 and the result of the run.

### F11 [low] E5 can be run cheaply instead of reasoned
Where: E5 (line 90).
Evidence: `git grep` for root-cd lines in `*check.sh` across all 153 remote branch refs takes seconds. Its 40 distinct lines hold only root literals that exist at the root (`lune run z-nile/roots`; `cd "$ZN_ROOT/pickman" && lune run tests/run`) or words the scan doesn't read.
Recommendation: record E5 as run with this method. Worktrees that exist only locally are covered by their own PR's gate.

### F12 [low] c0371's own check.sh adds a sixth red line to main until c0371 is done
Where: check.sh AC2 (line 18).
Evidence: in `./zn check c0371`, AC2's live scan reports `z-nile/.tracker/issues/c0371/check.sh: tests/acceptance/c0120/check-paths-scan.luau (from z-nile)`. The cause is the repo-form Touched entry, the very defect this chore fixes.
Recommendation: say in Existing work and in the PR that this line is expected until done, or name the file through `$ZN_ROOT` (zz-test line 78).

### F13 [low] Accuracy points in the steps, the case comments and the Rules table
Where: Implementation step 1 (line 134); acceptance case 1; Rules and mutants.
Evidence:
- Step 1 says "the spec stays green", but the live case is red on main until step 2. It should say "the other three cases stay green; the live case keeps its five lines".
- The move isn't a rename (git sees an add and an edit), so "renames-only" can only mean "no behaviour change".
- Case 1's comment says "a parent of an entry", but the case tests no parent.
- The Rules table has no row for the `cd "$(git rev-parse --show-toplevel)"` form or for a home-form entry (cases 3 and 1 kill those mutants without rows).
- No case kills rule 3 matching any backtick instead of `\``.
- The spec header leaves out the echo rule.

Recommendation: fix these wordings and add the three rows.

## Lesson candidates (for the lead)
- z-design: before designing a change to a promoted spec, `git grep -l <spec path>` the unfinished item documents and name how each hit relates (fold, sequence or re-prep, decided by the user). Why: c0371 and prepared c0141 move the same spec's scanner into two modules with opposite rules. Check: which other unfinished items name this promoted spec on their Overrides line or in their Touched modules?
- zz-test: a scanner rule keyed on a shell command (`echo`, `grep`) checks command position, because a quoted word is text. Why: c0371's echo rule silenced `grep -qF "echo" tests/gone.md`. Check: does the rule fire on the command's name inside a quoted argument?
- zz-test: a per-line reader of shell states what it does with what bash carries across lines (cd, open quotes, subshells) and pins a multi-line case. Why: c0371's root reading stopped at the end of the line while live checks cd on line 1 of a `bash -c` script. Check: what does the reader see on line 2 of a `bash -c` script that starts with a cd?

Verdict: changes
