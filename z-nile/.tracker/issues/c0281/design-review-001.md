# Review NNN: c0281 (design mode)
Inputs: prep worktree `prep-board-round-rule-spy-pin` at d029bbe4c (uncommitted prep files: `c0281.md` f29faa47e798, `check.sh` 67ce8c4341c8, `acceptance/mutants.luau` 80a480844bcb, `experiments/prototype.patch` bd5d0be3e098); `z-nile/engine/board.luau`, `boardview.luau`, `board.html`; `z-nile/tests/tooling/board-review.spec.luau`; `z-nile/tests/acceptance/c0118/{model,page}.spec.luau`; `z-nile/tests/lib/t.luau`; `z-nile/lib/ac.sh`; c0250's and c0121's designs and c0250's prototype board.luau hunks on origin/main 0f2c2f94a; `./zn capture c0281` (faf4be36f, a confirmed capture, no marker).

What I ran: `git apply --check` of the prototype on HEAD (applies; origin/main has not changed any touched file). A scratch copy outside every repository (`mktemp -d` under `$TMPDIR`, the prototype applied with `patch -p1`), then `mutants.luau` through `./zn run --time 300` from the copy's z-nile home. It reproduces E4: base 5 cases green, `boardview.rounds` restored, 12/12 killed, both equivalents green, and every one of the 12 is killed by the F3 case alone. On a probe copy of the runner I added mutants and equivalents (results quoted below). `tests/run` on `repo-fence.spec` in the worktree: 9 passed, the one failure is :593, the environment case E7 names. `lune run z-nile/affected` and `grep -rlF` over every home's `tests/acceptance` for the touched paths (findings below). Overrides `none` holds: the lesson's basename hits only `c0115/layout.spec.luau`'s file-exists check, which stays green.

### F1 [medium] The fixture seeds no backlog raft, so a board that leaves out a backlog raft's folder, its backlog members' or the rafts retired into it passes every spec
Where: c0281.md, Design, "The case" (fixture list) and Rules and mutants; `experiments/prototype.patch` F3 case; `acceptance/mutants.luau` MUTANTS
Evidence: `scan` walks rafts and issues in three states (`backlog`, `active`, `done`, board.luau:188), and the raft pane shows `review rounds` for every raft (board.html:300). Backlog rafts do hold rounds today: `pickman/.tracker/rafts/R0094/` has `design-review-001.md` (a raft-mode review). The F3 fixture has one done raft (R0010, with a done member) and one active raft (R0020, no members), and both retired rafts are kept by R0010. I ran these mutants against the prototype spec with the runner:
- X2: `if rawRaftById[raft.id].state ~= "backlog" then reviewFiles(...) end` around the raft's own call. **Survives F3.** No spec in AC5 kills it either: model.spec has no backlog raft, and page.spec's backlog R0110 has no review file.
- X1: members only when `i.state == "done"`. **Survives F3.**
- X3: retired folders only when the keeper is done. **Survives F3.**

X1 and X3 die in c0118's model.spec only because its R0010 and c0011 are *active*. Their backlog forms (`i.state ~= "backlog"`, keeper `state ~= "backlog"`) are seeded by no spec (I reasoned this from model.spec's and page.spec's fixtures; I did not run it). The keeper is in backlog at the moment of a fold (z-raft recombines backlog rafts), so that is the usual case. The Design says "each raft's list holds every entry of its folder, its members' folders and the folders of the rafts retired into it", and AC2 says "every mutant that keeps the round-file rule from boardview.rounds (…, a folder left out, …)", but a folder left out by state is red nowhere.
Critique: this repeats zz-test/seed-every-enumerated-case: the code walks three state folders and the fixture seeds two, with members and fold keepers in one. The tempting fix is to add a backlog raft with one review file. That alone kills X2 but not the backlog-member or backlog-keeper forms.
Consequences: `seen` becomes 3. The fixture-vacuity assertion grows. Three mutants and rows join the table, so step 3's "12 killed mutants" becomes 15. AC2's label stays true as worded ("a folder left out" now covers state). F3 still runs last, so F1/F2 are untouched. No anchor is new: the three anchors below each occur once in board.luau today (`if issue.raft then\n\t\t\treviewFiles(i.dir, files[issue.raft])`, `files[raft.id] = {}\n\t\treviewFiles(rawRaftById[raft.id].dir, files[raft.id])`, `if files[keeper] then\n\t\t\treviewFiles(r.dir, files[keeper])`), and E6 must be re-checked against them.
Recommendation: add to the F3 fixture:
- a backlog raft `rafts/R0030/` (`R0030.md` with `design: ready`, `design-review-001.md`, `notes.md`);
- a backlog member `issues/c0031/` (`c0031.md` with `raft: R0030`, `design-review-001.md`);
- a raft retired into it, `rafts/retired/R0029/` (`retired: R0030`, `R0029.md`, `review-001.md`).

