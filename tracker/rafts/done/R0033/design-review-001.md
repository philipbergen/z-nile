# Review 001: R0033 (design mode)
Inputs: prep worktree at f62ab36 plus uncommitted `tracker/rafts/R0033/{R0033.md,check.sh}`, `tracker/issues/c0063/{c0063.md,check.sh,acceptance/narrowed.spec.luau,experiments/narrowing.patch}`; `tests/acceptance/f0031/*`, `tracker/issues/done/f0031/{f0031.md,check.sh}`; R0034 `experiments/prototype.patch`, the `proto-game-over-to-lobby` worktree diff, and f0065's acceptance specs in `prep-game-over-to-lobby`.

Spot runs, in a `--no-hardlinks` clone under the scratchpad (no tripwire, no `REPOSITORY CHANGED`):
- Unpatched: `narrowed.spec` gives 1 pass and 5 fails, all on assertions (the wiring is right).
- With `narrowing.patch`: `stylua --check` passes, and `narrowed.spec` plus the four f0031 specs give 34 passed (confirms E1).
- With `prototype.patch` and the narrowing: `narrowed.spec`, the four f0031 specs and `c0003/scripts.spec` give 37 passed (confirms the f0031 part of E2).
- The prototype's f0031 diff is byte-identical to `narrowing.patch`, apart from the index lines, and its `c0063/acceptance` is identical to the prep's.

Override check: grepping `tests/acceptance` outside f0031 for `PlayAgain|playAgain|PLAY_AGAIN|setCursor|FlowView|structure.luau` finds only Logic's `Session.playAgain`/`Game.playAgain` (f0016, f0017, f0018, f0023, f0030; kept by f0065), f0018's raw-intent rejection list, and c0003's structure needles, which don't name `PlayAgain`. So nothing outside the four files blocks f0065. f0065's own `place.spec` pins `Camera.setCursor(<x>.cursor)` and `:FireServer()`, so loosening those here loses no guard once R0034 lands.

### F1 [high] AC1 passes when the kept cases are gutted: the narrowing pins case names, but not their bodies
Where: `tracker/issues/c0063/acceptance/narrowed.spec.luau:67-149`; c0063 Regression guard ("What stays true is still pinned"); Rules and mutants row 3
Evidence: on the patched clone I applied three mutants that keep every case name and every pinned needle:
- In `overlay.spec`, the body of "dying shows no banner" became `t.expect(o ~= nil).toBe(true)`.
- In `place.spec`, the two assertions of "Camera no longer locks the mouse unconditionally" became `t.expect(camera ~= nil).toBe(true)`.
- In `presentation-run.spec`, "a play-again request outside game over changes nothing on screen" lost both its `ok == false` and its `toEqual(before)`.

`narrowed.spec` still passed 6/6, and the f0031 specs still pass, so AC1 and AC2 are green. The needle lists cover only some cases. Nothing checks the bodies of "play shows nothing" (banner/detail nil), "dying shows no banner", "the level-clear pause has no banner or fade" (its `o.fade).toBe(0)` counts toward the ">= 3", but its banner nil does not), "the place keeps its Ready, Intent and Snapshot RemoteEvents", "Main computes Flow.overlay with … GAME_CONFIG", the cursor lock and cursor flag cases, "Main starts every adapter before it signals Ready", "FlowView uses the Flow feature" (its `includes(... logic("Flow"))`), or the second presentation-run case. The Regression guard says each of these is "still pinned".
Critique: AC1 promises "still assert what stays true", and a wrong execution (an over-eager narrowing, or a hand edit instead of `git apply`) passes it. The tempting fix is more needles. That stays partial and grows a long, brittle list that is easy to leave incomplete.
Consequences: a stronger pin makes `narrowed.spec` (promoted permanently as `tests/acceptance/c0063/narrowed.spec.luau`) stricter about f0031's text. Any later chore that narrows f0031 again must also narrow c0063's spec. That is already true for the case-name lists, so this adds a duty but not a new kind of one. A byte-for-byte pin of the four files would also break on a pure stylua reformat.
Recommendation: pin the number of assertions per case. Map each case name to the count of `t.expect(` in its body after stripping comments (split the code at each `it(`), compare the whole table with `toEqual`, and take the counts from the patched files. One table per file replaces most of the ad hoc needles and kills every gutting mutant, since each removes or merges an assertion. Keep the existing needles for the narrowed lines (`calls <= 1`, `found <= 1`, the `setCursor` pattern, the results-stay lines), because a count alone can't tell a narrowed assertion from a rewritten one. Add Rules and mutants rows "a kept case's body gutted, name kept" (overlay dying, place cursor lock, presentation-run second case), mark them `run`, record them under E3, and add a line to `narrowed.spec`'s header saying a future narrowing of f0031 updates these tables.

