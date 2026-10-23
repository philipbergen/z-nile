# Review 014: R0042 (design mode)
Inputs: prep-z-nile at e5f671e (R0042.md, check.sh, harvest.md, design-review-013 and design-refute-013, skimmed 006 to 012; c0111 and c0119 documents, check.sh files and acceptance specs; the diff c93dd45..e5f671e). The prototype `.worktree/proto-scope-fidelity`: both issue folders (documents, check.sh files and acceptance specs) are identical to this tree. I read its `scripts/tracker/trail.luau`, `cmd.capture` and the metrics reader in `cmd.metrics`, and the marker text in its skills.
Round 013's F1 and F2 are settled by the user's decision "Never cross; mark it" (2026-10-20), and I don't reopen it. On `capture` the decision holds: no fixture or real-tree item I tried names another item's capture. F1 below is about the other reader of the trail, the metrics dater, which the decision didn't name and the refute says still works.

Run on the prototype:
- c0111's and c0119's acceptance specs: `64 passed, 0 failed, 11 spec files`.
- `luau-lsp analyze` of `trail.luau`, `main.luau` and both acceptance folders: exit 0.
- `lessons --check`: `21 lessons, 106 harvest entries, ok`.
- `capture c0111`, `capture c0119`, `capture` of c0075, c0083, c0004, c0001 and R0010.
- `tracker.sh metrics`: `before | 39 | 161 | 4.1`. E4 recorded 41 rafts.

I didn't run `promote-check`.

Lessons pass (item 10, `lessons --when design --full`):
- Failed: `tracker/item-history-spans-moves-and-compaction`. Its check asks that every lookup of "its first review, its dates" never infers identity across an id change "but mark it instead". The metrics dater neither crosses nor marks: it misdates or silently drops a raft whose life starts at a compaction (F1).
- Failed: `testing/seed-every-enumerated-case` and `ticket-prep/spec-design-correspondence`. `metrics-lessons.spec` seeds no compaction, so the Design's sentence "a renumbered raft dates from its compaction … so it still counts as before" has no case, and the sentence is false for a rotation (F1).
- Failed: `ticket-prep/restated-rules-move-together` and `tracker/exhaustive-lists-name-new-things`. The new marker is in the tracker row and c0119's Design, but not in the ready-raft and item 11 texts that list "a marked capture". Several passages still describe crossing (F2).
- Passed or not applicable: `no-vacuous-pass` (capture's marker cases assert presence and absence), `one-reader-per-format`, `guards-trust-only-origin` (`capture` reads `origin/main`), `new-rules-migrate-existing-work` (ready-raft's scope step, and Cost names c0075 and c0083), `never-narrow-captured-scope` and `no-scope-cut-as-fix` (item 11 below; no Recommendation here cuts).

