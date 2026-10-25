--!strict
-- View: first-person presentation math, engine-free (numbers in, numbers out). The client adapters
-- turn these results into parts, the camera and remote calls.
--
-- World mapping: tile x is world X and tile y is world Z, in studs. A yaw of 0 looks along -Z (north),
-- and a positive yaw turns left, so heading yaws follow the usual camera-frame convention.
local Maze = require("./Maze")
local Movement = require("./Movement")
local Pellets = require("./Pellets")
local Session = require("./Session")

export type Rect = { x0: number, y0: number, x1: number, y1: number } -- inclusive tile range
-- A key's action. "Snap" is no key's any more (f0104): the touch snap button (R0012) still recentres the look.
export type Action =
	Movement.Intent
	| "Jump"
	| "Fire"
	| "LookUp"
	| "LookDown"
	| "LookLeft"
	| "LookRight"
	| "Snap"
-- The arrow keys held down.
export type Arrows = { up: boolean, down: boolean, left: boolean, right: boolean }
-- The look and whether it is springing back to the heading (after the arrows were let go).
export type Steer = { look: Look, spring: boolean }
export type Rgb = { r: number, g: number, b: number } -- 0..255
export type Look = { yaw: number, pitch: number } -- radians, relative to the heading
export type Pose = { x: number, y: number } -- tile coordinates
export type PelletPart = { x: number, y: number, z: number, diameter: number } -- world studs; y is up

local PI = math.pi
local TAU = 2 * math.pi

-- The walls are a stud lower than the ghosts (f0101), so a jump can look over them: from the standing eye a
-- ghost behind a wall stays hidden (E3).
local SCALE = { tileStuds = 8, wallHeight = 9, eyeHeight = 4, fieldOfView = 80 }
-- Desktop keys (user, 2026-10-17): W A S D move, Space jumps, E fires, the arrows look.
local KEYS: { [string]: Action } = {
	W = "Forward",
	A = "Left",
	D = "Right",
	S = "Back",
	Space = "Jump",
	E = "Fire",
	Up = "LookUp",
	Down = "LookDown",
	Left = "LookLeft",
	Right = "LookRight",
}
local ARROWS: { [string]: string } =
	{ LookUp = "up", LookDown = "down", LookLeft = "left", LookRight = "right" }
local GHOST_COLORS: { [string]: Rgb } = {
	blinky = table.freeze({ r = 255, g = 0, b = 0 }),
	pinky = table.freeze({ r = 255, g = 184, b = 255 }),
	inky = table.freeze({ r = 0, g = 255, b = 255 }),
	clyde = table.freeze({ r = 255, g = 184, b = 82 }),
}
local YAWS: { [Maze.Heading]: number } = { N = 0, W = PI / 2, S = PI, E = -PI / 2 }

local View = {}
View.SCALE = table.freeze(SCALE)
View.TUNNEL_MARGIN = 12 -- classic row 14's first walls are 11 tiles in from each edge
View.TURN_SECONDS = 0.12 -- per quarter turn
View.MAX_PITCH = math.rad(80)
View.MOUSE_RADIANS_PER_PIXEL = 0.004
View.KEYS = table.freeze(KEYS)
-- A ghost's body: the walls' old height, so it stands a stud above the lowered walls (f0101).
View.GHOST = table.freeze({ width = 6, height = 10 })
View.GHOST_COLORS = table.freeze(GHOST_COLORS)
View.FRIGHTENED_COLOR = table.freeze({ r = 33, g = 33, b = 255 } :: Rgb)
View.WHITE = table.freeze({ r = 255, g = 255, b = 255 } :: Rgb)
-- Pellets float just below the eye line; a power pellet is bigger and pulses, in real seconds.
View.PELLET = table.freeze({ height = 3, pellet = 1, power = 3, pulseSeconds = 0.5, pulseMin = 0.7 })

-- An angle in (-pi, pi].
local function wrap(a: number): number
	local r = (a + PI) % TAU - PI
	if r == -PI then
		return PI
	end
	return r
end

function View.world(x: number, y: number): (number, number)
	return x * SCALE.tileStuds, y * SCALE.tileStuds
end

function View.headingYaw(h: Maze.Heading): number
	return YAWS[h]
end

-- The axis wraps if any tile on its first column (or row) is walkable for ghosts.
local function wraps(m: Maze.Maze, column: boolean): boolean
	local n = if column then m.height else m.width
	for i = 0, n - 1 do
		local tile: Maze.Tile = if column then { x = 0, y = i } else { x = i, y = 0 }
		if Maze.passable(m, tile, "ghost") then
			return true
		end
	end
	return false
end

function View.bounds(m: Maze.Maze, margin: number?): Rect
	local k = margin or View.TUNNEL_MARGIN
	local mx = if wraps(m, true) then k else 0
	local my = if wraps(m, false) then k else 0
	return { x0 = -mx, y0 = -my, x1 = m.width - 1 + mx, y1 = m.height - 1 + my }
end

