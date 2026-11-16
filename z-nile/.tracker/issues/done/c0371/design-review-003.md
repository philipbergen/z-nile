# Review 003: c0371 (design mode)
Inputs: prep worktree `prep-check-paths-homes` at fa94e0fbd (clean). Read:
- c0371's c0371.md, check.sh, the three acceptance specs, `experiments/` (checkpaths.diff, E5, E7), design-review-001/002, design-refute-001/002 and harvest.md;
- `./zn capture c0371` (efa610174);
- c0141's folder: its two specs, diffed against c0371's copies, which differ only in names, fixture folders and stylua layout. Its Scope decision line is the branch's only change to c0141 against origin/main;
- c0375 on origin/main (close superseded items);
- the zz-review, zz-test and z-design rules this cites, and the lessons harvest.md names.

How I ran it:
- A scratch clone of the worktree, `scratchpad/rv3-c0371`, with its remote pointed at nothing and origin/main 1a6a3a156 merged in. `v3-checkpaths.luau` is the module and `v3-spec.luau` is c0120's spec; c0371's three specs are under `tests/acceptance/c0371/`.
- `patch` confirms that c0141's module 46f7d115 plus `experiments/checkpaths.diff` gives v3 byte for byte.
- On the clone, c0371's specs pass 16/16, 4/4 and 1/1, and c0120's passes 4/4 (25/25). The Affected specs command prints the 31 specs listed, exactly.
- Every probe ran under `./zn run --time`. The probes are in `scratchpad/rv3c0371-probes/`:
  - `diff.luau`: what c0141's module and v3 read and report, for every check.sh;
  - `lines.luau` and `lits.luau`: what each module reads, per line or per file;
  - `cases.luau` with `cases1.txt` and `cases2.txt`: hand-written cases through both modules' `scan`, in a fixture like c0371's spec;
  - `mut.sh` with `apply.luau`: mutants run against c0371's homes spec without its live case, then c0120's spec.
  - Case numbers `#n` below are the cases files' own numbers.

