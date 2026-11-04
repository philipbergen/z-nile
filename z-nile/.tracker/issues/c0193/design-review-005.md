# Review 005: c0193 (design mode)
Inputs: prep worktree HEAD 7871c2f9 plus the uncommitted `c0193.md`, `check.sh`, `acceptance/*.spec.luau`, `prototype.patch` (sha1 a3cc2a06…), design-review-001..004, design-refute-001..004 and `harvest.md`. Also read:
- `./zn capture c0193` (capture 6495f5f3);
- c0191's reference runner (`ref-bounded.pl.txt`) and its document, for the CPU limit it gives `tests/run`;
- c0181's document (`prep-lessons-codify-consolidate`): rule 3, the harvest `codify` line, `codify.agree`, the sweep's "with its mutant run".
Dropped from design-review-004: F1, F2, F3, F4 (each re-run below, not taken from the refute).

Runs: all in a throwaway clone (since deleted) with `prototype.patch` applied and the reference runner at `z-nile/lib/bounded.pl`. Every `lune` ran under `perl lib/bounded.pl --time N --`. Afterwards, `ps` showed no `lune`, `hostile-` or `bounded` process of mine.
- **Unmutated.** scan 5, texts 7, loops 19, problems 10, tree 5, docs 2 and the meta spec 1 all passed. scanners passed 6 (2.3 s wall), and finishes passed 12 (8.7 s); each of those two ran once. AC6's two-file form passed 6 of 6.
- **Gate checks.** `bash -n check.sh` and `AC_LIST=1` both pass: 9 criteria listed. `stylua --check` and `selene` are clean on the new files and the specs. `luau-lsp analyze` printed no diagnostics. `tests/meta/architecture.spec` passed 2, and `tests/tooling/repo-fence.spec` passed 10.
- **Review 004 F1, re-run.**
  - I changed `loops.luau:96` to `at = string.find(line, name, at, true)` and ran the `loops.find` case alone through `hostile.finishes(…, scanners.texts(), 3)`. It failed: `loops.find: did not finish within 3 s; it stopped in its witness "", before any text ran`.
  - With `)` and `<` taken out of `scanners.ALPHABET`, scanners.spec fails: `loops.find compares with ")"`.
- **Review 004 F2, re-run.** I emptied the `why` of `graph.luau`'s `while #stack > 0 do` entry. Both the meta spec and tree.spec failed with `z-nile/lib/graph.luau:431: loop "while #stack > 0 do": its loops.ALLOWED entry gives no reason`.
- **Review 004 F3, re-run.** I added the executor's harvest note, then ran AC9's command: exit 0, no broken-pipe trace.
- **Review 004 F4.** The lesson is 13 lines, and its body is 1,152 bytes.
- **Counts after the raft.** 71 covered files, 3 proven loops, 35 listed entries (8 with a named sweep), and 76,955 texts.
- **Overrides.** `git grep -nF 'tests/meta' -- z-nile/tests/acceptance pickman/tests/acceptance` hits only:
  - runs of `architecture.spec`;
  - c0120's layout list of moved files;
  - c0154's durations fixture.

  None of them pins `tests/meta`'s set of files. The new spec's `affected` output is `ALL`. "Overrides: none" holds.

Scope: the Problem is the capture, verbatim. The lesson carries the rule and the check question, reworded only from "the index" to "its position", with detail added. The c0181 question ("which part can be a check") is answered with a lint, a sweep and a fail-closed step. Nothing is in Non-goals that the capture asked for. The captured outcome is delivered whole, and the machinery is proportionate: milliseconds of lint and about 2 s of sweep per full gate.

Both round-4 mechanisms now hold:
- **Per-loop reach** is a recorded, mutation-run claim. The case reaches its loop, and the mutant fails the sweep.
- **The meta case** removes the red window in both landing orders.

What is left is one wrong record in the c0181-first branch and stale text.

### F1 [low] The c0181-first `codify` line credits the meta case with killing SW1, but the meta case passes with SW1 applied
Where: Non-goals, the c0181 bullet: `- codify zz-arch/scanning-loops-advance: z-nile/tests/meta/scanning-loops.spec.luau :: "[…] …" mutant: stopping graph.stripComments's comment branch from advancing (SW1)`. Compare the Rules and mutants row "the lint's enforcing ref runs in every gate | meta | an entry's reason emptied | run".
Evidence: in the clone, I changed `lib/graph.luau:350` from `i = nl or n + 1` to `i = i` (SW1). `lune run tests/run -- tests/meta/scanning-loops.spec.luau` then gave `1 passed, 0 failed`. The meta case is a static lint. The loop is listed, so a dynamic spin in it is invisible to the lint; only the sequestered sweep (scanners.spec) kills SW1. c0181 asks that a codify line's mutant has been run against its ref: its sweep reads "the lint or spec case first, with its mutant run". `codify.agree` only checks that a mutant is present, so nothing would catch the false line. An executor who runs it as c0181 asks sees it pass.
Critique: this is a false history line in a live branch (c0181 is prepared and has no `depends_on`). The document's own Rules table already names the right mutant. Nothing in the gate is wrong, which is why this is low.
Consequences: none. The meta case does kill "an entry's reason emptied" (re-run above), and an unlisted loop in a covered file is the same check.
Recommendation: make the codify line's mutant one the meta case kills, as the Rules row says: `mutant: an entry's why emptied (or an unlisted while true do in a covered file)`.

### F2 [low] Stale text: "no separate `tests/meta` file", a 28-line meta spec, and "the 33" entries the executor writes
Where:
- Design, "Where the checks run": "There is no separate `tests/meta` file: the sequestered specs hold the real-tree scan so the executor cannot weaken it".
- Files: "`z-nile/tests/meta/scanning-loops.spec.luau` (executor-written, 28 lines)".
- What the list holds: "the executor writes the 33 `why` texts".
- Implementation step 1: "each of the 33 `why` texts".
- Implementation step 5: "the 33 entries of `ALLOWED`".

Evidence:
- **The meta file.** Files, Touched modules, step 4 and AC6 all add the meta file, so the "Where the checks run" sentence contradicts the rest of the document.
- **Its length.** The prototype's meta spec is 34 lines.
- **The entry count.** The prototype's `ALLOWED` holds 35 entries: main's 33, plus `loops.luau:79` (`while at do`) and `hostile.luau:222` (`while #lines > 0 and …`), the design's own two loops.

