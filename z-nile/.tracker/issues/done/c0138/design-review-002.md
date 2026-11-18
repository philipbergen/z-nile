# Review 002: c0138 (design mode)
Inputs: prep worktree `prep-trail-compaction-reset` (base c199e8de, uncommitted prep): `c0138.md`, `check.sh`, `acceptance/{renamed,kept,docs}.spec.luau`, `prototype.patch`, `design-review-001.md`, `design-refute-001.md`, `harvest.md`. Prototype tree `proto-c0138` (base 20eb19ac): its engine and skill diff equals `prototype.patch` and its specs and `check.sh` equal the prep's (`diff`/`cmp`, all equal). `./zn capture c0138` (7769d615). `z-nile/engine/{trail,ids,compact,main}.luau`. Promoted `c0111/trail`, `c0114/trail-move`, `c0119/capture-cli`. Sibling prep `prep-c0118` (a99c5881, `prototype.patch`, acceptance specs). `origin/main` b962ea0f. `./zn lessons --when design --full` and `--skill zz-review`.
Dropped from design-review-001: none. Every fix is real (below), so no finding repeats as written. F1 here is a new hole in the mechanism behind 001 F1's fix.

## What I verified
All runs were in a throwaway clone (`mktemp -d` under the scratchpad, origin removed, checked out at 20eb19ac, `prototype.patch` applied, the prep's specs and `check.sh` copied in). Every command ran under `bounded.pl`. The clone is deleted after this review.
- **The prototype runs.** `renamed`, `kept` and `docs` pass 24/24 (7 + 14 + 3). In the clone, `./zn check c0138` passes AC1, AC2 and AC3. AC4's three promoted specs passed 24/24 but the run was flagged `sweeper: processes keep appearing; this run is not clean`. A second run of the same three specs was clean (24/24, no sweeper line), so I read the flag as environmental, not as c0138's.
- **No base drift.** `git diff --stat 20eb19ac origin/main` over `z-nile/engine`, `z-nile/tests/lib`, `z-nile/tests/run.luau`, `z-nile/skills/zz-rules`, `tests/lib`, `z-nile/lib`, `zn`, `z-nile/projects.toml` and the c0111, c0114, c0119 and c0120 acceptance folders is empty.
- **Round 1's fixes.**
  - F1: the `compact2` commit and case exist. I spot-ran M14 (the parent's map joined): it fails 4 cases. But see F1 below on why it dies. MD, the memo keyed by the map file instead of the sha (my own variant of M15), fails 2.
  - F2: the c0013 case exists. M16 (the note marks only a renamed start) fails exactly that case. The three restated sentences say "or is where the item first appears", and `docs.spec` pins it.
  - F3: E4 and Existing work now name the moved-and-changed-map exception.
  - F4: `ls-tree` survives only as mutant M13's name.
  - F5: the provenance sentence matches `./zn capture` (the capture's Solution is empty; the bullets came in b37679dc).
- **Scope.** The title and Problem are as captured. The capture commit has no Solution. Reading "the map lines the compaction commit adds" as the whole map resets a superset of what a `+`-lines reading resets: every added pair is in the whole map, and an unparseable line anywhere fails closed. `compact` writes the whole map each time (`main.luau:2958`, `formatMap(map, …)` over `ids.plan`, which maps every listed id, so a kept id appears as `X X`). Under that reading the Problem's outcome (a kept id rewritten in place starts no life) holds. No captured outcome is narrowed; I agree with 001 F5.
- **The note rule is exhaustive.** A start comes either from `life`, a first add (absent to present), or from `since`, a cut commit plus the document plus `resets`. So "renamed the id (or does not parse) or is where the item first appears" covers every marked start.
- **Overrides: none holds for the old wording.** `git grep -nF -e "compaction map and its document" -e "together with the item's document" origin/main -- ':!*.tracker/issues/done/*' ':!*.tracker/rafts/done/*'` finds only:
  - `trail.luau:315`, `SKILL.md:79` and the lesson (all three edited by this chore);
  - context lines in `active/c0117/prototype.patch` and `c0189/experiments/prototype.patch`.

  No spec pins the old wording. `git grep -n -e "compaction map" -e "item-history-spans" -e "| capture |" -e "trail\." origin/main -- '*/.tracker/issues/*/acceptance/*' '*/.tracker/issues/active/*/acceptance/*'` (excluding c0138) prints nothing. c0118's acceptance specs pin nothing from the lesson or the capture row (grep: no hits).
- **Merging with c0118.** c0118's prototype edits the zz-rules `board` row, two rows above `capture`. A synthetic three-way `git merge-file` of a `board`-row edit against this chore's `capture`-row edit gives 0 conflicts.
- **Fail-closed reads.**
  - `git diff-tree` on a zero sha exits 128.
  - On the empty tree it lists nothing. Both give nil.
  - Merge commits never reach `renames`: `git log --name-only` prints no files for a merge, so `cuts` never records one.
- **`compact` and the map.** `ids.plan` maps every listed id, and `parseMap` rejects a repeated new id. So a kept id can't also be the new side of another pair. The rule "an id changes meaning only if it stands on some side of a pair" is sound.
- **Spec labels.** AC1 to AC4 in `check.sh` equal the document's text (less the final period).
- **Size.** 110 matches the patch's 106 changed lines.

### F1 [high] The case that pins "a later compaction keeps an id an earlier one renamed" kills the cumulative-map mutant only because `compact2`'s parent is the `broken` commit; reading the parent's map when it parses passes every spec
Where: `kept.spec.luau` fixture order (`again`, `broken`, `compact2`); Rules row "a commit's answer comes from the map it leaves alone…" (M14); AC2 ("a later compaction whose map keeps an id an earlier one renamed does not restart it again"); the Design's consequence (1).
Evidence: `compact2`'s parent is `broken`, whose map is `# broken\nnot a map line\n`. M14 joins the parent's map, so it reads an unparseable text, `renamed` returns nil, and every item `compact2` touches resets. That is the only reason M14 dies. I ran M14′ on the prototype: the parent's map is joined only when it parses (in `trail.renames`, after `table.insert(maps, text)`: `local prev = git({ "show", `{sha}^:{file}` }); if prev and ids.parseMap(prev) then table.insert(maps, prev) end`). The result was `renamed` + `kept`: **21 passed, 0 failed**. Under M14′ the next real compaction (its parent holds a38f91f9's map, which parses and renames nearly every id) restarts every id the 2026-10-05 compaction renamed, though the new whole map keeps them. That is the outcome the Problem asks to stop, and AC2's sentence passes it.
Critique: this is the same hole design review 001 F1 found: no case shows that an earlier map is not mixed in. The fix's case is right in intent, but its kill rests on an incidental neighbour in a shared linear fixture, a fail-closed commit that resets everything. The tempting fix is to add M14′ to the table and call it killed.
Consequences: the case has to have a parent whose map parses and names the ids the case keeps.
- Moving `broken` before `again` does that. `compact2`'s parent becomes `again` (it parses and names c0020 and c0004), and `again`'s parent becomes `broken`, which M14′ skips. `again`'s own map already repeats the first compaction's pairs, so the c0030 and c0090 answers don't move.
- I made that reorder in the clone's copy of `kept.spec`. The prototype passes 14/14, and M14′ now fails 4 cases (the `renames` listing, c0004's arrival, c0020's reuse, the `compact2` case).
- The same reorder also kills a "whole history of the map file, every version that parses" reading.
Recommendation: reorder the fixture so that `compact2`'s parent leaves a parseable map that renames c0020 and c0004 (for example `broken` before `again`; verified above). Restate M14's row mutant as "an earlier version of the map (the parent's, or any in the file's history) joined when it parses", and record M14′ as run. Then question the mechanism, not just this hole. For every case that pins "this commit's data and no other's", check that its mutant still dies once the fail-closed neighbours are taken away: delete or reorder the `broken` commit in a scratch copy and rerun the "earlier data mixed in" mutants. Record that check in E5.
Lesson: z-design/spec-design-correspondence (its check: "Is each new case's recorded mutant killed by that case itself, not first by an older, stricter case"; here the killer is a stricter neighbouring commit, not an older case)

### F2 [medium] No commit changes both map files, so "the map file or files the commit changed" and "nil when any does not parse" are unpinned at the git level; three plausible mutants pass, and M9c's reason is not true
Where: Design, `trail.renames` and `trail.renamed` bullets; AC2 ("from the map files that commit changed"); Rules rows M9c (reasoned), M10 and M10b; `kept.spec` fixture; `renamed.spec` "joins the maps of several files…".
Evidence: three mutants, each run on the prototype, give `renamed` + `kept` 21 passed, 0 failed:
- MA reads only the first file listed (a `break` after the first `table.insert(maps, text)`). This is the natural "read the file `cuts` already reported" simplification.
- MB reads only the last file listed (`maps = { text }`).
- MC lets the last map decide parse failure (`bad = map == nil` per text, then `if bad then return nil end`). The pure case puts the broken map last only (`{ "c0300 c0030\n", "nope\n" }`).

ME (no `--diff-filter`) also passes. It reads a deleted map file, so `show` fails and every touched item resets; it errs on the fail-closed side.

M9c's row says it "needs two map files at one commit, one of them unreadable", and E5 adds "which no fixture builds". It can be built. In a scratch repository a commit with a readable `tracker/compaction.txt` and a gitlink at `z-nile/compaction.txt` (`git update-index --add --cacheinfo 160000,<missing sha>,z-nile/compaction.txt`) is listed by both `git diff-tree --root -r --no-renames --diff-filter=AM --name-only` and `trail.cuts`'s `git log`, and `git show <sha>:z-nile/compaction.txt` exits 128 (`fatal: bad object`).

Reach on the real tree: `tracker/compaction.txt` was moved away in 05b058ea (`R100 tracker/compaction.txt z-nile/compaction.txt`), so the two files don't coexist on main. That is why this is medium and not high. The Design still says "the retired `tracker/compaction.txt` that stays in a tree beside the current map", which is true of the fixture, not of main.
Critique: the Design walks `ids.MAP_FILES` and joins the results, and states that rule. The fixture seeds each file only alone, so dropping either half of the join passes (zz-test/seed-every-enumerated-case). The tempting fix is to drop "or files" from the Design. That is also a design change: reading `cuts[sha]`'s single file fails open for a commit that changes both maps.
Consequences: a `both` commit changes the fixture's HEAD map. Placed after `compact2`, its current map is `# both\nc0140 c0014\n`. No case reads HEAD's map: `capture` doesn't call `refuseStale`. The fixture grows by three commits, about 1 s. I built it in the clone's copy of `kept.spec`:
- `fourteen` and `fifteen` add c0014 and c0015;
- `both` writes `[LEGACY_MAP] = "# old compaction\nc0700 c0070\nc0150 c0015\n"` and `[MAP] = "# both\nc0140 c0014\n"` and rewrites both documents in place;
- the case "reads every map file one commit changed" expects both captures to start at `both`.

The prototype passes 15/15 (with F1's reorder), and MA and MB each fail the new case. Killing ME needs one more shape: a commit that deletes one map file, changes the other, and rewrites a kept item in place, which must not restart. Building M9c with a gitlink is optional. If it isn't built, the row's reason must say "buildable with a gitlink map entry; not built because …".
Recommendation:
- Add the `both` commits and case (above) and Rules rows for MA and MB.
- Add `t.expect(trail.renamed({ "nope\n", "c0300 c0030\n" })).toBe(nil)` to `renamed.spec` and a row for MC: the decider first and last.
- Add a row for ME with its case (a deleted map beside a changed one starts nothing for a kept item), or say why the Design accepts it.
- Correct M9c's reason and the "stays in a tree" sentence.
- Make E4's "the file it reads is the one `cuts` reported" say "for a commit that changed one map file".
Lesson: zz-test/seed-every-enumerated-case; z-design/reasoned-rows-claim-testable-reasons; zz-test/any-rule-places-the-decider-first-and-last

### F3 [low] The three restated sentences omit the git-failure reset that the Design's rule states
Where: Design, The rule, bullet 2 ("or git can't list or read it: then every item the commit touches restarts"); The new sentences (capture row, lesson, trail header): "(the map, as that commit leaves it, names the id on either side of a pair whose sides differ, or does not parse)".
Evidence: `trail.renames` returns nil on a failed `diff-tree` or `show`, and `resets(nil, …)` is true (`renamed.spec` zero-sha case). None of the three sentences says so. Read alone, they describe a reader for which an unreadable commit renames nothing.
Critique: z-design/restated-rules-move-together. The skill row is what a later author reads. The tempting fix is three more words in one place only.
Consequences: `docs.spec`'s `RENAMED` phrase is shared by the row and the lesson, and the header has its own pin. All three pins change with the words.
Recommendation: make all three say "…, or does not parse or can't be read)" (or similar), and pin the added words in `docs.spec`.

### F4 [low] Stale counts, an over-long header line, an incomplete drift check in step 1, and a Shared state list that names one of four SKILL.md editors
Where: E1 ("`kept` 15/15 (the setup and fourteen cases)", "25/25"); `design-refute-001.md` F1 ("15/15"); Scalability and E6 ("thirteen `capture` calls"); `prototype.patch` header line 10; Implementation steps, step 1; Checklist, Shared state.
Evidence:
- `kept.spec` has 14 `it` blocks (setup plus 13) and 12 `capture(` calls. The run prints `14 passed`, and all three specs give 24, not 25.
- The prototype's `trail.luau` line 10 is 158 columns (`awk 'length > 120'`). `stylua.toml` has `column_width = 110`, and the base file has no line over 120.
- Step 1's `git diff` lists `trail.luau`, `zz-rules`, c0119 and c0114. It leaves out `z-nile/engine/ids.luau` (Touched), c0111 and c0120's specs, `z-nile/tests/lib` (which `kept.spec` loads) and `main.luau` (`cmd.capture`). The Prototype paragraph claims all of those were checked.
- Shared state names only c0118's lesson edit. These also edit SKILL.md rows within three lines of `capture`:
  - c0118 (the `board` row);
  - c0117, active (the `workstreams` and `raft-plan` rows: `git show origin/main:z-nile/.tracker/issues/active/c0117/prototype.patch`, hunk `@@ -73,13 +75,13 @@`);
  - c0189, prepared (a `hooks` row after `skills`, with `capture` as context: hunk `@@ -79,6 +79,7 @@`).

  A three-way merge is clean (see What I verified), but applying any of those patches with context after this chore lands fails.
Critique: whoever reads a failure or reconciles a base trusts these numbers and lists.
Consequences: none.
Recommendation:
- Fix the counts.
- Rewrap the header comment at the module's width. `docs.spec`'s `flat` folds the wrap, so its pins still hold.
- Make step 1's diff cover every Touched engine file and every file the specs load.
- Name the three other SKILL.md editors in Shared state, with "merge, never re-apply a patch".

## Lesson candidates (for the lead)
- **A kill must not come from a fail-closed neighbour** (z-design/spec-design-correspondence, a note): in a linear fixture, a commit that resets everything (a broken map, an unreadable file) kills every "earlier data mixed in" mutant for the commit after it, whatever that commit's case pins. Check: for each "this commit and no other" case, does its mutant still die with the fail-closed commits deleted or moved away from it?
- **A join over a fixed list of sources needs a commit where two sources disagree** (zz-test/seed-every-enumerated-case, a note): `MAP_FILES` was seeded one file per commit, so "first only", "last only" and "last parse decides" all passed. Check: is there one input where every source the code joins is present and each one decides a different part of the answer?

Verdict: changes
