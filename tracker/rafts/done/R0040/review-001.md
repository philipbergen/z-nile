# Review 001: R0040 (code mode)
Inputs: branch R0040-barebones-game at 5cf2a7b (`git diff main...HEAD`); R0040, f0100, f0110, f0120 and f0130 documents, check.sh files and acceptance specs; the architecture, testing and tracker skills.

What I ran:
- `scripts/check.sh --full` passes (158 specs, 28 files, types, build).
- `tracker.sh check` passes for f0100 (4/4), f0110 (9/9), f0120 (7/7) and f0130 (6/6). The raft's `check.sh` passes 8/8: RC0, promote-check, RC1 and RC2.
- Sequestration: `git diff da41e5a -- 'tracker/**/check.sh' 'tracker/**/acceptance/**'` is empty.
- A throwaway fuzz outside the tree ran random play on the classic maze at speeds 1, 7, 29, 30, 31, 45, 59, 60, 61, 90, 119 and 120, with 30 seeds × 1,500 ticks each. It checked these invariants: centreline, occupied tile walkable, `Entered` ⇔ occupied change, `Wrapped` ⇔ position jump, the distance bound, stopped ⇒ on a centre, and heading never into a wall mid-tile. The only violations were the ones in F1 (14 ticks).

Where the implementation matches the design: I read `Movement.step` line by line against f0110's "exact order", and it matches in every step. The following all match their designs as well:
- the grace/missed/buffer branch order and the `exitHere`, on-centre guard, `prevExitDistance` and `nextExitDistance`;
- the `run` and `leftCentre` bookkeeping and buffer ageing;
- `Session`: the submit check order, the per-tick queue cap, `jumpTick` on `Wrapped`, and the `advance` epsilon and backlog drop;
- `View.interpolate`, `approachYaw`, `look` and `walls`/`bounds`;
- the thin server adapter.

A mid-tile `Back` on the half-tile tie (progress 60) is not a problem: `Back` always sets `moving = true`, so the player always leaves the tie in the same step, and the `Entered` it produces is a genuine re-entry.

### F1 [high] `Wrapped` (and so `jumpTick`) fires on ticks where the position does not jump: a `Back` that crosses the seam and then moves back across it in the same step
Where: `src/shared/Logic/Movement/init.luau:160` and `:210` (`wrapped = wrapped or w`, as f0110's step pseudocode says). The effect shows up in `src/shared/Logic/Session/init.luau:102-103`.

Evidence: reproduced at the default config (`speed = 30`) on the classic maze:
- Put the player on `(0,14)`, heading W and moving. After one step, `position` is `(-0.25, 14)`, with `tile = (0,14)` and `progress = 30`.
- The next step is `Back`:
  - `tile` becomes `(27,14)`, which wraps, and `progress` becomes 90;
  - the advance reaches `U` and steps to `(0,14)`, which wraps again;
  - `position` is `(0, 14)`, a continuous 0.25-tile move, but the events are `{Wrapped}`.
- `Back, Back` in one step at `(27,14)` E, progress 30 (position 27.25), also emits `Wrapped` (plus `Entered`). The two reversals cancel, and the position moves on to 27.5 without any jump.
- The fuzz found the same pattern at speeds 29, 31, 45, 59, 60 and 90 (for example `27.5 → 27` and `-0.75 → 0` with `Back`).

This breaks f0110 AC6 ("a `Wrapped` event occurs exactly on the ticks where the position jumps, including a reversal on the seam") and AC7. It also breaks the `Event` contract ("position() jumped by a maze width/height this step"). The sequestered specs pass because none of them reverses within one step's distance of the far side of the seam. `tunnels.spec`'s `wrapsMatchJumps` would catch it if it did.

Downstream, `Session` sets `jumpTick`, so `View.interpolate` refuses to lerp for that tick and the camera pops by up to one step, 2 studs, instead of sliding. Later consumers that treat `jumpTick` as a teleport get a false positive.

Fix: seam crossings within one step alternate in sign, so track parity rather than "any": `wrapped = wrapped ~= w` at both sites. Record this as a deviation from f0110's pseudocode. Add a unit spec in `tests/unit/Movement` for both scenarios above: a `Back` one tick past the edge centre toward the seam, and a double `Back` next to the seam. Each should expect no `Wrapped` and assert that `wrapsMatchJumps` holds.

### F2 [low] A snapshot with a new maze id builds a second maze and never removes the first
Where: `src/client/Main.client.luau:16-20`, and `src/client/MazeView.luau:57`, whose returned Model is discarded.

Evidence: f0130's Maintainability claims "it builds on the snapshot's `maze` id, so a second layout needs no client change". But if the server ever sends `maze = "b"` after `"classic"`, `MazeView.build` parents a second `Maze` model into `workspace`, and the classic walls stay where they are, overlapping the new ones. a2 has only one layout, so nothing fails today. The first multi-layout raft would inherit overlapping geometry.

Fix: keep the returned Model in `Main`, and `Destroy()` it before building the next one. That's one more nil guard, still inside JC1's "maze already built" category. Alternatively, drop the claim from the design.

## Judged criteria (code mode only)
- JC1 (f0130: the client adapters are thin): **pass**. Every conditional in `src/client/*.luau`, against the rubric:
  - `Camera.luau:19`, `if latest == nil or snap.tick > latest.tick then`: the out-of-order snapshot guard in `Camera.push` (with its first-time nil half). Allowed.
  - `Camera.luau:42`, `if snap == nil then return end`: the "no snapshot yet" nil guard. Allowed.
  - `Camera.luau:47`, `yaw or target`: the first-snapshot guard, so the view doesn't spin. It's an expression-level nil guard. Allowed.
  - `Controls.luau:18`, `if state == Enum.UserInputState.Begin then`: the Begin check. Allowed.
  - `Controls.luau:20-22`, `if action == "Snap" then onSnap() elseif action then intent:FireServer(action) end`: dispatching Snap versus an intent, where `elseif action` is the nil guard for keys with no action. Allowed.
  - `Main.client.luau:17`, `if built ~= snap.maze then`: the "maze already built" guard. Allowed.
  - `MazeView.luau` has no conditionals. Its loops iterate `View.walls(m)` and `Maze.tiles(m, "door")`, which are Logic results, so the adapter doesn't choose tiles.

  The key meaning (`View.action`, `View.KEYS`), angles (`headingYaw`, `approachYaw`, `turnRate`, `look`, `snap`), interpolation (`View.interpolate`), geometry (`View.walls`, `bounds`, `world`, `SCALE`) and pitch clamping are all `View` calls. The adapters' own arithmetic falls into two groups:
  - Conversions of `View` numbers into `Vector3`/`CFrame`, all specified in the f0130 Design: the rect centre and length in `MazeView`, `wallHeight / 2`, the ±0.5-tile floor extent, and the −0.5 floor centre.
  - The design-specified alpha, `(os.clock() - arrived) * Session.TICK_RATE`, and `turnRate() * dt`.

  There's no wrapping, clamping, lerp, key table or tile selection in the adapters. Total adapter size is well under RC1's 350 lines.

Verdict: changes
