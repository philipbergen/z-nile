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
export type Action = Movement.Intent | "Snap"
export type Look = { yaw: number, pitch: number } -- radians, relative to the heading
export type Pose = { x: number, y: number } -- tile coordinates
export type PelletPart = { x: number, y: number, z: number, diameter: number } -- world studs; y is up

local PI = math.pi
local TAU = 2 * math.pi

local SCALE = { tileStuds = 8, wallHeight = 10, eyeHeight = 4, fieldOfView = 80 }
local KEYS: { [string]: Action } = {
	W = "Forward",
	Up = "Forward",
	A = "Left",
	Left = "Left",
	D = "Right",
	Right = "Right",
	S = "Back",
	Down = "Back",
	Space = "Snap",
}
local YAWS: { [Maze.Heading]: number } = { N = 0, W = PI / 2, S = PI, E = -PI / 2 }

local View = {}
View.SCALE = table.freeze(SCALE)
View.TUNNEL_MARGIN = 12 -- classic row 14's first walls are 11 tiles in from each edge
View.TURN_SECONDS = 0.12 -- per quarter turn
View.MAX_PITCH = math.rad(80)
View.MOUSE_RADIANS_PER_PIXEL = 0.004
View.KEYS = table.freeze(KEYS)
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

return View
