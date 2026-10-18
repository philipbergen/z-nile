# Review 005: R0037 (design mode)
Inputs: worktree at dbe2da5 plus the uncommitted prep files: tracker/rafts/R0037/{R0037.md,check.sh,design-review-001..004.md,design-refute-001..004.md}, tracker/rafts/R0037/experiments/{overlap.luau,prototype.patch}, tracker/issues/d0105/{d0105.md,check.sh}, tracker/issues/d0105/acceptance/{radar,adapter}.spec.luau; src/shared/Logic/Hud/init.luau, src/client/DangerHud.luau, src/client/HudView.luau. I applied prototype.patch, then ran `stylua --check` on both patched files (clean), `bash tracker/issues/d0105/check.sh` (4/4 pass), `overlap.luau` (E1 pass), and the place, c0002, f0019, f0031, f0033 and unit Hud specs (110 passed, 0 failed). I ran six mutants against `adapter.spec` plus f0033 `adapters`, then `git checkout -- src`. src is clean.
Dropped from review-004: F1 (fixed).

Round-4 finding: F1 is fixed. The placement case now finds the three lines as one contiguous block directly after `RenderStepped:Connect(function()\n`, on the comment-stripped source, and requires exactly one `radar.Position` and exactly one `local view =`. On the prototype each of round 4's mutants fails that case on an assertion (`10 passed, 1 failed`, with f0033 still green):
- MA, the `Position` write moved to after the guard;
- MG, `local view` hoisted to before `Connect`;
- MH, `local view = Vector2.new(1920, 1080)`;
- MI, a second `radar.Position` written after the guard.
I also tried a new one, MD: the block moved into a dead top-level function, so the live step never places the radar. It is killed too, because it needs a second `local view =`.

The fix adds no state and no runtime rule. It only pins three lines' spelling and position. The documents give those lines verbatim. The Rules table has a `run` row for each of the four mutants, and E3 records them. stylua leaves the block unchanged, so the tab indentation in the needle is stable. The `\t\t` body indent also ties the `Connect` to the top level of a function body, which is why nesting the block inside an `if` fails.

What I checked and found no hole in:
- Reassigning `view` later in the step (MV, `view = Vector2.new(...)` without `local`) passes. It only runs after the write, so it cannot move the radar. It could only affect the arrows, which this raft leaves alone (Non-goals).
- Geometry: `HudView` sizes from `camera.ViewportSize`, and `DangerHud` reads `gui.AbsoluteSize` with `IgnoreGuiInset` true. Both are the full screen, so `layout` gets the same inputs. The bar's scale-1 bottom in the inset-respecting `HudView` gui is still the screen bottom, so the gap of one margin holds.
- Overrides: `scripts/affected` lists the specs the issue names. Of those, only f0033 `adapters` reads `DangerHud`, and it doesn't pin the corner. `Overrides: none` is right.
- Repository safety: the specs only read the place model, and `check.sh` only runs `tests/run`. Neither writes anything.

Verdict: approve