### F2 [medium] f0031's check.sh labels and its ACs will report as passing things that are no longer asserted
Where: `tracker/issues/done/f0031/check.sh` (AC1, AC2 and AC4 labels); `tracker/issues/done/f0031/f0031.md:205` (AC2) and AC1/AC4; c0063 Design ("f0031's check.sh is unchanged")
Evidence: after c0063 the gate (and every later `tracker.sh check f0031`, which c0063's AC2 runs) prints PASS for:
- `AC2: a PlayAgain remote that the server relays to Session.playAgain for the sender's own session`
- `AC1: … GAME OVER and the play-again prompt`
- `AC4: … game over, play again`

The specs behind them no longer check any of that. After f0065 lands, the remote is gone and AC2 still says PASS.
Critique: a Checked criterion that matches no real check is exactly what design mode item 2 guards against. A reader of check output, or of the done document, is told the play-again surface is guarded. Relabelling during execution isn't possible: the code-mode sequestration diff (`'tracker/**/check.sh'`, only R100 allowed) would flag it as high.
Consequences: editing a done item's `check.sh` and document is legitimate for a narrowing chore (ticket-prep section 3 lets c "drop the line naming it from the owning item's `check.sh`"). It has to happen in this prep commit. `narrowed.spec`'s first case checks only the `"$A/<name>.spec.luau"` arguments, so a relabel doesn't break it. RC1 already allows `tracker/` changes.
Recommendation: in prep, relabel f0031's AC1, AC2 and AC4 checks to what the narrowed specs pin (for example `AC2: the server stays thin: any Session.playAgain call is the sender's own, and no phase is read`). Below f0031's Acceptance criteria, add a dated note: "Narrowed by c0063 (2026-10-xx): the PlayAgain remote, handler, keys and prompt are no longer pinned; f0065 replaces them." Don't rewrite the historical AC text. Optionally, have `narrowed.spec`'s first case assert that the f0031 check.sh no longer contains `PlayAgain` or `play-again prompt`. Update c0063's Design line "f0031's check.sh is unchanged" to match.

### F3 [low] Between c0063 and f0065, main's PlayAgain wiring has no guard
Where: R0033 Risks & rollback
Evidence: after c0063 lands, and until R0034 does, nothing promoted checks that `Remotes.PlayAgain` exists, that Sessions handles it, or that FlowView fires it on Flow's keys. The deleted cases are "Sessions listens to PlayAgain", the remote and Beta-structure cases, and the `"PlayAgain"`/`PLAY_AGAIN_KEYS` needles in place. A regression to the shipped play-again flow in that window goes uncaught. Only `tests/unit/Flow` still pins the keys.
Critique: this is the accepted cost of narrowing first. It just isn't named.
Consequences: none beyond scheduling.
Recommendation: add a Risks line, "the play-again wiring is unguarded until R0034 lands; start R0034 right after R0033 is done, and don't merge other changes to `FlowView`, `Sessions` or the remotes in between". Rerun E2 if R0034's design changes, as the Risks section already says.

### F4 [low] The promoted `narrowed.spec` is a lasting pin on another item's spec text, and the affected selector never picks it
Where: `narrowed.spec.luau` (promoted to `tests/acceptance/c0063/`)
Evidence: it reads the f0031 specs with `fs.readFile` and requires nothing from them. So `scripts/check.sh --affected` doesn't select it when an f0031 spec changes; only `--full` does. It also pins the exact case lists for good.
Critique: a future chore narrowing f0031 sees only a `--full` failure, in a spec whose purpose (guarding this one narrowing) has passed.
Consequences: none if documented.
Recommendation: say in `narrowed.spec`'s header that it pins c0063's narrowing for good and that any later change to `tests/acceptance/f0031` must update it. Optionally, add c0063's own spec to the Affected specs section next to the four f0031 specs, so the Override check of a future issue that greps `tests/acceptance` for `f0031` finds it (the `renamed.id("f0031")` spelling already makes that grep match).

Verdict: changes
