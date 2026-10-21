# Review 013: R0042 (design mode)
Inputs: prep-z-nile at c93dd45 (R0042.md, check.sh, harvest.md, design-review-006 to 012 and design-refute-006 to 012; c0111 and c0119 documents, check.sh files and acceptance specs; the diff ef879b8..c93dd45). The prototype `.worktree/proto-scope-fidelity`: both acceptance folders match this tree, and c0119.md is byte-identical. Its c0111.md lacks only this tree's line 260 (the c0114 pointer about the map's earlier path). I read its `scripts/tracker/trail.luau`, `cmd.capture`, `cmd.compact` and `ids.parseMap`/`formatMap` against the Design. I read the programme reviews of c0114 to c0118 and c0120 only to check for conflicts.
Round 012's refutation holds for its own two fixtures: a header edit made together with a document edit is not a compaction, and a broken map is marked. F2 of round 012 is fixed. I don't reopen settled user decisions. F1 below is the seventh hole in the trail's identity rules (007 F1, 008 F1, 009 F1, 010 F1, 011 F1, 012 F1), so it questions the mechanism and puts a simpler rule to the user.

Run on the prototype:
- c0111's and c0119's acceptance specs: `67 passed, 0 failed, 11 spec files`.
- `luau-lsp analyze` of `trail.luau`, `main.luau` and both acceptance folders: exit 0.
- `lessons --check`: `21 lessons, 104 harvest entries, ok`.
- `capture c0111` and `capture c0119`, and `capture` over all 150 items on `origin/main`. Results: 98 first-add, 1 ambiguous (c0004), and 32 unmarked captures reached by crossing the one compaction (`a38f91f`). Only two of those 32 are open, c0075 and c0083.
- Two scratch fixtures (git repositories under the review's scratch directory, each with a copy of the prototype's `scripts/`), each running `scripts/tracker.sh capture` (F1).

I didn't run `promote-check`.

Lessons pass (item 10, `lessons --when design --full`):
- Failed: `tracker/item-history-spans-moves-and-compaction` ("its id before each compaction"). Two kinds of commit are read as compactions: a revert of a later compaction, and a restore of a map whose parent was unreadable (F1).
- Failed: `architecture/parsers-refuse-ambiguity`. An unreadable map at `<cut>~1` is read as "different", so the restore that follows it is taken as a compaction. "Unreadable" should count as "unknown", not as "a different map" (F1).
- Failed: `testing/seed-every-enumerated-case`. The Design lists "a revert" among the unproven cases, but no fixture reverts a compaction. The revert case stayed `reasoned`, on a premise that is false (F1, F2).
- The others pass or don't apply:
  - `no-vacuous-pass`: the marker cases assert both that the marker is present and that it is absent elsewhere.
  - `one-reader-per-format`: the trail uses `ids.parseMap`.
  - `guards-trust-only-origin`: `capture` reads `origin/main`.
  - `new-rules-migrate-existing-work`: ready-raft's scope step.
  - `never-narrow-captured-scope` and `no-scope-cut-as-fix`: see item 11, and F1 escalates rather than cuts.

