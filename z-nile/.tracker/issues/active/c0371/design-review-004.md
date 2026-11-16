# Review 004: c0371 (design mode)
Inputs: prep worktree `prep-check-paths-homes` at 01be55638 (clean); origin/main 1a6a3a156. Read:
- c0371.md, check.sh, the three acceptance specs, `experiments/` (E5, E7, E8-corpus.sh, E8-corpus.luau.txt, checkpaths.diff), design-review-001..003, design-refute-001..003 and harvest.md;
- the prototype `v5-checkpaths.luau` (md5 2632f55e) and `v5-spec.luau`;
- `./zn capture c0371`, c0141.md, the three lessons this prep added, and zz-review, zz-test, z-design.

Scope of this round, as briefed: the user ruled "Land with known edges", so whether the reader is complete is not judged. Judged here:
- whether the Known edges are truthful;
- regressions against main's reader (the scanner in origin/main's `c0120/check-paths.spec.luau`);
- whether each rule's mutant dies by its own case, and whether the fields agree;
- whether round 3's answers are true.

How I ran it:
- Scratch clone `scratchpad/rv4-c0371`, with its remote pointed at nothing and origin/main merged in. v5 is installed as `c0120/checkpaths.luau` and `c0120/check-paths.spec.luau`, and c0371's specs are under `tests/acceptance/c0371/`.
- Every probe ran under `../zn run --time`. Probes and outputs are in `/private/tmp/claude-501/-Users-philipbergen-code-pickman/3fbf9326-e053-49c8-ab1e-bfbc221fe8f4/scratchpad/rv4-probes/`:
  - `cases.luau`: main's scan and the prototype's on one fixture item, with the cases in `cases1..5.txt` (`#Cn` below);
  - `lost.luau`: every literal lost or gained;
  - `wt.luau`: main's scan against the prototype's over all open worktrees;
  - `comments.luau` and `onefile.luau`.
- `patch` confirms that c0141's module 46f7d115 (on origin) plus `experiments/checkpaths.diff` gives v5 byte for byte.

