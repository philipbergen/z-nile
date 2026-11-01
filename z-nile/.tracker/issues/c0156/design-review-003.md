# Review 003: c0156 (design mode)
Inputs: prep worktree `prep-whole-file-pins-keep-newlines` at c5ab507a with the uncommitted prep files (sha256 prefixes: `c0156.md` e59f4b48, `check.sh` 1b375ff4, `acceptance/consumers.luau` c81c1eb4, `docs.spec.luau` 6b886c24, `kills.luau` 8b362660, `pin.spec.luau` b5258341, `record.luau` 10eec88b, `scripted.luau` 2bc130e7, `experiments/mutants.py` 8708e8c7, `prototype.patch` ba4d71e7, `E9-comment-ends.luau` 97ef8127), `design-review-001/002.md`, `design-refute-001/002.md`, `harvest.md`, and `./zn capture c0156` (capture 3bf887d6). origin/main is c62b134c, and all eight base blobs the Design lists still match it. The prototype is the throwaway clone `…/tmp.fipPiC5Jjp/proto`, whose `check.sh` and acceptance folder are byte-identical to the worktree's (`cmp`). Every run below was made there, with `PICKMAN_FENCE_REAL_GIT` set and a time limit. Every edited file was restored afterwards: `cmp` against a saved copy, `git status --short` unchanged at 10 entries, and the one scratch script I added to the acceptance folder was removed.
Runs:
- `kills.luau`, `record.luau` and `consumers.luau` as check.sh runs them: all pass, about 0.2 s each.
- `mutants.py … kills-weak-f0024-no-mutant-case kills-counts-a-raise-as-a-kill kills-no-deletion-mutant record-guard-no-temp-check record-guard-refuses-everything record-join-entry-is-a-no-op`: `OK`.
- A hard-coded f0024 pin against kills, consumers and golden (F1).
- A kills variant with mutants generated from each file (F1).
- A warn-only guard in the record against `record.luau` (F2).

Scope: the capture's outcomes are c0103's pin keeping line breaks, the digest recomputed, a comment-join mutant killed by each pin, one shared normaliser, and the record entry. The `Decided with the user (2026-10-25)` line adds c0103's pin and the CRLF-safe join. Each of these has a Design and a Checked criterion (AC1–AC7). The Non-goals bullet added at prep (the exact-text pins) only adds detail. No scope finding.

Round 001 and 002 answers: I re-checked each one against the current files. R1 F2–F8 hold. R2 F3–F6 hold:
- the check.sh-only split, with `scripted.top()` taken from the argument;
- step 2's `active/` path, and the commit before step 6;
- the tolerated list in `pin.luau`, AC1 and its label;
- the lesson's new `check` clause, pinned by `docs.spec`.

R2 F1 (the verdict run from outside the pin) holds for the weakenings it named: `kills-weak-*-no-mutant-case` is killed in my run. But the kill check has a third hole in the same mechanism (F1 below). R2 F2 (one fixture per guard condition) holds: `outside` is refused under the fixture TMPDIR even though the prototype lies under the real temp folder, which shows the TMPDIR override reaches the child. But the refusal mechanism has a second hole (F2 below).

