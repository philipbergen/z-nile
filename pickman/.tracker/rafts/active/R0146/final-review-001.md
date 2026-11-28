# Review 001: R0146 (final mode, light path)
Inputs: `origin/main` at `6b7b2e030`, branch `R0146/1/c0196` at `8214ed470` (finish commit `be0c16ee2`), `git diff origin/main...HEAD`, `pickman/.tracker/rafts/active/R0146/{R0146.md,trace.md}`, `pickman/.tracker/issues/active/c0196/{c0196.md,check.sh,results.txt}`, `./zn capture c0196` (`6c7316afd`), `./zn guesses R0146` (`0 guesses, not approved`), `pickman/tests/unit/Hud/{picks-ring.spec.luau,picks-ring.watch.txt}`, `pickman/src/shared/Logic/{Awareness,Hud,Touch}/init.luau`, `pickman/src/client/{HudView,DangerHud}.luau`, `pickman/tests/acceptance/{f0147/hud,f0158/clear,f0158/ring}.spec.luau`.
Checks run: `z-nile/check.sh --affected` (GATE PASSED, 2/2 in `picks-ring.spec.luau`, 0 lint errors/warnings), `./zn check c0196` (1/1 PASS), `lune run z-nile/watch-check`, `./zn audit`, `./zn skills --check`, `./zn lessons --check`, `./zn trace R0146 --check` (`ok: R0146`).

## Light-path and trace summary
- **Level and Short note**: `c0196` is genuinely `easy` (adds only `pickman/tests/unit/Hud/picks-ring.spec.luau` and `picks-ring.watch.txt`; no `src/` code, guard, gate, data move, or promoted spec touched). `c0196.md` Problem, Non-goals, and Solution match `./zn capture c0196` (`6c7316afd`); `### Short note` includes all five required parts (`Problem`, `Change`, `Files`, `Test`, `Risk`), and `AC1` matches `Test:` and `check.sh:12`. The `Risk:` line misses the test weakness in F1.
- **Sequestration and Overrides**: `Overrides: none`. `git diff --find-renames=100% --name-status origin/main...HEAD -- 'tracker/**/check.sh' 'tracker/**/acceptance/**' '*/.tracker/**/check.sh' '*/.tracker/**/acceptance/**'` is empty. `lune run z-nile/affected -- pickman/tests/unit/Hud/picks-ring.spec.luau` selects only itself, and `grep -rnF -e "picks-ring" -e "picksBox" pickman/tests/acceptance` lists only `pickman/tests/acceptance/f0147/hud.spec.luau`, which is untouched.
- **Repository safety and bounded commands**: Pure Luau spec with no file I/O, git, process, or network calls; `check.sh:12` runs only `lune run tests/run -- tests/unit/Hud/picks-ring.spec.luau`.
- **Trace (`trace.md`)**: Filled at `be0c16ee2` and passes `./zn trace R0146 --check` (`ok: R0146`). `c0196:AC2` (`None.`) and `c0196:AC3` (`None.`) are vacuous rows derived from empty `### Judged` and `### Observed` sections. `c0196:P1`, `c0196:S1`, and `c0196:AC1` cite `picks-ring.spec.luau`, whose weak-test gap is F1 below; `c0196:S2` cites `check.sh:12` since both `f0147` and `f0158` are in `done/`. No source files changed (`## Source files` has no data rows; all `code` cells are `none`).

### F1 [medium] picks-ring.spec.luau passes an empty indicator list (0 sectors lit) and makes no assertion on the ring dots, so an empty or zero-size Awareness.ring passes vacuously
Where: `pickman/tests/unit/Hud/picks-ring.spec.luau:89, 108-113` (`c0196.md:26, 32`)
Evidence: `c0196.md:26` (`## Solution`) and `c0196.md:32` (`### Short note`) require checking `Hud.picksBox(Touch.blocks(l).score)` against `Awareness.ring` "at full extent (every sector lit)", and `picks-ring.spec.luau:98` titles the cases `overlaps no lit danger-ring dot`. Yet `fullRingDots` (`picks-ring.spec.luau:89`) calls `Awareness.ring({}, fw, fh)` with an empty list, and the loop (`picks-ring.spec.luau:108-113`) makes zero assertions on dot count, `d.lit`, or dot dimensions. Verified by running in Lune (`pickman`): `Awareness.ring({}, 1280, 720)` returns 48 dots with `0` lit (`lit == false` on all 48); stubbing `Awareness.ring` to return `{}` or 48 `0x0` dots (`d.w = 0, d.h = 0`) still passes `picks-ring.spec.luau` 2/2.
Critique: While today's `Awareness.ring` returns the same 48 boxes whether `list` is empty or full, passing `{}` leaves no dot lit and asserts nothing on the ring output, so a future change that omits unlit dots from `Awareness.ring`, drops a sector, or returns empty/zero-size dots would pass this spec silently.
Consequences: Passing 8 `"normal"` indicators (one per sector `0..7` at `bearing = k * math.pi / 4`, `distance = 0`, `look = "normal"`, `inView = true`) exercises the lit ring (`48/48` lit dots, verified in Lune) without depending on `Awareness.ring` emitting unlit dots, and asserting `#dots == Awareness.SECTORS * Awareness.RING.dots`, `d.lit == true`, and `d.w > 0 and d.h > 0` ensures an empty or zero-size ring fails loudly. Note that `pickman/tests/unit/Hud/picks-ring.watch.txt` will be refreshed by `./zn finish c0196`.
Recommendation: In `fullRingDots`, pass 8 `"normal"` indicators covering sectors `0..Awareness.SECTORS - 1` (`distance = 0`, `inView = true`) to `Awareness.ring(allSectors, fw, fh)`, assert `#dots == Awareness.SECTORS * Awareness.RING.dots` (`48`) per screen, and assert `d.lit == true and d.w > 0 and d.h > 0` for every dot before checking `overlaps(d, picks)`.
Lesson: zz-test/no-vacuous-pass
Erred: zz-test
Upstream: z-design