Round 2's answers, checked:
- **True:** F1 (comments), F4, F7 for the mutants it lists, F8 (#450 is c8cd4e18; the module is on Touched and named in the Overrides parenthesis) and F6 for rule E.
- **True except:**
  - F2: the bytes after a ` # ` that the word loop cuts off are never read (F2 (f) below).
  - F3: only the two idioms are continued, not the `'"$X"'` splice (F2 (e)). The brace rule it kept is wrong for bash (F2 (a)).
  - F5: "outside quotes" means outside double quotes only. Single quotes and comments still end a body (F4).
  - F9: "the experiments ran under `./zn run --time`" is recorded nowhere, and E5's header gives a bare `lune run` (F7).
- **Contradicted:** rule L counts the one-word echo that rule E (F6) reads as a value as a match (F3).

The corpora: over 241 live and 223 finished check.sh files, v3 reports nothing that c0141's module does not (0 new).
- What it silences is c0292, c0193, d0297, c0083 and R0013, all prose.
- One silence is a real miss: c0250's six spec paths (F3).
- The other new defects are in forms the corpus has only a few of today, or none. One live file has them: c0247's heredoc and its double-quoted script (F1, F2).

**Structural highs: 3** (F1, F2 and F4: each is a defect class in the reader, not a single missing case). Rounds 1 and 2 also found structural highs in this reader. The pattern is the same each time: a rule silences words based on state it inferred, so every construct the reader does not model fails open, contradicting the Design's "fails closed".

### F1 [high] The quoting pass reads heredoc bodies, `$'…'` strings and the double quotes inside `"$(…)"` as plain quoting, so an apostrophe in any of them inverts every context after it. This is review 002 F1's class, and the live c0247 has it
Where:
- Design item 2 (`quoting`), Existing work ("**Guards:** … fails closed … text the reader cannot place stays a path");
- the module's `quoting` (v3 lines 91-135).

Evidence:
- **Live, c0247** (backlog). Line 21 is `read -r -d '' PARA <<'EOF'`, followed by a paragraph of skill prose with 5 apostrophes ("the user's", "the dispatcher's", …).
  - The pass takes the odd one as an open single quote, and the state stays inverted until a later quote puts it back, by line 35.
  - I put two probe lines after c0247's line 23:
    - `check "AC9: the item's diff" git diff --quiet -- default.project.json`: v3 does not read `default.project.json`.
    - `(cd "$ZN_ROOT" && true); test -f z-nile/roots.luau`: v3 reads it from the root (`z-nile/roots.luau@ROOT`), but bash runs it from z-nile/, where it is missing.
  - c0141's module reads both correctly, and so does v3 when the same lines go before the heredoc (after line 20) or after line 35. The label line is still dropped after line 33.
  - The live case passes only because lines 24 to 34 hold no word whose reading changes, the same accident as review 002 F1.
- **Finished heredocs** have odd counts too: c0058 has 3 apostrophes in its heredoc. R0026 (4), c0076 (8) and c0185 (128) happen to be even.
- **Regressions against main.** In a z-nile item, c0141's module reports each of these and v3 reports nothing:
  - #4, #30: a heredoc (`<<'EOF'`, `<<-EOF`) holding `it's`, then the label line above (`default.project.json`);
  - #5: the same heredoc, then `check "AC1" bash -c 'cd "$ZN_ROOT" && true'`, then `test -f z-nile/roots.luau`. The inverted pass reads the script's cd as a top-level cd that lasts to the end of the file;
  - #11: `x=$'it\'s'`, then the label line. In `$'…'`, `\'` is an escape, but the pass ends the string there;
  - #12: `x="$(echo "it's")"`, then the label line. Inside `$(…)`, double quotes start a new level of quoting, but the pass simply toggles `"`.

Critique:
- Every rule reads this state: H's quoted-argument test, S's double-quote test, FILES' quote test, R's group and script ends, and the `$(` count.
- The tempting fix is to skip heredoc bodies. That leaves `$'…'` and nested quotes. An end-of-file check that the pass finishes at the top level would not catch c0247 either, because its apostrophes balance before the end.

Consequences:
- A heredoc body runs from the line after `<<WORD` (also written `<<'WORD'`, `<<"WORD"` or `<<-WORD`) to the line that is exactly `WORD` (tabs stripped for `<<-`).
  - `<<<` is a here-string, not a heredoc, and a `<<` inside quotes starts nothing.
  - The rest of the `<<` line is still shell (`cat <<EOF | grep …`).
  - Main reads words on the body's lines (c0185's bodies are fixture JSON). To drop nothing main reports, the body's words can keep main's per-line reading while changing no state.
- A `$(` or backtick inside double quotes opens a quoting level of its own, in which `"` and `'` are quotes again, and its `)` closes that level. This is a stack. It also replaces `dqSub`, whose count is today the only thing that makes c0292's line 67 balance.

Recommendation:
- In `quoting`, model:
  - heredoc bodies (no state change);
  - `$'…'` with its escapes;
  - a stack of levels for `$(`, backticks and `"` (the current `ctx` and `dq` are its top).
- Keep a backstop: when the pass ends a file inside a quote or a heredoc, read that file with c0141's per-line reading and the root reading off. Then the reader fails closed, as the Design claims.
- Cases, each reported as c0141's module reports it:
  - c0247's shape (an odd-apostrophe heredoc, then the label line and the root-group line);
  - `<<-`;
  - `$'it\'s'`;
  - `"$(echo "it's")"`;
  - `cat <<EOF | grep -q x` with `src/gone.luau` on the line after the terminator.
- Mutants: heredocs read as shell; `\'` in `$'…'` taken as the end of the string; `"` inside `$(…)` toggled.
- Correct the Guards sentence, then rerun E1 and E5 with each fix applied alone.

Lesson: zz-test/shell-readers-carry-state-across-lines (its review 002 note covers comments, and heredocs, `$'…'` and nested quoting are the same class)

