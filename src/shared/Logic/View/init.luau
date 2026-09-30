--!strict
-- View: first-person presentation math, engine-free (numbers in, numbers out). The client adapters
-- turn these results into parts, the camera and remote calls.
--
-- World mapping: tile x is world X and tile y is world Z, in studs. A yaw of 0 looks along -Z (north),
-- and a positive yaw turns left, so heading yaws follow the usual camera-frame convention.
local Maze = require("./Maze")
local Movement = require("./Movement")
local Session = require("./Session")

export type Rect = { x0: number, y0: number, x1: number, y1: number } -- inclusive tile range
export type Action = Movement.Intent | "Snap"
export type Look = { yaw: number, pitch: number } -- radians, relative to the heading
export type Pose = { x: number, y: number } -- tile coordinates

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

function View.interpolate(prev: Session.Snapshot?, latest: Session.Snapshot, alpha: number): Pose
	local a = if alpha ~= alpha then 1 else math.clamp(alpha, 0, 1)
	local to = latest.player
	if prev == nil or to.jumpTick > prev.tick or prev.tick >= latest.tick then
		return { x = to.x, y = to.y }
	end
	local from = prev.player
	return { x = from.x + (to.x - from.x) * a, y = from.y + (to.y - from.y) * a }
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

function View.action(keyName: string): Action?
	return KEYS[keyName]
end

return View