Set `want.R0030 = entries({R30, C31, R29})`, assert `seen == 3`, and add `R30/notes.md` and R0029's `review-001.md` to the vacuity check. Add three MUTANTS and rows:
- "a backlog raft's own folder left out" (X2);
- "members kept only outside backlog" (`i.state ~= "backlog"`);
- "rafts retired into a backlog keeper left out".

Also give the Design's "both paths must reach the rule, which dedups by path" its own row: a mutant that dedups by base name before the call. The fixture already kills it through R0009's `review-001.md`, but no row lists it. Update step 3's count and record the new run in E4.
Lesson: zz-test/seed-every-enumerated-case

### F2 [medium] AC3 checks only the old pin's forbidden texts, so a spec that keeps the old pin's required texts (or any scan tuned to the 12 mutants) passes every check
Where: c0281.md, Rules and mutants row "the pin reads no source text"; AC3; `mutants.luau` EQUIVALENTS
Evidence: I added `t.expect(has(fs.readFile(`{here}/engine/board.luau`), "boardview.rounds(")).toBe(true)` to the prototype's F3, which is the Design's "`has(src, "boardview.rounds(")` goes too", kept. The unchanged runner printed `base: 5 cases passed`, `killed:` ×12 and `green:` ×2, so AC1, AC2 and AC3 pass. The same holds for a spec that keeps the `local function reviewFiles.-\nend\n` body extraction with `t.expect(body ~= nil)`. More generally, a pure source scan with no spy passes too: it requires the exact `reviewFiles(i.dir, files[issue.raft])`, `reviewFiles(r.dir, files[keeper])` and `boardview.rounds(files[raft.id])` lines, forbids an `if` inside reviewFiles' loop, and forbids `local _ = boardview`. That scan kills all 12 mutants with `expected …` messages and leaves both equivalents green, because each equivalent adds only text the *old* scan forbade. Step 2 ("`readSource`, `code(` and `has(src` no longer appear") is an instruction, not a check. The capture asks to *replace* the source pin with a spy, and the Rules row claims "the pin reads no source text". No check fails while part of the pin stays.
Critique: a kept positive pin forbids correct idioms (lesson zz-test/source-pins-name-what-the-design-names: "once a behaviour case covers what a pin guarded, is the pin … deleted"). The tempting fix is a grep of the spec for `readFile` or `board.luau`. That is a source pin on the spec: concatenation bypasses it, and the header comment and F1's `fs.readFile` of the page trip it.
Consequences: equivalents that respell what the old pin *required* change AC3's meaning. Its label must say so, and the Rules row with it. A rename equivalent touches four occurrences, so `replaceOnce` can't build it: the runner needs a count-checked replace-all that fails closed when the count moves, as `replaceOnce` does for one.
Recommendation: add correct variants to EQUIVALENTS that any pin keyed on today's text rejects. I ran the first two on the prototype spec and both are green:
- (a) the call spelled `boardview["rounds"](files[raft.id])`, still through the module table at call time;
- (b) `reviewFiles` renamed `entriesOf` at all 4 occurrences, through a `replaceAll(src, old, new, 4)` that asserts the count;
- (c) reviewFiles' loop rewritten without `for _, name in fs.readDir(dir)` (e.g. `local names = fs.readDir(dir) for i = 1, #names do table.insert(into, dir .. "/" .. names[i]) end`).

Change AC3 (doc and check.sh label) to "an edit of board.luau that keeps the behaviour, whether it adds what the old source pin forbade or respells what it required, leaves board-review.spec green". Make the Rules row's mutant "(inverse) the old scan, in part or whole: red on each of the five equivalents", and record the run in E4.
Lesson: zz-test/source-pins-name-what-the-design-names

### F3 [low] The list comparison is a multiset deep-equal that prints table addresses: it fails a correct board that hands a path twice, and its message shows neither the raft nor the lists
Where: c0281.md, Maintainability ("any refactor of `reviewFiles` or the round loop that keeps the data flow stays green") and Usability ("shows the list the board handed the rule beside the expected one (`toEqual`'s message)"); prototype `t.expect(calls[k]).toEqual(want[raft.id])`
Evidence:
- A false red. I ran the correct variant "the members' `reviewFiles` call made twice" as an equivalent. `boardview.rounds` dedups by path, so the counts are unchanged, but F3 failed: `board-review.spec:240: expected deep-equal values, got table: 0x000000078d05c0d0`. That is a likely next change: c0250 (prepared) finds a blocked raft's members by the raft's `issues:` *and* each member's `raft:`, and a later rounds fix for draft rafts would naturally do the same union.
- An unreadable failure. That same message is what every kill prints. `t.luau:54` formats `show(actual)`, which for a table is its address, so the Usability claim is false.
- A misleading comment. A board refactored to capture `boardview.rounds` at load, the "captured call" mutant, fails on `calls[k] ~= nil`, whose comment says the board counts by itself.

Critique: switching to a set comparison alone fixes the false red but leaves the message unreadable.
Consequences: deduping in the spy drops no mutant: every listed mutant drops or adds a distinct path, and a doubled path is harmless to the rule.
Recommendation: in the spy, keep the sorted copy with duplicates removed. Compare `raft.id .. ":\n" .. table.concat(calls[k], "\n")` with the same string built from `want[raft.id]` using `toBe`: its message is `expected <want>, got <got>`, which names the raft, shows both lists and keeps the `expected …` kill rule. Before the per-raft loop, add `t.expect(#calls >= 3).toBe(true)` (or `>= 2` without F1) with the comment "board.luau calls boardview.rounds through the module table when it counts; a function captured at load hides the call from this spy". Add the doubled-members variant to EQUIVALENTS.

### F4 [low] The prototype's closing comment miscounts the design rounds
Where: `experiments/prototype.patch`, F3 case, the comment above `own(want.R0010)`
Evidence: the comment reads "R0010's two design rounds (c0011's two, R0008's one) and two code rounds", but its own breakdown is 2 + 1 = 3, and the next line asserts `toBe(3)`. The Design text correctly says 3. Step 1 lets the executor apply the patch as it is, so the wrong comment would land.
Critique: the comment would mislead whoever next edits the fixture.
Consequences: none.
Recommendation: "R0010's three design rounds (c0011's two, R0008's one) and two code rounds (R0010's and R0009's)"; regenerate the patch.

Not findings (checked):
- **Scope fidelity:** the Problem matches the capture. The Non-goals fence only what the capture doesn't name, and the capture's check question has AC2.
- **Repository safety:** `mutants.luau` checks every write against its mktemp prefix. The child spec writes only under the fixture's own `.cache`. `history.read` in the copy only reads, and under ac.sh's ceiling finds no repository. check.sh executes only sequestered files.
- **c0250's prototype:** its board.luau hunks keep all six anchors and do not touch the rounds loop.
- **Bounded commands:** E2 ran through `./zn run`; the mutant runs inherit the check's CPU limit.

Lesson candidates (for the lead to place; I write none):
- zz-test/seed-every-enumerated-case, a note: "a spy that asserts every input reaches a shared function is only as wide as the fixture: seed every state the caller walks (backlog rafts, backlog members, a backlog fold keeper), since a state filter is a pre-filter too. Ask: which state folder does no raft, member or keeper of the spy's fixture sit in?"
- zz-test/source-pins-name-what-the-design-names, a note: "when a behaviour case replaces a source pin, prove the pin is gone with correct variants that respell what it *required* (the call's spelling, the helper's name, the loop's form), not only variants that add what it forbade. Ask: does a spec that keeps one of the old pin's positive assertions still pass every check?"

Verdict: changes