### F1 [high] AC7 says "every" join and deletion mutant, but kills.luau runs a fixed, published set, so a pin hard-coded to those few mutants passes every check while its file is no longer pinned whole
Where: `acceptance/kills.luau` lines 167–180 (the mutants are the record's `--joins` entries plus one named deletion per file); `check.sh` AC7 ("rejects every comment-join and deleted-assertion mutant of each file it pins"); c0156.md AC7, the Design's `kills.luau` paragraph, and the Rules row "a pin's verdict is wired to its file, run from outside the pin".
Evidence: kills.luau tests each file with a handful of mutants, against far more places a careless edit could land:

| file | lines | `t.expect(` lines | lines with `--` | mutants kills.luau runs |
|---|---|---|---|---|
| f0014 | 41 | 5 | 4 | 2 |
| f0024 | 374 | 44 | 17 | 2 |
| f0026 | 987 | 149 | 32 | 3 |

On the prototype I replaced golden.spec's `exactly24` with a pin of just the two mutants kills runs:
```luau
local n = pin.normalise(text)
return #pin.digest(text) == #D24
	and string.find(n, "t.expect(updates).toBe(6)", 1, true) ~= nil
	and string.find(n, "top-N list of runs\n", 1, true) ~= nil
```
Results:
- `kills.luau`: `all checks passed`;
- `consumers.luau`: `all checks passed` (`pin.digest(`, `pin.joined(` and the require are still there);
- golden.spec: 5 passed.

Then I deleted another assertion from f0024 (the record's `stores-no-count` line, `t.expect(#names).toBe(if table.find(names, "HiscoreTop|all") then 7 else 6)`). Golden.spec still gave `5 passed, 0 failed` and kills.luau still `all checks passed`. AC1, AC4 and AC5 never run the pin, and AC3 and AC6 run this same golden.spec, so `./zn check c0156` is 7/7. That is a wrong implementation passing check.sh while c0128's AC4 ("both narrowed files are pinned whole") no longer holds. AC7's label is also not what its command checks: "every … mutant" is checked by one deletion out of 149 assertions in f0026.
Critique: this is the third hole in "is the pin's verdict wired". Round 001 used a weakened compare. Round 002 used a weakened compare plus a deleted case that a once-per-spec probe hid. Here the mutant set is small and known in advance, so a verdict only has to answer those mutants. The tempting fix is to add a few more named mutants to the record or to kills.luau. That is still a fixed list a pin can name, and it still doesn't match "every".
Consequences: generating mutants from each pinned file brings three things:
- **A rule for which lines are mutated.** Joins need a non-blank next line (`pin.joined` refuses a blank one). Deletions apply to any line that holds `t.expect(`, including one that starts a multi-line assertion.
- **A cost.** I measured it, below.
- **The served mutant must be raw text.** Today's deletion mutant is `pin.without(lf, …)`, the normalised text with ids masked to `ID`. That works for a digest pin but differs from the file in more than the deletion, so a generated mutant should be the raw file minus one line.

Under the pin rule every line break and every assertion counts, so every such mutant must be killed. No allow-list is needed.
Recommendation: question the mechanism. AC7's mutants are derived from each pinned file, not taken from a list. kills.luau builds them from the file's own LF text:
- each line that holds `t.expect(`, deleted (raw line removal);
- each line that holds `--` and whose next line is non-blank, joined to that line with one space.

It keeps the record's join entries as well (AC5 still checks that they are real), and requires `#mutants` per file to equal the count it derived (no silent skip; today a record entry whose old text is missing is skipped at line 171).

I ran exactly this as a scratch copy of kills.luau on the prototype. It made 11, 63 and 177 mutants, the real pins killed all of them by their verdict, and the whole run took 3.9 s, so the cost is acceptable. With the hard-coded `exactly24` above, the generated deletions turn kills red.

To cover the change:
- Add a third synthetic pin to kills.luau's self-test: one that checks only one known needle and is green on its file. The generated mutants must not all count as killed on it.
- Add Rules rows `kills-probe-pin-f0024` (the edit above) and `kills-fixed-mutant-set` (kills.luau back to the record list), both run.
- Record the time in E8.
- Update the Design's `kills.luau` paragraph, the Observed paragraph, and step 6's counts.

If the author would rather keep a sample, AC7's label and AC7 must say what is sampled and why that is enough. That rewording needs the user, because the captured outcome is "pinned whole … killed by each".
Lesson: zz-test/seed-every-enumerated-case, zz-test/narrowing-pins-the-whole-file

### F2 [medium] record.luau checks the refusal's message, not the refusal: a guard that prints the message and carries on passes AC5 (a second hole in the round-002 F2 mechanism)
Where: `acceptance/record.luau` lines 131–150 (`refused` returns `has(r.stderr, REFUSAL)`); AC5 ("refuses a folder that is not the pickman home of a separate clone, each of its four conditions on its own"); the Rules row for the record's refusal.
Evidence: on the prototype I replaced the record's `sys.exit(f'{root}: not the pickman home …')` with `print(f'{root}: not the pickman home …', file=sys.stderr)`. That guard warns and goes on to `path.read_text()` and `path.write_text(...)`. `record.luau` still gave `all checks passed`, all five refusal and accept lines `ok`. The refused fixtures are empty folders, so the warn-only record crashes at its first read with a `FileNotFoundError` traceback, and the needle is still on stderr. The prep's own `record-guard-no-temp-check` kill line shows the same thing from the other side: its stderr starts `Tr…` (a traceback). Pointed at a real checkout's `pickman/`, the warn-only record would write and restore tracked files there, and a crash between the two would leave them changed. Preventing that is what the guard is for.
Critique: the tempting fix is a sentinel pinned file in each refused fixture, checked for "unchanged". The record restores each file in `finally`, so the file would read the same afterwards, and a real file would let a non-stopping record start `lune run tests/run` inside the fixture.
Consequences: the check must tell "stopped at the guard" from "crashed later". That needs the exit code and a stderr shape, and the accept case must still show it got past the guard.
Recommendation: in `refused`, require the effect as well as the message:
- the exit code is non-zero;
- stdout is empty;
- stderr is one line holding the refusal text and no `Traceback`.

For the accept case, require the opposite: no refusal text, and a stderr naming the missing first file (the `FileNotFoundError` the Design says it stops at). Add a Rules row `record-guard-warns-only` (the edit above), run, and say in the Design's `record.luau` paragraph that a refusal is checked by its exit and output, not by its words alone.
Lesson: zz-test/guard-needs-its-own-case, zz-arch/guard-no-is-explicit

### F3 [low] Stale names and two small mismatches in the Design and the scripts
Where: c0156.md
- line 74, Chore checklist **Guards**: "`record.spec` runs the record's refusal";
- line 84, Maintainability: "found by `consumers.spec`'s list";
- line 105, Affected specs: "`record.spec` reads the record by its renamed id".

kills.luau header lines 6–8; record.luau line 108.
Evidence:
- **Renamed scripts.** Round 002 F3 turned both specs into the check.sh-only scripts `record.luau` and `consumers.luau`, but the three sentences above still name the old specs.
- **Which case kills.** kills.luau's header says a kill is "the verdict's own assertion ('expected true, got false' on the 'exactly' case)". The code (`killedByVerdict`) and the Design accept that message from any case, so the CRLF case kills too.
- **Unjailed record.** check.sh runs the executor-edited record unjailed: `--joins` from kills.luau and record.luau, and five fixture runs in record.luau. The Guards sentence doesn't name that, so a code reviewer working from zz-test's "Caught only by review: check.sh files' own commands" has no pointer to it.
- **Fixture path.** record.luau puts its fixture at `$(pwd -P)/.cache/c0156-record`, not under the top it is given. Under check.sh that is `z-nile/.cache`, but a hand run from the repository top or from `pickman/` makes and `removeDir`s the fixture in another home's `.cache` (zz-test/guards-move-with-the-working-directory).

Recommendation: rename the three references. Make the kills.luau header say "any case's `expected true, got false`". Add to Guards: "check.sh runs R0045's record outside the jail (`--joins`, and record.luau's five fixture runs), so the code review reads its `--joins` and guard paths". Take the fixture from the top it is given (`{TOP}/z-nile/.cache/c0156-record`), the home check.sh fences.

### F4 [low] kills.luau tests each pin with z-nile's `pin`, and consumers.luau only checks that pickman's forwarder contains the re-export text
Where: `kills.luau` line 58 (`["@tests/lib/pin"] = pin`, the z-nile module); `consumers.luau` line 25 (`has(forward, 'return require("../../../z-nile/tests/lib/pin")')`).
Evidence: in the gate, AC3 runs the pins against pickman's `tests/lib/pin.luau`, while kills.luau injects z-nile's module directly. The forwarder check is a substring test. A forwarder that has that line in a comment and returns a table of its own passes `consumers.luau`, and kills.luau never loads it. Exploiting this takes a deliberately shadowing forwarder, because the constants must still satisfy both modules, so it is low. But "the rule lives once" (AC2) is then a probe that a comment satisfies.
Recommendation: `consumers.luau` compares the forwarder's non-comment lines exactly with the one line `return require("../../../z-nile/tests/lib/pin")` (the Design gives the file's text), with a Rules row `consumers-forwarder-shadowed`.

Lesson candidates (for the lead):
- "A kill check's mutants are derived from the pinned text (every assertion line, every comment line break), not listed: a fixed, published mutant list can be answered by a verdict that pins only those (c0156 design review 003 F1). Check: replace the verdict with probes of exactly the listed mutants: does the kill check go red?"
- "A refusal case asserts the refusal's effect (non-zero exit, nothing after it: no output, no traceback), not only its message: a guard that warns and carries on prints the same words (c0156 design review 003 F2). Check: turn the guard's exit into a print: does its case go red?"

Verdict: changes
