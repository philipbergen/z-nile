# Review 002: R0040 (code mode)
Inputs: branch R0040-barebones-game at b19997a (`git diff main...HEAD`); review-001.md and refute-001.md; R0040, f0100, f0110, f0120 and f0130 documents, check.sh files and acceptance specs; the architecture, testing and review skills.
Dropped from review-001: none. F1 and F2 were answered `fixed` in 4148b8d, and both fixes are verified below.

What I ran:
- `scripts/check.sh --full` passes (160 specs, 28 files, types, build).
- `tracker.sh check` passes for f0100 (4/4), f0110 (9/9), f0120 (7/7) and f0130 (6/6). R0040's `check.sh` passes 8/8 (RC0 ×6, RC1, RC2).
- Sequestration: `git diff da41e5a -- 'tracker/**/check.sh' 'tracker/**/acceptance/**'` is empty (da41e5a is `tracker: start R0040 Barebones game`).
- A throwaway fuzz outside the tree ran 600,000 steps: 200 seeds × 600 ticks on each of five mazes. The mazes were the row tunnel (`"  P  "`), the vertical shaft (`"#.#","#P#","#.#"`), a fully open 6×6 grid that wraps on every row and column, a 5×5 lattice with tunnels on both axes, and classic. Each seed used a random speed in 1..120 and a random buffer window. Half the steps carried 1–4 intents, and half of those intents were `Back`. It checked that `Wrapped` ⇔ the position jumped (|Δx| > width/2 or |Δy| > height/2), and that the unwrapped displacement never exceeds 2·speed/U + 1 tiles. There were 55,522 `Wrapped` steps and 0 violations. With `~=` put back to `or` in a scratch copy of Logic, the same fuzz reports 24,248 violations, so it would have caught the bug.

F1 fix, parity (`wrapped = wrapped ~= w`, `Movement/init.luau:160,210`), argued case by case:
- **Seam crossings in one step all lie on one axis.**
  - Intents can wrap only through a mid-tile `Back`. A grace turn needs `leftCentre`, and `Back` clears it, so no grace turn can follow a `Back` in the same step. Every `Back` that wraps is therefore on the axis of the last heading.
  - Movement reaches at most one centre per step, because `speed ≤ U` and the first centre is `U − progress` away. So movement wraps at most once, along the post-intent heading.
- **The crossings alternate in sign.**
  - A wrapping `Back` from `(0,y)` W lands on `(w−1,y)` E. The only next crossing is E over the same seam, and it's opposite in sign. The mirror case, and the vertical axis, work the same way.
  - A non-wrapping `Back` keeps the player on the same side of the seam.
  - Parity is therefore exactly "net jump ≠ 0".
- **Specific cases:**
  - A `Back` on the seam alone (speed 1, or at the progress-60 tie) still reports `Wrapped`. For example, −0.25 → 27.758 at speed 1.
  - A `Back` followed by movement back across the seam reports nothing.
  - `Back, Back` and `Back ×3` + movement cancel.
  - Vertical tunnels behave like horizontal ones (shaft, lattice and open grid in the fuzz).
- **Downstream:**
  - `Session.step` sets `jumpTick` only on a real jump now.
  - `View.interpolate` snaps when `jumpTick > prev.tick`. That's still right when several snapshots arrive in one frame, since `Camera.push` keeps the immediately previous one and ticks are consecutive: the backlog drop in `Session.advance` shortens a frame's steps but never skips a tick.
  - The seam cases above now lerp the 0.25-tile slide instead of popping.
- **New unit specs:** the two cases in `tests/unit/Movement/movement.spec.luau` fail under `or` and pass under `~=`. The positive case (a `Back` that does jump) stays covered by `tunnels.spec`.
- **Deviation:** recorded, with a reason, in f0110's Verification log.

F2 fix: `Main.client.luau` keeps the built `Model` and destroys it before building a layout with a new maze id. It's correct, and it adds one nil guard.

What else I looked for and didn't find:
- **Server authority:** `Sessions` passes `raw: any` straight to `Session.submit`, which validates with `isIntent` and caps the queue per tick. A repeated Ready is ignored, and `PlayerRemoving` drops the session.
- **Clock:** `Session.advance` handles NaN or non-positive dt, the epsilon, and the backlog drop.
- **Maze validation:** the open-edge rule on both axes, and reachability.
- **Rendering:** `View.walls` and `bounds` periodic margins, and `approachYaw` at exactly π.
- **Camera:** the `Camera.push` ordering guard.
- **Performance:**
  - per-step table allocations in `Maze.neighbor`, `occupied`, `players` and the queue swap are small and bounded;
  - the f0120 bench (50 players × 60 s) passes well inside budget;
  - one snapshot per player per tick is as designed.

## Judged criteria (code mode only)
- JC1 (f0130: the client adapters are thin): **pass**. Every conditional in `src/client/*.luau`, against the rubric:
  - `Camera.luau:19`, `if latest == nil or snap.tick > latest.tick then`: the out-of-order snapshot guard in `Camera.push`, with its first-time nil half. Allowed.
  - `Camera.luau:42`, `if snap == nil then return end`: the "no snapshot yet" nil guard. Allowed.
  - `Camera.luau:47`, `yaw or target`: an expression-level first-time guard. Allowed.
  - `Controls.luau:18`, `if state == Enum.UserInputState.Begin then`: the Begin check. Allowed.
  - `Controls.luau:20-22`, `if action == "Snap" then onSnap() elseif action then intent:FireServer(action) end`: dispatching Snap versus an intent, where `elseif action` is the nil guard for an unmapped key. Allowed.
  - `Main.client.luau:18`, `if built ~= snap.maze then`: the "maze already built" guard. Allowed.
  - `Main.client.luau:20`, `if model then model:Destroy() end` (new in 4148b8d): a first-time nil guard ("no model built yet"). It decides nothing a test could check. Allowed.
  - `MazeView.luau` has no conditionals. Its loops iterate `View.walls(m)` and `Maze.tiles(m, "door")`, which are Logic results.

  Positions (`View.interpolate`, `world`), angles (`headingYaw`, `approachYaw`, `turnRate`, `look`, `snap`), geometry (`walls`, `bounds`, `SCALE`) and key meaning (`View.action`, `View.KEYS`) are all `View` calls. The adapters' remaining arithmetic is one of two kinds:
  - conversion of `View` numbers into `Vector3`/`CFrame`: the rect centre and length, `wallHeight / 2`, the ±0.5 floor extent and the −0.5 floor centre;
  - the design-specified alpha `(os.clock() - arrived) * Session.TICK_RATE`, and `turnRate() * dt`.

  There's no interpolation, wrapping, clamping, tile choice or key table in the adapters.

Verdict: approve
