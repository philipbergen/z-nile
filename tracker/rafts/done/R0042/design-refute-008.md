# Refute 008: R0042
Round 008 is this re-prep's round 3. It had no high finding, but answering it added rules and spec cases, so it was more than minor, and round 009 follows (ticket-prep step 5.4).

Verification on `.worktree/proto-scope-fidelity`, synced with this tree:
- `scripts/check.sh --full` printed `GATE PASSED (full)`.
- c0111's `check.sh` passed 11/11, and c0119's passed 4/4.
- `promote-check R0042` printed `promote-check OK`.
- `luau-lsp analyze` of both acceptance folders and `scripts` exited 0.
- `lessons --check` printed `21 lessons, 95 harvest entries, ok`, and `--uncovered R0040 R0042` printed that every finding is covered.

- F1: fixed:
  - `trail.ranges` takes `cuts`: every commit that changed `tracker/compaction.txt`, newest first, each with its own map. It walks back one cut at a time. `trail.read` builds the cuts from `git log --format=%H <head> -- tracker/compaction.txt` and parses each map at its own commit.
  - `trail.spec` pins two cuts (R0300 to R0030 to R0003), a renamed-away id stopping the walk, an unmentioned id crossing every cut, and an unreadable map.
  - `capture-cli.spec` adds a second compaction (c0030 to c0003), and the earlier assertions follow it.
  - Round 007's sentence that the next `compact` keeps working was wrong for the single-map reader. It holds now.
  - consequences: one `git show` per compaction commit (one today). The mutant "only the latest compaction" fails both specs.
- F2: fixed. There is one rule everywhere: the capture is the newest commit whose subject is `tracker: new` with the item's id, as it was at that commit, in its leading id list.
  - Code: `trail.namedIds` reads that list, and each commit carries the id of its span (`Commit.id`), so a pre-compaction capture matches its old id.
  - Text: ticket-prep, the tracker skill's row and c0119's Design say the same thing.
  - Effect on the real tree: c0114's capture is now its own `fb7fd80`, with the user's 2026-10-20 decisions as added `Decided with the user` lines. c0083's is `cda52f9`.
  - A decision on a prepared member lands by a pull request merged as `tracker: scope <id> <what>`, which is not a capture. `land` edits only draft documents. A restore sends the raft back to prep.
  - The spec pins make-issue's `tracker: new <id> <title>` subject, which the lookup relies on.
  - consequences: this is one rule, the one the user approved for `capture`, written once, so it needs no new user decision. Its mutants (any issue id, the current id instead of the span's, `tracker: scope` accepted, every word scanned) each fail a case.
- F3: fixed: `capture-cli.spec` adds a raft (`capture R0010`, from its first add), a `check.sh` written in the same first add as c0020's legacy document (its text must not be printed), a `tracker: scope c0010` commit and a `tracker: new c0050` commit that also edits c0010, and a later landed pre-compaction capture. The mutants "accept every file" and "kind is always issues" now fail. consequences: none.
- F4: fixed:
  - Both Implementation steps name `trail.luau` (AC10) and `cmd.capture` (AC4).
  - The metrics Output bullets are back under Metrics.
  - c0119's Affected specs names `main.luau`'s `ALL` and `tracker-guarded`, and E1 and R0042's Experiments phase carry this round's counts.
  - c0111 is `design: reviewed` again.
  - The lesson `tracker/item-history-spans-moves-and-compaction` now asks about every compaction and the id at the time.

  consequences: none.