Scope fidelity (item 11, against the prototype's `capture`):
- c0111 (`ef5a7a5 tracker: new c0111 Skill lessons`, unmarked). The Problem gained only the four `Scope decision` lines. The captured Solution bullets are verbatim, with an `As designed` paragraph after them. Non-goals were rewritten, but no captured outcome moved into them: seeding is c0112 by decision, and code-review harvest is in scope. Every outcome has a Design and a criterion. The captured **metrics** outcome ("show whether lessons reduce review rounds") has AC9, but F1 shows that AC9 passes while the table goes wrong after the next compaction.
- c0119 (`ab750c0`, unmarked): the Problem-to-Solution diff against the capture is exactly the `Decided with the user (2026-10-20)` block. AC1, AC2 and AC4 cover the rules and the command.

### F1 [medium] The metrics dater narrows a raft's life at a compaction and dates it by the first add after that. A rotated raft is dropped today (41 to 39 rafts), and after the next compaction every renamed pre-lessons raft counts as "after"
Where: c0111 Metrics, **The reader** ("the first add along the raft's folders and its pre-compaction id"); The trail, **Metrics** ("a renumbered raft dates from its compaction, which predates lessons, so it still counts as before"); prototype `cmd.metrics` (`trailLib.oldestAdd(trailLib.read("rafts", raft.id, …))`); design-refute-013 F1 consequences.
Evidence:
- **Today, rotated rafts count nowhere.** The 2026-10-05 map rotates R0010 to R0001 with R0100 to R0010, and R0020 to R0002 with R0200 to R0020. At `a38f91f`, `tracker/rafts/done/R0010/design-review-001.md` and `…/R0020/design-review-001.md` are `M`, not `A`. `read` narrows both lives to `a38f91f`, `oldestAdd` finds no add, `start` is nil, and `roundsSplit` counts neither. `tracker.sh metrics` on the prototype prints `before | 39 | 161 | 4.1`, while E4 records `before | 41 | 165`. The Design says these rafts "still count as before". The same happens to any raft that keeps its id while the compaction rewrites its document (its `issues:` ids): its review file isn't added in the narrowed life either.
- **After the next compaction, the split inverts.** `compact` is a recurring tool, and review 013 and the Cost paragraph both plan for "each future compaction". Once lessons have landed, a compaction that renames R0050 to R0005 writes `A tracker/rafts/done/R0005/design-review-001.md` in its own commit. The life starts there, `oldestAdd` is the compaction, and its time is at or after the cutoff, so the raft counts as **after**, with its pre-lessons rounds. Rotated or rewritten rafts drop out, as above. The table the captured outcome asks for ("to show whether lessons reduce review rounds") then compares old rafts with old rafts.
- **No case sees it.** `metrics-lessons.spec` seeds no `tracker/compaction.txt` (grep finds no `compact`), so AC9 passes either way. The trail cases that do cover compaction test `capture` only.

Lesson: tracker/item-history-spans-moves-and-compaction
Critique: The user's decision fixed `capture`: a scope baseline must never name another item, so it fails safe by marking. The dater reuses `capture`'s narrowing, but a date doesn't fail safe that way. A wrong date files the raft in the wrong column and nothing marks it. The tempting fix is to let the dater cross compactions again as a "best effort", or to count a raft whose life starts at a cut as "before". The first brings back the identity inference that seven rounds broke and the user rejected. The second misfiles every raft prepped after lessons and then compacted.
Consequences: the dater needs a date that survives an id change without identity inference. The raft's own `created:` frontmatter does: `tracker.sh new raft` writes it, compaction rewrites only ids, and every raft with a design review has one today. It has day granularity, and it dates creation, not the first review, so a raft created before the cutoff day but first reviewed after counts as before.
Recommendation:
- Keep the trail date when the raft's life isn't cut (`read`'s notes are empty). When it is cut, or when the trail gives no add, date the raft by `created:`: "after" when that date is on or after the cutoff commit's UTC date, otherwise "before". Write this in Metrics, and replace the false Metrics sentence in The trail.
- Optionally print, under the table, how many rafts were dated by `created:`, so the fallback is visible.
- Spec cases in `metrics-lessons.spec`, each with a compaction commit that writes `tracker/compaction.txt`:
  - a pre-cutoff raft renamed by a post-cutoff compaction counts before;
  - a raft created after the cutoff and then renamed counts after;
  - a rotated raft (review file `M`) is dated, not dropped.
- Mutants:
  - "date by the trail even when cut": kills the first case;
  - "a cut raft counts before": kills the second;
  - "undated when no add": kills the third.
- Record the change as an E-entry with the real tree's counts (41 dated rafts). Correct design-refute-013's consequence line in the answer.

### F2 [low] The texts that list "a marked capture" name two markers, not three. Several passages still describe the crossing trail
Where:
- c0119 Appendix, ready-raft step 2 and review item 11 ("a capture marked `(no capture commit: first add)` or `(ambiguous: …)`"), pinned by `scope-docs.spec` lines 114 and 141;
- c0119 Design line 48 ("98 fall back to a first add"), Scalability ("one `git show` per compaction commit"), Rules rows "every compaction is walked, not just the latest" (its case `follows every compaction …` no longer exists) and "capture follows compaction …";
- c0119 `check.sh` AC4 label ("prints an item's capture across moves, legacy names and compaction");
- c0111 line 46 ("every folder and id an item has had") and line 221 ("its pre-compaction id"); E5 (crossing results, not marked superseded);
- R0042.md line 39 ("every folder and pre-compaction id it has had");
- prototype `cmd.metrics` comment ("and its id before compaction").
Evidence: c0119's Design and refute 013 say every marked capture counts as not matching at ready. The ready-raft text an executor pastes treats only the first two markers that way. On every case I found (the fixture, and c0075, c0083, c0004, c0001 and R0010 on the real tree), the compaction marker comes together with `(no capture commit: first add)`. So ready-raft still asks, and this is not a wrong result today. But a reader of ready-raft or item 11 can't tell that the third marker counts. The other passages contradict "no id change is followed".
Lesson: ticket-prep/restated-rules-move-together
Recommendation: in the ready-raft and item 11 Appendix texts, say "a marked capture (any of the three markers capture prints: tracker skill, `capture` row)", and pin that phrase in `scope-docs.spec`. Fix or delete the stale passages and rows listed above, and mark E5 as superseded by E8.

Verdict: changes
