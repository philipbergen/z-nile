# Review 004: c0193 (design mode)
Inputs: prep worktree HEAD 7871c2f9 plus the uncommitted `c0193.md`, `check.sh`, `acceptance/*.spec.luau`, `prototype.patch` (sha1 ac605e9fd118…), design-review-001..003, design-refute-001..003 and `harvest.md`. Also read:
- `./zn capture c0193` (capture 6495f5f3);
- origin/main b5bde7ae, which since 7871c2f9 adds no `while` or `repeat` line in a covered path and leaves zz-arch and zz-test unchanged;
- c0191's reference runner `ref-bounded.pl.txt` (`.worktree/prep-no-leaked-processes`, de3ad691);
- c0181 as it stands (`.worktree/prep-lessons-codify-consolidate`, 6d9318e5 plus its uncommitted `c0181.md`, `design: ready`): policy rules 1 to 3, the caps, the harvest `codify` line, "Gate" and its zz-execute edits.

Runs: every run was in a throwaway clone with `prototype.patch` applied and the reference runner at `z-nile/lib/bounded.pl`. Every `lune` ran under `perl z-nile/lib/bounded.pl --time N --`.
- Unmutated: scan 5, texts 7, loops 19, problems 10 and tree 5 all passed, and docs passed 2 of 2. finishes passed 12 (8.3 s wall) and scanners 6 (2.8 s); each of those two ran once.
- AC9's command passed once I added the executor's harvest note.
- I left no process behind: `ps` shows only other sessions' runs. The clone is deleted.

Dropped from design-review-003 (each re-run, not taken from the refute):
- **F1, the file tie.** I set `paths.luau:49`'s entry to `sweep = "skills.oldNames"`. tree.spec failed both ways: `…paths.luau:49: loop "while true do": its entry names the scanners case "skills.oldNames", whose module is z-nile/engine/skills.luau, not this file`, and the per-entry case named the module. The conditional sibling case (raftcheck, boundcmd) reads correctly.
- **F1, the `loops.find` part.** It is not fixed: see F1 below.
- **F3, the search.** I re-ran the `+`-line awk over every `*.patch`, `*.diff` and `*.diff.txt` under `.worktree/*/…/.tracker/issues/`, keeping targets in covered paths and dropping specs, `pickman/src`, `.tracker/` and `tests/acceptance`. Its live hits match the table: c0117's four engine files, c0118's board and boardview, c0121's serve, c0135 (R0061) raftplan, c0144 look 2, c0157 slot 1, c0178 images 1 and c0191 main.luau 1. The other hits are done items (c0081, c0115, c0116, c0154), whose loops are already on main.
- **F4.** finishes.spec's "names the witness when a scanner hangs on it" passes, and the message reads as designed.
- **F5.** tree.spec now requires every root to contribute files, and scanners.spec checks `NEEDLES` against `ALPHABET`.
- **F6.** Answered with a recorded reason.
- **F7.** docs.spec pins the clause, and the lesson's `check:` states the limit.

Scope: the captured Problem is verbatim, and the lesson carries the rule and the check question. The c0181 question ("which part can be a check") is answered with a lint, a sweep and a fail-closed step. Nothing has moved into Non-goals. The captured outcome is delivered whole. I find the machinery proportionate as it stands: about 2 s of sweep and milliseconds of lint per full gate.

Two seams are left. The fix for round 3's `loops.find` point added a case that does not reach the loop it is listed for (F1). The c0181-first branch is now concrete, but it puts the gate red across steps that zz-execute runs the gate in (F2). Everything else I found is cosmetic.

### F1 [medium] The `loops.find` case added for review 003 F1 never enters the loop it is listed as sweeping (`writes()`'s `while at do`); its Rules row's `reasoned` claim is false, and a non-advancing mutant passes the sweep and hangs tree.spec instead
Where: `prototype.patch` `scanners.CASES` (`loops.find`: `call = "#m.find(text)"`, witness `while i <= n do\n\ti += 1\nend\n` → `1`); `loops.ALLOWED["z-nile/tests/lib/loops.luau"]` (`while at do`, `sweep = "loops.find"`); Rules and mutants row "the design's own text walker is swept … reasoned: loops.luau is also the file under test, so the mutant would break the spec's own lint; the witness and the case's presence are pinned"; `acceptance/scanners.spec.luau` "feeds every character that a case's module compares with" (only `@znile/` modules are read).
Evidence:
- **The witness skips the loop.** `writes(l, boundName)` runs only on body lines. The witness's only body line is `\ti += 1`, so `string.find("\ti += 1", "n", 1, true)` is nil and the `while at do` body never runs.
- **The texts skip it too.** No text of `scanners.texts()` (at most 4 characters, or a needle with one character on a side) holds a `while … do` header with an `end`. So the 74,237 texts never reach `writes()` at all.
- **The mutant passes the sweep.** In the clone I changed `loops.luau:96` to `at = string.find(line, name, at, true)`, so the loop does not advance. I ran the `loops.find` case alone through `hostile.finishes("zscratch", {case}, scanners.texts(), 3)`. It printed `true` with an empty message: the sweep passed.
- **The mutant hangs tree.spec.** With the same mutant, `perl lib/bounded.pl --time 5 -- lune run tests/run -- …/tree.spec.luau` was stopped by the runner: `bounded: stopped at the wall-clock limit (--time 5 s): lune`.
- **What the row claims.** The row says the mutant "would break the spec's own lint". What it does is spin, in-process, inside a spec run that `tests/run.luau` does not bound (it has no timeout). That is the incident's failure mode inside this issue's own gate.
- **The alphabet check skips it.** The check reads only `@znile/` modules, so `loops.luau`'s own compared characters are never checked: `)` (`:47`) and `<` (`:165`, `:178`) are not in `scanners.ALPHABET`.

