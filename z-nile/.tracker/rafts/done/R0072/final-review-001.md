# Review 001: R0072 (final mode)
Inputs: HEAD `905f909f4` (`R0072: trace skeleton`, 2026-11-15 15:59:59 -0800) on `R0072/2/c0193`. The top layer's finish commit is `7b8ec3756` (`c0193: Lesson scanner loops advance`). Layer 1 is `16218897e` (`c0192: Lesson bound every probe`), stacked on `897c0475e`. Read: `git diff origin/main...HEAD` (42 files), `R0072.md`, `c0192.md`, `c0193.md`, their `check.sh` files, c0193's acceptance specs, both `results.txt` files, `./zn capture c0192` and `./zn capture c0193` (both confirmed captures, no marker), `review-001.md`, `review-002.md` and their refutes, the harvest files, and the changed sources. `trace.md` is filled in the worktree. `Commit:` is `7b8ec37561287880b45932b7f0021c3134115ad2`.

Runs, each probe through `./zn run --time <seconds> --`, scratch files under `z-nile/.cache/final-r0072/` (removed after):
- `./zn trace R0072 --check` in this worktree: 27 lines, exit 1. The first is `row Commit, commit: table is stale (R0072/1/c0192 is not stacked on the layer below)`. The other 26 are `check.sh:<n> did not run green for this stack`, one per `check.sh` line the table cites. The stale line names no commit.
- The same filled table in a shared clone whose local `main` is `897c0475e` and whose `origin` is removed: `ok: R0072`.
- `loops.find` on the shapes below, and stylua (`stylua.toml`, column 110) on the long `table.insert`.
- A scratch copy of `loops.luau` with the rules in F1 and F2, over the real tree and over copies of `loops.spec` (19), `problems.spec` (10), `loops-writes.spec` (10) and `scanning-loops.spec` (1): 40 passed, 0 failed.

Checked and holding:
- Scope. Each capture is one Problem outcome and an empty Solution template. Each document's title and Problem are the capture's, word for word. Each lesson keeps the captured check question.
- The count of loops. `loops.find` over the 119 covered files reports 5 proven and 77 listed, and `loops.problems` reports 0. I read the five proven loops (`affected.luau:31`, `stats.luau:169`, `specs.luau:109`, `run.luau:360`, `record.luau:29`). Each steps its variable, and the body leaves the bound alone. `run.luau:360` walks `schedule.order`'s list and does not insert into it.
- Sequestration. The acceptance diff is one addition, `z-nile/.tracker/issues/active/c0193/acceptance/watch.txt`. Its six paths are the six source files in the trace. `./zn finish` writes that file.
- The human's rulings. All three bullets under `## Open to the human` in `R0072.md` carry `Ruled (user, 2026-11-13)`. `slow.tsv` holds the two rows the first ruling asks for.
- c0192. `check.sh` and the meta case pin the lesson. `lessons.luau` knows neither `enforced_by` nor `unattributed`, so AC4's and AC5's conditional branches did not run, as their designs allow. The stack changed source files, so a code cell cannot be `none` (c0301). c0192's code cells cite `inputs.tsv` and say the lesson is the implementation.

### F1 [high] loops.find proves a loop whose body writes its bound once stylua wraps the call, and when the bound's owner is replaced
Where: `z-nile/tests/lib/loops.luau:88-110` (`writes`), used at `:182`. Design rule 4 is `c0193.md:55`. AC4 is `c0193.md:239`.
Evidence: Stylua, with this repository's `stylua.toml`, rewrote a breadth-first loop whose `table.insert` does not fit in 110 columns into:
```
	while head <= #queue do
		local item = queue[head]
		head += 1
		table.insert(
			queue,
			childOf(
				item,
				"someLongArgumentNameNumberOne",
				"anotherLongArgumentNameNumberTwo",
				"yetAnotherLongArgumentNameToForceTheWrap"
			)
		)
	end
```
`loops.find` reports `advances=true` for that text. The same loop with `table.insert(queue, child(item))` on one line reports `advances=false`. Four more texts report `advances=true`:
- `while i <= opts.max do` / `i += 1` / `opts = { max = i + 1 }`. Each pass sets `max` to `i + 1`, so the loop does not end.
- `while i <= opts.max do` / `i += 1` / `opts["max"] = i + 1`.
- `while i <= #q do` / `i += 1` / `table.move(a, 1, 1, #q + 1, q)`.
- `while i <= #q do` / `i += 1` / `q` / `:push(i)`.

