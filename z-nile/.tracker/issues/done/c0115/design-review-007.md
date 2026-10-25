# Review 007: c0115 (design mode)
Inputs: prep-c0115 at 24d4014 (the delta `git diff 7f6068e..HEAD`: the user's decisions on G1 to G11), with rounds 001 to 006 and their refutes for context; the prototype proto-c0115 at 713339d (`./zn check c0113` 2/2, `lune run z-nile/roots` from the root and from `z-nile/`); `./zn capture c0113`, `./zn capture c0115`; `./zn lessons --when design --full`.

Scope of this round: the delta only. G2's rename map, the prompt, the README, AGENTS.md and the overrides agree (`launch-raft` → `z-run`, `execute-raft` → `zz-execute`, `skills.RENAMED`/`RENAMED_PATH`, `INLINED`, the template's hard rule 1, 13 links). G4's pass 3 cuts issue documents at `\n## Design\n` and rafts after their frontmatter: on the prototype every changed hunk of c0075.md and c0083.md lies after the Design heading, and the touched files are exactly the ones §8 lists. c0113's captured title, Problem, Non-goals and Solution are unchanged apart from one `Decided with the user` line. G11's empty-range branch is correct.

### F1 [medium] AC14 passes when it finds nothing to scan
Where: c0115 `check.sh`, `backlog_clean` and `rename_finished`; §11 (l)
Evidence: `backlog_clean` takes its roots from `for r in $(lune run z-nile/roots); do find "$r/issues" …; done` inside a process substitution, so a failing `lune run` gives an empty loop, `bad` stays empty, and the check passes. `ac.sh` cds to the item's project home. On the prototype, `lune run z-nile/roots` run from `z-nile/` fails with "Failed to resolve script at path …/z-nile/z-nile/roots (NotFound)", exit 1. §11 (m) says z-nile's home becomes `z-nile/` at the rebase. From then on AC14's independent half scans nothing and passes. Every `find` path is relative too, and so are the rename script's own `roots()`, so its `--check` can also report 0 and pass. §11 (l) lists AC10's command and the fallback path for the rebase, but not AC14.
Critique: AC14 is the only check of the user's G4. It can pass because it found nothing, not because the backlog is clean. The obvious fix is to add AC14 to (l). That only moves the trap to the next home or registry change.
Consequences: a fail-closed scan needs a floor. "At least one item directory" holds today (c0113 is unfinished), but it will not always hold.
Recommendation: make `backlog_clean` fail closed:
- run `lune run "$ZN_ROOT/z-nile/roots"` and anchor every root at `$ZN_ROOT`;
- `return 1` when the roots command fails or prints nothing;
- count the documents it read and print the count;
- anchor the script's `roots()` at the repository root the same way.

Add AC14 to §11 (l), and a Rules row: the mutant "roots command fails" (for example `lune run z-nile/nosuch`) must turn AC14 red.
Lesson: testing/no-vacuous-pass, testing/guards-move-with-the-working-directory

### F2 [medium] c0113's AC2 becomes vacuous when z-nile's home moves, and its paths are not on the recheck list
Where: `z-nile/.tracker/issues/c0113/check.sh` AC1 fallback and AC2; c0115 §11 (l), (m)
Evidence: AC2 is `bash -c '! git ls-files --error-unmatch .claude/README.md …'`, run after `ac.sh` cds to c0113's project home (z-nile's, today the root). git pathspecs are relative to the cwd. Once c0120's decided rework makes z-nile's home `z-nile/`, AC2 asks for `z-nile/.claude/README.md`, which never exists, so it passes even if c0115 left `.claude/README.md` in place. The same goes for AC1's fallback `"$PWD/tests/acceptance/c0115"`. §11 (l) and (m) name these places for c0115's own `check.sh` only. c0113's `check.sh`, written in this delta with the same assumption, is not named.
Critique: c0113 is closed by `./zn done` on the strength of these two checks, so a vacuous AC2 closes it on a false claim.
Consequences: none beyond the recheck list.
Recommendation:
- Anchor AC2 at the repository root: `git -C "$ZN_ROOT" ls-files --error-unmatch -- .claude/README.md`, or the `:/.claude/README.md` pathspec.
- Derive AC1's fallback from c0115's promoted location, not `$PWD`.
- Add c0113's `check.sh` to §11 (l).
- Rerun `./zn check c0113` with `.claude/README.md` restored, and require AC2 to be red.
Lesson: testing/guards-move-with-the-working-directory, testing/no-vacuous-pass

