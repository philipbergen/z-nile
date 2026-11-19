# Review 001: R0132 (final mode)
Inputs: HEAD 44f01f047 (trace table at 6caf0af25; the two commits after it change tracker files only) against origin/main 055f3acb2 (`git diff origin/main...HEAD`, merge base 055f3acb2); `trace.md`; R0132.md and its `check.sh`; d0413.md, its `check.sh`, `acceptance/loops.spec.luau`, `acceptance/watch.txt`, `guesses.md`, `prototype.patch`; `./zn capture d0413` (a746f7efe841, no marker); review-001.md, refute-001.md, harvest.md and the lesson `zz-execute/rerun-a-branch-only-red-after-finish`.

What was checked:
- `./zn trace R0132 --check`: `ok: R0132` (run before my one edit to `trace.md`).
- `./zn check d0413`: 5/5.
- `z-nile/check.sh --project z-nile --full` on HEAD: `1285 passed, 0 failed, 211 spec files`, `GATE PASSED (full)`. This is the run that proves S5 ("`z-nile/check.sh --full` passes its z-nile stage") on the finished stack; the Verification log holds only the earlier run with three reds and the reruns that cleared them.
- Sequestration: the only change under `check.sh` or `acceptance/` is the added `acceptance/watch.txt`, which `./zn finish` writes. `check.sh` and `loops.spec.luau` are untouched.
- Scope: the document's Problem, Non-goals and Solution are the capture's, word for word. Each of the five Solution outcomes has a Design paragraph and a Checked criterion; S5 is carried by AC5 under the recorded guess G1.
- Every cell of the trace table against the files at HEAD: the design lines (37, 41, 44, 45, 46, 100, 102, 139 to 143, 146, 149), the spec cases (lines 59, 67, 90, 101, 114, names exact), the `check.sh` lines (24, 28, 30, 34, 36) and the code lines (`guesses.luau:43`, `raftplan.luau:105`, `:108`, `:125`). One cell was wrong (F1). The Source files table names both changed engine files and nothing else in the diff is source.
- Substance of the code: `guesses.parse` drops exactly the trailing empty lines and keeps the array contiguous, as the removed `table.remove` loop did. In `depsFirst`, `taken[at]` and `met[id]` mark the same entries `placed[id]` did when ids are distinct, so each pass picks what it picked before; a pass always finds an entry while one is not taken, so `#issues` passes place every entry once, a repeated id included. The diff holds nothing the design does not name.
- Substance of the tests: the scan case fails on main's loops (M9), the repeated-id case runs in a bounded child and compares the whole output, and AC1's merge-base line fails when a loop is listed instead of rewritten (E6).

### F1 [low] The trace cell for d0413:P4 cited the wrong line for Usability
Where: z-nile/.tracker/rafts/active/R0132/trace.md, row `d0413:P4`, design cell
Evidence: the cell read `z-nile/.tracker/issues/active/d0413/d0413.md:67 (Usability)`. Line 67 of d0413.md is "New: `z-nile/.tracker/issues/d0413/acceptance/loops.spec.luau` (promoted to …)", under Affected specs. The Usability text that answers P4 ("`./zn finish` and the full gate stop failing on the scan for every raft") is line 59. `./zn trace R0132 --check` passed with the wrong line, so the tool does not catch it.
Critique: a reader following the table lands on a line that says nothing about `finish`. The tempting fix is to leave it, since the check is green.
Consequences: none. The cell's other citation (line 37) was right, and the claim is met.
Recommendation: I corrected the cell to `d0413.md:59 (Usability)` in `trace.md`; commit that edit with this review. Nothing else to change.
Erred: zz-execute
Upstream: none

Verdict: approve
