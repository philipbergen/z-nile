---
id: f0120
type: feature
title: Game session server
raft: R0040
depends_on: [f0110, c0390]
emergent: false
design: ready
created: 2026-09-28
---

# f0120: Game session server

## Problem
Each player needs their own maze instance ("solo mazes"), simulated authoritatively on the server at a fixed tick. Intents arrive over remotes, and state is replicated only to the client that owns it.

## Non-goals
- Ghosts, pellets, score, lives, game flow and hiscores (later rafts add fields to the session and the snapshot).
- Matchmaking, and several players in one maze. The API is keyed by player id so that's possible later, but a2 uses one player per session.
- Client prediction: the client renders server state, interpolated (f0130). Prediction is future work if latency feels bad.
- Unreliable remotes. Snapshots use a reliable `RemoteEvent` for now, and `jumpTick` makes the client robust to missing snapshots anyway.

## Solution
- A pure `Session` feature: one maze instance with players, a validated and rate-limited intent queue, a fixed-tick `step` that returns events, a versioned snapshot, and the server's fixed-step clock.
- A thin server adapter, `src/server/Sessions.luau`: it creates a session per joining player, forwards remote intents to `Session.submit`, steps every session on `Heartbeat` through the clock, and sends each player their own snapshot.
- Characters are disabled, and the remotes are declared in `default.project.json`.

## Design

### Decisions made in prep
- **Tick rate**: **30 Hz**.
- **The server places no geometry.** It only simulates. Each client builds its own maze locally at the world origin (f0130), so no player ever sees another's maze and no spatial offset is needed. With `Players.CharacterAutoLoads = false` there is no physics body to place.
- **Snapshot schema v1** is extensible: later issues add top-level fields and bump `v` only on an incompatible change.
- **Ready handshake** (decided by the user, 2026-09-29, after design-review-002 F4): the server creates and joins a player's session only when that client fires `Remotes.Ready`, which it does after it is listening for snapshots. So no simulated time passes before the player can see it. Later rafts' ghosts and timers can't act on an unseeing player.
- **One snapshot per player per step**, sent only to its owner.
- **Rate limit**: at most **4** queued intents per player per tick. More are refused with `"rate limited"`. Humans press at most a few keys per tick; the cap bounds server work under spam.
- **Clock**: at most **5 steps per frame**. A longer frame (a server hitch) drops the backlog instead of spiralling.

### `src/shared/Logic/Session/init.luau`
```lua
local Maze = require("./Maze")
local Movement = require("./Movement")

export type PlayerId = string
export type Config = { movement: Movement.Config, maxIntentsPerTick: number }
export type PlayerSnapshot = {
	x: number, y: number,         -- Movement.position: continuous tile coordinates
	heading: Maze.Heading,
	moving: boolean,
	jumpTick: number,             -- tick of the latest position discontinuity for this player, -1 if none
}
export type Snapshot = { v: number, tick: number, maze: string, player: PlayerSnapshot }
export type Event = { kind: string, player: PlayerId, x: number?, y: number? }  -- a Movement event plus the player id
export type Session = {           -- `tick` is public read-only; the other fields are internal
	tick: number,                 -- steps completed (time t in the sim harness)
	...
}
export type Clock = { rate: number, maxSteps: number, acc: number }

Session.TICK_RATE = 30
Session.SNAPSHOT_VERSION = 1
Session.MAX_STEPS_PER_ADVANCE = 5
Session.DEFAULT_CONFIG: Config        -- frozen { movement = Movement.DEFAULT_CONFIG, maxIntentsPerTick = 4 }

function Session.new(maze: Maze.Maze, seed: number, config: Config?): Session   -- validates config
function Session.join(s: Session, id: PlayerId)          -- spawns at the maze spawn; errors "already joined"
function Session.leave(s: Session, id: PlayerId)         -- idempotent
function Session.players(s: Session): { PlayerId }       -- sorted
function Session.submit(s: Session, id: PlayerId, raw: any): (boolean, string?)
function Session.step(s: Session): { Event }
function Session.snapshot(s: Session, id: PlayerId): Snapshot   -- fresh tables; errors "unknown player"
function Session.newClock(rate: number?, maxSteps: number?): Clock   -- defaults TICK_RATE, MAX_STEPS_PER_ADVANCE
function Session.advance(c: Clock, dt: number): number   -- whole steps to run now
```
- **`new`**: `tick = 0`, no players. `config` defaults to `DEFAULT_CONFIG`. It errors (message naming the field) if `Movement.validateConfig` fails or `maxIntentsPerTick < 1`. `seed` is stored for later rafts (ghost randomness). It's unused in a2 but part of the API now, so the sim model's `new(seed)` never changes shape.
- **`submit`** checks, in this order:
  1. unknown player → `false, "unknown player"`;
  2. `not Movement.isIntent(raw)` → `false, "invalid intent"`;
  3. queue full → `false, "rate limited"`;
  4. otherwise it appends to that player's queue and returns `true, nil`.
  - Anything a client sends goes through this, and nothing else from the client is trusted.
