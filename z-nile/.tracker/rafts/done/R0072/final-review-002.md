# Review 002: R0072 (final mode)
Reviewer: claude-fable-5-2
Inputs: HEAD `09a4dc0f8` (`R0072: trace for the finished stack`) on `R0072/2/c0193`. The top layer's finish commit is `43f8094fc` (`c0193: Lesson scanner loops advance`), layer 1 is `1e6f313df` (`c0192: Lesson bound every probe`), stacked on `origin/main` `91ee2ac62`. Read: `git diff origin/main...HEAD` (45 files), `R0072.md`, `c0192.md`, `c0193.md`, the three `check.sh` files, `trace.md`, `./zn capture c0192` and `./zn capture c0193` (both confirmed, no marker), the changed sources in full (`loops.luau`, `hostile.luau`, `scanners.luau`, `scan.luau`, both meta cases, `loops-writes.spec`, `slow-tier.spec`). `final-review-001.md` and `final-refute-001.md` were read only after the findings below were formed.

Why a second final review: `final-review-001.md` was written by a fallback model, and layer 2's code changed after it (its F1 and F2 fixes in `loops.luau`, and `Allowed.sweep` widened back to `(string | boolean)?`). This review judges the stack as it stands.

Runs, each probe through `../zn run --time <seconds> --`, scratch files under the worktree's `.cache/fr2/` (removed):
- `./zn trace R0072 --check`: `ok: R0072`, exit 0.
- `lune run tests/run -- tests/tooling/loops-writes.spec.luau tests/meta/scanning-loops.spec.luau`: 14 passed, 0 failed.
- `loops.find` over 29 hand-built loop texts (the results that matter are in F2 and under "Checked and holding").
- `loops.find` over `loops.files()`: 82 loops, 5 proven (`affected.luau:31`, `stats.luau:169`, `specs.luau:109`, `tests/run.luau:360`, `record.luau:29`), 77 listed.
- The F2 loop as a real program: one million passes without `i` moving.

Not run (heavy disk load, as instructed): `z-nile/check.sh` in any mode, `./zn check c0192`, `./zn check c0193`, the slow-tier `finishes.spec` and `scanners.spec`, and the 23 advance-stopping mutants of `c0193.md:265`. Their recorded results (`results.txt`, the Verification logs) were taken as given.

Checked and holding:
- The five proven loops. I read each. Every one steps its variable at the top level, and no body line writes the bound. `tests/run.luau:360` walks `schedule.order`'s list and inserts nothing into it.
- Variable and bound rewrites in code stylua leaves as written. These all report `advances=false`: `q[#q + 1] = i` under `#q`; `n = n + 1` and `n += 1` under `n`; `st.n += 1` and `st["n"] += 1` under `st.n`; `a.b = { c = i + 1 }` and `a["b"] = …` under `a.b.c`; `table.insert(a.b, i)` and `a.b[#a.b + 1] = i` under `#a.b`; `table.insert(self.other, q)` under `#q`; `q = nil`; `x, i = i, x`; a step followed by `i -= 1`, with or without a trailing comment; a nested function that sets `i = 0`; `while i <= i do`; a step followed by `--[[ x ]] i -= 1` on the same line.
- Still proven, as the design says they are invisible to a line scan (`c0193.md:58`): a write through an alias (`local o = st` then `o.n += 1`), an aliased `insert(q, i)`, `rawset(q, …)`, and a method on the owner of a dotted bound (`self:push(i)` under `self.count`). zz-arch rule 9 and the lesson's check question hand these to the reviewer. Not findings.
- `local i: number` then `i += 1` at the top level is proven, and raises at run time (arithmetic on nil), so it fails closed.
- `if a == f("k=v") then i = 0 end` on one line is proven, because `assigns` stops at the first `=` on a line. Stylua (no `collapse_simple_statement` in `stylua.toml`) rewrites that into three lines, where the reset is seen. Not reachable through the gate. Not a finding.
- Review 002 F3 at run time. `loops.luau:261` refuses every sweep that is not `false` and not a string, so `sweep = true` gives the "names the scanners case that sweeps it, or false" problem. `loops-writes.spec:86` builds that entry through `:: any` and expects exactly one problem, and passes. The type `(string | boolean)?` at `loops.luau:17` is what the sequestered `problems.spec:21` needs. No entry of `loops.ALLOWED` uses `true`. The hole is not reopened.
- Sequestration. The only addition under an `acceptance/` folder is `c0193/acceptance/watch.txt`, whose six paths are the six source files of the trace; `./zn finish` is its writer (lesson zz-review/finish-watch-is-generated). No `check.sh` or spec changed.
- Scope. Each capture holds one Problem and an empty Solution template; each document's title and Problem are the capture's words; each lesson keeps the captured check question.
- The human's rulings. `slow.tsv:57-58` holds the two rows the first ruling asks for. `slow-tier.spec`'s `present()` accepts a row whose spec is still sequestered and still refuses a path with no file.
- The trace's line citations. Every `loops.luau`, `hostile.luau`, `scanners.luau`, `scan.luau`, `slow.tsv` and `inputs.tsv` range I opened holds what its cell says (`loops.luau:88-120` is `writes`, `:150-220` is `find`, `:225-287` is `problems`, `:330-738` is `ALLOWED`). The cited `check.sh` lines are the criteria named. The acceptance-spec lines are the cases named.

