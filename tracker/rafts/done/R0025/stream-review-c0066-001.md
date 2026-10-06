# Review 001: c0066 (stream mode)
Inputs: `git diff R0025-ready-raft...ws-c0066` (tests/lib/cleanup.luau, tests/acceptance/c0038/deferred.spec.luau, tracker/issues/active/c0066/c0066.md); the c0066 document, `check.sh` and `acceptance/cleanup.spec.luau`; the testing skill's repository-safety rules. Ran `scripts/tracker.sh check c0066` (2/2 passed) and `scripts/check.sh --affected` (infrastructure changed, so all specs: 1281 passed, 0 failed, wall 97.2 s).

Checked, no finding:
- Scope: the diff touches only the three Touched modules (the c0066 change is one Verification log line). The sequestered `check.sh` and `acceptance/cleanup.spec.luau` are unchanged. No stream-review/refute files belong to the stream yet.
- Design: the retry applies only to "not empty" / "No such file" errors. The poll is 50 ms via `task.wait`. A missing path returns at once, and so does a tree that vanished after a failed removal. `tries >= 2` guarantees one retry after a race even when the first attempt used the whole bound. Other errors are re-raised at once with `error(err, 0)`. The final message reads `could not remove <path> after <n> tries: <err>; left: ...`. The listing is breadth-first, sorted per directory and capped at 20.
- The `cleans up` body changes only from `fs.removeDir(work)` to `cleanup.removeTree(work)`. The setup `removeDir` calls are untouched.
- Repository safety: the library sets no env or git configuration, runs no process and writes nothing. It touches only the path it is given. No guard file is touched.
- Weak-test check: the spec kills the single-attempt mutant (calls == 3), the deadline-before-first-retry mutant (calls >= 2 after a 0.1 s attempt with a 0.05 s bound), the retry-everything mutant (calls == 1), the busy-loop mutant (calls <= 12) and the depth-first listing mutant. In depth-first order, `a`, `a/b` and 18 files fill the 20 slots and `top.txt` is cut. The spec does not depend on wall-clock accuracy except through bounded counts.

### F1 [low] The per-directory sort of the left-behind listing is not pinned by the spec
Where: `tracker/issues/active/c0066/acceptance/cleanup.spec.luau` ("gives up after its bound and lists what is left"); `tests/lib/cleanup.luau:leftBehind`
Evidence: the spec asserts only that the message contains `top.txt`. A listing that is breadth-first but unsorted (dropping `table.sort`) still passes, because `fs.readDir` order is not asserted anywhere. The Rules table lists "breadth-first and sorted" as one rule with only a depth-first mutant.
Critique: the code is correct, and `table.sort` is present. The gap is in the sequestered spec, so the stream can't fix it. The risk is only a later regression that reorders the listing.
Consequences: none for this issue. Pinning the order would need the spec to compare the full `left:` text.
Recommendation: no change to c0066. The Opus raft review may note it. If it is worth closing, file a chore. Do not ask the stream to edit the sequestered spec.

Verdict: approve