Scope fidelity (item 11, against the prototype's `capture`):
- c0111 (`ef5a7a5 tracker: new c0111 Skill lessons`, unmarked): since round 012 only the Design changed (hunks at lines 235 to 302 and the rows). Round 011's comparison still holds: the Problem gained only `Scope decision` lines, the captured Solution bullets are verbatim, and every outcome has a Design and a criterion.
- c0119 (`ab750c0 tracker: new c0119 c0120; …`, unmarked): the Problem to Solution diff against the capture is exactly the `Decided with the user (2026-10-20)` block. The changes since round 012 are the marker list in Design, E1, a row and the tracker-skill row in the Appendix. AC1, AC2 and AC4 cover the rules and the command.

### F1 [medium] "Parsed map differs from its parent's" still lets two kinds of commit pass as compactions: a revert of any compaction after the first, and a map restored after an unreadable one. Each prints another item's capture with no marker
Where: c0111 The trail, **read** ("left the map file unreadable (a bad line, a deletion, a revert)"; "a map that parses and differs from its parent's"), **sameMap**, **crossing**; prototype `trail.read` (`compaction`, `unproven`); design-refute-012 ("The revert case goes through the same unproven path, since the revert leaves no readable map"); c0119 Design marker list
Evidence:
- **A revert of a later compaction leaves a readable, different map.** Only a revert of the *first* compaction deletes `tracker/compaction.txt`. `origin/main` already has one compaction (`a38f91f`), so every future compaction's revert restores the previous map, which parses and differs from its parent's. In fixture B:
  - `tracker: new c0010 Alpha` (its document mentions c0140) and `tracker: new c0140 Pi`;
  - compaction 1 renames c0010 to c0001 and c0140 to c0010, and rewrites ids in documents;
  - `tracker: new c0150 Nu`;
  - compaction 2 keeps c0001, renames c0010 to c0002 and c0150 to c0010 (a rotation), and rewrites Alpha's document;
  - `git revert HEAD`, which is GitHub's Revert button on the compaction PR.

  Before the revert, `capture c0001` correctly prints `tracker: new c0010 Alpha`. After it, `capture c0001` (Alpha) prints:
  ```
  capture c38f257… tracker/issues/c0150/c0150.md tracker: new c0150 Nu
  ```
  There is no marker. The trail reads the revert as compaction 1 again: its map renames c0010 onto c0001, and c0010 held a document just before (Nu's). From there, compaction 2 carries it on into c0150. `capture c0010` (Pi, back at c0010) and `capture c0150` (Nu) are only marked as first add, so their real captures are lost too.
- **A restored map counts as a compaction.** `sameMap(m, nil)` is false, so a cut whose parent's map was unreadable always "differs". In fixture A:
  - Alpha and Pi, then the rotating compaction (c0010 to c0001, c0140 to c0010), then a prep edit of c0001;
  - one commit breaks the map (a bad line; in a second run, it deletes the file). It touches no document, so nothing is marked, and `capture c0001` is still right;
  - one commit restores the map and edits c0001's document (a squash-merged fix PR).

  `capture c0001` (Alpha) then prints `capture 2293a63… tracker/issues/c0140/c0140.md tracker: new c0140 Pi`, with no marker. So does `capture c0010`. The deletion run gives the same result.
- **No case can see either path.** `capture-cli.spec` seeds the header-plus-edit case and the broken map at the edit itself. No fixture has a second compaction that is then reverted, or a broken map followed by a restore.

Lesson: tracker/item-history-spans-moves-and-compaction, architecture/parsers-refuse-ambiguity, testing/seed-every-enumerated-case
Critique: Each round's rule infers "this commit applied this map" from something next to it. Rounds 007 to 010 inferred it from ids, round 011 from the document's presence, and round 012 from the map's text changing. Each inference has had a counterexample, and every counterexample needs a commit (a revert, a restore, a hand edit) that the compaction tool didn't make. The tempting seventh patch is to recognise a compaction by its header (`# tracker.sh compact, <date>, from origin/main <base>`, which `cmd.compact` writes), and to require a base sha no earlier map named. That would catch both fixtures, because a revert or a restore brings back a header already seen. But it trusts a free-text line that a hand edit can copy or invent. It also makes c0114 carry the header format, and c0118 dates done items through the same reader. The next round would likely find the next commit shape.
Consequences:
- Any rule that crosses an id change has to trust some record of the change. The only record `compact` writes is the map file itself, which reverts and restores rewrite.
- Every rule so far has been unsafe in the same direction: it crosses when unsure. The marker exists so that an uncertain capture fails safe, and ready-raft already asks the user about every marked capture.
Recommendation: escalate to the user: should `capture` keep following items across compactions, or mark them?
- **(a) Patch 7: keep crossing, and prove a compaction by its header.**
  - A cut is a compaction only when its map parses and its header names a `from origin/main <base>` that no map earlier in history named.
  - Any other cut that changes the map's parsed content and touches the item's document is unproven, and is marked: a revert, a restore, a hand edit, or a map whose parent's was unreadable.
  - Spec cases: fixture A, fixture B, and a revert of a revert (marked, not crossed).
  - Mutants: "header ignored", "unreadable parent counts as different", "revert crosses".
  - Cost: no new marks today, and c0075 and c0083 keep their crossed captures. The rule is still an inference, and c0114 must preserve the header when it moves the map.
- **(b) The simpler rule: `capture` never crosses an id change.**
  - An item's life also starts at any cut that touched its document, unless the cut's map parses the same as its parent's. That covers a compaction, a revert, a restore and an unreadable map.
  - A capture found in no life gets a marked fallback, `(no capture commit: across a compaction at <sha>)`. `crossing`, the document proof and the second marker drop out of `capture`'s path. The only remaining guess (same parsed map means no rotation) fails safe: if it is wrong, the item is marked, not misattributed.
  - The dating readers (`cmd.metrics`, and c0118's done times per its programme review) may keep crossing as a best effort, because a wrong date there is a statistic, not a scope baseline. The Design has to say so, as a separate `trail.read` mode.
  - Cost to the user: 32 more items are marked on today's tree (131 of 150). Only c0075 and c0083 are open, and both are already in the one-time audit that R0042's Risks lists, so readying costs no extra question today. After each future compaction, every open item it renamed needs one `Scope decision` line at its next ready.
  - Spec cases: fixture A, fixture B, and the existing two-compaction case, which becomes "marked".
  - Mutants: "cross at a compaction", "unreadable parent is no boundary".
- Whichever option the user picks:
  - fix the **read** text, which says a revert leaves the map unreadable;
  - record the decision as a `Decided with the user` line in c0111 and c0119;
  - update the lesson `item-history-spans-moves-and-compaction`'s `check` to match;
  - make the `capture-cli.spec` cases for fixtures A and B `run` rows.

### F2 [low] Row "only a compaction commit is crossed" is still `reasoned`, on the premise round 012 disproved
Where: c0111 Rules and mutants, "only a compaction commit is crossed | c0119 capture-cli | cross at any life start | reasoned: equivalent here, since the document proof also stops it (recorded in E5)"
Evidence: round 012 F1 showed that the document proof can't separate a compaction from a commit that carries an old map, because after a rotation the old path always holds a document. Its Recommendation asked to replace this row with run rows, and refute 012 lists three run mutants but leaves this row and its reason as they were. The mutant "cross at any life start" is plausibly killed now, by the reused-number case: there, the map at the add renames an id onto the reused one.
Recommendation: run that mutant on the prototype, and record the case that kills it, or drop the row if F1(b) removes crossing from `capture`.

Verdict: changes