- **`step`**:
  1. `tick += 1`.
  2. For each player in `players(s)` order: take and reset the queue, then call `Movement.step(maze, move, queue, config.movement)`.
  3. For each returned event, append `{ kind, player = id, x, y }`. On `Wrapped`, set that player's `jumpTick = tick`.
  - **`jumpTick`** means any position discontinuity: the client must not interpolate across it (design-review-001 F9). In a2 the only discontinuity is a tunnel `Wrapped`. **Every later teleport must set it too**: a respawn after a death (f0170), a level reset, or a rejoin.
  - It returns all events in player order. **Sim tick semantics**: intents submitted before step k (so in the harness, intents at k) act in step k, and the events are visible at time k+1 = the new `tick` (c0090).
- **`snapshot`** builds new tables every call:
  - `v = SNAPSHOT_VERSION`, `tick = s.tick`, `maze = maze.id`;
  - `player`: `position()`, `heading`, `moving` and `jumpTick`.
  - It's JSON-safe and has only string keys, so it survives a `RemoteEvent` unchanged.
- **`advance`**:
  - `dt` that is NaN or ≤ 0 → 0.
  - Otherwise `acc += dt` and `n = floor(acc * rate + 1e-9)`. The epsilon makes 60 frames of 1/60 give exactly 30.
  - If `n > maxSteps`: `acc = 0` and return `maxSteps`.
  - Else `acc = max(0, acc - n / rate)` and return `n`.

### Server adapter: `src/server/Sessions.luau` (ModuleScript) and `Main.server.luau`
```lua
-- Sessions.luau (sketch; about 40 lines in the prep prototype)
local Maze = require("@game/ReplicatedStorage/Shared/Logic/Maze")        -- c0390: cross-root requires use @game
local Session = require("@game/ReplicatedStorage/Shared/Logic/Session")
function Sessions.start()
	Remotes.Ready.OnServerEvent(player) -> if sessions[player] == nil then sessions[player] = Session.new(Maze.layout(Maze.DEFAULT), player.UserId); Session.join(s, tostring(player.UserId)) end
	Players.PlayerRemoving    -> sessions[player] = nil
	Remotes.Intent.OnServerEvent(player, raw) -> if sessions[player] then Session.submit(s, id, raw) end   -- result ignored
	RunService.Heartbeat(dt)  -> for _ = 1, Session.advance(clock, dt) do for player, s in sessions do Session.step(s); Remotes.Snapshot:FireClient(player, Session.snapshot(s, id)) end end
end
```
- **`Main.server.luau`** becomes `require("./Sessions").start()`, keeping its comment header.
- **The adapter holds no decisions.** Validation, rate limiting, stepping and clock maths are all `Session` calls.
- **No `PlayerAdded` handler is needed**: sessions start on `Ready`. A repeated `Ready` is ignored (the nil guard), so a client can't reset its own session.
- **A connected client's session is never replaced** (design-review-002 F7). Later rafts reset the world (death, level clear, play again) inside the same `Session`, so `tick` keeps increasing and `jumpTick` marks the jump. f0130's `Camera.push` relies on ticks never going backwards for one connection.
- **`default.project.json`**:
  - add `"Players": { "$properties": { "CharacterAutoLoads": false } }`;
  - under `ReplicatedStorage`, add `"Remotes": { "$className": "Folder", "Ready": { "$className": "RemoteEvent" }, "Intent": { "$className": "RemoteEvent" }, "Snapshot": { "$className": "RemoteEvent" } }`.
  - Both are declarative, so `tests/place` can check them (E1).

