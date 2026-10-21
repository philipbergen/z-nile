# Review 010: R0042 (design mode)
Inputs: prep-z-nile at 691889c (R0042.md, check.sh, harvest.md, design-review-006 to 009 and design-refute-006 to 009; c0111 and c0119 documents, check.sh files and acceptance specs). The prototype `.worktree/proto-scope-fidelity`: both acceptance folders and both documents are byte-identical to this tree. I read its `scripts/tracker/trail.luau`, `cmd.capture`, `cmd.renumber`, `cmd.compact`, `cmd.remap` and `compact.luau` against the Design.
I checked every round-009 refutation against the tree and the prototype. They hold, so no round-009 finding is repeated. Settled user decisions (2026-10-20) are not reopened: the read-only `tracker.sh capture <id>`, and the tooling staying in Luau on Lune. F1 questions the trail mechanism, which rounds 007 F1, 008 F1 and 009 F1 already found holes in.

Run on the prototype:
- c0111's and c0119's acceptance specs: `63 passed, 0 failed, 11 spec files`.
- `lessons --check`: `21 lessons, 97 harvest entries, ok`.
- `capture c0111` and `capture c0119`.
- A scratch Lune probe of `trail.ranges` and `trail.added`, run on copies of `trail.luau` and `ids.luau` in the scratch directory.

I didn't run `promote-check`.

Lessons pass (item 10, `lessons --when design --full`): I asked each design lesson's `check` of the draft.

Failed:
- `tracker/item-history-spans-moves-and-compaction`: a ledger line can describe a tree that `origin/main` never had (F1).
- `architecture/parsers-refuse-ambiguity`: a cut keeps one of several lines for an id, and treats lines in order as simultaneous (F1).
- `ticket-prep/specify-every-named-artifact`: a merge of the new ledger file has no rule (F2).

The others pass or don't apply:
- `guards-trust-only-origin`: the trail reads `origin/main`.
- `one-reader-per-format`: `trail.added` parses exactly the `<old> <new>[ <dir>]` line that `cmd.renumber` writes, and skips its `#` header.
- `new-rules-migrate-existing-work`: renumbers from before this lands get the marked fallback (c0005).
- `exhaustive-lists-name-new-things`: the command table, the Worktrees list and `USAGE` name `capture`, and the full gate passed with the new tracked file.

No lesson was added since round 009, so there are none to judge.

