# Review 001: R0051 (code mode)
Inputs: HEAD 56a860f4 (branch R0051-touch-fire-and-hop), origin/main 411403e9 after `./zn sync --fetch`, merge base e8efb175; `git diff origin/main...HEAD`; R0051.md and its check.sh, f0110.md, its check.sh and acceptance specs (buttons, fold, adapters, hunt); pickman `.tracker/architecture.md` and `game-design.md`. Main's commits since the merge base touch only tracker and lesson files, none of the raft's code.

Runs (by this reviewer, on 56a860f4):
- `./zn check f0110`: 6/6 criteria passed.
- `bash "$(./zn find R0051)/check.sh"`: 4/4 passed (RC0 full pickman gate, RC0 f0110, RC0 promote-check, RC1 the hunt spec from its sequestered path). Exit 0.
- Sequestration: `git diff --find-renames=100% --name-status origin/main...HEAD -- 'tracker/**/check.sh' 'tracker/**/acceptance/**' '*/.tracker/**/check.sh' '*/.tracker/**/acceptance/**'` lists only `M pickman/.tracker/rafts/active/R0051/check.sh`. That is the user-approved fix recorded in R0051's "Addressed during execution" (2026-10-26). It changes one line, `F0110_SPECS="$ZN_ROOT/$F0110/acceptance"` to `F0110_SPECS="$PWD/$F0110/acceptance"`, plus a trailing comment. The fix is correct: from `pickman/`, `../zn find f0110` prints `.tracker/issues/active/f0110`, which is relative to the project home that `ac.sh` changes to, so `$PWD/…/acceptance` exists before promotion. After promotion, the existing `[[ -d ]]` fallback still finds `tests/acceptance/f0110`. No other sequestered file changed, and f0110's check.sh and acceptance specs are untouched.
- A Lune probe of the unit spec's synthetic boxes (400×300, 844×390, 390×844, margin 5): the fire button is raised on all three (fire.y 176/266/720 against hop.y 210/300/754). This is the evidence for F1.

### F1 [low] The unit case "level with the hop button unless…" never reaches the level branch, and it asserts the implementation's own formula
Where: pickman/tests/unit/Touch/touch.spec.luau, the case "the fire button is level with the hop button unless that reaches the snap control's band"
Evidence: on all three synthetic boxes `Touch.fireRect` takes the raised branch (probe above). The first assertion is `fire.y == math.min(hop.y, snap.y - box.margin - hop.w)`, which copies `Touch.fireRect`'s expression. The second (`fire.y + fire.h <= snap.y - margin or fire.y == hop.y`) follows from the first, so it adds nothing. A mutant that always raises the button (dropping `math.min`'s first argument) passes this unit case.
Critique: this costs no acceptance coverage. `buttons.spec` (AC1) pins the level placement on the 1080×1920 and 1920×1080 samples and kills M7, so the gate still catches the mutant. The unit case only claims coverage it lacks. The tempting fix is to add one large box, which still leaves the case restating the formula.
Consequences: none beyond the unit file. It is not sequestered, so the author may edit it.
Recommendation: add a box where the level branch holds (for example 1920×1080 with margin 5, if the probe shows level there). Assert the observable rule rather than the expression: on that box `fire.y == hop.y`, on a raised box `fire.y + fire.h == snap.y - box.margin`, and on both `fire.y <= hop.y`. Alternatively, drop the case and rely on `buttons.spec`.

## Judged criteria (code mode only)
None (f0110 has no Judged criteria; OC1 is Observed, for the user on a phone).

Other checks, with no finding:
- Correctness: `Touch.zone` keeps its four-argument meaning (fire and hop nil). The half-open `inside` helper handles a nil rectangle. The order is snap, fire, hop, then the halves. A button finger is recorded with its zone, so `taken` limits each zone to one finger, its moves emit nothing (only `look` emits), and its lift only clears it. `Touch.track` still clones state. `Hud.jumpButtons` always returns rows (`JUMP.small` or `JUMP.large`), so `[1]` is safe. `Touch.fireRect` matches the Design's formula.
- Controls: the hook is read on every touch event. `placed and placed.fire` passes nil when there is no hook or no layout yet. One local `fire()` serves both E and the fire effect, with the same guard as before (no keys or no aim sends nothing). The hop effect sends `Hop.INTENT`. There is no new remote and no new require.
- HudView: the `Fire` (CYAN, FIRE) and `Hop` (WHITE, JUMP) frames are built as the Design says (`Active = false`, `Visible = TouchEnabled`, transparency 0.6, a disc corner, a `Caption` through `label()` with a full black outline). The caption is kept beside its frame, with no `FindFirstChildOfClass`. `lay` computes `Touch.buttons(l)` from the inset layout once per layout. `HudView.buttons()` is nil before the first layout.
- Main: the fifth argument `HudView.buttons`.
- Architecture: the `Touch -> Hud` edge and Touch's row are already in `architecture.md`, and Hud requires only Levels and Session, so there is no cycle. Logic stays engine-free (AC6). The server stays authoritative: the buttons send the existing intents.
- Performance: nothing new per frame. There are three more rectangle tests per touch event, and the buttons are computed only per layout.
- Repository safety: no new script. The only check.sh change is the spec path, which reads under the home's `.tracker`.
- Lessons: assert-between-press-and-release, new-controls-get-inset-and-turn-cases, drawn-from-the-visible-root and pin-call-site-arguments are met by the sequestered specs. The new lesson `z-design/check-paths-from-the-home` is one a different raft could fail, so it is not a restated finding.

Verdict: approve
