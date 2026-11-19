# Review 001: R0132 (code mode)
Inputs: f13a1b9bd (layer 1, d0413) against origin/main 962cf7472 (`git diff origin/main...HEAD`); R0132.md and its check.sh; d0413.md, its check.sh, acceptance/loops.spec.luau, acceptance/watch.txt, prototype.patch, results.txt.

What was checked:
- The code diff in `z-nile/engine/guesses.luau` and `z-nile/engine/raftplan.luau` matches `prototype.patch` line for line (compared with `diff`). The prototype is what prep's E2 to E6 ran.
- Correctness, read through by hand:
  - `guesses.parse`: walking `for at = #lines, 1, -1` and setting `lines[at] = nil` from the end keeps the array contiguous, and it stops at the first line that is not empty. That is the same as the old `table.remove` loop. `gmatch` on `norm .. "\n"` always gives at least one line.
  - `depsFirst` with distinct ids: `taken[at]` and `met[id]` mark the same entries that `placed[id]` did, so each pass picks the same entry. The ring fallback is still "the first entry not taken". Its comment calls this "lowest id" and that holds, because `plan` hands `depsFirst` a list sorted by `byId`.
  - `depsFirst` with a repeated id: each pass takes exactly one entry, so `pick` is never nil before `#issues` passes. Traced by hand: `{A(dep B), B, B}` gives `B, A, B` and the loop ends.
  - `pick: number?` is narrowed inside `if pick`. The gate's luau-lsp stage passed.
- Sequestration: the name-status diff lists only `A z-nile/.tracker/issues/active/d0413/acceptance/watch.txt`. This is the file `./zn finish` generates, not an edit to a sequestered file (lesson `zz-review/finish-watch-is-generated`). It names exactly the layer's two source files. No spec and no `check.sh` changed.
- Runs:
  - `./zn check d0413`: 5/5.
  - `z-nile/check.sh --affected`: GATE PASSED, z-nile `113 passed, 0 failed, 14 spec files`.
  - `stylua --check` and `selene` on both files: clean.
  - `./zn promote-check R0132`: OK.
  - By path: `tests/meta/scanning-loops` 1 passed, `c0193/tree` 5 passed and `c0185/selector` 2 passed. `c0120/check-paths` and `c0371/check-paths-homes` each fail one case, on c0411's `check.sh`. This branch does not touch that file, and the same reds are on origin/main.
- Repository safety: the only new process is the spec's `hostile.bounded(10, …)` child, which writes only under `.cache/d0413-dup`. No guard file was touched. Nothing is left unbounded.
- Architecture: both functions stay pure. No signature changed and no dependency edge was added.

### F1 [low] The Verification log leaves `c0185/selector` recorded as a red only this branch has, with no later run showing it green
Where: z-nile/.tracker/issues/active/d0413/d0413.md:161 (Verification log, step 3)
Evidence: The log says `c0185/selector` was "red on this layer … green on origin/main". Implementation step 3 says "a red only on the branch is a stop". The log gives the cause: the unpromoted acceptance spec had no `watch.txt` before `finish` wrote one. That is correct. But no line records that the red went away once `./zn finish d0413` wrote `acceptance/watch.txt`. The reviewer reran it at f13a1b9bd: `tests/acceptance/c0185/selector.spec.luau: 2 passed, 0 failed`. As written, the record shows a branch-only red that step 3 treats as a stop, which nothing then clears.
Critique: A reader of the done issue (the final review, `./zn trace`, a later executor using this log as a model) sees a branch-only red that was passed over on an explanation alone. The tempting fix is to soften step 3's wording. That would be an edit to the design's document, and the stop rule is right as it stands.
Consequences: none. This is one appended line. The underlying gap, where a layer's unpromoted acceptance spec is selected for every path until `finish` writes its watch file, is d0297's, which is active in R0131.
Recommendation: Append one line to the Verification log saying that after `./zn finish d0413` wrote `acceptance/watch.txt`, `tests/acceptance/c0185/selector.spec.luau` gave 2 passed, 0 failed, so no branch-only red remains. Candidate lesson for the lead (zz-execute): when a red that only the branch shows comes from the layer's own unfinished state, rerun it after `finish` and record that result before you move past step 3's stop. The check is: "Is every branch-only red in my log followed by the run that shows it gone?"
Erred: zz-execute
Upstream: none

## Judged criteria (code mode only)
The issue has no Judged criterion.

Verdict: approve
