# Review 011: R0042 (design mode)
Inputs: prep-z-nile at 136cb05 (R0042.md, check.sh, harvest.md, design-review-006 to 010 and design-refute-006 to 010; c0111 and c0119 documents, check.sh files and acceptance specs). The prototype `.worktree/proto-scope-fidelity`: both member folders are byte-identical to this tree. I read its `scripts/tracker/trail.luau`, `cmd.capture`, `cmd.renumber`, `cmd.compact`, `cmd.remap`, `compact.luau` and `ids.plan`/`ids.parseMap` against the Design.
Round 010's refutation holds: no ledger is written or read, so none of its F1 scenarios can occur, and F2 is moot. Settled user decisions (2026-10-20) are not reopened. F1 questions the trail's compaction rule, the fifth hole found in the trail's identity inference (007 F1, 008 F1, 009 F1, 010 F1).

Run on the prototype:
- c0111's and c0119's acceptance specs: `62 passed, 0 failed, 11 spec files`.
- `lessons --check`: `21 lessons, 99 harvest entries, ok`.
- `capture` for every prepared raft's members, and for c0111 and c0119.
- Two scratch fixtures (git repositories under the review's scratch directory, holding a copy of the prototype's `scripts/`), each running `scripts/tracker.sh capture` (F1).

I didn't run `promote-check`.

Lessons pass (item 10, `lessons --when design --full`):
- Failed: `tracker/item-history-spans-moves-and-compaction` ("its id before each compaction (each one writes only its own map)"). The trail takes every commit that touched the map file to be a compaction (F1).
- Failed: `architecture/parsers-refuse-ambiguity`. An unreadable map, and an id that a complete map doesn't name, are both read as "the same id before", not refused or marked (F1).
- Failed: `testing/seed-every-enumerated-case`. No fixture has a commit that touches `tracker/compaction.txt` without compacting, or an id with history that had no item at a compaction (F1).
- The others pass or don't apply:
  - `no-vacuous-pass`: the marker cases assert the text and that it is absent elsewhere.
  - `one-reader-per-format`: `read` uses `ids.parseMap`.
  - `exhaustive-lists-name-new-things`: `USAGE`, the command table and the Worktrees list name `capture`.
  - `new-rules-migrate-existing-work`: the audit is ready-raft's scope step.
  - `never-narrow-captured-scope` and `no-scope-cut-as-fix`: see item 11.