`q:push(i)` on one line reports `advances=false`. AC4 requires that the bound "is a number, a name or `#name` that the body never writes". Rule 4 names this case: "no `table.insert/remove/…(B`, no method call on it (`B:push`), so a queue that grows by the step is unproven". `writes` sees `table.<fn>(` only when that call sits immediately before the bound on the same line, and for a dotted bound it looks for the whole path. A proven loop needs no entry, so no reviewer reads it. `loops.spec` holds the one-line forms. `loops-writes.spec` holds wrapped assignments. Neither holds a wrapped call on the bound. No loop in today's tree is proven wrongly.
Critique: One more pattern for "the bound and a comma on a line" closes the stylua shape and leaves the owner write, `table.move`, and the method split after the receiver. `writes` lists the forms of a write and reads every other mention of the bound as harmless.
Consequences: A wider `writes` turns a proven loop into a listed one. I ran a scratch copy with the three rules below and with F2's rule:
- The real tree is unchanged: 119 files, 5 proven, 77 listed, 0 problems. The five proven loops stay the five above.
- Copies of `loops.spec` (19), `problems.spec` (10), `loops-writes.spec` (10) and `scanning-loops.spec` (1) passed, 40/40.
- Every shape above reports `advances=false`. `while i <= opts.max do` / `i += 1` stays proven. `local c = items[i]` under `#items` stays proven. A wrapped `table.insert` whose own-line argument is another name stays proven. `local c = rows[cols[i]]` / `i += 1` stays proven.

The fix is on layer 2, so `./zn finish c0193` and the restack of F3 follow. Lines inserted in `writes` move every `loops.luau` citation in the trace below `:88`.
Recommendation:
- In `writes`, count three more forms as a write:
  - a line that holds nothing but the bound, with or without a `#` before it and a comma after it;
  - for a dotted bound, any assignment to its root name, through the same `assigns` test (`opts = …`, `opts["max"] = …`, `opts.other = …`);
  - a `table.<fn>(` anywhere before the bound on the line.
- Add cases to `z-nile/tests/tooling/loops-writes.spec.luau`. Must not prove: the wrapped `table.insert(` / `queue,` loop as stylua writes it; `opts = { max = i + 1 }` and `opts["max"] = i + 1` under `while i <= opts.max do`; `table.move(a, 1, 1, #q + 1, q)` under `#q`; `q` and `:push(i)` on successive lines. Must still prove: `while i <= opts.max do` / `i += 1`; `local c = items[i]` under `#items`; a wrapped `table.insert` whose own-line argument is another name. Those positive cases kill the mutant "any line that names the bound is a write" and the mutant "any name alone on a line is a write".
- Rerun the meta case. The five proven loops must stay proven, with no new entry.
- Record the deviation beside review 001 F1 in `c0193.md`: a call argument on its own line, and a write to the owner of a dotted bound, void the proof.
- In `trace.md`, replace the AC4 sentence that names this finding with the new cases, and correct the `loops.luau` line numbers.
Lesson: zz-arch/assignment-forms-void-proofs

### F2 [medium] A step that exists only inside a block comment or a long string proves the loop
Where: `z-nile/tests/lib/loops.luau:167-195`. The body loop tests every line for a step (`:185-193`) and has no notion of a line inside `--[[ … ]]` or `[[ … ]]`.
Evidence: `loops.find` reports `advances=true` for both texts, and neither loop has a statement that steps `i`:
- `while i <= n do` / `f(i)` / `--[[` / `i += 1` / `]]` / `end`
- `while i <= n do` / `local s = [[` / `i += 1` / `]]` / `emit(s)` / `end`

A full-line `-- i += 1` reports `advances=false`. `loops-writes.spec:82` puts `[[` at column 0, which makes `endOf` miss `end` and sets `scansText`. An indented long bracket still has its `end`, and the step pattern then matches the line inside it. AC4 asks that the loop's own top level steps its variable. A commented step is not a step. No loop in today's tree has this shape.
Critique: Tracking `--[[` and `]]` by line needs a reader that also knows quotes and the levels of `[=[`.
Consequences: One rule covers it: a body line that matches `%[=*%[` voids the proof, because from there the lint cannot tell code from text. A loop whose body holds a long string or a block comment becomes a listed loop, and so does one whose body holds `[[` inside a short string. That is the safe direction. The scratch copy from F1 reports both shapes `advances=false`, keeps the five proven loops and 0 problems, and the four specs pass. `rows[cols[i]]` does not match the pattern and stays proven. `loops-writes.spec:82` still sees `scansText` for a `[[` at column 0, because the end is still unfound.
Recommendation:
- In `loops.find`, void the proof when a body line matches `%[=*%[`. Say so in the comment at the top of `loops.luau`.
- Add cases to `loops-writes.spec`: both shapes above must not prove. `while i <= n do` / `local c = rows[cols[i]]` / `i += 1` must still prove, which kills the mutant "any `[` voids the proof".
- Make this change in the same commit as F1, so the layer is finished once.
Lesson: zz-test/source-text-pins-read-the-code

