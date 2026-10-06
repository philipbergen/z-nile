# Review 001: R0033 (code mode)
Inputs: e123e21 (after `scripts/tracker.sh sync --fetch`, synced to 6a50c11); `git diff origin/main...HEAD`; R0033.md and check.sh; c0063.md, check.sh, `acceptance/narrowed.spec.luau`, `experiments/narrowing.patch`; f0031.md (the dated note) and f0031's check.sh; R0034.md, `experiments/{prototype,c0063-narrowing}.patch` and f0065's acceptance specs. Runs: `scripts/check.sh --full` GATE PASSED (1371 passed, 195 files); `scripts/tracker.sh check c0063` 2/2 PASS; `scripts/tracker.sh check R0033` 4/4 PASS; the sequestration diff shows only three `R100` renames.

What I checked:
- **Diff against the patch.** The diff to `tests/acceptance/f0031/` is byte-identical to `experiments/narrowing.patch` once `index` and `@@` lines are ignored, and that patch is identical to R0034's `experiments/c0063-narrowing.patch` (the one E2 ran with the prototype).
- **Diff against the design table, row by row.** Every row is done as the table says:
  - overlay: the constants line goes; ready and play are per-field (banner, detail, fade, flash); the three prompt lines go; three cases are deleted and the `View` require is dropped.
  - adapter: the three-remote loop is kept; two cases are deleted and `fs` is dropped; the two `toBe(1)` become `<= 1`, and the per-call shape check (sender's own `tostring(x.UserId)`) still runs on any call left; the phase case is unchanged.
  - place: `setCursor` is matched to any field; FlowView keeps "requires Flow" and `:FireServer(`.
  - presentation-run: the three `playAgain` lines go, and the results-stay-up check now uses banner and detail.
  - Every file has its `Narrowed by c0063:` header. No row is weakened beyond what the table says, and no case outside the table changed.
- **Dropped guards against f0065.** Every guard that is dropped and should still hold after f0065 is pinned again, in its new form, by f0065's sequestered specs:
  - keys, and no movement key is a continue key: `results.spec` "Return and KeypadEnter are the continue keys, and no movement key is one".
  - prompt only at game over: `results.spec` "only game over has a prompt …".
  - remote present: `place.spec` "the remotes are Ready, Intent, Snapshot, ToLobby and LobbyStatus …".
  - handler takes only the sender: `returns.spec` "only the sender goes …" and "what the client sends … is ignored".
  - FlowView fires on Flow's keys: `place.spec` "FlowView sends ToLobby with no arguments, on a tap or Flow's continue keys …".
  - Beta structure: `place.spec` "the Beta runtime structure check asserts the new remotes …".
  - cursor field: `place.spec` "Main asks Flow … and frees the mouse by the overlay".
- **Interim gap.** Until R0034 lands, nothing pins the PlayAgain remote. The raft's Risks section records this (design review 001 F3), so I don't count it as a finding.
- **Kept needles against the prototype.** In R0034's prototype, Sessions reads no `.phase` or `gameover` (`isOver` lives in Logic's Session), `Camera.setCursor(overlay.cursor)` matches the narrowed pattern, and FlowView still calls `:FireServer()` with no arguments.
- **Repository safety.** The diff only removes reads and assertions from text-reading specs (the `fs` require is removed, not added). No new write path, and no fence, hook or `ac.sh` change.
- **Logic of playing again.** f0016, f0017, f0018, f0023 and f0030 pin it, and none of them is touched.

### F1 [low] The verification log's gate count is the pre-narrowing baseline, but reads as the result of step 3
Where: tracker/issues/active/c0063/c0063.md, Verification log
Evidence: the log ends "Gate (`scripts/check.sh --full`, at the claim): … 1376 passed in 195 files". On e123e21, `scripts/check.sh --full` reports 1371 passed in 195 files. The narrowing deletes exactly five cases (overlay: 3, adapter: 2), and 1371 + 5 = 1376. So the logged number is the gate before the patch, while the sentence before it describes steps 1 to 3 (apply, stylua, check) as done.
Critique: a reader who compares the log with a later gate sees five cases vanish without explanation. The tempting fix is to just swap the number for 1371.
Consequences: none beyond the doc. The `--full` count is not used by `tracker.sh done` or metrics.
Recommendation: in the log, give both numbers: "1376 passed at the claim (before the patch); 1371 passed after it (5 cases deleted by the narrowing, as designed)".

## Judged criteria (code mode only)
None.

Verdict: approve