function View.walls(m: Maze.Maze, margin: number?): { Rect }
	local b = View.bounds(m, margin)
	local rects: { Rect } = {}
	for y = b.y0, b.y1 do
		local start: number? = nil
		for x = b.x0, b.x1 + 1 do
			local wall = x <= b.x1 and Maze.kind(m, { x = x % m.width, y = y % m.height }) == "wall"
			if wall then
				start = start or x
			elseif start then
				table.insert(rects, { x0 = start, y0 = y, x1 = x - 1, y1 = y })
				start = nil
			end
		end
	end
	return rects
end

-- How far between the previous and the latest snapshot we are, `elapsed` real seconds after the latest one
-- arrived: snapshots come one per step, Session.STEP_RATE steps per real second.
function View.alpha(elapsed: number): number
	return elapsed * Session.STEP_RATE
end

function View.interpolate(prev: Session.Snapshot?, latest: Session.Snapshot, alpha: number): Pose
	local a = if alpha ~= alpha then 1 else math.clamp(alpha, 0, 1)
	local to = latest.player
	if prev == nil or to.jumpTick > prev.tick or prev.tick >= latest.tick then
		return { x = to.x, y = to.y }
	end
	local from = prev.player
	return { x = from.x + (to.x - from.x) * a, y = from.y + (to.y - from.y) * a }
end

-- The tick on the screen between the previous and the latest snapshot, at the same clamped blend
-- View.interpolate uses: the latest tick with no usable previous snapshot or a blend that is not a number.
function View.shownTick(prev: Session.Snapshot?, latest: Session.Snapshot, alpha: number): number
	if prev == nil or prev.tick >= latest.tick or alpha ~= alpha then
		return latest.tick
	end
	return prev.tick + (latest.tick - prev.tick) * math.clamp(alpha, 0, 1)
end

export type GhostPose = { x: number, y: number, heading: Maze.Heading, look: Session.Look, flash: boolean }

-- Where each ghost is drawn between the previous and the latest snapshot, in the latest snapshot's order.
-- A ghost that jumped (a tunnel wrap or a reset) between the two is not blended across the jump.
function View.interpolateGhosts(
	prev: Session.Snapshot?,
	latest: Session.Snapshot,
	alpha: number
): { GhostPose }
	local out: { GhostPose } = {}
	local a = if alpha ~= alpha then 1 else math.clamp(alpha, 0, 1)
	local before: Session.Snapshot? = if prev and prev.tick < latest.tick then prev else nil
	local ghosts: { Session.GhostSnapshot } = latest.ghosts or {}
	for i, g in ghosts do
		local x, y = g.x, g.y
		local fromList: { Session.GhostSnapshot } = if before and before.ghosts then before.ghosts else {}
		local from = fromList[i]
		if before and from and from.name == g.name and g.jumpTick <= before.tick then
			x, y = from.x + (g.x - from.x) * a, from.y + (g.y - from.y) * a
		end
		table.insert(out, { x = x, y = y, heading = g.heading, look = g.look, flash = g.flash })
	end
	return out
end

function View.approachYaw(current: number, target: number, maxDelta: number): number
	local diff = wrap(target - current)
	if math.abs(diff) <= maxDelta then
		return wrap(target)
	end
	return wrap(current + (if diff > 0 then maxDelta else -maxDelta))
end

function View.turnRate(): number
	return (PI / 2) / View.TURN_SECONDS
end

function View.look(l: Look, dx: number, dy: number): Look
	local k = View.MOUSE_RADIANS_PER_PIXEL
	return {
		yaw = wrap(l.yaw - dx * k),
		pitch = math.clamp(l.pitch - dy * k, -View.MAX_PITCH, View.MAX_PITCH),
	}
end

function View.snap(_l: Look): Look
	return { yaw = 0, pitch = 0 }
end

-- Where a pellet is drawn: its tile's centre at View.PELLET.height, sized by its kind.
function View.pellet(slot: Pellets.Slot): PelletPart
	local x, z = View.world(slot.x, slot.y)
	local p = View.PELLET
	return { x = x, y = p.height, z = z, diameter = if slot.kind == "power" then p.power else p.pellet }
end

-- A pellet's size factor `seconds` of real time in. A power pellet swings smoothly between pulseMin and 1,
-- once per pulseSeconds, starting full; a pellet, or a time that is NaN or infinite, is 1.
function View.pulse(kind: Pellets.Kind, seconds: number): number
	if kind ~= "power" or seconds ~= seconds or math.abs(seconds) == math.huge then
		return 1
	end
	local p = View.PELLET
	local wave = 0.5 + 0.5 * math.cos(2 * PI * seconds / p.pulseSeconds)
	return p.pulseMin + (1 - p.pulseMin) * wave
end

function View.action(keyName: string): Action?
	return KEYS[keyName]
end

local function finite(v: number): boolean
	return v == v and math.abs(v) ~= math.huge
end

