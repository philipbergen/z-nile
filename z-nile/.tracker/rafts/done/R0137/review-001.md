# Review 001: R0137 (code mode)
Inputs: `git diff 9c78a02bb...HEAD` at 08f8ec16d (layer 1, d0416; origin's main is 9c78a02bb, read with `git ls-remote`), d0416.md, d0416's check.sh, acceptance/ (narrow.py, nested-second-review.spec.luau, watch.txt), experiments/prototype.patch, guesses.md, R0137.md and its check.sh

What I checked:
- Layer equals the prototype: the control-cli hunks of the diff and `experiments/prototype.patch` are the same, line for line, down to the blob ids (`64a44fb15..b5fc0b79e`). No engine, helper or other spec file changes.
- The pin on this layer: `./zn run --time 60 -- python3 -I .../narrow.py "$PWD"` answers "the stale base 9c78a02b with exactly the three d0416 hunks", exit 0.
- The pin after landing, in a throwaway clone under my scratch folder with a bare origin: main at this HEAD gives "landed base ... unchanged"; one more empty commit on main still passes; a squash landing (base plus one commit holding the new file) passes; a branch on the landed main that turns `"stalled"` into `"failed"` is refused at line 426. After promotion check.sh falls back to `tests/acceptance/d0416`, and AC5's grep leaves out `--exclude-dir=d0416`, so the promoted narrow.py, which names the file, does not turn AC5 red. `./zn promote-check R0137`: OK (2 passed).
- The edited case still proves what it proved: a quiet nested reviewer, started by a real `z-design` author step under the same limits as c0095 (`tool_seconds = 8`, `stall_seconds = 8`), ends `stalled`. The `n == 1` line stops the case from reading the author's own state when no reviewer ran. The first half (heartbeat, `review=0`, `bashmax`) is byte for byte as before. `lune run tests/run -- --slow tests/acceptance/c0117/control-cli.spec.luau`: 24 passed, 0 failed. `nested-second-review.spec.luau`: 5 passed, 0 failed.
- watch.txt: it names `z-nile/engine/dispatch.luau` and `z-nile/engine/dispatcher.luau` (plus the four helpers the spec requires), which is what the design's Maintainability section says. That is the zz-test rule for a layer that changes no source file: it watches what its spec requires. `./zn finish` changed no other watch file, which is right: control-cli sits inside `tests/acceptance/c0117/`, so it is covered by c0117's ticket watch and gets no `<stem>.watch.txt`, and c0117's watch only lists source files, none of which this layer changes.
- Sequestration: `git diff --find-renames=100% --name-status 9c78a02bb...HEAD` over the check.sh and acceptance globs lists only `A .../d0416/acceptance/watch.txt` (the file finish generates). check.sh, narrow.py, nested-second-review.spec.luau and prototype.patch are blob-identical to the prep commit 3400d2661. The move into `active/` is R100 in 9c78a02bb.
- Nothing beyond the design: the other files in the diff are tracker files (spend rows, the Verification log line, the empty results.txt that finish wrote). Repository safety: no spec, check.sh or script in the diff writes outside a fixture. narrow.py only reads (ls-remote, cat-file, merge-base, show).

### F1 [low] The Verification log's gate result is blank and points at a session scratch file instead of saying what ran
Where: z-nile/.tracker/issues/active/d0416/d0416.md, Verification log, the R0137 layer 1 line ("... dispatch-guards), gate . The whole output is kept in the session's scratch file `d0416-finish.txt`.")
Evidence: the sentence "gate ." has no result. The layer's `results.txt` is committed empty (0 bytes). The reason: `lune run z-nile/affected -- --project z-nile --own-acceptance <the layer's paths>` selects only `tests/acceptance/c0117/control-cli.spec.luau`. That spec is in `tests/slow.tsv`, and `z-nile/specs` without `--slow` leaves it out (specs.luau line 6), so finish's gate ran no spec. The log points the reader at `d0416-finish.txt` in the session's scratch folder, which nobody can open after the session ends.
Critique: a reader cannot tell "the gate passed" from "the gate ran nothing" (the second is what happened). The empty results.txt also matters later. The final review's trace cannot cite a spec case for AC2 or AC3, because `trace --check` passes a spec cell only when results.txt lists it. Those rows have to cite the `check "ACn:` lines of check.sh, which `./zn check` ran green. The tempting fix is to type "gate passed" into the blank, which hides the same fact.
Consequences: none beyond the wording. The trace rows citing check.sh lines are already allowed by `trace.luau` (a check command line of a finished issue).
Recommendation: replace the blank with what ran. For example: "finish's affected gate selected only control-cli, which is slow-tier, so it ran no spec and results.txt is empty; control-cli ran with `--slow` under AC2 (24/24)". Quote the counts from the finish output in the log itself instead of pointing at the scratch file. Leave the empty results.txt as finish wrote it, and when trace.md is filled, cite check.sh's AC lines for d0416's test cells.
Lesson: zz-execute/measure-from-a-kept-copy
Erred: zz-execute
Upstream: none

## Judged criteria (code mode only)
- JC1: pass. d0416 has no Judged criteria ("None."); nothing to rule on.

Verdict: approve
