# Review 001: R0037 (code mode)
Inputs: HEAD 801fed5 against origin/main b0f3ea9 (`scripts/tracker.sh sync --fetch`); `git diff origin/main...HEAD` (`src/shared/Logic/Hud/init.luau`, `src/client/DangerHud.luau`, d0105 verification log, spend files); R0037.md and its check.sh; d0105.md, its check.sh, `acceptance/radar.spec.luau` and `acceptance/adapter.spec.luau`; `src/client/HudView.luau`; the review, architecture, testing and tracker skills.

What I ran:
- `bash tracker/rafts/active/R0037/check.sh`: 4/4 PASS. That covers the full gate, d0105's check.sh, promote-check and RC1.
- Sequestration: `git diff --find-renames=100% --name-status origin/main...HEAD -- 'tracker/**/check.sh' 'tracker/**/acceptance/**'` printed nothing.
- Mutant: I changed `radarBox`'s bottom inset to `barHeight + margin` (one margin instead of two). `radar.spec` went to 5 of 7 failing. I restored the file with `git checkout`.

Correctness: I checked `radarBox` by hand against the golden boxes and the empty-size corner at `{1264, 675}`. It matches the Design, line for line. The power bar and the radar measure the same screen, so they agree:
- `HudView` builds its layout from `camera.ViewportSize` and pins the bar to the bottom of a ScreenGui that keeps the default inset. The inset only moves the top edge, so the bar's bottom is the screen's bottom.
- `DangerHud`'s ScreenGui sets `IgnoreGuiInset = true`, so its `AbsoluteSize` is the whole viewport.

A zero `AbsoluteSize` on the first frame gives a box off the screen for one frame. The next step fixes it, so it is harmless. The placement runs before the snapshot guard, as the Design says.

Architecture: the adapter only copies a pure result onto the frame. `DangerHud -> Hud` is an adapter requiring a Logic feature through `@game/ReplicatedStorage`, which is legal. The diff adds no Logic edge and does not touch `architecture.md`.

Performance: each frame allocates two small tables and one `UDim2`. The Design accepts that cost, and it is small next to the tables the step already builds.

Repository safety: the diff has no spec, check.sh or script.

### F1 [low] The touch jump-button conflict is deferred to f0029, but f0029 does not record it
Where: d0105.md, Non-goals ("The touch jump button, and safe-area insets ... Both belong to f0029"); `tracker/issues/f0029`.
Evidence: on touch devices, Roblox's default jump button sits in the bottom-right corner. That is where the radar now goes (x = width - 136 and up, y about 165 to 285 px above the bottom at 1280×720). In the old top-right spot the two could not collide. `rg -i "jump|radar|safe"` on f0029's documents finds only its general "safe-area-aware layout rules" line. Nothing there mentions the jump button or the radar.
Critique: the deferral is a decision, and it lives only in a d0105 sentence. Whoever preps f0029 will read f0029 and may never see it. The obvious fix is a note in d0105, but d0105 already says it.
Consequences: f0029 then has to place two bottom-right elements (the radar and the power bar) around the jump button. It may need `radarBox` to take an inset, or a mobile corner.
Recommendation: capture the conflict where f0029 will see it. Use make-issue for a backlog note, or edit f0029's Problem if the tracker skill allows that in this PR. Name the radar and the power bar together, so f0029's specs cover both. This does not block the PR.

## Judged criteria (code mode only)
None.

Verdict: approve