Old findings (`final-review-001.md`), judged against this commit:
- F1 (wrapped call on the bound, owner write, `table.move`, split method): the fix is real. `loops.luau:91-98` and `:112` do the three things recommended, each of the five shapes reports `advances=false`, `loops-writes.spec:102` pins them and `:118` pins the read-only forms as still proven. Its last recommendation, "In `trace.md`, replace the AC4 sentence that names this finding with the new cases", was not done: F1 below.
- F2 (step inside a block comment or long string): the fix is real for long brackets (`loops.luau:182-184`, `loops-writes.spec:125`). The same hole is open through a quoted string continued with a backslash: F2 below.
- F3 (`trace --check` failed): fixed. The check prints `ok: R0072`.
- F4 (slow-tier wording): fixed. `zz-test/SKILL.md:50` says the sweep spec is in the slow tier and how to run it, and `c0193.md:301` records the departure from "Where the checks run".

### F1 [medium] The AC4 row of trace.md says no case holds the shapes that the current code and spec do hold, and cites neither the cases nor the recorded deviation
Where: `z-nile/.tracker/rafts/active/R0072/trace.md:21` (the `c0193:AC4` row), its design and test cells.
Evidence: The test cell ends "No case holds a table call on the bound that stylua wrapped, or a step inside a block comment (final review F1 and F2)". At this commit `z-nile/tests/tooling/loops-writes.spec.luau:102` ("does not prove a loop whose bound is written through a wrapped call, an owner, table.move or a split method"), `:118` ("still proves loops whose bound is only read") and `:125` ("does not prove a step that sits inside a block comment or a long string, and keeps nested indexing") hold exactly those shapes, and pass. The cell cites `loops-writes.spec` lines 17, 23, 28, 49 and 58 only. The code cell cites `loops.luau:88-120` and `:150-220`, which now include the bound-alone rule (`:91-94`), the owner rule (`:95-98`), the `table.<fn>(` rule (`:112`) and the long-bracket rule (`:182-184`). No cited test proves those four rules. The design cell cites the deviations at `c0193.md:293` and `:299`, not `c0193.md:301`, where these four rules are recorded. So for AC4 the row does not hold as design = test = code: the code has behaviour whose test and design record the row leaves out, and the row states something false about the tests. `./zn trace R0072 --check` cannot see this, because the cells are well-formed.
Critique: The code and the spec are right; only the record is stale. The tempting fix is to delete the false sentence and stop there, which leaves the four rules with no cited test.
Consequences: The edit is to `trace.md` only, in one cell row. It changes no source file, so `Commit:` stays `43f8094fc` and the check still passes, as it does now with the trace commit on top. No spec case is needed.
Recommendation: In the `c0193:AC4` row, replace the "No case holds …" sentence with the three cases above, cited as `z-nile/tests/tooling/loops-writes.spec.luau:102`, `:118` and `:125` with their names, and add `z-nile/.tracker/issues/active/c0193/c0193.md:301` to the design cell beside `:293` and `:299`. Rerun `./zn trace R0072 --check`.
Lesson: z-design/restated-rules-move-together

