# Review 004: c0183 (design mode)
Inputs: prep worktree `prep-register-arcade-projects` at bd2f1ff7 plus its uncommitted c0183 folder (c0183.md sha256 7c69938cbf18…, check.sh b46a119d37cf…, acceptance/*.spec.luau, experiments/*, design-review-001..003, design-refute-001..003, harvest.md) and the four new prep lessons (zz-test history-tolerant-checks-need-a-done-check, pin-expected-text-not-documents, sentences-in-checks-are-grep-patterns; z-ticket capture-subject-lists-every-id); prototype `proto/repo` at 19636459 (429eb774 prep, 19636459 implementation), whose check.sh, four specs, E4-digests.py and E2-rehash.py are byte-identical to the worktree's (E2-proto.py differs only by round 3's F3 sentences, which the implementation commit already carries); origin/main f9088d4d (since the prototype's base 8ed94993 only `c0183/spend.md` changed); c0141's prototype `origin/proto-check-paths-home`.
Capture: judged against `git show cda05ea6:…/c0183.md`. Everything before `## Design` is byte-identical except the frontmatter (`design`, `size`, `solo`, `status`).
Evidence runs: clones under `scratchpad/review4/` (`head`: clone of `proto/repo`; `done`: the same with c0183 moved to `issues/done/` and its specs moved to `z-nile/tests/acceptance/c0183`), identity review@localhost, origin the prototype only.
Dropped from design-review-003: F1 (fixed, re-run below), F2 (refutation accepted: `tests/lib` is the shared-helper convention, gate-cover already leans on unpinned `cachepaths`, and the edits that matter, a missing root or a lost counter, still fail gate-cover's every-root case and pickman's c0015 shape check, both pinned by `narrowed`), F3 (fixed, re-run below).

### F1 [low] E6 still says check.sh spells `pickman/.tracker` "through `$T`", which round 3 removed
Where: c0183.md, Unknowns & experiments, E6, fourth bullet (line 421): "check-paths at first read `pickman/.tracker` inside AC6's new sentence as a path from z-nile/. check.sh now spells it through `$T`."
Evidence: `grep -n '\$T' check.sh` finds nothing; Design item 7 and E7 say the sentences are inline grep patterns. The E6 sentence is in the present tense ("now spells").
Critique: an executor or a later reviewer reading E6 is told the opposite of check.sh and of the lesson this prep wrote (sentences-in-checks-are-grep-patterns), which names `$T` as the mistake.
Consequences: none beyond the text.
Recommendation: make it past tense and point forward: "…check.sh then spelled it through `$T`; round 3 replaced that with inline grep patterns (E7, Design item 7)."
Lesson: z-design/restated-rules-move-together

### F2 [low] zz-rules' opening paragraph still describes the registry, the roots and the homes as pickman's and z-nile's only
Where: Design item 6 ("The skills restate the projects as pickman and z-nile in three sentences"); `z-nile/skills/zz-rules/SKILL.md:8`.
Evidence: on the prototype, `git grep -nE "pickman's is|for pickman .* for z-nile|pickman/. gives pickman|pickman/\.tracker/., .z-nile/\.tracker/|z-nile's .*, pickman's" -- 'z-nile/skills/*/SKILL.md' z-nile/README.md AGENTS.md 'pickman/skills/*/SKILL.md'` hits:
- `zz-rules/SKILL.md:8`: "`z-nile/projects.toml` lists the projects, each with the root that holds its issues and rafts: pickman's is `pickman/.tracker/` and z-nile's, the tooling's, is `z-nile/.tracker/`. … Each project also has a home …: `pickman/` for pickman (…) and `z-nile/` for z-nile (…). … The folder you run `./zn` in also gives the project (`pickman/` gives pickman, `z-nile/` z-nile; …)". Unchanged by the prototype. After c0183 it reads as the whole registry.
- `zz-rules/SKILL.md:19` (compaction's `pickman/.tracker/`, `z-nile/.tracker/`): examples only; `compact.luau:100-104` guards every registry root, so the text is not wrong. Excluded.
- `zz-test/SKILL.md:21` (where each project's specs live): the new homes have no `tests/` until c0184, which owns that sentence. Excluded.
The design's "three sentences" was not a pasted search, and line 8, the paragraph that defines projects, is the one a reader meets first.
Critique: the operative rules (Projects, Paths) are fixed, so no command goes wrong; but the definition paragraph contradicts the registry the day this lands. The tempting fix is rewriting the pinned clause, which `c0120/docs.spec.luau:56` pins ("pickman's is `pickman/.tracker/` and z-nile's, the tooling's, is `z-nile/.tracker/`"), and that spec is already one of `narrowed`'s digest rows.
Consequences: appending after the pinned clause keeps c0120 docs.spec and `narrowed`'s digest untouched (no new override). An enumerated list of the five would be another place a sixth project must edit; the rule form avoids that.
Recommendation: in Design item 6 add a fourth skill edit, appended right after the pinned clause on zz-rules:8: "; every other project's is `<name>/.tracker/`, with its home `<name>/` (c0183: `arcade`, `portal`, `snake`, `invaders`, `asteroids`)", and the same in the run-folder sentence ("`snake/` gives snake, and so on"). Pin it in check.sh's `ac6` as one more inline `grep -qF` pattern (starting with a word character), add it to E2-proto.py, and replace "three sentences" with the pasted search above.
Lesson: zz-review/lists-paste-their-search

## Round-3 answers (checked)
- F1 (check.sh read as paths): holds. In clone `head`: `./zn check c0183` 6/6 PASS; c0120 `check-paths.spec` 4/4; with c0141's `checkpaths.luau` and `check-paths.spec.luau` from `origin/proto-check-paths-home` copied in, 4/4. In clone `done`: c0120 `finished.spec` and c0114 `finished.spec` 11/11, and `./zn check c0183` from `done/` 6/6 (once the empty `acceptance/` folder my `git mv` left behind was removed; `./zn done` doesn't leave that folder). `ac6` runs as a shell function inside `check`'s `$(…)` subshell, which inherits it. The mutant that drops `--project portal`/`--project arcade` from zz-rules' Projects sentence fails AC6 only (5/6). No pattern starts with `(`. AC1 and AC3's remaining `cd "$ZN_ROOT" &&` are followed by `"$PWD/z-nile/roots"` and `shasum`, so the scanners find no literal there.
- F3 (portal and library unnamed): holds. Both sentences name the portal and the arcade library; c0114 docs.spec's override pins the new start. R0061's z-ticket edit only appends after "(zz-rules skill, Projects)." (`git diff $(git merge-base origin/R0061-z-nile-header-slug-scans origin/main) origin/R0061-z-nile-header-slug-scans -- z-nile/skills/z-ticket/SKILL.md`), so AC6's substring survives either merge order.

## Checked and clean
- Scope: Problem, Non-goals and Solution are unchanged from cda05ea6.
- Prototype gate: `proto/gate.log` (18:10, after the 18:02 implementation commit, with this check.sh) ends `GATE PASSED (full)`.
- In-flight branches: across every origin branch, only R0061, impl-c0117/c0118/c0121, proto-c0144 and proto-merge-past-tracker-only touch AGENTS.md, README, z-ticket or zz-rules, and none of their diffs touches a sentence c0183 edits (`git diff -U0 <base> <b> | grep -E "game work|The game is the|A game is a project|project root, .pickman|direct-push|registry entry only|There, game"`: no hits). No branch touches projects.toml, deploy.yml or the overridden specs.
- Lessons: with the worktree's c0183 folder and the four new lessons copied into `head`, `./zn lessons --check` prints "144 lessons, 889 harvest entries, ok". The four lessons are general rules another raft could break, not restated findings. capture-subject-lists-every-id matches `trail.namedIds` (a range ends the leading id run).
- Repository safety: check.sh's real-repository commands are still read-only (`roots`, `list`, `audit`, `--plan`, `shasum -c`, `grep`). Round 3 added none.

## Candidate lessons (for the lead)
- Tooling, not a lesson: `trail.namedIds` silently ignores a range in a `tracker: new` subject. Capturing "`./zn land` refuses a `tracker: new` subject whose id list ends in a range" would make capture-subject-lists-every-id something the tool enforces rather than something people have to remember.

Verdict: approve
