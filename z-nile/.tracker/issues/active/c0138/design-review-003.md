# Review 003: c0138 (design mode)
Inputs: prep worktree `prep-trail-compaction-reset` (base c199e8de, uncommitted prep): `c0138.md`, `check.sh`, `acceptance/{renamed,kept,docs}.spec.luau`, `prototype.patch`, `design-review-00{1,2}.md`, `design-refute-00{1,2}.md`, `harvest.md`. Prototype `proto-c0138` (20eb19ac): `git diff -- z-nile/engine z-nile/skills` is byte-equal to `prototype.patch`, and its `check.sh` and the three specs are byte-equal to the prep's. `./zn capture c0138` (7769d615) and b37679dc. `z-nile/engine/{trail,ids}.luau` (main and prototype), `ids.plan`, the real compaction a38f91f9. Sibling worktrees `impl-c0118`, `prep-c0118`, `impl-c0121`. `origin/main` 0a52390b. `./zn lessons --when design --full`, `./zn lessons --skill zz-review --full`.
Dropped from design-review-002: none. Every fix is real (below), so nothing repeats as written. F1 is a new hole in the mechanism behind 002 F2, the join over several map files.

## What I verified
Every run was in a throwaway clone (`mktemp -d` under the scratchpad, origin removed, 20eb19ac checked out, `prototype.patch` applied, the prep's specs and `check.sh` copied in), each command under `bounded.pl`. Only single spec files ran. The clone is deleted. The main checkout, the prep and the prototype are unchanged.
- **The prototype passes.** `renamed` and `kept` pass 24/24 (7 + 17).
- **No base drift.** `git diff --stat 20eb19ac origin/main` over `z-nile/engine`, `z-nile/tests/lib`, `z-nile/tests/run.luau`, `z-nile/skills/zz-rules`, `z-nile/lib`, `zn`, `z-nile/projects.toml`, `tests/lib` and the c0111, c0114, c0119 and c0120 acceptance folders is empty. That holds across 123 commits.
- **Round 2's fixes are real.**
  - `broken` now sits before `compact`.
  - `both`, `dropped` and the gitlink commit exist with their cases, and the decider-first case is in `renamed.spec`.
  - All three restated sentences say "or does not parse or can't be read", and `docs.spec` pins it.
  - I ran M7, M9c and ME myself on the full `kept.spec`. Each fails exactly the case its row names: M7 fails 2, M9c fails 1, ME fails 1.
- **The systematic neighbour check the brief asked for.** I made a copy of `kept.spec` with every fail-closed commit removed: `broken`, `dropped` and the gitlink commit, plus the three cases that read them. The prototype passes the reduced copy 14/14. Every mutant that could have been dying on a neighbour still dies there, on its own case:

  | mutant | what it reads | fails | killing cases |
  |---|---|---|---|
  | M6 | the parent's map | 11 | |
  | M10b | only the current file listed | 3 | c0012, `both` |
  | M13 | every map file present | 2 | c0070 |
  | M14b | the parent's map when it parses | 4 | `compact2`, c0004, c0020 |
  | M15 | one memo slot | 2 | c0020, `compact2` |
  | MOH (mine) | the map at `origin/main` instead of at the commit | 5 | c0020, c0030 |

  I also re-derived each Rules row's kill from the case's own commit and its parent. No other row depends on a neighbour. M9 and M9b die only on the direct `renames` calls, and that is acceptable: `cuts ⊆` `diff-tree`'s listing, so "a cut commit with no map file listed" can't be reached end to end.
- **Scope.** The title and Problem are as captured, and the capture commit's Solution is empty. On the whole-map reading I reached the same verdict independently:
  - For an added or modified file, the post-image's added lines are a subset of the post-image, so every id the literal reading names is named by the whole map.
  - Any line that fails to parse also fails the whole map. Cross-line duplicates fail only the whole map.
  - Deleted files are read by neither.

  So the whole map resets a superset of what the literal reading resets, and the Problem's outcome (a kept id rewritten in place starts nothing) is delivered in full. The one extra reset is an item whose identity didn't change at a hand edit that keeps a stale pair (`again` for c0030). It is marked, it is conservative, and the Decision paragraph names it. It narrows no captured outcome.
- **Fixture realism.** `ids.plan` maps every listed id, so `compact` can write `X X`. a38f91f9's real map has 112 differing pairs and no identity pair. Both shapes are seeded: an id kept by an `X X` pair (c0010) and one kept by being absent from the map (c0070, R0010).
- **Git assumptions.**
  - `git show <sha>:<file>` doesn't apply a `diff.<driver>.textconv` from `.gitattributes`, nor `core.autocrlf` (tested).
  - `diff-tree` is plumbing: `diff.renames`, `diff.orderFile` and `diff.ignoreSubmodules=all` don't change its listing. The last one does hide a gitlink from `git log` (`cuts`), but in the gitlink commit `cuts` still lists the retired map, so the case holds.
  - `git -c submodule.recurse=true pull` of the dangling gitlink succeeds (exit 0), so the user's global git config, which the fixtures inherit, can't break the setup there.
  - The gitlink is listed as `A` only because `dropped` deleted the map first. A map that turns into a gitlink in one commit would be `T`, and `AM` skips it. On main that shape is absurd, and the fixture comment says "listed as added", which is accurate.
- **Restatements.** `git grep` (outside `.tracker` and acceptance) for "not followed", "starts its life", "new life" and "compaction map and" on origin/main finds the header, the capture row, the lesson, `main.luau:5300` (the marker text) and `trail.luau:315` (`read`'s comment, see F3).
- **Overrides: none.** The four promoted trail specs (c0111 `trail`, c0114 `trail-move`, c0119 `capture-cli`, c0120 `trail-home`) passed 29/29 with the prototype's behaviour (under MF, which equals the prototype on single-file commits). `trail.read` has one caller, `cmd.capture`. c0139's sequestered `conflicts.spec` runs `capture` only to check that it isn't refused.
- **Sibling branches.** `impl-c0118` and `impl-c0121` touch neither `trail.luau` nor `ids.luau`.
  - They edit the `board` row of `SKILL.md`. The `capture` row is only context in that hunk.
  - They append to the lesson after line 13, while this chore edits line 11.
  - Both merges are clean, as Shared state says.
- **Counts.** `kept` has setup plus 16 cases, and the fixture has 21 commits, as E1 and E6 say. `prototype.patch` has 107 changed lines, not 106 (F4).

### F1 [medium] A `renames` that drops a map file that does not parse passes every spec; "a parse failure of any one resets" is pinned only on the pure `renamed`, never where `renames` applies it
Where: Design, `trail.renames` bullet ("When a commit changes more than one map file, every one is read and the ids joined (a parse failure of any one resets)"); Rules row "every map file a commit changed is read and joined…" (MC is killed only in `renamed.spec`); `kept.spec` fixture; AC2.
Evidence: mutant MF changes one line in `trail.renames`:
```luau
if ids.parseMap(text) then
	table.insert(maps, text)
end
```
This replaces `table.insert(maps, text)`, so a map file that does not parse is skipped. Results with MF:
- `renamed` + `kept`: 24 passed, 0 failed.
- c0111 `trail`, c0114 `trail-move`, c0119 `capture-cli`, c0120 `trail-home`: 29 passed, 0 failed.

Why it survives:
- `broken` changes one file. MF skips it, `#maps == 0` returns nil, and c0011 still restarts.
- The gitlink commit fails on `show`, not on parsing.
- `renamed.spec`'s decider-first and decider-last case calls `renamed` directly, so a caller that filters before `renamed` sees the texts is never tested.

Under MF, a commit that changes both map files, one of which doesn't parse, renames only what the parseable one names. A kept-in-place item there is followed across a map nobody can read, which is the fail-open zz-arch rule 7 forbids. The Design states the opposite.
Critique: this is the third round to find a hole in the join over several map files. Round 2 found MA, MB, MC and ME, and the fix seeded "both parse", "one deleted" and "one unreadable (last)". It did not seed "one does not parse". The pure case pins the rule in `renamed`, and zz-test/pin-fail-safes-where-they-act asks for it where the decision is taken. Reach on main is nil today, because the two map files have never coexisted since 05b058ea. That is why this is medium and not high, the same reasoning as 002 F2. The tempting fix is one commit with the broken file first.
Consequences: MF's twin, "only the last file's parse failure counts" applied in `renames`, needs the broken file last as well. `diff-tree` lists `tracker/compaction.txt` before `z-nile/compaction.txt`, so that takes two commits. Both are fail-closed commits, so they must not sit right before a case that pins "this commit's data and no other's" (002 F1's lesson).

I built this in the clone's copy of `kept.spec`:
- add c0018 and c0019 to `fourteen`;
- insert two commits after `both`, before `dropped`:
  - `badold`: `[LEGACY_MAP] = "# broken old\nnot a map line\n"`, `[MAP] = "# fine\nc0141 c0014\n"`, and c0018 rewritten;
  - `badnew`: `[LEGACY_MAP] = "# old compaction\nc0700 c0070\n"`, `[MAP] = "# broken new\nnope\n"`, and c0019 rewritten;
- add one case, "restarts an item when one of two map files a commit changed does not parse, first or last": `restartedAt(capture("c0018"), "badold")` and `restartedAt(capture("c0019"), "badnew")`.

The prototype passes 18/18, and MF fails exactly the new case. `dropped`'s parent changes, but `dropped` reads only its own retired map, so its case doesn't move (verified: it passes). Two commits and two `capture` calls add about 1 s.
Recommendation:
- Add the two commits and the case above.
- Add MF to the "read and joined" row, and point the row at the new case, not only at `renamed.spec`.
- Question the mechanism: the join takes per-file outcomes {parses, does not parse, can't be read, deleted} × {first, last}. The fixture now seeds parses+parses, deleted+parses, and parses+unreadable (last). This addition covers does-not-parse first and last. Record that matrix in E5, so the next change to the join checks it against the matrix rather than adding one mutant at a time.
- If the lead would rather collapse the join (a commit that changed more than one map file counts as unreadable, so every touched item resets), that resets unnamed items in that shape. That is a narrowing of "only for an item whose id is named", so it goes to the user, not into the design.
Lesson: zz-test/pin-fail-safes-where-they-act; zz-test/seed-every-enumerated-case

### F2 [medium] Implementation step 1 will almost surely fire, and its fallback "re-run … the mutants" names a runner the executor doesn't have
Where: Implementation steps, step 1 ("must be empty … (else merge and re-run `kept.spec`, the promoted trail specs and the mutants)"); Rules and mutants preamble ("`mutants.py` in the prep scratch folder"); E5.
Evidence:
- The runner is not in the issue folder. `find` over the prep and the prototype finds no c0138 `mutants.py`. It lives in a session scratchpad (`…/scratchpad/c0138/mutants.py`). Other preps commit theirs as `experiments/mutants.py`, for example c0155, c0164 and R0044.
- Step 1 diffs `z-nile/engine` and `z-nile/skills/zz-rules` against 20eb19ac. `impl-c0118` and `impl-c0121`, both in flight, already change `z-nile/skills/zz-rules/SKILL.md` and the lesson (Shared state names them).
- `z-nile/engine` includes `main.luau`, which most tooling issues edit.

So once either sibling lands, step 1 is not empty. It then tells the executor to re-run 24 mutants it can't run, for drift (docs rows) that changes no mutant's outcome. `git apply prototype.patch` also fails on the `SKILL.md` context once c0118's `board` row lands. Only `git apply -3` or a hand edit works, and the steps don't say which.
Critique: z-design/instructions-runnable-where-they-run. An executor must either ask or skip a required step. The tempting fix is to commit the script. That alone still sends a docs-only drift through a full mutation run.
Consequences: a committed runner edits the engine files in the executor's worktree. It must restore them from a saved copy, as the prep's does, and must never touch git. It must name its 24 mutants as exact edits, so a merged base whose text moved fails loudly rather than skipping a mutant. That is the same failure as my own runner's "NOT APPLIED" guard.
Recommendation:
- Commit the runner as `experiments/mutants.py` in the issue folder, with every mutant as an exact edit, refusing when an edit doesn't apply.
- Split step 1's trigger:
  - drift in `trail.luau`, `ids.luau`, `main.luau`'s `cmd.capture`, `tests/lib` or the trail specs: re-run `kept.spec`, the promoted trail specs and `experiments/mutants.py`;
  - drift only in `zz-rules` (the expected c0118 and c0121 rows and lesson paragraphs): merge with `git apply -3` (or by hand, from The new sentences), then run `docs.spec` and `./zn lessons --check`.
Lesson: z-design/instructions-runnable-where-they-run

### F3 [low] `read`'s doc comment is a fifth restatement of the rule, unpinned, and its new wording drops "does not parse or can't be read"
Where: `prototype.patch`, the `trail.read` comment ("…or at a later commit that changed a compaction map and its document and renamed its id (`since`; `renames`, `resets`)"); Design, Restated rules ("four places").
Evidence: `git grep -n "compaction map and its document" origin/main -- z-nile/engine` hits both `trail.luau:8` (the header) and `trail.luau:315` (`read`'s comment). The Design counts only the header. The new `read` wording says "renamed its id" only. It leaves out the fail-closed reset that 002 F3 added to the other three. `docs.spec` doesn't read it.
Critique: z-design/restated-rules-move-together. A reader of `read`'s comment sees a narrower rule than the code. The tempting fix is to add the words without pinning them.
Consequences: `docs.spec`'s header case already reads `trail.luau` flattened, so one more `has(...)` pins it.
Recommendation: write `read`'s comment as "…and renamed its id, or whose map does not parse or can't be read (`since`; `renames`, `resets`)". Count it in Restated rules, and pin the added words in `docs.spec`'s trail case.
Lesson: z-design/restated-rules-move-together

### F4 [low] Round 2's fail-closed-neighbour finding is harvested to a lesson whose check doesn't catch it, and the patch count disagrees with itself
Where: `harvest.md` ("design-review-002 F1: z-design/spec-design-correspondence"); the Prototype paragraph ("106 changed lines"); `design-refute-002.md` F3 ("107 changed lines").
Evidence:
- spec-design-correspondence's `check` asks whether a case's mutant is "killed by that case itself, not first by an older, stricter case". 002 F1's killer was a fail-closed neighbour commit in a shared linear fixture, not an older case.
- z-design step 5.3 says a finding that repeats a lesson "sharpens that lesson's `check`". No lesson file changed in the prep (`git status`), and round 2's candidate went nowhere. This round's brief had to ask for the neighbour check by hand.
- `grep -c '^[+-]' prototype.patch` gives 115, less 8 file headers, which is 107.
Critique: the next prep with a linear fixture and a "broken" commit will repeat 002 F1, because no check asks about it.
Consequences: none beyond the lesson edit.
Recommendation:
- Sharpen spec-design-correspondence's `check`: "…not first by an older, stricter case or by a fail-closed neighbour in a shared fixture (remove the fail-closed commits or cases: does each row's mutant still die?)". Add a note citing c0138 design review 002 F1.
- Fix the count to 107.

## Lesson candidates (for the lead)
- **Pin a join's fail-safe at the caller, per source position** (a note on zz-test/pin-fail-safes-where-they-act): when a rule joins several sources and "any one fails, all fail", a caller that filters the failing source out before the join, then treats "nothing left" as failed, passes every single-source case and every pure case. Check: is there an end-to-end case with one failing source beside a good one, with the failing one first and with it last?
- **Fallbacks in Implementation steps must be runnable from the repo** (a note on z-design/instructions-runnable-where-they-run): "re-run the mutants" points at a session scratchpad. Check: does every script a step names live in the issue folder, and does the step's trigger fire only on drift that could change that script's outcome?

Verdict: changes