### F2 [low] A step that exists only inside a backslash-continued quoted string still proves the loop, and a paren inside a string defeats the "one whole scan.advance call" test
Where: `z-nile/tests/lib/loops.luau:59` (`steps` strips `%s+%-%-.*$` before matching), `:182-184` (only `[[` forms void the proof), `:37-55` (`closesAtEnd` counts parens inside string literals).
Evidence: Both texts report `advances=true`, and stylua leaves both loops as written.
- `while i <= n do` / `local s = "x\` / `i += 1 --\` / `"` / `emit(s)` / `end` (body lines one tab in). The middle line is string content. The comment strip removes ` --\`, and what is left matches the step pattern. Run as a program with `i, n = 1, 3`, the loop made one million passes with `i` unchanged.
- `while i <= n do` / `i = scan.advance(i, g("(")) - f(")")` / `end`. The `(` in the first string and the `)` in the second cancel, so the call is read as closed by the statement's last character. This is the shape `c0193.md:53` rules out (`scan.advance(i, j) - f(k)`), and it can return `i`.

AC4 says a loop is proven only when its own top level steps its variable, through one whole `scan.advance` call. Neither text meets that. Both need a deliberate, odd line: a string that happens to hold a step followed by `--`, or parens in string literals on a `scan.advance` line of a loop that reads no text. Nothing in today's tree has either shape, and the five proven loops are unaffected. That is why this is low, and why it does not hold the verdict.
Critique: Final review 001 F2 closed the long-bracket form of the first shape by refusing the proof when the lint cannot tell code from text. A quoted string that spans lines is the same situation. Teaching the line scan to read strings is the tempting fix, and it is a second parser.
Consequences: One rule covers each without reading strings. A body line that ends with a backslash is inside a continued string, and a `scan.advance` step line that holds a quote character cannot have its parens counted. Refusing the proof in both cases only moves loops from proven to listed. `\z` continuation ends its line with `z`, not a backslash, so the first rule must name it too. A `"` in a step line's trailing comment would also void that proof, which is the safe direction.
Recommendation: Capture it as an issue (it changes `loops.find`, so it is a new layer, not a records edit): void the proof when a body line ends with `\` or `\z`, and do not count a `scan.advance` line holding `"`, `'` or a backtick as a step. Cases for `loops-writes.spec`: both texts above must not prove; `i = scan.advance(i, next)` and a body with an ordinary one-line string must still prove.
Lesson: zz-test/source-text-pins-read-the-code

### F3 [low] The loops.find sweep case's witness does not show that the call reaches writes()
Where: `z-nile/tests/lib/scanners.luau:53-58`; the loop it sweeps is `z-nile/tests/lib/loops.luau:100`.
Evidence: The witness is `{ text = "", result = "1" }`: the number of loops `find` returns for the wrapped text. `find` returns one loop for that text whether or not `writes` is ever called (for instance if the wrapper's header stopped parsing as `V < B`, so `boundName` were nil). The witness therefore holds for a case that no longer reaches the listed loop. What ties the case to the loop today is the recorded mutant SW8 (`c0193.md:276`), a one-time run. The design gives this witness (`c0193.md:45`) and says per-loop reach is a recorded claim, so the code matches its design.
Critique: A witness is defined as "the result only the scanner's work produces" (`c0193.md:43`). A count of loops is not that for `writes`.
Consequences: `find` exposes nothing that depends on `writes` except `advances`. A call that returned `advances` for a text whose only bound write is found inside the `while at do` loop (the second occurrence of the name on a line) would make the witness depend on the loop.
Recommendation: Fold into the issue of F2, or leave as recorded: change the case's call to return the first loop's `advances` for a body line where the bound's write is its second mention, with the witness result `false`. No change is asked of this stack.

## Judged criteria
- c0192: its document says "Judged: None." (`c0192.md:140`). Nothing to rule on. The trace's `c0192:AC6` and `c0192:AC7` rows are the tool reading those "None." lines as claims (c0301); their cells say so and prove nothing, which is the honest content for them.
- c0193: its document says "Judged: None." (`c0193.md:247`). Nothing to rule on. The same holds for the trace's `c0193:AC10` and `c0193:AC11` rows.

## Lesson candidates (for the lead)
- F1, a note on `z-design/restated-rules-move-together`: a fix made after a final review changes what the trace's cells must cite. A sentence in the trace that names an open finding is a restated fact, and it goes stale when the finding is fixed. Check: after the revision, does any trace cell still describe the finding as open, and does the row cite the cases that pin the fix?
- F2, a note on `zz-test/source-text-pins-read-the-code`: a line lint that refuses to prove inside a long bracket has the same duty for every other way a string spans lines or hides the characters it counts. Check: for each character the lint counts or strips (a paren, `--`), what does it decide when that character sits inside a string literal?

Verdict: changes