Results:
- **Specs:** 31/31 pass (homes 22, touched-from-home 4, uses-module 1, c0120's 4).
- **E8 re-run:**
  - 464 check.sh files (c0375 was added since); 35 literals lost, 13 of them would-be reports, **0 gained**.
  - The 13 are exactly the Design's list (c0193 ×4, c0292 ×4, c0083 ×3, d0297 and R0013 ×1 each).
  - I read the other 22 lost literals: all are echo messages, for-list prose, or root reads that exist at the root.
  - So inside E8's corpus (live and finished), there is **no regression against main**.
- **Open worktrees (149), main's scan against the prototype's (`wt.luau`):**
  - Lost: only the intended ones (f0201 ×40, c0292 ×33, and c0141's exemption for c0293, c0195 and c0371).
  - **Gained: c0261's `scripts/tracker`, in 48 worktrees.** This is a real check.sh that main reads right and the prototype reports (F1).

Counts:
- **Regressions against main confirmed: 1 on a real check.sh** (c0261, outside E8's corpus), 0 inside E8's corpus, plus 15 synthetic shapes in ordinary forms (F1, F3, F4; 13 of them are on no list).
- **Untruthful Known-edge statements: 4** (F2 (a) to (d)).

### F1 [high] Narrowing grep's pattern rule to command position makes reports main never makes: `git grep` (live in c0261's check.sh), wrapper functions, and every introducer that takes options
Where:
- Design item 5 ("`grep` and `rg` get the same condition as echo");
- the Known edges' command-position bullet;
- E5 ("c0261 `scripts/tracker`" filed under "plain missing paths of older states");
- the module's `command and (w == "grep" …)` branch (v5 line 560).

Evidence:
- **c0261 AC12** is open in 48 worktrees and was withdrawn on main by #325. It reads `bash -c "specs=\$(git grep -lE 'models\\.toml|(engine|scripts/tracker)/(dispatch|…)' -- tests/acceptance …"`.
  - Main marks the pattern after the bare word `grep` and reads nothing.
  - The prototype reads `scripts/tracker`, because `grep` after `git` is not in command position. That path is missing from `z-nile/`, so the prototype reports it (`onefile.luau`: "main: (none); new: scripts/tracker").
  - E5 printed this report and filed it as an older state's missing path. Main does not report it on the same tree.
- **Synthetic cases** (main silent, the prototype reports the pattern; all are correct checks):
  - #C1 `! git grep -qF "tests/old.spec.luau" -- .`;
  - #C2 `git -C "$ZN_ROOT" grep -qF "scripts/old.sh"`;
  - #C8 `quiet grep -qF "src/x" "$F"` (a wrapper function the check defines);
  - #D6 `run grep …`;
  - #C7 `xargs -r grep`;
  - #C9 `time -p grep`;
  - #C4, #C5, #C6 `timeout -s KILL 10 grep`, `env -i grep`, `sudo -u x grep`. These are the listed edges, and they fail closed, not open (F2 (a)).
- "No reference to the old path remains" is an ordinary check, and `git grep` is its usual form. Two corpus files already use `git grep` (c0247, c0278), with non-path patterns today.

Critique:
- This is not an unmodelled form. It is a rule the Design changed: main keyed the rule on the bare word, the prototype on command position.
- So every command position the reader misses becomes a red gate on a correct check, which is the failure c0371 exists to fix.
- The tempting fix is to add `git` to the introducers. That leaves `git -C <dir>`, wrappers and every introducer that takes options.

Consequences:
- Round 1's defect was a **quoted** `"grep"` or `"echo"` argument (`foo "grep" tests/gone.md`). Main's rule is right for an unquoted `grep` word.
- Restoring main's rule for an unquoted grep word keeps round 1's fix. `foo grep tests/gone.md` (unquoted) then reads as main does, so it is no regression.
- Rule L's `matchedUse` takes the command's first word as its head. A `git grep -qF "$f"` body is then read as a use, which is main's reading (the list is read). The design can leave that as it is or reuse the same reading.

Recommendation:
- grep's, egrep's and rg's pattern is text when the word is in command position, **or when it is an unquoted word of its context** (outside double quotes, not inside a message or a code span).
- Cases, each reporting nothing:
  - `! git grep -qF "tests/old.spec.luau" -- .`
  - `git -C "$ZN_ROOT" grep -qF "scripts/old.sh"`
  - `quiet() { "$@"; }` then `quiet grep -qF "src/x" "$F"`
  - `timeout -s KILL 10 grep …`, `env -i grep …`, `xargs -r grep …`
- Cases still reported: `foo "grep" tests/gone.md` and `grep -qF "echo" tests/gone.md`.
- Mutant: drop the unquoted-word branch.
- Rerun E5 as a comparison with main (see F2): the result must gain 0, including c0261.

### F2 [high] The Known edges list is not truthful
Where: Design, **Known edges** (its header, the bullets and the closing paragraph); E5; E9.

Evidence (each from `cases*.out`):
- **(a) The header is false for the command-position bullet.**
  - The header says "An unmodelled form fails open or as main did".
  - `timeout -s KILL 10 grep`, `env -i`, `sudo -u x`, `xargs -r` and `time -p` each make a report main does not make (#C4 to #C7, #C9).
  - `find -exec grep`, listed as "not followed", is in fact read as a command (#C3), but only because `-exec` matches the `-c` test (`^%-[%a]*c$`). `-execdir` does not match.
- **(b) The `case` bullet states one consequence, and the other one is real too.**
  - The bullet says other shapes "pop a frame early".
  - The text test also takes a real close for a pattern. Example (#C17): a subshell whose `)` starts its line inside a `case` arm, as in `a)` / `(` / `cd "$ZN_ROOT"` / `true` / `)` / `test -f z-nile/roots.luau`.
  - Nothing is popped, and the root reading goes on past the subshell. Main reports `z-nile/roots.luau`; the prototype is silent (fails open).
- **(c) The heredoc bullet lists forms the reader handles, and misses two it misreads.**
  - It handles heredocs inside `$(…)` and inside `"$(…)"` (#C19, #D3), and `$'…'` inside double quotes (#C20). All three read as main.
  - `<<\EOF` (a quoted delimiter) is not detected, so an apostrophe in its body inverts the quoting. Main reports the label line's `default.project.json`; the prototype is silent (#C15).
  - (A here-string with a literal word is F3 (c).)
- **(d) The closing paragraph says "per form, the corpus has no case where the form changes a report", and E9 says E8 is the only evidence.**
  - The Design cites E5 for the open worktrees, and E5's own output holds c0261's new report (F1), filed as an old state's missing path.
  - E5 compares with nothing, and E8 leaves out `.worktree`.
- **Forms not on the list that read differently from main:**
  - **A root file of the home (`default.project.json`, `zn`, `AGENTS.md`, …) on an inner line of a multi-line double-quoted script** (#C21). The FILES test now uses the cross-line `dq` instead of main's per-line quote count. Main reports the file; the prototype is silent.
  - **A `case` pattern's `)` inside `$(…)`** (#C26). The quoting pass closes the `$(` level there, and the `'` in `echo "it's"` then inverts the quoting for the following lines (the label line is silenced).
  - **An echo message of several words used as data**, as in `for f in $(echo "src/a.luau src/b.luau"); do test -f "$f"; done` (#C25). Both paths are silenced. This is rule E's cost, and unlike rule H's cost it is not stated.

Critique:
- The user's ruling rests on this list: each unmodelled form is listed and measured.
- A list that names behaviour the reader does not have, and misses forms it misreads, misinforms that ruling.
- (a) matters most: its forms turn the gate red on a correct check, which the user was told they do not.

Consequences:
- F1's fix makes (a) true ("as main") for grep.
- Correcting (b) to (d) only changes text. The measurement change adds one experiment: E5 compared with main, which is `wt.luau`'s method.

Recommendation:
- Rewrite the header as each edge's real outcome (fails open, as main, or a report).
- After F1, the command-position bullet keeps only echo, printf, helpers and the `check` label, which read as main.
- State (b)'s second consequence, or fix it: a `)` that starts its line closes a subshell when a `(` of the same frame is open on an earlier line.
- Replace (c)'s first half with what the reader really does. Add `<<\WORD` (or model it: a backslash before the word quotes it).
- Add the three forms above with their outcome.
- Make E5 a comparison with main's reader over the open worktrees (main's literals read from the home, with Touched compared as written). Record its gained and lost lists, and make E9 cite both corpora.

Lesson: zz-test/measure-hand-written-readers-on-the-corpus ("fix every regression against the old reader": E5 ran the new reader over the worktrees but never ran the old one there)

### F3 [high] Forms the Design models read differently from main's per-line reading and report correct checks: comment lines in heredoc bodies and in scripts, a here-string, a root cd that goes on after its named form, and a label after `--check`
Where:
- Design item 2 (quoting: heredoc bodies, comments) and item 3 (rule R's forms);
- the module's `literals` comment cut (v5 lines 466-480), the label blanking (482), the heredoc start (163-182) and the cd branch (711-735).

Evidence. Each case is in a z-nile item (`cases2..5.out`):
- **(a) Heredoc bodies.**
  - Main skips a line that starts with `#` and cuts at ` # `. The prototype keeps the words of a body but drops both rules.
  - Each of these is reported now, and main reports nothing: `cat > "$T/x.md" <<'EOF'` / `# tests/gone.md` / `EOF` (#D1); `see the note # tests/gone.md` in a body (#D2); an indented `# tests/gone.md …` in a `bash <<'EOF'` script (#D5).
- **(b) Comments inside scripts.**
  - The code cuts ` # ` inside a script (`%s#%s`). The Design does not name this rule, there is no Rules row, and no case kills it (F5, ME).
  - The cut misses a comment that starts its line, and every comment in a double-quoted script. Main skips both:
    - `bash -c '` / `# tests/gone.md is made by the fixture` / `true'` (#E1);
    - the same with an indented comment in `bash -c "…"` (#E2).
  - The corpus has 11 comment lines inside scripts in 10 files, 3 of them live (d0297:21, c0173:34-35, c0174:34). All are indented, which is the only reason they read right.
- **(c) A here-string with a literal word** (`grep -q x <<< "abc"`, or `<<< abc`) starts a heredoc at its second `<`. The `<<<` test guards only the first. The rest of the file is then frozen as heredoc body:
  - #C13: a later `bash -c 'cd "$ZN_ROOT" && true'` becomes a top-level cd for the rest of the file, so main's report of `z-nile/roots.luau` is silenced;
  - #C14: a later comment `# tests/old.md was removed` is read and reported.
- **(d) A root cd whose argument goes on after the named form** is read from the root and drops the rest:
  - `cd "$(git rev-parse --show-toplevel)/z-nile" && test -f tests/run.luau` reports `tests/run.luau (from the repository root)` (#C10);
  - so does `cd "$ZN_ROOT"/z-nile && …` (#C11);
  - `H=z-nile; cd "$ZN_ROOT/$H" && test -f tests/run.luau` reports a path with a `$` in it, `$H/tests/run.luau`, which main never reports (#C12).
  - All three are correct checks, and main reads them from the home, where the files exist.
- **(e) "Blanked wherever `check` stands" also blanks after `--check`.** `stylua --check "src/gone.luau"` is silenced; main reports it (#L1). The corpus has this form 4 times, with variables (c0292:76, c0047, c0048, c0050).

Critique:
- None of these is an unmodelled form; each is a rule of the Design read more loosely than main. (a), (b), (d) and (c)'s #C14 are reports on correct checks.
- Comments in scripts and heredocs are in the corpus already. Today only the indent and the absence of path-like words keep them silent.
- The tempting fix for (b) is to widen the `%s#%s` pattern. That still misses a `#` at the start of a line.

Consequences:
- For heredoc bodies and scripts, main's two comment rules are what keeps "the body's words keep main's per-line reading" (review 003's consequence) true.
- A root cd that is no longer recognised in (d) reads as main reads it: from the home. List it as a Known edge, or model `"$ZN_ROOT"/<sub>` by joining the word after the closing quote.

Recommendation:
- (a) and (b): mark heredoc-body bytes in `quoting`. On a line of a heredoc body, inside a script, or inside double quotes, apply main's rules: skip a line whose first non-blank byte is `#`, and cut at ` # ` outside double quotes. Name the rule in item 2 and give it a Rules row.
- (c): a `<<` that is part of `<<<` starts nothing (test both of its `<`).
- (d): a cd is a root cd only when its argument ends at the named form: the quote or the word ends right after `$ZN_ROOT`, after `$ZN_ROOT/<sub>` with no `$` in `<sub>`, or after `$(git rev-parse --show-toplevel)`. Any other cd whose argument holds a `$` is no cd, as in main.
- (e): blank a label only after a `check` that is a command (not after `-`).
- Cases:
  - #D1, #D2, #E1, #E2, #C14, #C10, #C11 and #C12 each report nothing;
  - #C13 reports `z-nile/roots.luau (from z-nile)`;
  - #L1 reports `src/gone.luau`;
  - a heredoc line with a path and no `#` is still reported.
- One mutant per rule.
- Rerun E8 and the worktree comparison, with each fix applied on its own.

Lesson: zz-test/shell-readers-carry-state-across-lines

### F4 [medium] Rule H finds a search helper in the raw words of a function body: a comment or a message that says `grep "$1"` makes one, which contradicts the Design ("names grep in a message is none") and refute 003 F4 ("not words")
Where: Design item 4; `searchHelpers` (v5 lines 246-311: `gmatch` of `grep` over the body text, quotes and comments included).

Evidence: main reports `src/gone.luau` for each of these, and the prototype is silent (`cases4.out`):
- #H1: `lint() {` / `  # like grep "$1", but runs the linter` / `  lune run "$1"` / `}` / `lint "src/gone.luau"`;
- #H2: `fail() { echo "grep $1 failed"; return 1; }` / `fail "src/gone.luau"`.

The body is also cut at a raw brace count, so a `}` inside quotes ends it early. That case (#H3) happens to read right.

Critique: the case for "names grep in a message" (#31's `lint`) passes only because the word after `grep` is not positional.

Consequences: the stream rule L already uses (`keywordAt`: same context, outside double quotes and comments, command start) answers this for H too.

Recommendation:
- Count a `grep`, `egrep` or `rg` in a body only where `keywordAt` holds. With F1, also count an unquoted word of the body's context.
- Cases: #H1 and #H2, each reported.
- Mutant: the position test dropped.

Lesson: zz-test/one-rule-one-function

### F5 [medium] Seven plausible mutants of rules the Design or its Known edges name survive every case, the live ones included
Where: Rules and mutants; E3 ("69 mutants … all killed").

Evidence:
- `.cache/rv4mut/run.sh` in the clone applies each mutant. It runs the homes spec without its live case, and for a survivor also c0120's spec, the full homes spec and touched-from-home. All of these pass (30/30) for each mutant below.
- The killed controls are the quoted delimiter, the `$'` escapes, the `do`/`then` keyword test, helper recursion, the `"$@"` loop variable, the list end and `esac`.
- Survivors:
  - **MA:** `<<-` with no tab strip.
  - **MB:** `<<-` not detected. The `<<-` case still passes because a heredoc that never ends freezes the quoting, which gives the same report on its label line.
  - **MR:** a backslash escapes `'` inside a script, against item 2's "inside a script every byte but `'`".
  - **ME:** the script ` # ` cut removed (an unnamed rule, F3 (b)).
  - **MF:** the `case` text test's line-start alternative removed.
  - **MG:** its `;;` alternative removed. The Known edges name both alternatives, and only `in` is pinned.
  - **MN:** a helper call no longer ends when its script ends.

Critique: E3's count holds for its own list. Each survivor is a word the Design names, the same class as review 003 F6.

Consequences: none beyond the cases.

Recommendation: one case and one Rules row each.
- **MA and MB:** a `<<-` heredoc with an apostrophe, then `check "AC1" bash -c 'cd "$ZN_ROOT" && true'`, then `test -f z-nile/roots.luau`, reported from z-nile. The heredoc must end for the script to be a script.
- **MR:** `x='a\'`, then the root-group line, reported from z-nile.
- **ME:** F3 (b)'s cases.
- **MF and MG:** a multi-line `case` inside a root subshell whose patterns start their lines and follow `;;`, then a home path, reported.
- **MN:** `has() {…}`, then `check "AC1" bash -c 'has "$F" "x"' _ "tests/gone.md"`, reported.

Lesson: zz-test/seed-every-enumerated-case

### F6 [low] Records that are not true or not consistent
Where: frontmatter; E8 and the Known edges; E5's header; Design item 9; design-refute-003 F7.

Evidence:
- **`size: 1000`.** `git diff --numstat` counts added plus removed lines (`engine/main.luau`'s size table, `spend.luau`). The two c0120 files alone are 910 + 14 added and 279 removed: 1,203. With the skills and inputs.tsv it is about 1,208. That is 21% over the estimate, against z-raft's 1,500 cap.
- **"463 check.sh files, 241 live and 223 finished"** does not add up: 241 + 223 = 464.
- **E5's header still says `lune run .tracker/issues/c0371/experiments/E5-worktrees`**, which the hook refuses. Refute 003 F7 says this is fixed. E1 and E3 also still do not say they ran under `./zn run`.
- **The zz-test sentence** calls "an `echo` or `printf` message in command position" prose, without the one-word value (review 003 F7 asked for it).

Recommendation:
- Set `size:` to about 1,210.
- Correct the counts.
- Put `../zn run --time 290 --` in E5's header.
- Add "(a message of one word is a value)" to item 9's sentence. AC6's phrase still matches.

### F7 [low] The lesson this prep extended prescribes the narrowing that caused F1
Where: `z-nile/skills/zz-test/lessons/shell-rules-key-on-command-position.md`.
Evidence: its "How to apply" is to narrow `grep` and `echo` to command position and to pin the quoted-argument case. It does not say that the narrowing turns every command position the reader misses (`git grep`, a wrapper, `xargs -r`) into a new report. F1 is that outcome.
Recommendation: amend it, as in the lesson candidates below.

## Round 3's answers, checked
- **F1:** true for the cases and mutants it lists (M37, M38, M49, M50).
  - Not true: "skips heredoc bodies" drops main's comment rules inside them (F3 (a)), and the `<<-` case does not kill its mutant (F5).
  - Of the Known edges it names instead of the backstop, two are modelled (F2 (c)).
- **F2:** true for (a) to (f): the brace case is flipped, frames are pushed and popped, the double-quoted cd reads as main, the splice continues, and the comment cut follows the quoting pass at the top level.
  - Not true: (g) "with its limits listed" (F2 (b)).
- **F3:** true. c0250 is not among E8's lost literals, and the cases and mutants exist.
- **F4:** true for rule L (`done` is a keyword, nested loops are counted).
  - Not true for rule H: helper detection still reads words (F4).
- **F5:** true for the cases. The forms it calls Known edges are listed, but they make reports (F1, F2 (a)).
- **F6:** true.
- **F7:**
  - Not true for E5's header (F6).
  - True for the one-item wording: the Scope decision line says "unfold c0141 … into c0371".
  - The zz-test sentence still omits the one-word value (F6).
- **Fields checked and consistent:**
  - Overrides names c0120's check-paths spec. The issue is a chore, so it needs no depends_on.
  - Searching the promoted specs for the edited sentences of zz-test and z-design finds no spec that pins them.
  - The inputs.tsv line parses (`sel.parseInputs`). The selector prints only specs that exist (`affected.luau` line 170), so the line is harmless before `done`.
  - AC6's five phrases match item 9's sentence, and "in one convention for the whole list" matches item 3's bullet.
  - c0141 is `new`, with its Scope decision line.
  - c0141's prototype commit is on origin.
  - The specs write only `.cache/c0371-*` fixtures, and AC5 and AC6 only read.

## Lesson candidates (for the lead)
- **zz-test, a note on shell-rules-key-on-command-position:**
  - Rule: narrowing a rule the old reader applied wherever its word stood turns every command position the new reader misses into a new report. Narrow only the case that was wrong (the quoted word), and keep the old rule for the unquoted word.
  - Why: c0371's grep rule moved to command position, and c0261's `git grep` pattern became a red gate on a correct check.
  - Check: after which words that are not introducers can grep stand (`git`, `xargs -r`, a wrapper function), and does the old reader still mark its pattern there?
- **zz-test, a note on measure-hand-written-readers-on-the-corpus:**
  - Rule: run the old reader beside the new one on every corpus the design cites, the open worktrees included, and list what is gained.
  - Why: E5 ran only the new reader over 143 worktrees and filed a new report (c0261) as an old state's missing path.
  - Check: does each corpus experiment print what the old reader reports on the same files?

Verdict: changes
