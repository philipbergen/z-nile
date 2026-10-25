# Review 008: c0115 (design mode)
Inputs: prep-c0115 at ec280c0 (the delta `git diff a930488..HEAD`: the answers to round 007), with design-review-007 and design-refute-007; c0113's document and `check.sh` (`./zn capture c0113`); a scratch clone of proto-c0115 at 20e0d20 (its c0115 and c0113 `check.sh` and the rename script are byte-identical to this branch's).
Dropped from design-review-007: none. F1 to F8 are fixed, verified below.

Verified on the scratch clone, each from the root and from `z-nile/`:
- AC14 (07 F1, F7): green on the clean tree. Red for a planted `/launch-raft R0010` in a pickman design, a bare `ticket-prep` in a z-nile design, and `{SKILLS}/testing/SKILL.md` in a sequestered spec (the last caught by `backlog_clean` alone, the script reporting 0). `backlog_clean` alone is red when the roots command is `z-nile/nosuch`, prints nothing, or prints a root that doesn't exist ("no unfinished item's document was read"). The rename script's `--check` exits 1 with `z-nile/nosuch`. With z-nile's `home` set to `z-nile` in `projects.toml`, AC14 stays green and still reads the backlog.
- c0113 (07 F2): `./zn check c0113` 2/2. With z-nile's home moved to `z-nile` and `.claude/README.md` restored and tracked, AC2 is red. AC1 is also red there, because `lune run tests/run` resolves from the home, so it fails closed rather than vacuously.
- AC15 (07 F3): red with no raft, red with `raft: R0034` ("R0034 does not hold c0113"), green once c0115 and c0113 both carry `raft: R0099`. `./zn members` derives membership from the members' frontmatter, so the check reads the same source that `./zn done` closes from. It is a sound guard.
- 07 F4: `engine.COPIED_SKILLS = { "z-nile/skills" }`, walked by `clearLessons` and the G7 case. F5, F6 and F8 text is as the refute says.

### F1 [high] c0113 is `design: ready` with its template placeholders unfilled, including the `Overrides:` line
Where: `z-nile/.tracker/issues/c0113/c0113.md`, Regression guard, Acceptance criteria, Test plan, Implementation steps
Evidence: the Regression guard still reads `Overrides: <promoted specs (tests/acceptance/) this issue deliberately changes, each with its chore, or none>`. `### Checked` is empty, but c0113's `check.sh` has AC1 and AC2 under a header that says "One `check "ACn: ..."` per Checked acceptance criterion, in the same order as the issue doc". The Rules and mutants table, Affected specs, Unknowns and Implementation steps are bare template comments. The review skill (design mode 4) rates an unfilled Overrides placeholder high. This round's job was to approve c0113's Design for `design: ready`, and its acceptance criteria exist only in `check.sh`. The substance is fine: deleting `.claude/README.md` overrides no promoted spec (`grep -rlF .claude/README.md tests/acceptance` is empty; the README.md hits in c0082/audit and c0002/affected-place are fixture files), and c0115's Rules table already has c0113's AC2 row.
Critique: an executor or a later audit reading c0113 sees a ready design with no criteria and an open Overrides question. The fix is mechanical.
Consequences: none. c0113 gains no new rule.
Recommendation: in c0113.md:
- write `Overrides: none` (c0115 owns the deletion and its overrides);
- list `AC1: z-nile/README.md, which supersedes this page, covers each of its asks` and `AC2: the page this item added, .claude/README.md, is gone` under Checked, in check.sh order;
- add two Rules rows, or point at c0115's: README case "covers every ask of c0113" (mutant: a README missing the state diagram's stop edge), and AC2 (mutant: `.claude/README.md` restored, red, already run);
- write Affected specs as c0115's readme spec, Unknowns as "none", and Implementation steps as "none of its own: c0115's raft does the work, and `./zn done` closes c0113 with it".
Lesson: ticket-prep/required-steps-on-every-path

### F2 [low] `engine.COPIED_SKILLS` describes engine.copy but isn't read by it
Where: prototype `tests/lib/engine.luau:43`, `engine.copy`
Evidence: `engine.copy` copies `z-nile/` whole, and the constant is a declaration beside it. A later change that makes `copy` bring `pickman/skills` would leave the constant, and so the G7 case, silently narrower than the copy.
Recommendation: a comment in `engine.copy` that names the constant as the one to update, or have the case assert that each copied tree's `*/skills` folder is in `COPIED_SKILLS`.

Harvest check: round 7's entries map each finding to an existing lesson, and the two notes (empty-list pass, lint warnings filtered out) are lessons another raft could fail. No finding.

Verdict: changes