### Scalability
- **Per tick, per player**: one `Movement.step`, one snapshot of about 6 fields (about 100 bytes), and one `FireClient`.
- **Replication**: about 3 KB/s per player at 30 Hz, sent only to the owner.
- **CPU**: prep measured about 0.9 µs per player-tick in Lune (50 players × 1,800 ticks = 0.08 s). That's roughly 0.05 ms per tick for a full server, against a 33 ms tick budget. AC6 pins it at 4 s, a 50× margin.
- **Memory**: one session per player. The frozen classic maze is shared.

### Maintainability
- **Teleports**: any later feature that moves a player other than by `Movement.step`, such as a respawn or level reset, sets `jumpTick = tick`, so the camera cuts instead of sliding through walls.
- **The snapshot has one schema** in shared Logic, used by both the server (producer) and the client (consumer), so they can't drift. Later issues add top-level fields: pellets (f0290), game state (f0300), ghosts (f0310), score, lives and level (f0180).
- **New world state** (ghosts, pellets) goes into `Session` and its `step`. The adapter doesn't change.
- **N players per maze later**: the state is already keyed by `PlayerId`, and `step` iterates `players()`.

### Usability
- **For the player**: inputs apply on the next server tick (≤ 33 ms plus network), in order. Spam can't starve the server.
- **For developers**: the whole session is a sim model in five lines (see `acceptance/tick.spec.luau`), which is how AC3 and later rafts test the game headless.

### Touched modules
- `src/shared/Logic/Session`
- `src/server`
- `default.project.json`
- `tests/unit/Session`
- `tests/scenario`

### Affected specs
`lune run scripts/affected -- src/shared/Logic/Session src/server default.project.json tests/unit/Session tests/scenario` prints `ALL`, because a `default.project.json` change forces a full run. New specs: `tests/unit/Session/*.spec.luau`, optionally a scenario story, and the seven acceptance specs.

## Unknowns & experiments
- **E1 (run in prep: PASS)**: Can Rojo 7.7 declare `Players.CharacterAutoLoads = false` and the RemoteEvents in `default.project.json`?
  - Method: add them in a scratch worktree, run `rojo build`, and load the place with `@lune/roblox`.
  - Result: `CharacterAutoLoads false`, and `Remotes` is a Folder with `Intent` and `Snapshot` RemoteEvents.
- **E4 (run in prep: PASS)**: Is the per-tick cost small enough?
  - The prototype `Session` with the AC6 "busy" model took 0.079 s for 50 × 1,800 steps, three runs within 1%.
  - The busy player was moving 1,754 of 1,801 ticks.
- **E6 (run in prep: PASS, with c0390)**: Can the server adapter require Logic in a way the gate accepts?
  - Relative paths can't satisfy both the disk graph and the place, which is c0390's Problem.
  - With `@game/ReplicatedStorage/Shared/Logic/...`, the gate's luau-lsp check (Roblox definitions and sourcemap) reported no errors in the prototype `Sessions.luau`.
  - With the c0390 prototype, the meta and c0020 place rules pass.
- **E3 (run in prep: PASS)**: The prototype passes all seven Session specs. The mutation check caught:
  - rate limit off by one;
  - snapshot aliasing internal state;
  - `jumpTick` never set;
  - the clock keeping its backlog past the cap;
  - the clock without the epsilon.
- **Residual unknown (Observed, OC1)**: runtime behaviour in the engine: `@game` requires, the `Ready` handshake, `PlayerRemoving` and `FireClient`. It can only be checked in Studio.

## Regression guard
- **The c0020 place rules**: `Sessions.luau` must be a ModuleScript under `ServerScriptService.Server`, and every require must resolve in the place. That depends on c0390 being merged.
- **`tests/place/structure.spec.luau`**: `Server.Main` stays a Script.
- **Meta**: `Session -> Maze` and `Session -> Movement` are declared in prep, and `tests/unit/Session` must exist.
- **Movement's (f0110) specs**: `Session` only calls its public API.

## Test plan
The acceptance specs already exist.
- **`acceptance/lifecycle.spec.luau`** → AC1. Cases:
  - initial state;
  - join, spawn and sorting;
  - double join;
  - idempotent leave;
  - rejoin;
  - independence of players and of sessions;
  - config validation.
- **`acceptance/intents.spec.luau`** → AC2. Cases:
  - the four accepted;
  - junk rejected;
  - unknown player;
  - per-player limit and reset;
  - default limit 4;
  - rejected intents have no effect;
  - submission order;
  - `Back` twice.