These counts are right where they describe main today: "33 of 36 today" and "67 files: 3 proven and 33 listed" (E3). The rest of the numbers I was asked to check are right: 76,955 texts, 13 lines, 1,152 body bytes, 3 proven and 8 sweeps ("seven-plus").
Recommendation:
- Replace the "Where the checks run" sentence with one that names both: the meta case runs in every gate from step 4, and the sequestered tree.spec and scanners.spec are its unweakenable twins from `done`.
- Say 34 lines.
- Say "the 35 entries (main's 33 and the two loops of the design's own `loops.luau` and `hostile.luau`)" in steps 1 and 5.

### F3 [low] "So every text reaches `writes()`'s loop" is wider than the case: the 15,602 texts that hold a line end never do
Where: Design, `scanners.luau` bullet ("The `loops.find` case wraps each hostile text into a body line that names the bound … so every text reaches `writes()`'s loop"); design-refute-004 F1.
Evidence: I added a flag on the first line of the `while at do` body in a copy of `loops.luau`, then ran the case's call over `scanners.texts()`:
- 15,602 of the 76,955 texts never enter the loop;
- every text without a newline does (0 misses);
- of the 16,354 texts that hold a newline, the 15,602 above never enter it.

A newline splits the body line, so `endOf` finds no `end` at the loop's indent and the body is not scanned.
Critique: this costs no coverage. `writes()` reads one line, so a line end can never reach it, and every other character does. Only the claim is too wide, and this document has been corrected for claims wider than the case before (review 002 F7).
Recommendation: say "every text without a line end (`writes()` reads one line, so a line end cannot reach it)".

### F4 [low] Step 4 writes the meta spec before `scanners.luau`, which the spec requires
Where: Implementation step 4 ("Then, with the `ALLOWED` entries of step 5 in the same commit …, `z-nile/tests/meta/scanning-loops.spec.luau`"), step 5 (`z-nile/tests/lib/scanners.luau`).
Evidence: the prototype's meta spec does `require("@tests/lib/scanners")` and passes `scanners.files()` as the sweeps. The `loops.luau` entry `sweep = "loops.find"` and main's seven sweep entries are refused unless their cases exist ("names the scanners case … which does not exist").
Recommendation: say the meta spec goes in step 5's commit, with `scanners.luau` and the 35 entries.

### F5 [low] The lint specs run `loops.find` in-process; a spin in it is bounded only by c0191's 1,200 s CPU limit per spec process
Where: Implementation steps 3 to 5; acceptance `loops`, `problems`, `tree` and the meta spec.
Evidence: review 004 showed it. A `writes()` that stops advancing hangs tree.spec in-process; the runner stopped it at its wall-clock limit. After c0191, `tests/run` has a 1,200 s CPU limit per process (c0191, `fence.specCpu`) and no wall-clock limit. So an executor who breaks `loops.luau` while porting it holds a core for up to 20 minutes per lane, and so does a later author who edits `loops.luau`.
- **The sweep does not cover this.** It does cover `writes()` (the loops.find case), but only in its own bounded child.
- **Step 3's warning does not cover it.** "Never run a spec that could spin outside `finishes`" cannot be followed for these four specs, which must run `loops.find` directly.

This machine's user is very sensitive to CPU load. I ran every spec in this review through `perl lib/bounded.pl --time N -- lune run tests/run -- …`: the jail and the runner work together.
Recommendation: in steps 4 and 5, tell the executor to run the four lint specs, and any mutant of `loops.luau`, through c0191's `./zn run --time 60 -- lune run tests/run -- <spec>` until they pass, and only then through `./zn check`. No spec change is needed.

Lesson candidate (for the lead to place; I write no lesson file): a harvest or ledger line that names "the mutant this ref kills" is a claim like a Rules row. Run that mutant against *that* ref, not against the item's strongest spec. Check: does this ref, alone, fail with this mutant applied? (F1)

Verdict: approve