Scope fidelity (item 11, against the prototype's `capture`):
- c0111 (`ef5a7a5 tracker: new c0111 Skill lessons`, unmarked): the title is unchanged. The Problem gained only the four `Scope decision` lines. The captured Solution bullets are verbatim, followed by "As designed". The Non-goals that changed follow the decisions: the R0039 seed went to c0112, code-review harvesting came into scope, and metrics were restored. Every captured outcome has a Design and a criterion.
- c0119 (`ab750c0 tracker: new c0119 c0120; …`, unmarked): the title, Problem, Non-goals and Solution are the capture, plus the `Decided with the user (2026-10-20)` block. AC1, AC2 and AC4 cover the rules and the command.

### F1 [medium] The trail treats every commit that touched `tracker/compaction.txt` as a compaction, and treats an id that no map entry names as the same item before the cut. Each gives another item's capture with no marker
Where: c0111 The trail, **ranges** ("failing that, the same id …"; "an unreadable map renames nothing") and **read** ("the cuts are every line of `git log … -- tracker/compaction.txt`"); prototype `scripts/tracker/trail.luau` `ranges` and `read`; c0119 Design (`capture`)
Evidence:
- **A commit that touches the map without compacting reapplies the map.** In fixture 1:
  - `tracker: new c0010 Alpha` and `tracker: new c0140 Pi` are committed;
  - a real `tracker: compact ids` renames c0010 to c0001 and c0140 to c0010 (the shape of `ids.plan`, where low new ids are high old ones' targets);
  - Pi gets a prep edit;
  - then a commit changes only the map's `#` header line.

  `capture c0001` (Alpha) then prints:
  ```
  capture 24c0082… tracker/issues/c0140/c0140.md tracker: new c0140 Pi
  # c0140 PI captured
  ```
  It prints Pi's document with no marker. Before the header edit, it correctly printed Alpha's. `capture c0010` (Pi) prints `capture: no history for c0010`.

  The header edit is a cut carrying the same map. The walk maps c0001 back to c0010 across that cut, reads Pi's post-compaction folder under c0010, and at the real cut maps c0010 back to c0140, which is Pi's capture. `ambiguous` sees three different span ids, so it stays false.
- **This will happen in the programme.** c0114, next in R0042's own chain, moves the tracker into `z-nile/` and the issues into `.tracker/` folders (c0114 Problem). The trail's reader has to follow that move. The map file's add at its new path carries the last compaction's map, which is exactly the reapplication above. A hand fix of the file, or a revert of a compaction, does the same (a revert deletes or rewrites the file and renames the ids back, and an unreadable map counts as "renames nothing").
- **An id the map doesn't name continues into another item's history.** `ids.plan` maps every item found at compaction, identities included (the real map's 112 lines are exactly the 112 ids that ever held a folder before it). So an id that is neither a key nor a value had no item at that compaction. The rule still walks back under the same id. In fixture 2:
  - `tracker: new c0020 Old` is committed, and later its folder is removed;
  - a compaction runs, and its map doesn't name c0020;
  - an item lands at c0020 with no capture subject (a renumbered or branch-created item, which round 010 says must be marked).

  `capture c0020` prints `capture 40da70e… tracker/issues/c0020/c0020.md tracker: new c0020 Old` with no marker. No documented flow deletes an item today, so this is the less likely path. It is the same rule, though: the walk crosses a cut that doesn't prove the item was there.
- No case can see either path. `capture-cli.spec` writes the map only in real compactions, and `trail.spec`'s "unmentioned id" row asserts the continue-as-same-id behaviour.

Lesson: tracker/item-history-spans-moves-and-compaction, architecture/parsers-refuse-ambiguity, testing/seed-every-enumerated-case
Critique: Round 010 moved the trail to "follow only what is authoritative, mark the rest". The compaction rule still infers authority from where the commit is: any commit touching the file is believed, and silence in the map is read as "unchanged". The tempting fix is to special-case the header line, or to skip a cut whose map equals the previous one. That guesses again: it breaks when a new file repeats a map at another path (c0114), or when a real compaction happens to produce the same map.
Consequences:
- A cut has to prove itself for the item being walked, and anything it can't prove has to be marked, as round 010 does for renumbers. This adds a third marker condition, which ready-raft and item 11 already treat as not matching.
- It costs one `git diff --name-status --no-renames <cut>~1 <cut>` per cut crossed, which is small (one or two compactions).
- c0114 inherits the rule when it moves the file, so it must not have to invent one.

Recommendation:
- **`ranges` / `read`: a cut is crossed only when its own commit proves the rename for this item.**
  - Where the map says `old → current` with `old ≠ current`, that cut commit must delete `old`'s document (any of its three folders) and add `current`'s.
  - Where it says `current → current`, the document is present at `<cut>~1` and at the cut.
  - A cut whose commit shows none of this (a header edit, a copy at a new path, a revert) is not a compaction for this item: read straight through it under the same id, if the document is unchanged in that commit.
  - An id that no entry of a readable map names, as key or value, had no item at that compaction: the walk stops there.
  - An unreadable map, or a cut that contradicts the folders, stops the walk and sets a flag that `capture` prints as ` (ambiguous: the id's history crosses an unproven compaction)`. Never read it as "renames nothing".
- **Text:** say this in The trail (**ranges**, **read**), in c0119's marker list, in the tracker skill's `capture` row, and in the lesson's `check`: "each compaction, proved by its own commit's renames".
- **Spec cases** (`trail.spec` for the pure walk, given each cut's proof; `capture-cli.spec` end to end):
  - a header-only edit of the map after a compaction: the captures of the renamed items are unchanged;
  - the map file re-added at another path with the same content (the c0114 shape);
  - an id with pre-compaction history that the map doesn't name, reused by an item with no capture subject: marked first add, never the old item's text;
  - an unreadable map at a cut: marked.
- **Rows:** "any commit touching the map is a cut", "an unnamed id continues", "an unreadable map renames nothing". Run each on the prototype, and replace the "unmentioned id" row in c0111's table.
- **c0114:** name in its Design that the move keeps this rule, which is a pointer, not new scope.

### F2 [low] A marked capture never matches, even after the user's `Scope decision`, so ready-raft asks again on every later ready
Where: c0119 Appendix, ready-raft step 2; prototype `capture f0027`, `f0028`, `f0029`
Evidence: R0012's three members print `(no capture commit: first add)` (`a985927 Game design decisions and backlog: …`). The step says a marked capture "counts as not matching". It then says the user's answer lands as a `tracker: scope` line "before you ready the raft". But the capture stays marked after that decision lands, so a `stop` followed by a later `ready`, or a ready run in a new session, stops and asks again. Nothing says that a decision line on a marked item settles it.
Recommendation: In ready-raft step 2 and item 11, say that a marked capture matches once the document has a `Scope decision (user, …)` line dated after the newest commit `capture` printed, confirming its scope. Add the clause to `scope-docs.spec`'s ready-raft case, with a row "a decided marked capture still stops" (mutant: drop the clause).

Verdict: changes