-- The arrows held after `action` went down (true) or up (false). Other actions leave them as they are.
function View.press(a: Arrows, action: Action?, down: boolean): Arrows
	local key = if action then ARROWS[action] else nil
	return {
		up = if key == "up" then down else a.up,
		down = if key == "down" then down else a.down,
		left = if key == "left" then down else a.left,
		right = if key == "right" then down else a.right,
	}
end

-- Where the held arrows look, in quarter turns from the heading, positive left: up 0, left 1, right -1, down 2;
-- two together give the half quarters between (up and left 0.5, down and left 1.5, down and right -1.5).
-- Opposite arrows cancel; if every arrow held cancels, it is 0. Nil when none is held.
function View.arrowQuarters(a: Arrows): number?
	if not (a.up or a.down or a.left or a.right) then
		return nil
	end
	local side = (if a.left then 1 else 0) - (if a.right then 1 else 0)
	local ahead = (if a.up then 1 else 0) - (if a.down then 1 else 0)
	if side == 0 then
		return if ahead < 0 then 2 else 0
	end
	if ahead == 0 then
		return side
	end
	if ahead > 0 then
		return side * 0.5
	end
	return side * 1.5
end

-- One frame of the arrow look, after the mouse (and any other look input) has moved `look`. `prev` is what this
-- returned last frame. While an arrow is held the look turns from prev.look toward the arrows (pitch level) at
-- View.turnRate(), so any other look input is ignored; once they are all let go it springs back to the heading at
-- the same rate, until the look is moved by anything else (it differs from prev.look), which takes over from there.
function View.steer(prev: Steer, look: Look, a: Arrows, dt: number): Steer
	local step = View.turnRate() * (if finite(dt) and dt > 0 then dt else 0)
	local function toward(from: Look, target: Look): Look
		local dp = math.clamp(target.pitch - from.pitch, -step, step)
		return { yaw = View.approachYaw(from.yaw, target.yaw, step), pitch = from.pitch + dp }
	end
	local q = View.arrowQuarters(a)
	if q ~= nil then
		return { look = toward(prev.look, { yaw = wrap(q * PI / 2), pitch = 0 }), spring = true }
	end
	if look.yaw ~= prev.look.yaw or look.pitch ~= prev.look.pitch then
		return { look = { yaw = look.yaw, pitch = look.pitch }, spring = false }
	end
	if prev.spring then
		local back = toward(look, { yaw = 0, pitch = 0 })
		return { look = back, spring = not (back.yaw == 0 and back.pitch == 0) }
	end
	return { look = { yaw = look.yaw, pitch = look.pitch }, spring = false }
end

-- The heading a shot goes when the player, heading `heading`, aims: the held arrows' direction, else the look's
-- yaw, rounded to the nearest quarter turn. A tie (exactly half way, as up and left is) goes ahead or behind, the
-- way the player is travelling, never to the side.
function View.aim(heading: Maze.Heading, s: Steer, a: Arrows): Maze.Heading
	local q = View.arrowQuarters(a) or (if finite(s.look.yaw) then wrap(s.look.yaw) / (PI / 2) else 0)
	local n = math.floor(q + 0.5)
	if q + 0.5 == n and n % 2 ~= 0 then
		n -= 1 -- exactly half way: the even quarter (ahead or behind)
	end
	n %= 4
	if n == 0 then
		return heading
	elseif n == 1 then
		return Maze.left(heading)
	elseif n == 3 then
		return Maze.right(heading)
	end
	return Maze.opposite(heading)
end

-- Where a shot's beam ends (f0100), in tile coordinates, for a player at (x, y) shooting along `heading`: the far
-- edge of the last open tile in that direction from the player's tile, short of the first wall, door or house
-- tile. A wrapping row ends the beam at the maze's edge: it is not drawn across.
function View.beamEnd(m: Maze.Maze, x: number, y: number, heading: Maze.Heading): (number, number)
	local dx, dy = Maze.delta(heading)
	local tile: Maze.Tile = { x = math.floor(x + 0.5) % m.width, y = math.floor(y + 0.5) % m.height }
	for _ = 1, m.width + m.height do
		local nextTile, wrapped = Maze.neighbor(m, tile, heading)
		if wrapped or not Maze.passable(m, nextTile, "player") then
			break
		end
		tile = nextTile
	end
	local ex = if dx ~= 0 then tile.x + dx * 0.5 else x
	local ey = if dy ~= 0 then tile.y + dy * 0.5 else y
	return ex, ey
end

-- The colour a ghost is drawn in: its own while normal, blue while frightened, white on the white half of a
-- blinking flash, and white for eyes going home. A name without a colour is white.
function View.ghostColor(name: string, look: Session.Look, flash: boolean): Rgb
	local c: Rgb = if look == "frightened"
		then View.FRIGHTENED_COLOR
		elseif look == "blinking" then (if flash then View.WHITE else View.FRIGHTENED_COLOR)
		elseif look == "eyes" then View.WHITE
		else GHOST_COLORS[name] or View.WHITE
	return { r = c.r, g = c.g, b = c.b }
end

return View
