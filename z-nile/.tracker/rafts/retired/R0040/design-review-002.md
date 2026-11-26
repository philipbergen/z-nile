# Review 002: R0040 (design mode)
Inputs: prep worktree at 36b83a2 plus its uncommitted changes (R0040.md, check.sh, harvest.md, design-review-001.md, design-refute-001.md; c0111.md, check.sh, acceptance/*.spec.luau; the 8 lesson files under .claude/skills/*/lessons/); scripts/tracker/main.luau, the skills, tests/; the prototype in .worktree/proto-skill-lessons (its c0111 folder, ledger and lessons are identical to the prep's), copied to a scratch clone under $TMPDIR (origin removed) for mutants and `promote-check`. In the prototype, `lessons --check` and `--uncovered R0040` pass.
Dropped from design-review-001: F1, F2, F3, F4, F5, F6, F7, F8, F9 (each fixed as design-refute-001 says. F1's `active/` seed and F5's two forms are in place, but see F2 and F3 below for holes in the same mechanisms).

### F1 [high] `promote-check` fails: two sequestered specs don't type-check, so RC0 can never pass and the executor may not fix them
Where: harvest.spec.luau:28-35 (`tree()`); skill-docs.spec.luau:78; R0040 check.sh RC0 `promote-check R0040`; ticket-prep step 4 "Dry-run the promotion"
Evidence: `scripts/tracker.sh promote-check R0040` on a scratch copy of the prototype (the real `lessons.luau` present) prints:
- `tests/acceptance/c0111/skill-docs.spec.luau(78,14): TypeError: Argument count mismatch. Function 't.expect' expects 0 to 1 argument, but 2 are specified`. `string.find` returns several values.
- `tests/acceptance/c0111/harvest.spec.luau(29,2): TypeError: Table type '{| items, lessons, problems, skills |}' not compatible with type 'Tree' because the former is missing field 'found'`.

It ends with `promoted acceptance specs would break tests/`. The runtime runner doesn't type-check, which is why every spec "passes". The `found` field came from round 1's F1 fix: the type changed, and one spec literal of it didn't.
Critique: Ticket-prep makes the dry-run a prep step: the only acceptable failures are requires of modules the raft will create. This isn't one of those, and nothing in Unknowns & experiments says `promote-check` was run after the round-1 fixes. During execution the specs are sequestered, so RC0 stays red until the raft escalates. The tempting fix is to patch the two lines and move on.
Consequences: Any later change to an exported type (`Tree`, `Item`, `Query`) brings the same hazard back, and the executor can't widen a type without breaking a sequestered literal. So the fix should leave the specs robust to a new optional field.
Recommendation: In harvest.spec, add `found = {}` to `tree()`. In skill-docs.spec:78, assert `t.expect(string.find(s, "record it as a lesson in", 1, true) == nil).toBe(true)`. Rerun `promote-check R0040` on the prototype after every answer round, and record the result in Unknowns & experiments next to E1. Harvest this finding into a lesson whose `check` asks "after any change to a typed interface or a spec, does `promote-check` pass?" (or sharpen an existing one), since runtime-green specs hid a type break.

### F2 [high] (repeat of design-review-001 F1) The CLI fixture still skips four of `load`'s six state folders, including `tracker/rafts/done`, where R0040 and nearly all past reviews live
Where: c0111.md Design, **load** (`{issues,rafts}/{,active/,done/}`); lessons-cli.spec.luau SEED; Rules and mutants row "load reads `active/`"
Evidence: The fixture's reviewed items are `rafts/R0010` (backlog), `rafts/active/R0050` and `issues/done/c0020`. `issues/c0040` holds only an `experiments/` subfolder, so it is not an item. Nothing is seeded in `tracker/rafts/done`, `tracker/issues/active` or a backlog issue with reviews. In a scratch copy of the prototype I made `load` skip `rafts/done` and backlog `issues`. lessons-cli (12 passed), harvest, select and prompt-lessons all still pass. A six-path list of folders, which is a natural way to write `load`, can lose any of them the same way. With `rafts/done` dropped, the consequence on `main` is concrete:
- The moment `done` moves R0040 into `tracker/rafts/done/` (204 review files live there today), its `harvest.md` stops being read.
- All 8 lessons become sourceless, so `lessons --check` fails for everyone. Ticket-prep 5.5 and execute-raft Phase 5 step 3 both require it to pass, so every later prep and raft is blocked.
- `--uncovered R0040` turns into `no such item`, and the prompt's counts drop to 0.

AC8 and RC1 can't see any of this, because they run before the move.
Lesson: testing/seed-every-enumerated-case
Critique: Round 1's fix added exactly the one folder the review named (`active/`). That is the hand-picked-fixture pattern this raft's own lesson warns against, so the mechanism, not just this hole, should change. The tempting fix is to add `rafts/done` too, which still leaves `issues/active` and backlog issues to the next round.
Consequences: Generating the fixture from the Design's cross product makes the spec and the Design state one list, so a seventh state folder (if one is ever added) has to be added in both. It adds six items to the exact `--uncovered` list, so that case's expected output changes. `found` and `no such item` walk the same loop and need the same cover.
Recommendation: In lessons-cli.spec, build the seed in a loop over `{ "issues", "rafts" } × { "", "active/", "done/" }`, one item per pair (for example `c0071`, `c0072`, `c0073`, `R0071`, `R0072`, `R0073`), each with a `design-review-001.md` holding one unharvested F1. Assert the exact `--uncovered` list (all six, in id order, plus the existing ones). Also assert `--uncovered R0073` (a done raft) exits 1 and lists its finding, and that a harvest in a done raft counts as a source, for example by moving R0010's ledger and reviews under `rafts/done/`. Replace the single "load reads `active/`" row with "load reads every state folder of both kinds", whose mutant is "any one of the six folders skipped" (run once per folder). Add a new source for `testing/seed-every-enumerated-case` in the ledger.

### F3 [medium] (repeat of design-review-001 F5) The "capture an issue" form tells stream subagents and reviewers to run `tracker.sh new`, which they are forbidden to do, and which publishes to `origin/main`
Where: c0111.md The skills ("Every other skill captures an issue … runs `scripts/tracker.sh new issue c lesson-<slug>`"); prototype Lessons sections of testing, architecture, tracker and review; execute-raft Phase 2B step 2; tracker skill "Published or carried"
Evidence:
- Execute-raft Phase 2B step 2 hands each Sonnet stream "the architecture, testing and tracker skills to follow" and the rule "never run `tracker.sh new`, `focus`, `commit` …; a problem the stream finds that no issue covers goes in its final report, and you file it". The new Lessons section of those same three skills says "capture it instead: `scripts/tracker.sh new issue c lesson-<slug> …`".
- The review skill's Lessons section gives every reviewer, including this one, the same `new issue` instruction. A reviewer's brief says "Write only that file", and design mode runs before any PR exists. The tracker skill says `new issue` is "pushed straight to `origin/main`", so a reviewer following it publishes shared state and leaves an issue folder in the prep tree, which the author's `git add -A` commits.
- The section's last sentence ("A reviewer puts a candidate lesson in its review … never in a file") contradicts the instruction just before it rather than replacing it.
Lesson: ticket-prep/instructions-runnable-where-they-run
Critique: Round 1 split the section by skill (writer vs non-writer). But the agent that reads a skill is not fixed by the skill: testing and architecture are read by the lead, by stream subagents and by reviewers. So "which skill" is the wrong axis, and the tempting fix (a "streams don't do this" clause in three skills) is a third patch to the same mechanism.
Consequences: Splitting by role adds one rule: a subagent never captures, it reports. The lead (the prep author or the raft lead) then either harvests it with `from:` (it can land a file) or captures it. Main-checkout and capture sessions are always leads, so for them the existing capture form stands.
Recommendation: Word the non-writer form by role, not by skill: "If you are a subagent (a reviewer, a stream, any agent with a brief), never run `tracker.sh new` and write no lesson file: put the candidate lesson (rule, why, check question) in your review or final report. If you lead the session, capture it: `scripts/tracker.sh new issue c lesson-<slug> …`." State it under The skills. Add to execute-raft Phase 2B step 2's stream rules that candidate lessons go in the stream's final report, and that the lead harvests them in Phase 4 step 5 with `from:`. In skill-docs.spec, assert every non-writer Lessons section contains the subagent clause (a fixed phrase, such as "If you are a subagent"), and that execute-raft's Phase 2B names lessons in the final report. Add a row with the mutant "a skill's Lessons section without the subagent clause".

### F4 [low] Which stream `no such item` goes to is not specified, but lessons-cli reads it from stderr
Where: c0111.md The command, `--uncovered` (line 139) and **Streams** (line 141); lessons-cli.spec.luau:179-181
Evidence: Streams lists what goes to stdout (including `no reviews`) and says "Warnings and usage errors go to stderr". `<id>: no such item` is neither a warning nor a usage error, and it sits beside `no reviews` (stdout) in the same three-case list. An implementation that prints it on stdout with exit 2 meets the Design but fails `has(missingErr, "R0099: no such item")`.
Lesson: ticket-prep/spec-design-correspondence
Critique: This is the round-1 F6 class: an assertion on a stream the Design doesn't state. It's small, but the spec is sequestered.
Consequences: none.
Recommendation: Add "and `no such item`" to the stderr half of the Streams sentence.

### F5 [low] AGENTS.md (and the Problem section) still say every skill records lessons when it finishes, which contradicts the two forms
Where: prototype AGENTS.md added sentence ("every skill reads its own when it starts and records new ones when it finishes"); c0111.md The skills (AGENTS.md bullet), skill-docs.spec AGENTS.md assertions
Evidence: After the round-1 F5 fix, only ticket-prep and execute-raft write lesson files. AGENTS.md is the first file every agent reads, and it still tells all of them to "record new ones". skill-docs pins only `lessons/` and `scripts/tracker.sh lessons` there, so the stale clause passes.
Lesson: ticket-prep/instructions-runnable-where-they-run
Critique: The project's entry point contradicts the skill sections that F5 fixed.
Consequences: none.
Recommendation: Specify the sentence, for example: "Each skill keeps what reviews and mistakes taught it in its `lessons/` folder, searched with `scripts/tracker.sh lessons`. Every skill reads its own when it starts; ticket-prep and execute-raft write them, and other skills capture them as issues." Have skill-docs assert that AGENTS.md does not contain "records new ones when it finishes".

### F6 [low] The code-review harvest is limited to `when: build` or `both` lessons, which forbids the preferred action for a design-class code finding
Where: c0111.md The skills, execute-raft Phase 4 step 5 ("with `when: build` or `both` lessons"); prototype execute-raft step 5
Evidence: A code review often finds a defect the design should have prevented, for example a sequestered spec that a wrong implementation passes, or a missing edge case. The best target is then an existing `when: design` lesson, such as `ticket-prep/spec-design-correspondence`, and the harvest step says to prefer adding a source to an existing lesson. As worded, the harvester must either create a duplicate build lesson or flip the design lesson to `both`, and flipping it puts a design-only question into every execution prompt.
Critique: The constraint has no stated reason and works against the "prefer an existing lesson" rule.
Consequences: none: sources are computed, so a code-review entry may name any lesson.
Recommendation: Reword it as "any lesson; a new lesson from a code review is usually `build` or `both`", in the Design and in the execute-raft text.

Verdict: changes