Critique: this is the third round in which a `sweep` claim tests less than it says: round 2 F1 (`paths.rewrite`), round 3 F1 (any case name), and now a witness that proves the call returns, not that the listed loop ran. The witness rule proves that a case reaches *some* of its module's work. The tie proves the case's module is the loop's *file*. Neither proves the listed *loop* runs. Prep's E14 proved that once per loop, by mutation, for the seven entries it had. The new entry skipped that step and was marked `reasoned`, and the reason does not hold (lesson z-design/reasoned-rows-claim-testable-reasons). The tempting fix is a new witness that holds the bound name in a body line. That fixes the witness only: 74,236 hostile texts would still never reach the loop.
Consequences:
- Reaching `writes()` with every text means the case's `call` has to wrap the text into a loop body, since `Case` has a `prefix` and no suffix. That is allowed: `call` is any expression on `text`.
- Widening the alphabet check to every case's module (through `scanners.files()`) brings in `loops.luau`'s `)` and `<`. Each must be added to `scanners.ALPHABET` (`20^3` → `22^3` texts of length 3: 8,000 → 10,648, a fraction of a second) or listed on `scanners.EXCEPT` with a reason.
- On the mechanism: per-loop reach is today a one-off prep fact. Every later `sweep = "<case>"` entry (c0191's seven `boundcmd` text loops, R0052's `raftcheck`) is in the same position.
Recommendation:
1. Make the `loops.find` case reach its loop with every text. For example, `call = '#m.find("while i < n do\\n\\ti += 1\\n\\tx(" .. text .. "n" .. text .. ")\\nend\\n")'`, so the bound name sits in a body line with the hostile text on both sides. Give it a witness only `writes()` can produce: for instance a call returning `tostring(m.find(…)[1].advances)` with witness text `table.insert(n, i)`, which gives `"false"` only because `writes()` saw the call.
2. Run the mutant above against `scanners.spec` alone (the sweep then fails within its limit), and mark the row `run`.
3. Extend scanners.spec's compared-character case to every case whose module `scanners.files()` maps. Add `)` and `<` to `scanners.ALPHABET`, or put them on `EXCEPT` with a reason.
4. Question the mechanism. The design should say which of these holds per-loop reach, and rule 9 / the zz-test bullet should say the same:
   - (a) **A standing reach probe.** One copy of the covered tree under `.cache` (fixture.luau already builds such copies), with a breadcrumb such as `_G.__c0193["<file>:<line>"] = true` inserted as the first body line of every `sweep = "<case>"` loop. All cases run once over the texts, and the spec requires every listed loop to be marked. That costs one extra sweep (about 2 s) per full gate.
   - (b) **A recorded reviewed claim.** The item that adds a `sweep` entry runs the stop-the-advance mutant against its case, as E14 did, and records it in its Rules table. The reviewer asks for it (zz-review item 0 already reads that table).

   (b) is the proportionate default, given how cost-sensitive the gate is. Either way, the claim stops resting on the case name alone.
Lesson: zz-test/no-vacuous-pass, z-design/reasoned-rows-claim-testable-reasons

### F2 [medium] (repeat of design-review-003 F2) The c0181-first plan writes step 6 after the code review and keeps the gate red across zz-execute's own pre-`done` gates. A non-sequestered `[zz-arch/scanning-loops-advance]` case removes the red window in both landing orders
Where: Non-goals, the c0181 bullet ("the executor writes step 6 (the lesson) *last*, right before `./zn done` … the gate between that commit and `done` is expected to report those two refs as missing … run the affected gate before step 6 and the full gate after `done`"); Implementation steps 6 and 7; zz-execute Phase 4 (the code-mode reviewer runs `z-nile/check.sh --full`), Phase 5 steps 2 and 3; c0181.md "Gate" (`lessons (./zn lessons --check --policy)`, unconditional), its zz-execute edit ("Phase 4 step 5 and Phase 5 likewise": confirm with `--check --policy --item <id>`), and policy rule 3 ("a lesson is enforced by a new case in a new spec file outside `tests/acceptance/` (`tests/meta/` or `tests/tooling/`)").
Evidence: c0181 is `design: ready` with no `depends_on`, so the c0181-first branch is live. Read against zz-execute, the plan cannot be followed as written:
- **Placed after the code review.** Step 6 holds the lesson, zz-arch rule 9, the zz-test bullet and the harvest note. "Right before `./zn done`" falls after Phase 4, so the code review never sees that text. `./zn check c0193` (AC8, AC9) is also red until then.
- **Placed before the code review.** The reviewer's mandated `z-nile/check.sh --full` is red on the policy stage: rule 3 finds no `z-nile/tests/acceptance/c0193/tree.spec.luau`.
- **Either way, Phase 5 is red before `done`.**
  - Step 2 reruns `z-nile/check.sh --full` after merging main.
  - Step 3, as c0181 rewrites it, runs `./zn lessons --check --policy --item c0193`.

  Both fail on the two missing refs, and the plan's "run the affected gate before step 6 and the full gate after `done`" contradicts step 2.