### F2 [low] picks-ring.spec.luau duplicates the test under (desktop) and (touch) with unused touch and device bindings
Where: `pickman/tests/unit/Hud/picks-ring.spec.luau:11, 34, 45, 52, 59, 66, 73, 96-100` (`pickman/.tracker/issues/active/c0196/results.txt:2-3`)
Evidence: `type Screen` defines `device: Inset?` and sets `device` on 6 of the 15 `SCREENS`, never reading `s.device`. Lines `96-120` iterate `for _, touch in { false, true } do` and interpolate `{if touch then "touch" else "desktop"}` in the case title, but never use `touch` inside the callback (`Hud.layout(s.width, s.height, core)`, `Touch.blocks(l).score`, `Hud.picksBox(...)`, and `fullRingDots(s)` execute identically twice), producing two duplicate case lines in `results.txt:2-3`.
Critique: Copied from `pickman/tests/acceptance/f0158/clear.spec.luau` (where `touch` and `device` feed `Hud.radarBox` and `Touch.buttons`), the loop gives the appearance of separate desktop and touch coverage while actually re-running the exact same Logic calls twice.
Consequences: Neither `Hud.picksBox` nor `Awareness.ring` takes a `touch` flag, and `HudView.luau:75-92` and `DangerHud.luau:142-164` place `Picks` and `Ring` identically regardless of `UserInputService.TouchEnabled` (already pinned to Logic by `f0147/hud.spec` and `f0158/place.spec`; a `tests/unit/` spec cannot load `@tests/lib/fakeengine` per `pickman/tests/meta/tiers.luau:100-108`). `SCREENS` already includes both desktop (`desktop 1280/1024/2560`, `touch desktop`) and touch screens/insets (`notched phone`, `small phone`, `old phone`, `tablet-sized portrait`), so a single unit case covers every desktop and touch sample without a dead loop.
Recommendation: Remove the unused `device` field from `Screen` and `SCREENS`, replace `for _, touch in { false, true } do` with a single case covering all 15 f0158 desktop and touch sample screens/insets (with a comment noting `Hud.picksBox` and `Awareness.ring` do not vary by `TouchEnabled`), and re-run `./zn finish c0196` so `results.txt` reflects the single case.
Lesson: zz-test/no-vacuous-pass
Erred: zz-execute
Upstream: z-idea

### F3 [low] c0196.md Verification log is blank after finish and trace skeleton
Where: `pickman/.tracker/issues/active/c0196/c0196.md:59-60`
Evidence: `## Verification log` still contains only `<!-- Appended at the end of execution: date, commands run, results. -->` after finish commit `be0c16ee2` and trace skeleton commit `8214ed470`.
Critique: `zz-execute` Phase 2 step 4 and Phase 5 step 1 require appending verification commands and results before `./zn finish` and before committing `trace.md`, because `z-nile/engine/trace.luau:501-518,655-664` forbids editing `c0196.md` after `trace.md`.
Consequences: Updating `picks-ring.spec.luau` for F1 requires re-running `./zn finish c0196` and regenerating `trace.md` anyway; filling `## Verification log` before `./zn finish c0196` keeps `trace.md` valid (`--check` passes) without extra commits.
Recommendation: Append the date, commands run (`z-nile/check.sh --affected`, `./zn check c0196`), and results under `## Verification log` in `c0196.md` before re-running `./zn finish c0196` and regenerating `trace.md`.
Erred: zz-execute
Upstream: none

## Judged criteria
None (`c0196` defines no Judged criteria).

Verdict: changes
