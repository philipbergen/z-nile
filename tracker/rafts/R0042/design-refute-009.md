# Refute 009: R0042
Round 009 is this re-prep's round 4. Its answer adds a mechanism (a renumber ledger), so it is more than minor, and round 010, the last allowed (round 5), follows.

The user was asked mid-round about the tooling language and chose to keep Luau on Lune as it is (2026-10-20). No scope changed.

Verification on `.worktree/proto-scope-fidelity`, synced with this tree:
- `scripts/check.sh --full` printed `GATE PASSED (full)`. Its lint stage first caught a shadowed local in the new `renumber` code, now renamed.
- c0111's `check.sh` passed 11/11, and c0119's passed 4/4.
- `promote-check R0042` printed `promote-check OK`.
- `luau-lsp analyze` of both acceptance folders and `scripts` exited 0.
- `lessons --check` printed `21 lessons, 97 harvest entries, ok`, and `--uncovered R0040 R0042` printed that every finding is covered.

- F1: fixed, by changing the mechanism as recommended. Every id change now leaves a record the trail reads.
  - `renumber` appends `<old> <new>` to `tracker/renumbered.txt`, plus the moved directory for a renumber by directory, and stages it. The file is `.txt`, which `rewriteUnder` (`.md` and `.sh` only) leaves alone.
  - c0111's trail takes cuts from both `compaction.txt` and the ledger. A renumber cut maps only the lines its commit added (`trail.added`). A commit that changed both files is a compaction, because `compact` rewrites ids inside the ledger.
  - A renumber by directory limits the old id's earlier history to that one folder, and the copy that kept the number keeps its other folders.
  - `capture` ends its header with `(no capture commit: first add)` when it falls back. The tracker skill's row and item 11 say what that means. Renumbers from before this lands get the marker (c0005: `947a5c6 … (no capture commit: first add)`).
  - `capture-cli.spec` runs a real `renumber`, by id and by directory, in a fixture worktree and asserts the ledger lines. It covers the renumbered item, the copy that kept its number, and the marker, both present and absent.
  - consequences: `renumber` writes one more file. The full gate passed with it (`c0052/renumber`, `c0081`, `tests/tooling/remap-once` green). The 8 mutants each failed a case (no ledger, no directory, ledger not read, folder limit ignored, kept copy stopped, every ledger line counted, no marker, marker always). "A commit that changed both files is a compaction" is `reasoned`: no fixture compacts after a renumber.
- F2: fixed: c0119's Scalability now counts one `tracker.sh capture` per item (a `git log` per span and a `git show` per cut). The prototype comment above `cmd.capture` states the current rule. consequences: none.
