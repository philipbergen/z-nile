# Review 006: c0458 (design mode)
Inputs: prep worktree `prep-collapse-reviews-and-tighten-caps` at 913bbbd79 with its uncommitted `z-nile/.tracker/issues/c0458/{c0458.md,check.sh,guesses.md,harvest.md,acceptance/{caps-modes,walk,docs,publish}.spec.luau,experiments/prototype.patch,design-refute-005.md}`; `design-review-005.md`. Checks made, every run through `./zn run`:
- `experiments/prototype.patch` (489 lines, 8 files) applied to a `git archive 1b78199b0` copy in `.cache/c0458-r6-proto`, its own repository, with the four specs copied into its `z-nile/tests/acceptance/c0458r6`. The copy's commits took their identity from the environment, and no identity was written to any git configuration. origin/main is now d60cb9f9d: since the base it changed tracker files and the id counter `z-nile/next` only.
- On that copy publish passes 4/4, walk 5/5 and caps-modes 4/4. docs fails 2/2 at `docs.spec:20` and `:41`, because the copy holds today's skills. With the base `publish.luau` put back, publish fails 3 of 4.
- Sixteen mutants of the prototype's `publish.luau` against `publish.spec`, and seven of its `easy.luau` and `work.luau` against `walk.spec`, one at a time, each restored after its run and the copy's tree checked clean. All sixteen are red. Of the seven, four are red and three stay green: two are F1, and the third (the walk's `next(r.raised)` test removed) is no finding, because item 10 makes the readers hand the walk nil when nothing is raised.
- `./zn promote-check c0458` inside the copy, with the current specs: no type error in c0458's four specs.
- A read-only probe of `trace.deriveClaims` on the document.
- `./zn capture c0458` compared with the document: Problem, Non-goals and Solution are the capture's text, line for line.
- Also read: `publish.luau` (`movedEdit`, `raiseEdit`, `validateMoves`), `main.luau:5466-5486` and `:7250-7300`, `workread.luau:333-450`, `work.luau:396-420`, `light.luau:286-330`, `lightgit.luau:150-250`, `easy.luau:26-180`, `tests/tooling/light-path.spec.luau:1296-1400`, `tests/tooling/easy-path.spec.luau:158-163`.

Round 5 answers. The refute file disputes nothing, so there is no refutation to accept or re-raise.
- F1 is fixed. The refusal case has one line per rule and a control. I checked each line of the raised ticket against the guard's conditions: each breaks exactly one. `publish.raiseWhole` is exported, `validateMoves` calls it in the patch, and AC4's text names the rules. Sixteen mutants are red, each on an assertion:
  - the raised ticket, six mutants: `now >= was`, `design == draft`, the raft before, the raft after, `level ~= easy` and `risk == level`, each removed;
  - the released member: `risk:` allowed, the raft before removed, the raft after removed;
  - the raft: list equality removed, the empty list after removed;
  - an empty raise accepted;
  - `raiseWhole`: disabled, the released members left out, the raised tickets left out, the raft left out.

  The row marks "released members left out" as reasoned. It is red at `publish.spec:83`. The Rules table keeps the publisher's rules in one row, where round 5 asked for a row each. I accept that: the row lists every mutant and each one is red.
- F2 is fixed in item 10, the patch and the spec. The empty raise is refused for the raft and for a member, and its mutant is red at `publish.spec:73`. The IO case the refute places in the Test plan is not there (F2 below).
- F3 is fixed for the rule and its own-level cases. Item 10 decides the rule, `raisedBy` takes `noted`, and both own-level mutants are red (`walk.spec:190` and `:191`). The below-level case cannot fail (F1 below). The IO case round 5 asked for, a raft of three with a short-noted ticket whose `risk:` was raised on main, was not taken. I accept that: `light-path.spec.luau:1371` runs the one builder through `stop`, and with the added assertion through the walk.
- F4 is fixed. The patch's text reads "raised c0011 to risky, c0012 to normal", and the "already holds" parenthesis is gone. The new words reach an existing assertion (F2 below).
- F5 is fixed in E5: the length, the files, the mutants and the criterion each spec checks match what I ran. The Test plan's run line was only half updated (F2 below).
- F6 is fixed. The reader gives `c0458:AC1` to `c0458:AC4` in `check.sh`'s order.
- F7 is fixed. Item 4 names the three passages, step 9's sweep has `Level:`, and `docs.spec:35` pins the line form in Final mode. That pin is not reached on today's skills, because the case fails earlier. Its row says reasoned, which is right.

### F1 [medium] AC8's below-level case cannot fail, and the rule that the highest line wins has no case
Where: `acceptance/walk.spec.luau:192-193` and `:186-188`; Design item 10 ("A line below a ticket's own level raises nothing"; "per ticket the highest of normal and risky wins"); Rules row "a line at or below a ticket's own level raises nothing"; refute-005 F3 ("AC8 has the cases (own level with and without the note, below it, ...)")
Evidence:
- Line `:193` gives `Level: c0011 easy` to a normal c0011 on a short note. `raisedBy` drops the word `easy` before it compares levels (`word ~= "easy"` in the patch). So the line tests that `easy` raises nothing, which `:190` and `:202` already pin. No case holds a ticket at risky, so no case has a line of normal or risky below a ticket's level.
- Mutant 1: the patch's condition changed to `(RANK[word] > current or noted[ticket] == true)`, so any line of normal or risky raises a short-noted ticket. `walk.spec`: "5 passed, 0 failed".
- Mutant 2: `and (out[ticket] == nil or RANK[word] > RANK[out[ticket]])` removed, so the last line wins. `walk.spec`: "5 passed, 0 failed". Line `:186` has two lines for two tickets. No case gives one ticket two lines.
- What each wrong reader does, read from the design and not run, because the prototype holds no `stop`:
  - Mutant 1, for a risky ticket on a short note with a `Level: normal` line: the walk says `release` and `stop` writes `risk: normal`. The publisher refuses the lowered level (`publish.spec:46`), so `stop` fails every time and the walk keeps saying `release`.
  - Mutant 2, for an easy c0010 whose reviews hold `Level: c0010 risky` and then `Level: c0010 normal`: the reader answers normal. `stop` publishes `risk: normal`, the publisher accepts it, and the ticket needs no design review where a review said risky.
- Today's reader has the highest rule pinned in `tests/tooling/easy-path.spec.luau:159-160`. That spec is the executor's to edit and does not call `raisedBy`.
Critique: round 5's rule gave the reader a second way to raise (the `noted` clause), and the case written for its limit uses the one word that can never raise. Round 4 accepted the same `easy` line as the below-level pin, when the only mutant was `>=` for `>`. The tempting fix is to reword the comment at `:192`.
Consequences:
- Pinning `{}` for a short-noted ticket above the line's level also pins that this line does not stop the ticket. It stays at `risk: risky` with only a short note. The next final-review round is what catches it: the brief asks for `Level: risky` for a ticket that needs a design review, and that is an own-level line on a short-noted ticket, which raises. Item 10 should say this in one clause, so the pinned value reads as decided.
- The Rules row "a line at or below a ticket's own level raises nothing" no longer states the rule. An own-level line raises a short-noted ticket, and the row under it says so. The row becomes the below-level rule.
Recommendation:
- Add three lines to AC8, with `local high = { c0010 = "easy", c0011 = "risky", c0012 = "normal" }`:
  - `raisedBy({ "Level: c0011 normal\n" }, high, { c0011 = true })` is `{}`;
  - the same call with no note is `{}`;
  - `raisedBy({ "Level: c0010 risky\n", "Level: c0010 normal\n" }, high, none)` is `{ c0010 = "risky" }`.

  I ran these three on the prototype as a probe spec. They pass there. Mutant 1 turns the first line red and mutant 2 the third.
- Reword the row to "a line below a ticket's own level raises nothing, short note or not", with the mutant "any line raises a short-noted ticket". Add a row "the highest line wins per ticket" with the mutant "the last line wins". Mark both `run`, with the red lines in E5.
- Add the clause from Consequences to item 10.
Lesson: z-design/spec-design-correspondence
Erred: z-design
Upstream: zz-review

### F2 [low] Three of round 5's answers left text behind that the executor reads
Where: refute-005 F2 ("the IO no-raise case ... is in the Test plan for the executor"); Test plan, the IO bullet, the "Edited existing specs" bullet and the "Run result at prep" line; `work.forRaft`'s `release` text in `experiments/prototype.patch`; `tests/tooling/light-path.spec.luau:1309`
Evidence:
- The no-raise IO case. Item 10 says "an IO case pins both" and the Rules row names "the IO no-raise case". The Test plan's IO bullet lists the raised raft, `stop` of that raft, `done` and `resolve`. It has no raft with nothing raised. The two fixtures (a final review with no `Level:` line, and one whose only line is at a full-design ticket's own level) and what the case expects (the raft still lists its three issues, each member still names it, `./zn ready <R>` readies it again) are in review-005 and refute-005 only. A grep of `c0458.md` for "no `Level:` line", "still lists" and "readies" finds nothing.
- The run line. It says "3 of 4 publish cases (the refusal case passes there, the old guard refusing everything)". With the base `publish.luau` on the copy, the refusal case fails at `publish.spec:41`, its new control. The case that passes is the empty raise. The same line's green half lists the prototype's files without `publish`, and says "AC1 and AC2 pass" without AC4.
- The release wording. Round 5 F4's fix took the words "not easy" out of the walk's `release` text. `light-path.spec.luau:1309` expects `has(walked.stdout, "not easy")` for that text, in a final-review case the Test plan lists as kept.
Critique: an answer that lives in the refute file binds nobody, and this is the second refute file in a row with one (round 5 F4 found the same in refute-004). The no-raise case exists for one trap: `raisedBy` answers an empty table, not nil, for both fixtures. The executor would have to rebuild those fixtures from one clause.
Consequences: none. A tooling spec is the executor's to edit, so the Test plan only has to say which assertion changes.
Recommendation:
- Put the no-raise case into the Test plan's IO bullet, with both fixtures and its three expectations.
- Correct the run line: the empty-raise case is the one that passes on origin/main. Add `publish` and AC4 to its green half.
- In "Edited existing specs", say that `light-path.spec.luau:1309` changes from "not easy" to the new wording, for example "raised c0010 to normal".
Lesson: z-design/restated-rules-move-together
Erred: z-design
Upstream: none

Verdict: changes
