# Review 005: c0371 (design mode)
Inputs: prep worktree `prep-check-paths-homes` at c36ee2f4a (clean); origin/main 257ccf5f0. Read:
- c0371.md, check.sh, the three acceptance specs, `experiments/` (E5, E7, E8-corpus.sh, E8-corpus.luau.txt, checkpaths.diff), design-review-001..004, design-refute-001..004 and harvest.md;
- the prototype `v6-checkpaths.luau` (md5 af794e84) and `v6-spec.luau` (md5 48ce4815);
- c0141.md, the lesson `shell-rules-key-on-command-position`, zz-review, zz-test line 78, z-design's Touched modules bullet.

Scope of this round, as briefed: the user ruled "Land with known edges", so whether the reader is complete is not judged. Judged here:
- whether the Known edges are truthful, and whether an ordinary form is missing from them;
- regressions against main's reader (the scanner in origin/main's `c0120/check-paths.spec.luau`);
- whether each rule's mutant dies by its own case, and whether the fields agree;
- whether round 4's answers are true.

How I ran it:
- Scratch clone `scratchpad/rv5-c0371` of the prep branch, its remote pointed at nothing, with origin/main (14 commits newer than the prep's base, bringing new check.sh files for c0132, c0226, c0287, c0375, d0331 and R0110) merged in. v6 is installed as `c0120/checkpaths.luau` and `c0120/check-paths.spec.luau`; c0371's specs are under `tests/acceptance/c0371/`. A second clone `scratchpad/rv5m` takes the mutants.
- `patch` confirms that c0141's module 46f7d115 plus `experiments/checkpaths.diff` gives v6 byte for byte.
- E8 finds the worktrees from the checkout's own path, and my clone lies outside `.worktree/`. So, for E8 and the comparisons, the clone's `.worktree` is a symlink to the real `.worktree` folder, which they only read.
- Every probe ran under `../zn run --time`. Probes and outputs are in `/private/tmp/claude-501/-Users-philipbergen-code-pickman/3fbf9326-e053-49c8-ab1e-bfbc221fe8f4/scratchpad/rv5-probes/`:
  - `cases6.txt` / `cases6.out`: 36 new shapes, main's scan against v6's on one fixture item each (`#n` below), with round 4's harness;
  - `cases7.txt` / `mutcase.log`: one input per surviving mutant, run on v6 and on the mutant;
  - `mut.py` / `mut.log` (homes spec without its live case) and `mutfull.log` (the four specs, live case included): 46 mutants;
  - `e8.log` (E8 as shipped), `e8b.log` (E8 with each file judged against its own tree), `wt.out` (main's full scan, Touched as written, against v6's over every open worktree);
  - `bash/t.sh`: bash's own behaviour for the pipeline, function, backtick and `cd -` shapes.

Results:
- **Specs:** 36/36 pass on today's main (homes 27, touched-from-home 4, uses-module 1, c0120's 4).
- **E8 as shipped** (`../zn run --time 1800 -- bash .tracker/issues/c0371/experiments/E8-corpus.sh`, about 4 minutes): `check.sh files read: 647; literals lost against main: 41; gained: 0`; 17 lost and missing, exactly the Design's list (c0193 ×4 ×2, c0083 ×3, c0292 ×4, d0297 ×1, R0013 ×1); gained and missing: 0.
- **E8 judged per tree** (`e8b.log`): 0 reports gained, the same 17 lost.
- **Full scans over 161 worktrees** (`wt.out`, Touched exemption included): gained 0; lost only the intended (f0201 ×59 ×2, c0292 ×52 ×3, c0141's exemption for c0195 and c0371).
- So **no regression against main appears in any corpus**. The regressions below are in shapes the corpus does not have.
- **Mutants:** I ran 46.
  - The mutants of round 4's rules are all killed except N6b, which is equivalent.
  - Ten mutants of named rules survive every spec (F3). One of them is N12b, the `case` test's `in` alternative.

Counts: highs 1 (F1); mediums 2; lows 1.

### F1 [high] The Known edges list is still not truthful: three bullets give the wrong outcome, and shapes that report correct checks are missing
Where: Design, **Known edges** (the backtick, rule L and function bullets; the header "Each unmodelled form below is given its real outcome"); module lines 711-723 (brace groups) and 734-775 (cd).

Evidence. Each case is in a z-nile item, `cases6.out`; bash's behaviour is checked in `bash/t.sh`.
- **Mislabelled "as main":**
  - **Backticks.** The bullet says "backtick command substitutions are not frames … (as main)". A root cd inside backticks holds for the rest of the file:
    - #9: `` d=`cd "$ZN_ROOT" && pwd` `` then `test -f tests/run.luau`. v6 reports `tests/run.luau (from the repository root)`; main reports nothing. That is a correct check.
    - #8: the same with `test -f z-nile/roots.luau`. Main reports it; v6 is silent.
    - So the outcome is reports **and** fails open.
  - **A `for` list spanning lines** ("rule L: … a `for` list spanning lines … (as main)"). #10: `for f in tests/gone.md \` / `  tests/gone2.md; do case "$x" in *"$f"*) ;; esac; done`. Main reports both; v6 reports only `tests/gone2.md`. The list ends at the first newline, so its first line is text: fails open.
  - **"A function that cds to the root, called later … as main"** holds only for `name() {` on one line:
    - #5: `function toroot { cd "$ZN_ROOT"; }` then `test -f tests/run.luau`;
    - #6: `toroot()` / `{` / `cd "$ZN_ROOT"` / `}` then the same test.
    - Both report `tests/run.luau (from the repository root)`; main reports nothing. The body is read as a brace group, whose cd holds after `}`. In bash the function only runs when called.
- **Not listed. Each one reports a correct check that main does not report:**
  - **A cd back after a root cd.**
    - #1: `cd "$ZN_ROOT"` / `git log -1 --format=%H` / `cd - >/dev/null` / `test -f tests/run.luau` reports `-/tests/run.luau (from the repository root)`. `cd -` appends `-/` to the root frame (line 769).
    - #2: `cd "$OLDPWD"` reports `tests/run.luau (from the repository root)`.
    - #3: any `cd "$VAR"` after a root cd changes nothing. A word with a `$` that is not a root form falls through lines 767-775, so the root reading goes on.
  - **A command in a pipeline.** bash runs each part of a pipeline in a subshell. v6 keeps the root reading after:
    - `{ cd "$ZN_ROOT" && git log -1; } | grep -q .` (#4);
    - `git ls-files | while read -r f; do cd "$ZN_ROOT"; done` (#14);
    - `cd "$ZN_ROOT" | true` (#23).
  - **A cd in a branch that may not run.** #26: `if [[ -n $X ]]; then cd "$ZN_ROOT"; else true; fi` / `test -f tests/run.luau` is reported. The spec pins this static reading (its `if [[ -n $ZN_ROOT ]]` case), but the Known edges do not state its cost.
- **Not listed. Each one silences a report main makes (fails open):**
  - **Parentheses in a heredoc body are read as frames.** #7: `(cd "$ZN_ROOT" && cat > "$T/x.md" <<'EOF'` / `see (the note` / `EOF` / `)` / `test -f z-nile/roots.luau`. Main reports; v6 is silent.
  - **Escaped or expanded parentheses**, not only `[[ =~ ]]` regexes: `[[ $x == a\( ]]` (#18) and `${x%%(*}` (#19), each inside a root subshell.
  - **A loop value echoed with a redirect.** #15: `for f in src/gone.luau; do echo "$f" >> "$T/list"; done` then `xargs test -f < "$T/list"`. `matchedUse` counts the redirect's words as message words, so the value is text.
- **Frequency:** none of these shapes changes a report in the corpus (E8 and both comparisons above: 0 gained). `shapes.sh` searched 585 distinct check.sh texts (the walk stopped at its 600 s limit, partway through the worktrees):
  - none uses `cd -`, `cd "$OLDPWD"`, `popd`, a piped brace group, `function name` as a definition, or `name()` with its brace on the next line;
  - the one backtick with a `cd` is inside a comment;
  - one pipes into `while`, with no cd (c0293);
  - two continue a `for` list over lines (c0285, c0359), and none of those words is a path;
  - eleven cd to a variable, all inside `$(…)` or `(…)` except one, and none after a root cd in the same frame.
- So nothing in today's corpus is exposed. The defect is the list's text, and the next check.sh that uses one of these shapes.

Critique:
- The user's ruling rests on this list: each unmodelled form is listed, with its outcome, and measured. Round 4's F2 was this finding, and refute 004 F2 answers "the Known edges list gives each form its real outcome".
- Three bullets still state "as main" for forms that report or fail open, and the "reports" shapes above are on no list.
- "Reports" is the failure c0371 exists to fix. A correct check.sh that returns with `cd -`, defines `function name {`, or uses a backtick substitution turns c0120's live scan red and blocks every finish that selects it.
- The tempting fix is to relabel the three bullets and add the rest. That leaves the cheapest regressions in place.

Consequences:
- Each modelled shape changes rule R. Each needs a case and a mutant, and E8 must be rerun.
- The shapes left as edges only need truthful text.

Recommendation:
- Model the three that are one-line rules, which turns their "reports" into "as main":
  - (a) a cd whose argument is neither a root form nor a literal folder (`cd -`, `cd "$OLDPWD"`, `cd "$T"`, `cd "$(…)"`) resets its frame to the home (`root = false`, `dir = ""`). That is main's reading.
  - (b) a root cd inside backticks is no root cd (as main). Alternatively, make backticks frames.
  - (c) `function name {`, and a `name()` whose `{` starts the next line, are function bodies.
- Cases:
  - #1, #2, #5, #6 and #9 each report nothing;
  - #8 reports `z-nile/roots.luau (from z-nile)`.
- Mutant: each of (a), (b) and (c) dropped.
- List the rest with their real outcome:
  - pipelines (#4, #14, #23): reports;
  - a cd in a branch (#26): reports, by the static reading the spec pins;
  - a `for` list spanning lines (#10): fails open;
  - parentheses in a heredoc body (#7): fails open;
  - any unquoted escaped or expanded parenthesis (#18, #19): fails open;
  - an echoed loop value with a redirect (#15): fails open.
- Rerun E8. It must still gain 0.
- If the author leaves (a) to (c) unmodelled instead, the bullets must say "reports" for them, and the user decides on that list.

Lesson: zz-test/measure-hand-written-readers-on-the-corpus (a corpus that agrees with the old reader says nothing about an edge it does not contain; each bullet's stated outcome needs its own fixture run)

### F2 [medium] The Design does not state the rules round 4 added; item 5 contradicts the grep rule the prototype has; the Rules table and the Test plan stop at round 3
Where: Design items 2, 3 and 5; Rules and mutants; Test plan; E3.

Evidence:
- **Item 5 contradicts the code.**
  - Item 5 says "`grep` and `rg` get the same condition as echo (their pattern rule was keyed on the bare word …)".
  - The prototype says the opposite (line 583, `if (command or unquoted) and (w == "grep" …`), and so do the Known edges ("A grep's pattern needs no position: any unquoted `grep` … as in main").
  - An executor who implements item 5 rebuilds round 4's F1: c0261's `git grep`, open in 48 worktrees.
- **Item 5 is stale on the label.** It still says the label "is blanked wherever `check` stands". The prototype exempts `--check` (line 504).
- **Item 2 misses round 4's quoting rules.** It names `<<WORD`, `<<-WORD` and `<<'WORD'`. It does not name:
  - `<<\WORD` or `<<"WORD"`;
  - that a here-string starts nothing;
  - main's two comment rules for the words of heredoc bodies and scripts (a line that starts with `#`, and a ` # ` tail);
  - the ` # ` cut that stops a script's parentheses.
- **Item 3 misses the cd rule.** It does not say that a cd whose argument goes on after the named form (`"$ZN_ROOT"/sub`, `$ZN_ROOT/$H`, `…toplevel)/sub`) is no root cd.
- **Rules and mutants has no rows for round 4.** None of these rules has a row: refute 004's N1 to N14, nor the FILES test's per-line quote count. E3 says "84 mutants (65 named)", but the table names only M rows.
- **The Test plan lists 22 cases; the spec has 27.** Missing:
  - "grep's pattern is text as main reads it …";
  - "a comment line or a ` # ` tail in a heredoc body or a script …";
  - "a cd that goes on after the named form …";
  - "a function that names grep in a comment or a message …";
  - "what the Design names stays pinned …".
- I ran round 4's mutants (`mut.log`). N1, N2, N3, N3b, N4a, N4b, N6a, N7a, N7b, N7c, N8, N8b, N9, N10, N11, N12, N13, N14 and N15 are all killed by the homes spec without its live case. So the record is missing, not the cases.

Critique:
- The Design is the executor's spec of record. Implementation step 3 names the diff "the reference", so the code will likely be right. But the document's rules disagree with the code and the spec.
- The final review's trace cites the Test plan, which does not name five of the cases.

Consequences: none beyond the text.

Recommendation:
- Restate round 4's rules in items 2, 3 and 5. Item 5's grep sentence becomes main's rule: any unquoted `grep`, `egrep` or `rg` word marks its pattern; a quoted one marks nothing.
- Add one Rules row each, `run`, with the mutant names above:
  - N1, the unquoted grep word;
  - N2, `<<\`;
  - N3 and N3b, the comment rules in heredoc bodies and scripts;
  - N4a and N4b, `<<-`;
  - N6a, the here-string;
  - N7a to N7c, the cd that goes on;
  - N8, `--check`;
  - N9, a helper body's position;
  - N10, the script's ` # ` cut;
  - N11 and N12, the case pattern's `;;` and line start;
  - N13, a backslash in a script;
  - N14, a helper call ends with its script;
  - N15, FILES' per-line quote count.
- List the five cases in the Test plan.

Lesson: z-design/spec-design-correspondence

### F3 [medium] Ten mutants of rules the Design or its Known edges name survive every spec, the live tree included
Where: Rules and mutants; E3 ("all killed").

Evidence:
- Each mutant below passes the homes spec without its live case (26/26, `mut.log`). It also passes the four specs with the live case (35/35, `mutfull.log`).
- Each one is killed by the one-line input shown (`cases7.txt`, `mutcase.log`: v6's findings against the mutant's):
  - **N12b**, the `case` text test's `in` alternative removed. Input: `(cd "$ZN_ROOT"; case "$x" in a) true ;; esac; test -f tests/run.luau); test -f z-nile/roots.luau`. v6 reports `tests/run.luau` (root) and `z-nile/roots.luau`; the mutant drops the first. In the spec's cases the line-start alternative covers every `in`. Round 4 found `in` the only alternative pinned; now it is the only one unpinned.
  - **X1 and X1b**, `keywordAt`'s `then` and `else` removed. Input: `for f in tests/gone.md; do if true; then for g in a; do case "$g" in *"$f"*) ;; esac; done; fi; test -f "$f"; done`, and the same with the inner loop after `else`. v6 reports `tests/gone.md`; the mutants are silent (the inner `done` ends the outer body).
  - **X7**, an echo message no longer stops at a backtick (item 7 names it). Input: ``echo "found `cat src/gone.luau`"``. v6 reports; the mutant is silent.
  - **X13**, a literal cd in a double-quoted script after a root cd joins the root frame. Input: `cd "$ZN_ROOT"` / `check "AC1" bash -c "cd pickman && test -d src/server"` / `test -f z-nile/roots.luau`. The mutant reports `pickman/z-nile/roots.luau`.
  - **X16**, a helper call anywhere, not only in command position (item 5 names it). Input: `has() {…}` / `foo has "tests/gone.md"`. v6 reports; the mutant is silent.
  - **X19**, a text-only `for` list runs to the line end instead of its `;`. Input: `for f in a; do case "$E" in *"$f"*) ;; esac; test -f src/gone.luau; done`. v6 reports; the mutant silences every path in the body.
  - **X33**, a script starts from the top-level stack's bottom frame instead of its current one (item 3: "a single-quoted script starts from a copy of the top-level frame"). Input: `(cd "$ZN_ROOT" && bash -c 'test -f z-nile/roots.luau')`. v6 reports nothing; the mutant reports it.
  - **X37**, a `<<` inside double quotes starts a heredoc. Input: `grep -qF "cat <<EOF" "$F"` / `(cd "$ZN_ROOT" && test -f z-nile/roots.luau)`. v6 reports nothing; the mutant reports it.
  - **X39**, a helper body's grep counts outside the body's context. Refute 004 F4 says "in the body's context". Input: `fail() { echo 'grep "$1" failed'; return 1; }` / `fail "src/gone.luau"`. v6 reports; the mutant is silent.
- **N6b is equivalent.** Removing the here-string's `i + 2 ~= "<"` guard changes nothing: `<<<` puts a `<` where the delimiter must start, so the delimiter pattern fails anyway.
- **Killed controls:** X2 (`do`), X14 (`esac`), X26 to X31, X35, X36 and N9.
- **Also survived, not counted above:**
  - X3 (a `$(` level that does not count its inner parentheses): my input did not kill it, so I did not show it is real;
  - X25 (`for` as an argument), X32 (a second `-e` in a helper) and X34 (a comment right after `(`): I judged these contrived.

Critique:
- E3's "all killed" holds for its own list. Each survivor is a rule the Design or a refute names. A future edit can break it with every spec green.
- X19 and X16 are the plausible slips: both fail open.

Consequences: none beyond the cases.

Recommendation:
- The ten inputs above become cases, each with its expected findings, and each gets a Rules row.
- Remove the N6b guard, or note it as redundant.

Lesson: zz-test/seed-every-enumerated-case

### F4 [low] Records that are stale or inconsistent
Where: frontmatter; the Design's reader paragraph, Existing work, E1, Affected specs; check.sh AC5; E8.

Evidence:
- **`size: 1210`.** v6 in c0120's folder is 952 + 14 added and 279 removed, which is 1,245. With the skills and inputs.tsv it is about 1,250 (v5 was 1,208). That is still under z-raft's 1,500.
- **"The homes spec 22 cases"** (the reader paragraph), "22/22 (v5 of the module …)" (E1) and "(22 cases)" (Affected specs). The spec has 27 cases, and the module is v6.
- **Existing work** says "the finished corpus's reports are unchanged except the 13 above (E8); E5 over open worktrees". E8 now says 17, and E5 compares with nothing.
- **AC5's `grep -v -e "/rafts/"`** exempts every raft's check.sh, not only "the raft's" (its label). An edit to R0072's check.sh (c0193's raft) would pass.
- **E8 judges a worktree's file against the checkout's tree, and compares literals without the Touched exemption that c0141 changes.**
  - My per-tree run (`e8b.log`) and the full-scan comparison (`wt.out`) both agree with E8: 0 gained. So the result stands.
  - Without them, the executor's rerun does not check the same thing.

Recommendation:
- Correct the counts and the size.
- Narrow AC5 to the item's own raft: the `raft:` line of c0371.md at check time. Or state why every raft is exempt.
- Record the per-tree and full-scan comparisons beside E8. Both scripts are in `rv5-probes/`: `rv5e8b.luau`, and `rv5wt.luau`, which is round 4's `wt.luau`.

## Round 4's answers, checked
- **F1:** true in the code, the spec and the corpus. N1 is killed; c0261's `git grep` reads as main; 0 gained over the checkout and 161 worktrees.
  - Not true in the Design: item 5 still says grep needs command position (F2).
  - "Position stays required for … helper calls, `for`" is true in the code, but nothing pins it (X16, F3).
- **F2:** true in part. `<<\EOF` is modelled (N2 killed), the header is rewritten, E9 cites both corpora, and the bullets round 4 asked for are there.
  - Not true: "each form its real outcome" (F1: backticks, `for` lists spanning lines, the function spellings).
  - Not true: "E5 is no longer cited as a comparison". The Existing work paragraph still cites it (F4).
- **F3:** true for (a) to (e) and for the FILES reading. N3, N3b, N6a, N7a to N7c, N8, N10 and N15 are killed, and the cases pass. N6b is equivalent.
  - None of these rules is in the Design (F2).
- **F4:** true for the position test (N9 killed). Its context part survives (X39, F3).
- **F5:** true. N4a, N4b, N13, N10, N11, N12 and N14 are killed. The `in` alternative is now the unpinned one (N12b, F3).
- **F6:** true as of round 4: the size, the counts (650 then, 647 on my corpus), E5's header and the zz-test sentence. The size has since moved with v6 (F4).
- **F7:** true. The lesson now says to narrow only the quoted case.

## Fields checked and consistent
- **Overrides and affected specs.**
  - Overrides names c0120's check-paths spec. The issue is a chore, so it needs no `depends_on`.
  - `lune run z-nile/affected` on the six Touched paths prints the same 31 specs the Design lists.
  - No promoted spec pins the sentences being edited. I searched for "backticked path per bullet", "resolves from its home" and "Then run `lune run z-nile/affected"; the only hit is a comment in c0120's finished.spec.
- **inputs.tsv:** the line's form (`<spec>\t*`) matches the file's other `*` lines.
- **AC6:** its five phrases match item 9's sentence, and "in one convention for the whole list" matches the z-design bullet. All six are absent from the skills today, so AC6 is red before the change.
- **c0141:** `new`, with its Scope decision line.
- **The prototype:** v6 is c0141's module 46f7d115 plus `experiments/checkpaths.diff`.
- **Repository safety:**
  - The specs write only `.cache/c0371-check-paths/`.
  - E8-corpus.sh writes only `z-nile/.cache/e8*.luau` and reads the worktrees.
  - AC5 and AC6 only read.
- **Bounded commands:** E5's and E8's headers name `../zn run --time`.

## Lesson candidates (for the lead)
- **zz-test, a note on measure-hand-written-readers-on-the-corpus:**
  - Rule: a corpus run that agrees with the old reader proves nothing about an edge the corpus does not contain. Run each listed edge on a fixture with both readers, and write the outcome you saw (as main, fails open, reports) on its bullet. Judge every corpus file against its own tree, and compare full scans (Touched included), not only literals.
  - Why: c0371's E8 gained 0 on 647 files, while three Known-edge bullets still stated "as main" for forms that report correct checks (backticks, the function spellings) or fail open (`for` lists spanning lines).
  - Check: which fixture case shows each bullet's stated outcome?
- **zz-test, a note on shell-readers-carry-state-across-lines:**
  - Rule: state carried across lines needs an exit for every way bash leaves it: a cd back (`cd -`, `"$OLDPWD"`), a cd to a variable, a pipeline's subshell, a function spelled `function name {`.
  - Why: c0371's root frame survived all four and reported correct checks from the root.
  - Check: for each state the reader carries, which commands end it in bash, and which case pins each one?

Verdict: changes
