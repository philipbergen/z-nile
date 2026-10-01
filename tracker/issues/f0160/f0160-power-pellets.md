---
id: f0160
type: feature
title: Power pellets
raft: R0090
depends_on: [f0150, f0170]
emergent: false
design: reviewed
created: 2026-09-28
slug: power-pellets
---

# f0160: Power pellets

## Problem
The four power pellets are worth 50 (f0150) and start a frightened period. The ghosts' reaction belongs to raft d, but the period itself belongs here: a per-level length from the `Levels` table, a countdown that only runs while the run is being played, a `PowerStarted` event, and a timer that restarts when another power pellet is eaten.

## Non-goals
- Ghost behaviour while frightened, ghost scoring 200/400/800/1600, flashing (f0200 and f0220). Flashes are in the `Levels` table already; nothing reads them yet.
- HUD and drawing (R0130).

## Solution
- `Game.power(g)` sets `frightened` to the level's frightened ticks (restart, never add) and returns `PowerStarted`. `Game.step` counts it down in `playing` only and emits `PowerEnded` on reaching zero. A death or a cleared level cancels it silently.
- `Session` calls `Game.power` when a power pellet is eaten (from f0150's eating path). `Frame.play.frightened` already exists (f0170); now it is live.
- A whole-run end-to-end spec plays the rules half of the game headless.

## Design

### Decisions made in prep
- **Duration** is `Levels.frightenedTicks(level, 30)`: 180 ticks on level 1, 150 on level 2, …, 30 on level 9. It is **0 on levels 17, 19 and 20 and from level 21 on**, but **level 18 has 1 s (30 ticks)** (design review F1; Table A.1). Where it is 0 the pellet still scores and stalls and `PowerStarted{ticks = 0}` is still reported (raft d needs it: ghosts reverse on every energizer, even when they don't turn blue), but no frightened time runs and no `PowerEnded` follows.
- **Frightened player speed** (user, 2026-09-30, review F4): while `frightened > 0 ` at the **start** of a tick, the player moves at `Levels.playerSpeed(base, level, true)` (34 units on level 1, 36 on 2–4, 38 on 5–20). Same rule as `moving`, so the step that eats the energizer is still a normal one, the next step is the first fast one, and the step on which `PowerEnded` is reported is the last fast one. The eating pause is computed at the speed of the tick the dot was eaten in (17 units for a dot eaten while frightened on level 1, as the arcade's slower "fright dots" speed).
- **Restart, not extend**: a second power pellet sets the counter back to the full period.
- **Only counts down in `playing`.** It is reset to 0 on death and on a cleared level (no `PowerEnded` event: the period did not run out, it was cancelled). While `ready`, `dying`, `levelclear`, `gameover` the counter is always 0, so "only runs down while playing" is an invariant rather than a separate rule.
- The per-tick order in `Game.step` is: decrement, then `PowerEnded` on zero, so a period of N ticks shows N at the tick of eating and ends N steps later.

### `Game` additions
```lua
function Game.power(g: Game): { Event }      -- PowerStarted { ticks, level }; frightened = Levels.frightenedTicks(level, tickRate)
-- Game.step (playing): frightened > 0 → frightened -= 1; hits 0 → PowerEnded { level }
-- Game.died / Game.cleared: frightened = 0 (already in f0170)
```
### `Session` additions
In the eating path: `if kind == "power" then applyGame(Game.power(play))`. The `PowerStarted` event is appended with the player id, `ticks` and `level`. `Session.Event` already has `ticks`. In `step`, `frightened = m.play.frightened > 0` is read at the start of the tick (before `Game.step`) and picks the speed column; f0170 already built `Levels.playerSpeed(…, frightened)` and the `Session.new` guard over both columns, so this issue only passes the flag.

### Scalability
One integer per player, one event per power pellet.

### Maintainability
The period length is data in `Levels`; raft d's ghosts read `frightened` from the frame/game and the `PowerStarted`/`PowerEnded` events, so this issue's API is what they consume.

### Usability
For the player nothing visible until ghosts exist; for developers the whole run is testable headless (`full-run.spec`).

### Touched modules
- `src/shared/Logic/Game`
- `src/shared/Logic/Session`
- `tests/unit/Game`

### Affected specs
`lune run scripts/affected -- src/shared/Logic/Game src/shared/Logic/Session tests/unit/Game` prints the same set as f0170's. New: the two acceptance specs.

## Unknowns & experiments
- **E1 (run in prep: PASS)**: the countdown semantics: a 180-tick period eaten at tick 14 shows 180 at tick 14, 179 at tick 15, 1 at 193, and ends at 194 with `PowerEnded`; a second pellet eaten at tick 14 after a first at tick 6 shows 173 just before and 180 after. All pass on the prototype.
- **E2 (run in prep: PASS)**: the whole-run spec (ready → eat → clear → level 2 → three deaths → game over → play again) and its determinism pass on the prototype, and `Session.kill` is the only route to a death.
- **E4 (run in prep: PASS)**: the frightened-speed numbers against an independent Python model on a 57-tile corridor: energizer eaten at tick 2, steps of 34 through tick 182 (`PowerEnded` at 182), then 30; with the slowdown on, dots eaten at 7 and 11 and positions 60/83/185/202/321 at ticks 3/4/7/8/12. The prototype matches; `power.spec` pins them.
- **E3 (mutation check, run)**: mutants G8 (death keeps the period), G9 (extends instead of restarts), S15 (frame frightened not wired), S17 (no period on a power pellet), L6 (level 17 frightens) and G14 (a cleared level keeps it) all killed. G10 (counts down outside play) is **equivalent**: `frightened` is 0 outside `playing` by construction.

## Regression guard
f0150's specs (eating and scoring of power pellets) must keep passing: they never use `Game.power`, and only compare `PelletEaten`/score. `frame.spec` (f0170) pins `frightened` as a number, now live.

## Test plan
- `power.spec.luau` → AC1: `PowerStarted` ticks and payload, the frame countdown, `PowerEnded`, restart, per-level lengths including 0, cancellation on death/clear, determinism.
- `full-run.spec.luau` → AC2.
- **The executor's own specs**: add a `Game.power` case to `tests/unit/Game`.

### Rules and mutants
| rule | spec :: case | mutant it kills | checked |
|---|---|---|---|
| a power pellet starts the level's period | power :: eating a power pellet reports PowerStarted… | no period started | run |
| the period is the level's (L1 180, L2 150, L9 30, L17 0) | power :: the period is the level's | wrong level row / level 17 frightens | run |
| the countdown shows in the frame | power :: the frightened time shows in the frame… | frame field hard-wired to 0 | run |
| it ends after exactly N ticks with PowerEnded | power :: it ends after exactly that many ticks | off by one / no event | run |
| restart, not extend | power :: a second power pellet restarts… | adds to the remaining time | run |
| death cancels it | power :: a death or a cleared level… | period survives death | run |
| a cleared level cancels it | power :: a death or a cleared level… | `Game.cleared` leaves the period running | run |
| runs down only in play | power :: the period only runs down while the run is in play | counts down in dying | reasoned: equivalent mutant, it was run and nothing can fail: the counter is already 0 outside play (recorded as E3) |
| no period where the time is 0 (17, 19, 20, 21+), but `PowerStarted{ticks = 0}`; no PowerEnded | power :: with no frightened time…; the period is the level's | ends a period that never began | run |
| level 18 has 1 s | power :: the period is the level's (18 → 30); level 18's single second… | hard-coded `level >= 17 → 0` | run |
| fast while frightened, normal after | power :: the player runs at the frightened speed… | frightened speed unused; speed read after the game step | run |
| a dot eaten while frightened costs 17 | power :: a dot eaten while frightened costs 17 units | pause computed at the base speed | run |
| whole run works and is deterministic | full-run :: both cases | any of the above broken | run |

## Acceptance criteria

### Checked
- **AC1**: Eating a power pellet reports `PowerStarted` (player, level, `ticks` = the level's frightened ticks: 180, 150, 120, 90, 60, …, 30 at level 9, 30 at level 18, 0 on levels 17, 19, 20 and from 21), the frame's `play.frightened` counts down one per tick while playing, `PowerEnded` comes exactly when it reaches zero, a second power pellet restarts the full period, a death or a cleared level cancels it without `PowerEnded`, where the time is 0 no `PowerEnded` follows, the player runs at the frightened speed for exactly the period (34 units against 30 on level 1; a dot eaten meanwhile costs 17), and it is deterministic per seed.
- **AC2**: A whole run plays headless through `Session`: the countdown, eating pellets and a power pellet, clearing level 1, level 2 with its own speed (its first step covers 34 units) and frightened time (180 then 150), three deaths, game over, and play again starting fresh; two runs with the same seed give the same frames.

### Judged
None.

### Observed
None in this issue (nothing visible until ghosts in raft d).

## Implementation steps
1. `Game.power` and the countdown in `Game.step`; add unit cases. Run AC1's Game-level cases. Commit.
2. Wire `Session`'s eating path to `Game.power`. Run AC1. Commit.
3. Run AC2; `scripts/check.sh --full`; `scripts/tracker.sh check f0160`. Commit.

## Verification log