### F3 [high] ./zn trace R0072 --check fails because origin/main moved after the skeleton
Where: `z-nile/.tracker/rafts/active/R0072/trace.md`, `Commit: 7b8ec37561287880b45932b7f0021c3134115ad2`. The stack's base is `897c0475e`.
Evidence: The check prints 27 lines. The first is `row Commit, commit: table is stale (R0072/1/c0192 is not stacked on the layer below)`. It names no commit. The other 26 are the `check.sh` lines the table cites, each "did not run green for this stack". They have this one cause: `finishedIssues` stays empty when the stack is not on `origin/main`. The skeleton commit is `905f909f4` at 15:59:59 -0800. `origin/main` is now `91ee2ac62`, four commits after `897c0475e`, each of them later than the skeleton: `3ccba0f50` (#467), `05324422f` (#465), `257ccf5f0` (#175), `91ee2ac62` (#471). None of those commits touches a file this stack changes. In a clone whose `main` is `897c0475e`, the same table prints `ok: R0072`.
Critique: The reviewer cannot restack. The check cannot pass in this review.
Consequences: A restack gives new finish commits, so `Commit:` changes. A verification-log line appended to `c0193.md` moves no line the table cites. F1 and F2 change `loops.luau`, so the restack comes after that fix and its `./zn finish c0193`.
Recommendation: After the fixes of F1 and F2, run `./zn finish c0193` and `./zn restack R0072`. Set `Commit:` in `trace.md` to the new finish commit of `R0072/2/c0193`, correct the `loops.luau` line numbers from F1, and run `./zn trace R0072 --check` until it prints `ok: R0072`.
Lesson: zz-review/not-stacked-is-main-moving

### F4 [low] After the slow-tier ruling, the text a spec writer reads still speaks as if the sweep runs in the gate
Where: `z-nile/skills/zz-test/SKILL.md:50` (the Hostile inputs bullet); `c0193.md:66` ("run in every z-nile full gate"); `z-nile/tests/slow.tsv:57-58`.
Evidence: The human ruled that `tests/acceptance/c0193/finishes.spec.luau` and `scanners.spec.luau` join the slow tier (`R0072.md`, Open to the human, F2). zz-test says of that tier: "not part of the affected or full gates". `c0193.md:66` still says the sweep runs in every z-nile full gate. The bullet says `hostile.finishes` runs the case "instead of hanging the gate". `docs.spec` reads that bullet as one line and pins `hostile.finishes`, `hostile.luau` and `scanners.luau` on it. `c0193.md:297` records that the two specs were listed.
Critique: The ruling stands. The sentences that say when the sweep runs were left as they were.
Consequences: A clause added to the bullet's one line keeps `docs.spec`'s pins. `SKILL.md` is not a source file. Appending a verification-log line moves no traced line. Inserting a line into the Design section above the acceptance criteria would move every later citation.
Recommendation:
- On the Hostile inputs line, add that the sweep spec is in the slow tier, so an affected or full gate skips it, and that a new or changed case is run by its path or by `z-nile/check.sh --slow`.
- Append a verification-log line to `c0193.md`: the two specs run in the slow tier, which departs from "Where the checks run".
- Both can ride the commit that answers F1.
Lesson: z-design/restated-rules-move-together

## Lesson candidates (for the lead)
- F1, a note on `zz-arch/assignment-forms-void-proofs`: a matcher that lists the forms of a write reads every form nobody listed as a read. Count the watched name alone on a line, a `table.<fn>(` anywhere before it, and a write to the owner of a dotted name, as writes. Check: for each name the proof watches, what does the matcher say when the formatter puts that name on a line of its own?
- F2, a note on `zz-test/source-text-pins-read-the-code`: a line lint that proves a statement refuses to prove once the body opens a long bracket. Check: what does the lint decide when the line it looks for sits inside `--[[ ]]`?
- F4, a note on `z-design/restated-rules-move-together`: a ruling that moves a check into the slow tier changes where the rule is enforced. Search for every sentence that says the gate runs it. Check: after the ruling, which sentences still say the full gate runs the sweep?

Verdict: changes