Scope fidelity (item 11, against the prototype's `capture`):
- c0119 (`ab750c0 tracker: new c0119 c0120; …`): title, Problem, Non-goals and Solution are the capture plus the `Decided with the user (2026-10-20)` block. Every rule has AC1 or AC2, and the command has AC4.
- c0111 (`ef5a7a5 tracker: new c0111 Skill lessons`): the title is unchanged. The Problem gained only four `Scope decision` lines, and the captured Solution bullets are verbatim, followed by "As designed". The Non-goals changed, but nothing was fenced off that the capture asked for. The seed went to c0112 by decision, code-review harvesting moved into scope, and metrics came back into scope. Every captured outcome has a Design and a criterion.

### F1 [medium] A ledger line records the renumber in the branch's tree, but the trail applies it to `origin/main`'s history. In the documented collision flow, the item that kept the number loses its capture, and the renumbered item gets the other item's document as its capture, unmarked
Where: c0119 Design, **`renumber` records itself**; c0111 The trail (`ranges`: "renamed away … the walk stops"; `read`); tracker skill, Conflicts; prototype `scripts/tracker/main.luau` `cmd.renumber` (lines 1461–1468), `trail.luau` `ranges`
Evidence:
- **The collision flow.** The tracker skill's Conflicts paragraph says that when two branches pick the same number, you run `git merge --abort`, then `tracker.sh renumber <ID>` on your own branch, and merge again. Collisions still happen for offline `new` (`PICKMAN_PUBLISH=0`, where the counter is never written) and for cutover preps. Say `origin/main` has c0510, published as `tracker: new c0510 …`, and my branch has its own unpublished c0510. `renumber c0510` on my branch appends `c0510 c0520`. The PR squash-lands as S. On `origin/main`, the folder `tracker/issues/c0510` before S was only ever the other item's.
- **What the trail does with it** (probe on the prototype's `trail.ranges`, cut S with map `{c0510 = c0520}`):
  - `c0510` (the item that kept the number) gives the single range `S..H`, because c0510 was "renamed away" and the walk stops. Its real capture is before S. `capture c0510` then prints `capture: no history for c0510` (exit 1) if it only had edits after S. If it was later moved to `active/` (a `D`+`A` under `--no-renames`), it prints the moved copy as a first add. Before round 009's fix it found its capture.
  - `c0520` gives `S..H` under c0520, then `S~1` under c0510. That span holds the other item's `tracker: new c0510 …`, whose `namedIds` include the span id, so `capture c0520` prints the other item's document with no marker. The Design says "a look-alike document is never taken for the item's". Here one is, and it looks like a real capture.
- **The same root, two more ways:**
  - **Two renumbers on one branch.** c0510 (published) → c0520 → c0530 lands as one commit adding both lines. `added` returns `{c0510 = c0520, c0520 = c0530}`, and `ranges` treats it as one simultaneous map. Probe: c0530's range before S is `c0520`'s folders, which `origin/main` never had, so the c0510 capture is lost. One map also holds one value per old id, so a repeated old id in one commit is silently collapsed (lesson `parsers-refuse-ambiguity`).
  - **`remap`.** A branch that renumbered before a compaction keeps its line in the old id space. `compact.luau`'s `rewritesIds` and `remap` rewrite only `.md` and `.sh` files, and the Design relies on that ("`.txt`, so `rewriteUnder` … never changes it"). After landing, that line is applied to the new id space, and it names whatever items hold those numbers then.
- **No case can see any of these.** `capture-cli.spec`'s `renumber` helper pushes each renumber straight to `main` from a tree that already has the old id's history. So every ledger line in the fixture is true of `main`.

Lesson: tracker/item-history-spans-moves-and-compaction, architecture/parsers-refuse-ambiguity
Critique: This is the fourth round to find a hole in the trail's identity rule:
- 007: compaction at all;
- 008: every compaction;
- 009: renumber leaves no record;
- now: renumber's record describes the wrong history.

A compaction map is computed on `origin/main` (`compact` refuses unless HEAD is `origin/main`), so it is true of the history the trail walks. A renumber line is computed in whatever tree runs it, usually a branch whose own history squash-merging erases. The tempting fix is to special-case the reader, for example to stop the "renamed away" walk only when the old folder disappears at the cut. That guesses again, and it still sends c0520 to the other item's history.

Consequences:
- The line has to be true of `origin/main` when it lands, so the writer must know whether `origin/main` ever had this item under the old id. The merge-base answers that.
- A second renumber on the same branch has to update the first line, or the reader has to apply lines in order. Applying in order fails here, because the middle id was never on `main`.
- `remap` gains one more file to rewrite.

Recommendation:
- **What `cmd.renumber` writes:**
  - It appends `<old> <new>[ <dir>]` only when the moved folder's document exists at `git merge-base HEAD origin/main`, which means this item was published under the old id and the branch contains that publish. With no `origin/main`, it always writes the line.
  - When the branch already added a line whose new id is `<old>` (the lines since that merge-base), it rewrites that line's new id instead of appending, so one landing commit maps the published id straight to the final one.
  - Otherwise it writes nothing, because `main` only ever sees the new id. That item's capture is then its marked first add, which item 11 already sends to the user.
- **What `remap` does:** it rewrites the ids in the ledger lines the branch added since the merge-base, with the same map it applies to documents.
- **What `trail.added` does:** it refuses a commit that adds two lines with the same old id: the cut maps nothing, the same as an unreadable map, and the commit is printed on stderr.
- **Text:** say all of this in c0119's **`renumber` records itself**, in The trail, in the tracker skill's Conflicts sentence, and in the lesson's `check` ("each renumber that `origin/main` saw").
- **Spec cases in `capture-cli`:**
  - the collision flow: a published `tracker: new c0510 …` on `main`, and a branch item c0510 committed locally, renumbered with `renumber c0510`, and landed as one squash commit. Assert there is no ledger line, that `capture c0510` prints the published capture, and that `capture c0520` is marked `(no capture commit: first add)` and is never the other item's text;
  - a published item renumbered twice on one branch and landed as one commit, whose `capture` is the original;
  - a renumber, then a compaction on `main`, then `remap` and landing, whose `capture` is the original.
- **Rows:** "ledger line written for an id `main` never had", "a chained renumber appends", "remap leaves the ledger", "a repeated old id kept silently". Run each on the prototype.

### F2 [low] The ledger has no merge rule, and the "commit that changed both files" reasoning rests on a premise that is false
Where: c0119 Design, **`renumber` records itself**; c0111 The trail, `read`; c0111 Rules and mutants row "a commit that changed both files is a compaction"; tracker skill, Conflicts and Landing step 4
Evidence:
- Two branches that each renumber append at the same end of `tracker/renumbered.txt`, so the second one's merge of `origin/main` conflicts. The repository has no `.gitattributes`. The Landing step says a merge that "conflicts, or … needs anything beyond renumbering colliding IDs", means `BLOCKED:` and stop. Conflicts treats only `CONFLICT (add/add)` on a document as a number clash.
- The Design and the reasoned row say a commit that changed both files is a compaction "because `compact` rewrites ids inside it". It doesn't: `compact.luau`'s `rewritesIds` takes only `.md` and `.sh` files, and the ledger keeps its old-space ids, which is right, because each cut reads its own commit's lines. So no `compact` commit changes the ledger, and the rule only matters for a hand-made commit.

Recommendation:
- Add `tracker/renumbered.txt merge=union` in a `.gitattributes`. In the tracker skill's Conflicts, say that a conflict on the ledger keeps both lines in order. Add a fixture case that merges two branches' appends.
- Reword the read rule's reason to "a compaction cut wins, because its map is the whole tree's", or drop the claim.

Verdict: changes
