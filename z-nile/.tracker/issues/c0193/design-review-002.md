# Review 002: c0193 (design mode)
Inputs: prep worktree HEAD 7871c2f9 with the uncommitted `c0193.md`, `check.sh`, `acceptance/*.spec.luau`, `prototype.patch`, `design-review-001.md`, `design-refute-001.md` and `harvest.md`; `./zn capture c0193` (capture 6495f5f3); origin/main 5480e8a0 (since 7871c2f9 it adds only `z-nile/tests/lib/deploylist.luau`, which has no loop, so the specs' inputs are unchanged); origin/impl-c0117 (PR #125); the in-flight preps c0191 (`.worktree/prep-no-leaked-processes`, de3ad691) and c0181 (`.worktree/prep-lessons-codify-consolidate`, 6d9318e5). Everything below ran in a throwaway clone with `prototype.patch` applied, each command under an outer `perl` alarm. Unmutated, all eight acceptance specs pass (scan 5, texts 7, loops 17, problems 9, tree 4, docs 3, finishes 12 in 7.2 s, scanners 5 in 1.5 s). So do the twelve specs that read the edited skills or the new files (c0081/skill-doc, c0114/docs, c0115/absence, docs, layout and skills, c0120/docs and layout, c0127/skill, c0077/cache-paths, `tests/meta/architecture`, `tests/tooling/repo-fence`: 82/82). I left no process behind.
Dropped from design-review-001: F7 (AC9 greps `^sources:.*c0193`), F8 (E9 recorded; a crash is reported with its code). F6 is fixed (16 characters; texts.spec pins the rule, not the count); one narrower gap of its new check is F7 below. F5's table is right: I re-ran the prototype lint over every listed branch and got 16, 14, 15, 1, 2, 1 and 1 problems in the same files. The gap is elsewhere (F5 below).

Scope: the captured outcome is the zz-arch lesson with the rule and its check question. The lesson (E10, AC8, AC9) keeps the rule and the question, worded with "position" for "index", and adds to them. Nothing is narrowed or moved into Non-goals. The c0181 question ("which part can be a check") is answered in kind: a lint, a sweep and a fail-closed step. That codification is proportionate as a whole. It is over-built in one place, a second bounded-process runner beside c0191's (F3). Each of the three checks still has a hole of the kind round 1 found, so this round questions the mechanisms (F1, F2, F4).

### F1 [high] The sweep still passes cases that never reach their scanner's loop: `paths.rewrite`'s case reaches neither listed loop, and a case that returns only on the empty text counts as run (repeat of design-review-001 F1)
Where: `prototype.patch` `tests/lib/scanners.luau` (`paths.rewrite` case), `hostile.luau` driver and `finishes` (`tonumber(returned) == 0`); `acceptance/tree.spec.luau:81-88`; `loops.ALLOWED["z-nile/engine/paths.luau"]`; AC7 ("each case reaching its scanner"); Rules row "a raftcheck case reaches the loop" (reasoned).
Evidence:
- In the clone I made every swept loop stop advancing: `ids.luau:149` `i = stop + 1` → `i = at`; `paths.luau:66` `from = s + 1` → `from = s`; `paths.luau:86` `pos = s + 1` → `pos = s`; `skills.luau:377,430` `pos = (b :: number) + 1` → `pos = a :: number`. Then I ran `hostile.finishes` once per case over `scanners.texts()` with a 3 s limit. `ids.rewritePaths`, `skills.oldLessonIds` and `skills.oldNames` each "did not finish within 3 s". `paths.rewrite` returned **`ok=true`** with both of its loops spinning.
  - The cause: the case calls `m.rewrite(text, { ["z-nile/a"] = "z-nile/b" })`. But `paths.rewrite(text, dirs)` takes an id → item-dir map, and it derives its roots with `paths.rootOf` (`^(.+)/issues/[^/]+$` …), which is nil for `"z-nile/b"`. So `roots` is empty, the outer `while true` breaks on its first pass, and the inner loop is never entered.
  - Both `loops.ALLOWED` entries for `paths.luau` say `sweep = "paths.rewrite"`, and tree.spec accepts them. The reviewed list therefore claims a sweep that tests nothing.
  - The fix is cheap. With the same inner-loop mutant, the case `m.rewrite(text, { c0001 = "z-nile/.tracker/issues/active/c0001" })` over texts that include `az-nile/.tracker/issues/c0001` "did not finish within 3 s".
- A fixture that raises on every non-empty text (`if text ~= '' then error('signature changed') end`) passed `hostile.finishes(…, hostile.texts(), 5)` with `ok = true`. The empty text is always first, and it is the one return the count needs.
- `finishes(name, cases, {})` runs no text, and the `#inputs > 0` guard lets it pass.
- tree.spec's raftcheck case asks only that the prefix contain `\ncheck "RC0` and end with `check "RC1: `. But `raftcheck.judge` (origin/impl-c0117 `raftcheck.luau:84-89`) returns early unless `string.sub(text, 1, #head) == head`. So a prefix built from a template rendered with other variables than the `rendered` that `call` passes returns early on every text, and every early return counts as a run. The Design says the prefix "starts with the rendered RC0 head", and nothing pins that.
Critique: round 1 counted raises. The hole is the mechanism itself, "a case that returned is a case that ran": an early return, an argument of the wrong shape and a no-op all return. AC7's "each case reaching its scanner" is checked by nothing. Before this round, the only mutant run over a real scanner was graph's (E5). The tempting fix is a threshold ("returned on more than one text"), but `paths.rewrite` returns on every text and would still pass.
Consequences: proving that a case reaches its scanner needs evidence that the scanner did its work. So each case states an input and the output that only the loop's work produces: a new field, data in `scanners.luau`, and a `call` that yields the scanner's result. `scanners.texts()` needs needles that carry a root (`z-nile/.tracker/issues/c0001`). A raftcheck case's witness replaces the prefix assertion.
Recommendation:
1. `Case` gains `witness: { text: string, result: string }`, required whenever `call` is not a fixture's. Before the sweep, the driver evaluates the call on `prefix .. witness.text` and fails the case with `<case>: its witness gave <got>, not <result>: the call does not reach the scanner's work` when the result differs. `call` becomes an expression whose value is compared through `tostring` or JSON.
   - `paths.rewrite`: `z-nile/.tracker/issues/c0001` → `z-nile/.tracker/issues/active/c0001`, with the dirs map in its real shape.
   - `raftcheck.judge`: the head plus one valid RC1 line → nil.
   - Add the root-bearing needles to `scanners.texts()`.
2. `finishes` refuses an empty text list, and fails a case that returned on no non-empty text.
3. In prep, one Rules row per `sweep = "<case>"` entry of `loops.ALLOWED`: the mutant stops that loop's advance and the sweep must fail (run as above, with a short limit). This is the check that found `paths.rewrite`.
4. finishes.spec cases: a witness whose result differs fails and names the case; a fixture that raises on every non-empty text fails; an empty text list is refused. tree.spec's raftcheck case requires the case's witness, not the prefix's substrings.
5. The zz-test bullet and the lesson's **How to apply** say that a case proves it reaches its scanner with a witness.
Lesson: zz-test/no-vacuous-pass

### F2 [medium] `hostile.bounded` accepts `math.huge` and any limit past perl's alarm range, then runs with no wall limit and no CPU limit (repeat of design-review-001 F2's mechanism)
Where: `prototype.patch` `hostile.bounded` (`not (seconds >= 1) or seconds ~= math.floor(seconds)`) and `BOUND` (`ulimit -t "$0"; exec "$@"`); AC3; Rules row "the limit is a whole number of seconds, 1 or more".
Evidence: in the clone, `hostile.bounded(math.huge, { "sh", "-c", "ulimit -t" })` returned `code = 0, stdout = "unlimited\n", stderr = "Inf: line 0: ulimit: Inf: invalid number\n"`. `hostile.bounded(1e20, …)` returned `stdout = "unlimited\n"` with `alarm() with negative argument` and `ulimit: 1e+20: invalid number` on stderr. `math.floor(math.huge) == math.huge`, so the whole-number check passes. Because of the `;`, a `ulimit` that fails still runs the command.
Critique: a guard that fails open on an argument it accepts breaks zz-arch rule 7, the same way round 1's 0.5 did. The CPU limit was added as the second line, and it fails open too.
Consequences: an upper bound is a new rule with a stated maximum. `ulimit -t … || exit 126` brings a new exit code. A hard limit the caller already inherited (c0191 plans a 1200 s spec-runner CPU limit; `ulimit` refuses to raise a hard limit) would then refuse a run that is already bounded. So the shell has to keep a lower inherited limit rather than fail.
Recommendation: refuse a limit above a stated maximum (for example 3600, or c0191's 86400), as `seconds >= 1 and seconds <= MAX and seconds == math.floor(seconds)`. Run `{ c=$(ulimit -t); [ "$c" != unlimited ] && [ "$c" -le "$0" ] || ulimit -t "$0"; } || exit 126` (c0191's jail shell form: it keeps a lower inherited limit and otherwise sets one or stops), and report 126 as "the CPU limit could not be set". Add finishes.spec cases: `math.huge`, `2^31` and `1e20` are refused before anything starts; a command started under a lower inherited limit still runs and sees that limit. Add Rules rows for "upper bound removed" and "`;` for `||`".
Lesson: zz-arch/guard-no-is-explicit

### F3 [medium] `bounded` has no lifeline: a SIGKILLed wrapper leaves the command's group running with no wall limit and out of the jail sweeper's reach, and only TERM of the four trapped signals is pinned
Where: `prototype.patch` `BOUND` (`setpgrp(0, 0)` in the child); Design, Chore checklist "Guards" ("so no process outlives the call even where … the wrapper is killed"); Maintainability (c0191); `finishes.spec` "stops the whole group when the wrapper is signalled"; Rules row "a signalled wrapper kills the group".
Evidence:
- I extracted `BOUND` to a file, ran `perl bound.pl 20 sleep 13.371` and sent the wrapper `kill -9` after 1 s. One second later `ps` showed `76324 1 76324 sleep 13.371`: alive, PPID 1, in its own process group (I killed it by hand).
- The child leaves the caller's group (`setpgrp(0, 0)`). The jail's sweeper (tests/run's wrapper, `kill 'KILL', -getpgrp()`) kills only its own group, so it never reaches this child, despite round 1's "the jail's sweeper catches it". The `seconds + 1` CPU limit stops a spinner after about 31 CPU-seconds by default. It never stops a process that waits: a sleeper, or a `lune` blocked on a pipe.
- finishes.spec sends only `TERM`. A mutant that removes the INT handler (Ctrl-C, the commonest way a run ends early), the HUP handler or the PIPE handler passes every case, and the Rules table lists only "the TERM handler removed".
- Round 1's F3 was harvested into zz-arch/children-need-a-lifeline, which asks for "a supervisor whose stdin is a pipe from the parent [that] kills the group on end of file". The fix does not have one.
- c0191 is in prep now (`c0191.md` §bounded.pl, E3: "runner killed with `kill -9` (the watchdog stopped the group within its grace)") and designs exactly that runner. Its Existing work (2) says perl-alarm specs are "covered by the jail's sweeper", which is false for a child that called `setpgrp`.
Critique: the repo would get two bounded runners, and the second lacks the lifeline the first already has. This machine's user treats a leaked process as a defect, and the design's sentence promises more than the code does.
Consequences: a lifeline adds a watchdog process to every sweep, which needs its own case that kills the wrapper. Reusing c0191's runner instead adds `depends_on: [c0191]` and a landing order.
Recommendation: choose one of these with c0191's lead (one runner):
- (a) Give `BOUND` the jail sweeper's shape: the command's group holds a watchdog that reads a pipe whose only write end the wrapper holds, and that kills its group on end of file.
- (b) `depends_on: [c0191]`, and `finishes` runs the driver through c0191's `bounded.pl` without changing its own interface.

Either way:
- Correct the Guards sentence.
- Add finishes.spec cases for each way the wrapper can end:
  - a SIGKILLed wrapper leaves no sleeping grandchild within 1 s;
  - a wrapper sent INT exits 130, and one sent HUP exits 129, with the group gone in both cases.
- Add one Rules row per handler.
- Tell c0191 that its Existing work (2) does not hold for a child that leaves the group.
Lesson: zz-arch/children-need-a-lifeline

### F4 [medium] The proof is textual, so writes through a call, a closure or an alias still prove loops that spin, and a proven loop that reads text needs no sweep (repeat of design-review-001 F4's mechanism)
Where: `prototype.patch` `loops.find` (`assigns`, `writes`, `steps`) and `loops.problems` (a sweep is asked only of a listed loop); Design "What proven means"; AC4; zz-arch rule 9.
Evidence: `loops.find` in the clone returned `advances = true` for each of these:
- `local function back() i -= 1 end` / `while i <= n do back(); i += 1 end` (a closure steps back; spins).
- `local function push(x) table.insert(q, x) end` / `while i <= #q do push(q[i]); i += 1 end` (the bound grows through a helper; spins).
- `while i <= #q do local r = q; table.insert(r, r[i]); i += 1 end` (an alias).
- `while i <= self.n do self:grow(); i += 1 end` (a method on the bound's owner).
- `while i <= n do i += 1; set(function() i = 0 end) end` (a closure literal that resets i).
- `while i <= n do i = scan.advance(i, j) - f(k) end` (`steps` takes `scan%.advance%(V, .+%)$`, so any tail that ends in `)` passes).

`loops.problems` asks for `sweep` only on the listed path. A proven loop that reads text, the closure shape above included, is never listed and never swept. On the tree today, three proven loops read text (`lease.luau:61`, `main.luau:751`, `run.luau:149`, all argument loops).
Critique: round 1 added textual rules. Every round can find another write that the loop's own text doesn't show, because Luau upvalues and aliases are invisible to a line scan. The proof can't be made sound this way. What it can do is say what it proves and stop being the only line for scanners.
Consequences: if a sweep is required of every loop that reads text, the three proven argument loops need a sweep decision (`false`, with a reason) in a place that is not `ALLOWED`, where a listed proven loop is stale. Voiding the proof on calls to same-file functions that assign V lists more loops.
Recommendation:
1. State the limit in the Design, in AC4, in rule 9 and in the lesson's check: "proven" means no write that the loop's own text shows. A write through a call, a closure or an alias stays the reviewer's question.
2. Ask for a sweep decision for every loop that reads text, proven or not. For example, `loops.SWEPT[path]` keyed by header, in file order, with the same stale and name rules, checked by `problems`.
3. Anchor the `scan.advance` form to a call with balanced parentheses (`^V = scan%.advance%(V, [^()]*%)$`, or a parenthesis count), with a loops.spec case for `- f(k)`.
4. Optionally void the proof when the same file defines a local function that assigns V or writes B and the body calls it, or when the body binds a local to B. Either way, add a loops.spec case per shape above that asserts the documented outcome.
Lesson: zz-test/guard-needs-its-own-case

### F5 [medium] Existing work misses the mid-prep sibling c0191, whose new shell-command tokenizer adds seven text-reading loops: the incident's own class
Where: Design, Chore checklist "Existing work" (only branches on origin are measured); Implementation step 5.
Evidence: c0191 (`.worktree/prep-no-leaked-processes`, in prep; its doc lines 96 and 105) adds `z-nile/engine/boundcmd.luau` (reference `experiments/ref-boundcmd.luau.txt`) and `z-nile/engine/reap.luau` (`ref-reap.luau.txt`). I ran the prototype's `loops.problems` over both:
- `boundcmd.luau`: 8 problems (lines 67 `repeat`, 100, 111, 118, 138, 200, 208, 263); 7 of those loops read text (quotes, backslashes, `$(` depth).
- `reap.luau`: 2 problems (210 `while at ~= 1 do`, 238 `while grew do`).

The search for other in-flight code was `grep -lE "^\s*(while|repeat)\b" .worktree/prep-*/z-nile/.tracker/issues/*/experiments/*` plus every `prototype.patch` under `.worktree/prep-*` (hunks adding `while`/`repeat` in covered paths). Its only hits beyond c0193 are c0191's two files and `z-nile/.tracker/issues/c0083/experiments/classify.luau`, which sits under `.tracker/` and is skipped. The local proto branches carry the same loops as their impl branches already in the table.
Critique: the chore checklist asks for mid-prep items. `boundcmd` is a quote-and-backslash parser, the scanner most in need of a sweep case, and c0191's design says nothing of `loops.ALLOWED` or `scanners.luau`. Whichever lands second meets ten lint failures and a case to write (with a witness, F1), and nobody has told it.
Consequences: none to the specs. The notice goes to one more lead, and the per-branch table gains a mid-prep row.
Recommendation: add c0191 to Existing work with the search above and its counts. Say what the second to land does: list the ten loops with reasons and add a `boundcmd` scanners case. Send it to c0191's lead now and record the sending. Rerun the search over every `.worktree/prep-*` before the final round.
Lesson: z-design/new-rules-migrate-existing-work, z-design/quote-other-preps-before-promising

### F6 [medium] c0181's design expects this lesson's check to be a spec case named `[zz-arch/…] …`, while c0193 names none and pins the lesson text that c0181 will convert in a promoted spec
Where: Non-goals (c0181 bullet); `acceptance/docs.spec.luau:51-69` (promoted); the case names in `tree.spec`, `scanners.spec` and `loops.spec`.
Evidence: c0181.md (prep-lessons-codify-consolidate, 6d9318e5) says on line 104: "c0193 … its prep writes a spec case named `[zz-arch/…] …`". Its policy rule 3: "A spec ref is `<path> :: "<case>"` … the case is named `[<this id>] …`", and a lint ref must be `z-nile/lints/<slug>.luau` holding `lesson = "<id>"`. Rule 2 caps the lesson body (part 1,200 and full 500 bytes).
- `grep -n "\[zz-arch" acceptance/*.spec.luau` in c0193's folder returns nothing, and the lint lives in `tests/lib/loops.luau`.
- Once promoted, docs.spec requires the lesson's `**Enforced by**` paragraph to name four files, plus "14 h", "PR #125" and "c0193", in 20 lines or fewer.
- c0193's Non-goals quote a c0181 that no longer exists: "the `codified <path>` harvest form" is now `- codify <id>: <ref> mutant: …`. They also say the paragraph is one "that c0181 can turn into the field".
- Promoted specs are never edited. Turning the paragraph into `enforced_by`, and renaming the cases to `[id] …` later, would each need an override chore.
Critique: the capture asks for the c0181 design of which part is a check. The design reaches c0181's goal but not c0181's format, and its own promoted spec blocks the conversion it promises.
Consequences: renaming cases now costs nothing. Moving the lesson-text pins to check.sh means they run only at `done`, which is right for today's text. If c0181 lands first, its policy applies to this new lesson (`enforced_by` with `enforced: part`, or `not_codifiable`), and AC9's `lessons --check` must pass it.
Recommendation: name the cases that decide the rule `[zz-arch/scanning-loops-advance] …`: tree.spec "has no loop…", scanners.spec "finishes…", the loops.spec incident case and the scan.spec incident case. Move the lesson-content pins (the Enforced by paragraph, "14 h", "PR #125", the line cap) from docs.spec to a check.sh AC8 line. Keep in docs.spec only rule 9 and the zz-test bullet. Quote c0181's current text in Non-goals, and say what each side does if the other lands first.
Lesson: z-design/quote-other-preps-before-promising, zz-test/promoted-specs-pin-rules-not-sets

### F7 [low] The alphabet check sees only `==`/`~=` literals, while AC7 claims "every character its module compares with"
Where: `acceptance/scanners.spec.luau` `compared()`; AC7.
Evidence: `ids.rewritePaths` branches on `string.match(before, "[%w_/%.}%$%-]")`, and neither `}` nor `_` is in `scanners.ALPHABET`. The check passes because it reads only `== "x"` and `~= "x"` forms. One-character plain `string.find` needles and `string.byte` comparisons are invisible to it too.
Recommendation: word AC7 and the Design as "every one-character literal it compares with by `==` or `~=`". Alternatively, widen `compared()` to the literal members of `[…]` classes and to one-character plain `find` needles, with `EXCEPT` reasons for letters and digits. Either way, add one case per form the reader claims.

### F8 [low] check.sh's labels lag the document's AC3, AC4 and AC7
Where: `check.sh` AC3 ("passes scanners that return or refuse on every text … leaving no child and no folder"), AC4 and AC7.
Evidence: the document's AC3 adds the never-ran case, the crash, the limit refusal, the group kill and the 128 + n code. Its AC4 adds the reset, bound and end-by-structure clauses. Its AC7 adds "each case reaching its scanner, and the alphabet". The labels say none of this.
Recommendation: copy each Checked criterion's current text into its `check "ACn: …"` label (after F1, F2 and F4 change them).
Lesson: z-design/spec-design-correspondence

### F9 [low] scanners.spec pins today's six scanner names in a promoted spec
Where: `acceptance/scanners.spec.luau` `REQUIRED` and "has a case for each text scanner …, once each".
Evidence: the case requires exactly these six names, each once. tree.spec already holds the rule that every listed text loop names a case that exists. Retiring `skills.oldNames` (a c0115 rename helper) or renaming a case would turn the gate red and need an override chore.
Recommendation: put the six-name check in check.sh's AC7 line, which runs at `done` (a claim about today's tree). Keep the promoted spec on the rule: unique names, and every case runs.
Lesson: zz-test/promoted-specs-pin-rules-not-sets

### F10 [low] finishes.spec spins a core for 4 s in every z-nile full gate
Where: `acceptance/finishes.spec.luau` "fails a scanner that never returns" (limit 4).
Evidence: the spec took 7.2 s of wall time here, 4 s of it a 100%-CPU spin. The case asserts only the message and the block (texts 17..32 of 40), and the driver reaches text 20 within a few tenths of a second.
Recommendation: a limit of 2 holds the same assertions with ample margin over `lune`'s start. This machine's user treats gate CPU as a cost.

Lesson candidates (for the lead to place; I write no lesson file):
- A sweep case proves it reaches its scanner's work with a witness (an input and the output only that work produces), and each listed sweep is mutation-checked by stopping its loop's advance. Check: if this loop never advanced, would the sweep that names it fail? (F1)
- A textual proof of a runtime property states what it cannot see (upvalues, aliases, calls) and is never the only line. Check: which write to this variable or bound does the loop's own text not show? (F4)

Verdict: changes