### F3 [medium] G9's path is blocked: `./zn ready` refuses a raft holding c0113, which is still `design: draft`
Where: `z-nile/.tracker/issues/c0113/c0113.md` frontmatter (`design: draft`); c0115 G9; the tracker skill (`./zn ready` "checks the raft and every member are `design: ready`", main.luau:2002, 2913, 3071)
Evidence: G9 says "c0113 joins c0115's raft when that raft is formed and `./zn done` closes it". c0115 is `design: ready`, but c0113 is still `design: draft`, and only ticket-prep (z-design) may move it. Nothing in c0115 or c0113 says who reviews c0113's new Design and check.sh, or who moves its `design:` field. No step adds c0113 to the raft either: c0115's `raft:` is empty, and no Implementation or Readiness step names c0113, so nothing notices if the raft is formed without it. The path itself is sound: the tracker has no retire command (`./zn` usage), and a member closed by `done` is the only way. It also respects the capture (`./zn capture c0113` differs only by the added decision line and the filled Design).
Critique: either `ready` refuses, and the executor (or the z-raft operator) stops to ask, or the raft is formed without c0113 and c0113 is never closed.
Consequences: setting `design: ready` on c0113 needs a review record. This round reviewed c0113's Design and check.sh as part of G9, so the record can be this round, said explicitly. c0113's `depends_on` stays empty, since it rides in c0115's raft.
Recommendation:
- In this prep's commit, move c0113 to `design: ready`, recording that design review 007 covered its Design and check.sh (F2 fixed first).
- Add a step to c0115's §9 Readiness: "the raft holds c0115 and c0113", checked when the raft is formed.
- Have `./zn ready` (or c0115's AC11/audit note) catch a raft that omits c0113. At minimum, add a line to the raft-forming step that names it.
Lesson: ticket-prep/required-steps-on-every-path, ticket-prep/new-rules-migrate-existing-work

### F4 [medium] The G7 case scans `pickman/skills` lessons that `engine.copy` never copies, so the first game lesson turns it red
Where: `acceptance/prompt.spec.luau`, "the fixture's copied tooling carries every skill's lessons"; `tests/lib/engine.luau` `engine.copy`
Evidence: `engine.copy` copies `zn`, `scripts/` and `z-nile/` (minus its state), and never `pickman/skills`. The case walks the real `z-nile/skills/*/lessons` and `pickman/skills/*/lessons`, and errors on any file missing from `f.main`. Today `pickman/skills/*/` has no `lessons/` folder (all architecture lessons went to zz-arch, G3), so the case passes. G3 itself says "A game lesson written later goes in `pickman/skills/pickman-arch/lessons/`". The first such lesson makes the promoted c0115/prompt spec fail with "the fixture lacks pickman/skills/pickman-arch/lessons/…", in a commit that changes only a Markdown file under `pickman/`.
Critique: a promoted spec that pins today's set rather than the rule. The rule the user decided is that the copied skills carry their lessons, and only z-nile's skills are copied. `engine.clearLessons` also walks `pickman/skills`, which is harmless but suggests a copy that doesn't happen.
Consequences: making `engine.copy` also copy `pickman/skills` would change what every pickman-raft fixture inlines (the prompt spec's seeded `pickman-play` is meant to be the only pickman skill). That widens the user's "Copy lessons too" (stated for `z-nile/skills`), so it isn't the fix.
Recommendation:
- Scope the case to the folders `engine.copy` copies (`z-nile/skills`), named from one constant in `engine.luau` that both use.
- Keep `count > 0`.
- Add a Rules row. Its mutant is a pickman lesson planted in a scratch copy, and the case must stay green.
Lesson: testing/promoted-specs-pin-rules-not-sets

### F5 [low] Programme-review F5's answer still states the guess G4 replaced
Where: c0115.md, "Programme review … F5"
Evidence: "their re-prep follows c0115 (G4); c0120's check-paths spec keeps exempting their current files by content". The user's G4 is now "Rewrite in c0115", and §8 overrides c0120/check-paths' c0083 entry.
Recommendation: restate F5's answer as G4's decision, and point it at §8 and AC14.
Lesson: ticket-prep/restated-rules-move-together

### F6 [low] Pass 3 leaves half-renamed sentences in backlog designs, and step 5b doesn't say to reword them
Where: Implementation step 5b; the prototype's c0083.md and c0083/check.sh AC8
Evidence: the name rule rightly skips the bare words `review` and `tracker`. That leaves "no step in the zz-execute, review, tracker or z-design skills" in c0083's AC8 and its design. Step 5 asks for a line-by-line reading and rewording of lesson bodies, but step 5b only says "read its list and diff".
Recommendation: step 5b reads the pass 3 diff line by line, like step 5, and rewords a half-renamed sentence by hand in documents only (never in a sequestered file beyond the user's exception). It lists those in the PR description.
Lesson: ticket-prep/bulk-renames-skip-ordinary-words

### F7 [low] AC14's independent half misses the slash-command form and a variable-built path
Where: `backlog_clean` regex
Evidence: `(^|[^a-z0-9_./-])$old` excludes a preceding `/`, so `/launch-raft R0010` in a design is not flagged. A sequestered spec that reads `` `{SKILLS}/ticket-prep/SKILL.md` `` is flagged by neither half when it has no bare name elsewhere. On today's tree c0120/acceptance/docs.spec.luau line 108 has that form (it also trips the bare-name rule via its case title, and it is done before c0115 runs). The script's own forms cover the slash form. Separately, the script rewrites a sequestered file only when it names a literal `.claude/skills/<old>`, while `backlog_clean` fails on any bare hyphenated name in one. A sequestered file with only a bare name would leave AC14 red with no fix inside the user's exception.
Recommendation:
- Let `backlog_clean` also match `/<old>` at a word start (`(^|[^a-z0-9_.-])/$old\b`).
- State in §8 what the executor does when AC14 flags a sequestered file that the script's path gate skipped: escalate under the user's G4 exception, never hand-edit.

### F8 [low] JC2's rubric checks the README against z-run but not zz-execute
Where: JC2
Evidence: the README now describes the protocol as zz-execute's (its "## Skills" row and flow step 4), but the rubric checks each sentence "against zz-rules, zz-test and z-run".
Recommendation: add zz-execute to JC2's list.
Lesson: ticket-prep/restated-rules-move-together

Harvest check: round 6's entries are a real lesson note (seed every position and spacing of a list a rule walks), not a restated finding. No finding.

Verdict: changes