- **`done` itself passes.** `cmd.done` runs `runCheck`, and AC9 calls `./zn lessons --check` without `--policy`. So the plan's red window is real, and it sits exactly where the protocol runs gates.

The open gap was handed to c0181's lead. c0181's current text has no exception for an item's own sequestered spec. But c0181's rule 3 already names the route that needs none: a new case in a new spec file under `tests/meta/` or `tests/tooling/`.
Critique: this is the second round against the same mechanism, a lesson ref that points at a spec which exists only after `done`. Round 3's recommendation made the window explicit. It is still a window in which every protocol gate is red (lesson z-design/no-check-red-between-steps). An executor who meets it will improvise: skip the reviewer's full gate, write `not_codifiable`, or point at the sequestered path, which rule 3 refuses.
Consequences:
- A non-sequestered case can be weakened by the executor. The sequestered `tree.spec` and `scanners.spec` still pin the same rule from `done` on, so weakening it gains nothing.
- The extra case duplicates the lint, not the sweep: a few milliseconds per gate.
- The `[zz-arch/…]` names in the sequestered specs can stay; they are harmless. Or they can drop the prefix.
- c0181's lead no longer needs to change rule 3 for this item, but the general gap is still worth sending.
- Touched modules gains the new spec file.
Recommendation:
1. Add `z-nile/tests/meta/scanning-loops.spec.luau` (executor-written, in step 4 or 5, beside the lint), with one case: `"[zz-arch/scanning-loops-advance] every loop in the tooling is proven or listed"`. It runs `loops.problems` over `loops.files()`, as tree.spec does.
2. In both landing orders, the lesson's `enforced_by` (or, before c0181, its **Enforced by** paragraph) names that case. Under c0181 the harvest line is `- codify zz-arch/scanning-loops-advance: z-nile/tests/meta/scanning-loops.spec.luau :: "[…] every loop…" mutant: an unlisted while true do added to a covered file (or the loops.luau entry deleted)`.
3. Step 6 then returns to its place before the code review. The gate is green at every step, and the "write it last, red until `done`" text and its gate exception are deleted from Non-goals.
4. Add a Regression-guard line: the meta spec is not promoted and can be edited, and the sequestered tree.spec is the guard.
5. Keep the one-line note to c0181's lead about the general gap.
Lesson: z-design/no-check-red-between-steps, z-design/quote-other-preps-before-promising

### F3 [low] AC9's last pipe stops `./zn lessons` mid-write and prints a stack trace on a passing check
Where: `check.sh` AC9 (`"$ZN_ROOT/zn" lessons --skill zz-arch --full scanning-loops-advance | grep -qE "^sources:.*c0193"`).
Evidence: in the clone, AC9's command exited 0 and printed `tracker lessons: Broken pipe (os error 32)` with a Lune stack traceback. `grep -q` exits at its first match and closes the pipe while `zn` is still writing. It passes because the pipeline's status is grep's. Under `pipefail` it would fail.
Recommendation: capture first, then match: `S=$("$ZN_ROOT/zn" lessons --skill zz-arch --full scanning-loops-advance) && printf '%s\n' "$S" | grep -qE '^sources:.*c0193'`. Alternatively, drop `-q` and redirect to `/dev/null`.

### F4 [low] The Design says the lesson is 12 lines; the file in `prototype.patch` is 13
Where: Design, Documents ("`zz-arch/lessons/scanning-loops-advance.md` (12 lines; …)"); Non-goals ("1,152").
Evidence: `wc -l` gives 13 lines and 1,562 bytes. The body after the frontmatter is 1,152 bytes with its last newline (1,151 trimmed, the measure c0181 uses), which is under the 1,200 cap and matches the text. AC9 allows up to 20 lines, so nothing fails.
Recommendation: say 13 lines.

Lesson candidates (for the lead to place; I write no lesson file):
- A witness proves that a call reaches its module's work, not that a named loop runs. When a list entry claims that a sweep covers one loop, the claim is proven per loop, by stopping that loop's advance and seeing the sweep fail. A `reasoned` row for it is tried first. Check: does the mutant that stops *this* loop fail *this* case? (F1)
- A lesson's enforcing case is one that exists at the step that writes the lesson: a non-sequestered spec, not the item's own spec, which is promoted only at `done`. Check: does the ref resolve at every gate between writing the lesson and `done`? (F2)

Verdict: changes