- **`acceptance/tick.spec.luau`** → AC3. Cases:
  - `TICK_RATE`;
  - `snapshot.tick = t`;
  - an intent at k shows at k+1;
  - events with the player id at the right ticks;
  - `assertDeterministic` over 5 seeds.
- **`acceptance/snapshot.spec.luau`** → AC4. Cases:
  - exact v1 key sets;
  - JSON round trip;
  - fresh tables;
  - `jumpTick`;
  - a custom maze id.
- **`acceptance/clock.spec.luau`** → AC5. Cases:
  - defaults;
  - 30 Hz at 30, 50, 60 and 144 fps and over uneven frames;
  - cap and backlog drop;
  - zero, negative and NaN;
  - a custom rate.
- **`acceptance/bench.spec.luau`** → AC6: the busy model really moves, and 50 × 1,800 ticks take under 4 s.
- **`acceptance/place.spec.luau`** → AC7:
  - `CharacterAutoLoads` is false;
  - the three remotes exist (Ready, Intent, Snapshot);
  - `Sessions` starts sessions on `Ready`'s `OnServerEvent` and has no `PlayerAdded` handler (design-review-003 F3);
  - `Main` requires `Sessions`;
  - `Sessions` requires `Session` and `Maze`.
- **The executor's own specs**:
  - `tests/unit/Session`: `DEFAULT_CONFIG` values; `players` after leave; events for two players in id order.
  - **Recommended, not checked**: a scenario story in `tests/scenario/` using `Session` as the sim model on the classic maze (walk west, stop at (6,23) at tick 28, turn north, and so on), as a readable example for later rafts. The behaviour itself is pinned by AC3 (design-review-001 F4 dropped the raft check for it).

## Acceptance criteria

### Checked
- **AC1**: A session starts at tick 0 with no players. It joins players at the spawn (heading W), lists them sorted, refuses double joins, leaves idempotently, allows rejoining from the spawn, keeps players and sessions independent, and validates its config.
- **AC2**: `submit` accepts only the four intent strings from joined players, at most `maxIntentsPerTick` (default 4) per player per tick. It returns the designed reasons otherwise, and accepted intents apply in submission order in the next step.
- **AC3**: Driven through the sim harness, a session's snapshot at time t has `tick = t`. An intent at k acts in step k, events carry the player id and are stamped when visible, and runs are deterministic per seed.
- **AC4**: The snapshot has exactly the v1 fields (`v`, `tick`, `maze`, and `player` with `x`, `y`, `heading`, `moving`, `jumpTick`). It round-trips through JSON, is a fresh table each time, and `jumpTick` is the tick of the latest position discontinuity (in a2, a tunnel jump).
- **AC5**: The clock yields 30 steps per simulated second at any frame rate, caps a long frame at 5 steps and drops the backlog, and ignores zero, negative and NaN frame times.
- **AC6**: 50 sessions × 1,800 ticks of busy play, with a snapshot built every tick, step in under 4 s.
- **AC7**: The built place has `Players.CharacterAutoLoads = false`, `ReplicatedStorage.Remotes.Ready`/`Intent`/`Snapshot` RemoteEvents, and a server `Main` that requires the `Sessions` ModuleScript, which requires the `Session` and `Maze` features. Sessions start on `Ready`, not `PlayerAdded`.

### Judged
None.

### Observed
- **OC1** (Studio, with f0130 in place):
  1. Start a 2-player local server test (Test → Clients and Servers, 2 players).
  2. Each client sees only its own maze and no characters.
  3. The Output window shows no require or remote errors.
  4. Each player moves independently: turning in one window doesn't affect the other.
  5. Closing one client leaves the other running.

## Implementation steps
1. `Session.new`, `join`, `leave`, `players` and `snapshot`. Run AC1 and AC4 (keys). Commit.
2. `submit` and `step`. Run AC2 and AC3, then AC4 (`jumpTick`). Commit.
3. `newClock` and `advance`. Run AC5. Then AC6. Commit.
4. The `default.project.json` additions, `Sessions.luau` and `Main.server.luau`. Run AC7 and `scripts/check.sh --full`, which includes the Roblox type check of the adapter. Commit.
5. `tests/unit/Session` and the scenario story. Run `scripts/tracker.sh check f0120`. Commit.

## Verification log