### F2 [high] The root reading's scopes are not bash's. A brace group ends it (the spec pins this wrong reading); a subshell's cd replaces the top-level one; a literal cd outlives its subshell; a double-quoted script's cd lasts to the end of the file; a `'"$X"'` splice ends a script's cd; a ` # ` in quotes hides a `)`; a top-level `case` `)` ends it
Where:
- Design item 3 (rule R) and item 9 (the zz-test sentence);
- the homes spec's case "a group that closes at the end of its line" (`{ cd "$ZN_ROOT" && true; }; …`, spec lines 307-308) and its header;
- v3 lines 309 (the ` # ` cut), 482-526 (parens and braces), 547-563 (slots and the literal cd), 476-481 (`slotOf`);
- E6.

Evidence: each case is in a z-nile item unless it says otherwise; the fixture has `z-nile/roots.luau` and `z-nile/tests/run.luau`.

(a) **A brace group runs in the current shell.**
- Bash prints `b` for `cd a; { cd b && true; }; echo ${PWD##*/}` (run here). A `( … )` subshell gives `a`.
- So `{ cd "$ZN_ROOT" && true; }; test -f z-nile/roots.luau` runs the test at the root, where the file exists, and a right reader reports nothing.
- The spec requires the report `z-nile/roots.luau (from z-nile)` (#2), so a reader that follows bash fails AC1.
- `{ cd "$ZN_ROOT" && true; }; test -f tests/run.luau` is silent (#1), although that path is missing at the root.
- A function body's `}` is the only one that ends a cd made inside it, for the text after the definition.

(b) **One top slot.**
- `cd "$ZN_ROOT"`, then `(cd "$ZN_ROOT/pickman" && true)`, then `test -f tests/run.luau` is silent (#26).
- The subshell's cd replaces the top-level reading and its `)` ends both, but bash runs the last line at the root.

(c) **A literal cd is appended to the slot for good.**
- `cd "$ZN_ROOT"`, then `(cd pickman && test -d src/server)`, then `test -d src/server` (#10): v3 reads line 3 as `pickman/src/server` (present) and is silent.
- Bash runs it at the root, where `src/server` is missing.
- c0141's module reports `src/server (from z-nile)`, so this is a regression against main.

(d) **A `bash -c "…"` script is not a context.**
- Its `cd` is taken as a top-level cd that lasts to the end of the file.
- Live c0247 line 48, `bash -c "cd '$ZN_ROOT/z-nile' && …"`, makes v3 read every later line of c0247 from `z-nile/` at the root. That is right only because c0247 is z-nile's own.
- In a pickman item with the same line 48, then `test -f tests/run.luau` (#28): c0141's module reports `tests/run.luau (from pickman)` and v3 is silent (a regression).
- `test -d src/server` in the same item (#27): v3 reports `z-nile/src/server (from the repository root)`, a false report on a correct check.

(e) **Splices end a script.**
- `check "AC1" bash -c 'cd "$ZN_ROOT" && test -f '"$F"' && test -f tests/run.luau'` is silent (#3). So is the three-line script with `grep -qF "'"$W"'" AGENTS.md` on its line 2 (#24).
- The `'"$X"'` splice is the common way to put a variable into a single-quoted script. Only `'"'"'` and `'\''` are continued.

(f) **The comment cut.**
- `line = string.gsub(line, "%s#%s.*$", "")` cuts at a ` # ` inside quotes too, so the `)` after it is never read.
- `(cd "$ZN_ROOT" && grep -qF "a # b" AGENTS.md)`, then `test -f z-nile/roots.luau` (#6): c0141's module reports it, and v3 is silent (a regression).
- This breaks the Design's "every byte of every line is read".

(g) **A `case` pattern.**
- A top-level `cd "$ZN_ROOT"`, then `case "$x" in a) true ;; esac`, then `test -f tests/run.luau` is silent (#14).
- E6 names this edge only "in a multi-line script".

Critique:
- R is the one rule that reads more, and each gap above is a place where the reader's scope model differs from bash's.
- (c), (d) and (f) silence paths that main reports, against Non-goal 3. (a) is pinned the wrong way, so it cannot be fixed without changing the spec.
- The tempting fix is one more special case per shape. Fixing the brace rule alone would break function bodies.

Consequences:
- Directories form a stack. A subshell, a command substitution, a backtick, a script (single- or double-quoted) and a function body each push a frame that copies its parent's directory, and their close pops it.
- A cd, from the root or literal, changes only the top frame.
- Brace groups, `if`, `while`, `for` and `case` bodies push nothing.
- A function body's frame ends at its `}`. A top-level call of a function that cds to the root (#13: `toroot() { cd "$ZN_ROOT"; }`, then `toroot`, then `test -f tests/run.luau`) is then still missed. Read such a call as that cd, or record the limit in E6.
- In a `case … in` up to its `esac`, the `)` that ends each pattern is not a close.

Recommendation:
- Replace the two slots with that stack, read on F1's quoting levels.
- Cut comments where the quoting pass marks one, never at a ` # ` inside quotes.
- A `'` that ends a script, followed with no blank by a quoted or plain word and a reopening `'`, continues the same script.
- Flip the brace case in the spec: `{ cd "$ZN_ROOT" && true; }; test -f z-nile/roots.luau` reports nothing, and with `tests/run.luau` it reports `tests/run.luau (from the repository root)`.
- Add one reporting case each for (b) to (g), and one for a function body (`f() { cd "$ZN_ROOT"; }`, then a home path: read from the home).
- Mutants: a brace group pops; a subshell's cd replaces its parent's; a literal cd outlives its frame; a double-quoted script is no frame; a splice ends the script; the ` # ` cut kept; a `case` pattern's `)` closes.
- Change the zz-test sentence to "to the end of the subshell, command substitution, script or function body that holds the cd", and keep AC6's phrase "after `cd "$ZN_ROOT"` from the repository root".
- Rerun E1 and E5.

Lesson: zz-test/shell-readers-carry-state-across-lines

### F3 [high] Rule L takes a value that echo or printf prints for a match, so the live c0250's six spec paths are no longer read. Rule E's own rule says a one-word message is a value
Where:
- Design item 8 ("or in an echo/printf message");
- `matchedUse` (v3 line 233: `if head == "echo" or head == "printf" then return true`).

Evidence:
- c0250 (prepared, lines 56-66):
  - `fastSpecs() { for s in tests/acceptance/c0068/stop.spec.luau tests/acceptance/c0117/dispatch.spec.luau tests/acceptance/c0118/model.spec.luau tests/tooling/work.spec.luau tests/tooling/readycheck.spec.luau tests/tooling/approve.spec.luau; do grep -qF "	$s" tests/slow.tsv || printf '%s\n' "$s"; done; }`;
  - then `runFast` runs `lune run tests/run -- $(fastSpecs)`.
- `$s` is grep's pattern and an argument of printf, never a message, and the list is a list of files the check runs.
  - c0141's module and main read all six; v3 reads none (diff.luau, `LIT-` lines).
  - They exist today, so nothing is reported. If one moves, the scan stays silent.
- Synthetic regressions:
  - `for f in tests/gone.md; do echo "$f"; done | xargs cat` (#8);
  - the c0250 shape with a missing spec (#9).
- Mutant Mp (printf removed from `matchedUse`) survives every case, the live one included. No case uses printf in a loop.

Critique:
- A loop that prints its items is the usual way a shell function returns a list.
- Rule E already says what a message is (several words) and what a value is (one word). Rule L uses a looser test of its own.

Consequences:
- A use is a match only when it stands inside a message of several words in rule E's sense: printf's format, or echo's message with other words (`echo "missing $fact"`, c0083's shape, stays text).
- `echo "$f"`, `printf '%s\n' "$f"` and `printf "%s\n" "$f"` are values.

Recommendation:
- Make `matchedUse` call rule E's message reading on the word stream (see F4).
- Cases, each reported:
  - c0250's shape with a missing spec;
  - `echo "$f"` piped to xargs;
  - `printf '%s\n' "$f"`.
- Cases still prose: c0083's and c0193's shapes.
- Mutants: echo or printf arguments counted as matches; Mp.

Lesson: z-design/one-reading-per-value

### F4 [high] Rules L and H read the check with tokenizers of their own, which know neither single quotes, comments nor command position, so a loop body ends at a stray `done` and a function becomes a helper because a message names grep
Where: `textOnlyLoop` (v3 lines 251-283), `matchedUse` (lines 215-246), `searchHelpers` (lines 139-189); design-refute-002 F5.
Evidence: c0141's module reports each of these and v3 is silent, in a z-nile item:
- #7: a loop over `tests/gone.md` whose body is `grep -qF "$f" "$E" || exit 1 # not done yet`, then `test -f "$f"`, on separate lines. `textOnlyLoop` ends the body at the `done` in the comment.
- #22: `… grep -qF "$f" 'not done'; test -f "$f"; done`. A `done` in single quotes counts, because `restDq` tests double quotes only. So refute F5's "by words outside quotes" holds for double quotes only.
- #23: `… || ./zn done c0001; test -f "$f"; done`. A `done` that is an argument counts.
- #31: `lint() { lune run "$1" || { echo "lint failed: grep the log"; return 1; }; }`, then `check "AC1" lint "src/gone.luau"`. The word grep anywhere in the body makes `lint` a search helper.
- #15: `typecheck() {` on one line, `  lune run "$1" || return 1; }` on the next, then `has() { grep …; }`. The body runs on to the next line that starts with `}`, so it takes in `has`'s grep.
- #32: `passes() { lune run tests/run -- "$1" 2>&1 | grep -q " 0 failed"; }`, then `passes "tests/acceptance/c0001/gone.spec.luau"`.
  - The Design discloses the cost of "a quoted literal file path given to a helper".
  - But `passes` greps its own output and is not a search helper in the user's sense (has, g, words, has_all all pass a positional parameter as grep's pattern).
- Mutants Mw (`while` and `until` not counted as nesting) and Mhrg (rg dropped from helper detection) survive every case.

Critique:
- Each rule re-reads the raw text with `gmatch` and gets the quoting, comment and command-position rules wrong that the word loop gets right.
- The next finding would be another copy's gap. Review 002 F5 asked for "the same reader the word loop uses", and the answer kept a second reader.

Consequences:
- Run the quoting pass and the word loop once over the whole text into a word stream: each word with its byte, context, quoting, comment flag, command position and frame.
- Rules H, L and E and the helper detection read only that stream.
- A search helper is then a function whose body, read on the stream, passes one of its positional parameters as grep's or rg's pattern: `$1` and up, `"$@"`, `"$*"`, or a `for w in "$@"` variable. The same holds for a call to such a helper with one of them.
- With the argument position known, only the arguments at the pattern positions are text. That closes #32 and reads `has "skills/x.md" "text"`'s file again, a cost the Design can then drop.

Recommendation:
- Build the stream and rewrite L, H and E on it.
- Cases: #7, #22, #23, #31, #15 and #32, each reported; `while` and `until` nesting; an `rg` helper.
- Mutants: a `done` in a comment or in single quotes counted; a `done` that is an argument counted; grep mentioned anywhere makes a helper; the body runs to the next line that starts with `}`; Mw; Mhrg.

Lesson: zz-test/one-rule-one-function

### F5 [medium] Command position is narrower than main's grep rule, so a pattern after an assignment prefix, `timeout`, or a `check` that does not start its line is read as a path
Where: Design item 5; `INTRODUCERS` and the label blanking (v3 lines 192-209 and 311).
Evidence: v3 reports `src/x (from z-nile)` for each of these, and c0141's module reports nothing:
- `LC_ALL=C grep -qF "src/x" "$F"` (#16);
- `timeout 10 grep -qF "src/x" "$F"` (#18);
- `true; check "AC2: y" grep -qF "src/x" "$F"` (#17). The label is blanked only at the start of a line, so the command after it is not at command position.

c0120's own literal case has `…; check "AC4" ./zn audit`. Existing work names only the shapes review 002 ran. None of these is in the corpus today (0 new reports).

Critique: each turns the gate red on a correct check, which is the failure this item fixes.
Recommendation:
- A word after one or more `NAME=value` words at command position is at command position.
- `timeout <n>`, `nice`, `nohup` and `sudo` (with their options) are introducers.
- Blank every `check "<label>"`, wherever the `check` stands.
- Cases: #16, #17 and #18, each reporting nothing. One mutant each.

Lesson: zz-test/shell-rules-key-on-command-position

### F6 [medium] Seven plausible mutants survive every case, the live one included
Where: Rules and mutants; E3.
Evidence: `mut.sh` ran each mutant against the homes spec without its live case plus c0120's spec (19/19), then with the live case (20/20):
- Mw: rule L's nesting counts only `for`;
- Mp: printf dropped from `matchedUse`;
- Mb: the `${NAME}` form is not a use;
- Me: egrep dropped from the grep rule;
- Mrx: `--regexp` is not treated as `-e`;
- Mhrg: rg dropped from helper detection;
- Mbr: the `{` after a top-level root cd is not counted. Then `cd "$ZN_ROOT" || { echo "no root"; exit 1; }`, the usual guard, ends the root reading at its `}`, and nothing pins it.

Each one is a word the Design names. E3's "50 mutants, all killed" holds for its own list.
Recommendation:
- One case and one Rules row each. F3 and F4 cover Mp, Mw and Mhrg.
- For Mbr: `cd "$ZN_ROOT" || { echo "no root"; exit 1; }`, then `test -f tests/run.luau`, reported from the root.

Lesson: zz-test/seed-every-enumerated-case

### F7 [low] Statements that are not true or not recorded
Where: E5 and E6, Design header "One item", design-refute-002 F9, Design item 9.
Evidence:
- E5's header says to run `lune run .tracker/issues/c0371/experiments/E5-worktrees`, which the hook refuses. Neither E5 nor E1 nor E3 says the run used `./zn run --time`, although refute F9 says it did.
- E6 names the `case` edge only in a multi-line script (F2 (g)).
- The Design says "One item (the user's ruling …)", while refute F8 calls the one-item reading "the coordinator's decision". c0375's capture ("c0141, absorbed by c0371") suggests the user knows, but no `Decided with the user` line records it.
- Design item 9's zz-test sentence claims more than the code: "the group … that holds the cd" (F2 (a)), "a function that runs grep or rg" (F4) and "an `echo` or `printf` message" without the one-word value.
- Design item 3 (c0141's part) quotes only the new first clause of z-design's Touched bullet. Say that the rest of the bullet ("Then run `lune run z-nile/affected …`") stays.

Recommendation:
- Record the `./zn run --time` wrapper in E5's header and in E1, E3 and E5.
- Fix E6 and the zz-test sentence together with F2 to F4.
- Either word the header as the coordinator's reading or record the user's confirmation.
- Say that the rest of the Touched bullet stays.

Lesson: z-design/restated-rules-move-together

## Lesson candidates (for the lead)
- zz-test, a note on shell-readers-carry-state-across-lines:
  - Rule: a quoting pass models every byte that is not shell (comments, heredoc bodies, `$'…'`) and every construct that nests quoting (`$(` and backticks inside double quotes). An unmodeled one fails open, and an end-of-file balance check does not see it.
  - Why: c0247's live heredoc (5 apostrophes) inverted the pass for the 12 lines after it.
  - Check: what state does the pass hold on the line after a heredoc that holds `it's`?
- zz-test, new:
  - Rule: a reader that tracks where a command runs keeps the shell's scopes as a stack. Subshells, command substitutions, scripts and function bodies push one; brace groups and compound commands do not.
  - Why: c0371's prototype ended a cd at `}` (its spec pinned this), let a subshell's cd replace its parent's, and kept a literal cd past its subshell.
  - Check: what does bash print for `cd a; { cd b; }; pwd`, and what does the reader read there?
- z-design, a note on one-reading-per-value:
  - Rule: a rule that makes a word text checks the word's use against the other rules' value readings.
  - Why: rule L took `printf '%s\n' "$s"` for a match while rule E calls a one-word echo a value, which dropped c0250's six spec paths.
  - Check: in which of the rule's matching uses is the variable printed as a value?

Verdict: changes
