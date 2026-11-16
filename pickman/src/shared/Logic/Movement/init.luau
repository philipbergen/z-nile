--!strict
-- Movement: rail movement of one player through a Maze. Positions are integer sub-tile units, so
-- every tick lands on exact values. Turns are buffered and taken at tile centres; corners are
-- classic (stop unless a turn is buffered); Back is an immediate literal reverse; tunnels wrap.
local Maze = require("./Maze")

export type Intent = "Left" | "Right" | "Back" | "Forward"
export type Config = {
	speed: number, -- integer sub-tile units per tick, 1..UNITS
	turnBufferTicks: number, -- integer >= 1: steps a buffered Left/Right stays pending
}
export type State = {
	tile: Maze.Tile, -- the tile whose centre the player is on or last passed
	heading: Maze.Heading,
	progress: number, -- integer units 0..UNITS-1 from tile's centre toward its neighbour ahead
	moving: boolean,
	buffered: Intent?, -- "Left" | "Right" | nil
	bufferLeft: number, -- steps the buffered turn remains pending (0 when none)
	leftCentre: boolean, -- the last step moved the player off tile's centre (cornering grace)
	run: number, -- centres passed straight since the last turn, Back or stop; capped at width + height
}
export type Event =
	{ kind: "Entered", x: number, y: number }
	| { kind: "Stopped", x: number, y: number }
	| { kind: "Wrapped" }

local UNITS = 120
local INTENTS: { Intent } = { "Left", "Right", "Back", "Forward" }
local DEFAULT_CONFIG: Config = { speed = 30, turnBufferTicks = 24 }

local Movement = {}
Movement.UNITS = UNITS
Movement.INTENTS = table.freeze(INTENTS)
Movement.DEFAULT_CONFIG = table.freeze(DEFAULT_CONFIG)

local function isWhole(v: any): boolean
	return type(v) == "number" and v == math.floor(v) and v == v
end

function Movement.validateConfig(c: Config)
	if not isWhole(c.speed) or c.speed < 1 or c.speed > UNITS then
		error(`movement: speed must be a whole number of units in 1..{UNITS}, got {c.speed}`, 0)
	end
	if not isWhole(c.turnBufferTicks) or c.turnBufferTicks < 1 then
		error(`movement: turnBufferTicks must be a whole number >= 1, got {c.turnBufferTicks}`, 0)
	end
end

function Movement.isIntent(v: any): boolean
	for _, i: Intent in INTENTS do
		if v == i then
			return true
		end
	end
	return false
end

function Movement.spawn(m: Maze.Maze, heading: Maze.Heading?): State
	local h: Maze.Heading = heading or "W"
	local tile = { x = m.spawn.x, y = m.spawn.y }
	return {
		tile = tile,
		heading = h,
		progress = 0,
		moving = Maze.passable(m, (Maze.neighbor(m, tile, h)), "player"),
		buffered = nil,
		bufferLeft = 0,
		leftCentre = false,
		run = 0,
	}
end

function Movement.position(s: State): (number, number)
	local dx, dy = Maze.delta(s.heading)
	local f = s.progress / UNITS
	return s.tile.x + dx * f, s.tile.y + dy * f
end

function Movement.occupied(m: Maze.Maze, s: State): Maze.Tile
	if s.progress * 2 < UNITS then
		return { x = s.tile.x, y = s.tile.y }
	end
	return (Maze.neighbor(m, s.tile, s.heading))
end

local function turn(h: Maze.Heading, intent: Intent): Maze.Heading
	if intent == "Left" then
		return Maze.left(h)
	end
	return Maze.right(h)
end

-- Can the player step from `tile` toward h?
local function open(m: Maze.Maze, tile: Maze.Tile, h: Maze.Heading): boolean
	return Maze.passable(m, (Maze.neighbor(m, tile, h)), "player")
end

local function clearBuffer(s: State)
	s.buffered = nil
	s.bufferLeft = 0
end

-- Distance, in units, back to the nearest centre passed straight since the last turn, Back or
-- stop (tile's included) that has an exit toward h. Infinite when there is none.
local function prevExitDistance(m: Maze.Maze, s: State, h: Maze.Heading): number
	local back: Maze.Heading = Maze.opposite(s.heading)
	local tile = s.tile
	for j = 0, s.run - 1 do
		if open(m, tile, h) then
			return j * UNITS + s.progress
		end
		tile = (Maze.neighbor(m, tile, back))
	end
	return math.huge
end

-- Distance, in units, on to the next centre ahead that has an exit toward h. Infinite when the
-- corridor ends first.
local function nextExitDistance(m: Maze.Maze, s: State, h: Maze.Heading): number
	local tile = s.tile
	for k = 1, m.width + m.height do
		tile = (Maze.neighbor(m, tile, s.heading))
		if not Maze.passable(m, tile, "player") then
			return math.huge
		end
		if open(m, tile, h) then
			return k * UNITS - s.progress
		end
	end
	return math.huge
end

-- At a centre: take a buffered turn if its exit exists, else stop if blocked ahead.
local function decide(m: Maze.Maze, s: State)
	local pending: Intent? = s.buffered
	if pending and open(m, s.tile, turn(s.heading, pending)) then
		s.heading = turn(s.heading, pending)
		s.moving = true
		s.run = 0
		clearBuffer(s)
	elseif s.moving and not open(m, s.tile, s.heading) then
		s.moving = false
		s.run = 0
	end
end

-- Distance in units to the next tile centre ahead, and that tile: 0 and the player's own tile when on a centre.
function Movement.nextCentre(m: Maze.Maze, s: State): (number, Maze.Tile)
	if s.progress == 0 then
		return 0, { x = s.tile.x, y = s.tile.y }
	end
	return UNITS - s.progress, (Maze.neighbor(m, s.tile, s.heading))
end

-- Stops the player where they stand, on a tile centre (a wall pick, f0126): no buffered turn survives it, and the
-- straight run starts over. Refuses a player between centres.
function Movement.halt(s: State)
	if s.progress ~= 0 then
		error("movement: halt between tile centres", 0)
	end
	s.moving = false
	s.run = 0
	s.leftCentre = false
	clearBuffer(s)
end

-- Lets a halted player go on: moving again when the way ahead is open, still stopped facing a wall.
function Movement.resume(m: Maze.Maze, s: State)
	if s.progress == 0 and not s.moving then
		s.moving = open(m, s.tile, s.heading)
	end
end

function Movement.step(m: Maze.Maze, s: State, intents: { Intent }, c: Config): { Event }
	local wasMoving = s.moving
	local before = Movement.occupied(m, s)
	local wrapped = false

	for _, intent: Intent in intents do
		if intent == "Back" then
			if s.progress > 0 then
				local n, w = Maze.neighbor(m, s.tile, s.heading)
				s.tile = n
				s.progress = UNITS - s.progress
				s.heading = Maze.opposite(s.heading)
				s.moving = true
				wrapped = wrapped ~= w
			else
				s.heading = Maze.opposite(s.heading)
				s.moving = open(m, s.tile, s.heading)
			end
			clearBuffer(s)
			s.run = 0
			s.leftCentre = false
		elseif intent == "Forward" then
			clearBuffer(s)
		else
			local h: Maze.Heading = turn(s.heading, intent)
			local exitHere = s.run > 0 and s.progress > 0 and open(m, s.tile, h)
			if exitHere and s.leftCentre and s.progress * 2 < UNITS then
				-- cornering grace: cut the corner, keeping the distance already travelled
				s.heading = h
				s.leftCentre = false
				s.run = 0
				clearBuffer(s)
			elseif
				not (s.progress == 0 and open(m, s.tile, h))
				and prevExitDistance(m, s, h) < nextExitDistance(m, s, h)
			then
				-- a missed turn: drop it, and any older one with it
				clearBuffer(s)
			else
				s.buffered = intent
				s.bufferLeft = c.turnBufferTicks
			end
		end
	end

	if s.progress == 0 then
		decide(m, s)
	end

	local left = false
	if s.moving then
		local remaining = c.speed
		while remaining > 0 and s.moving do
			if s.progress == 0 then
				left = true
			end
			local d = math.min(remaining, UNITS - s.progress)
			s.progress += d
			remaining -= d
			if s.progress == UNITS then
				local n, w = Maze.neighbor(m, s.tile, s.heading)
				s.tile = n
				s.progress = 0
				wrapped = wrapped ~= w
				s.run = math.min(s.run + 1, m.width + m.height)
				decide(m, s)
			end
		end
	end
	s.leftCentre = left and s.progress > 0 and s.moving

	if s.buffered then
		s.bufferLeft -= 1
		if s.bufferLeft <= 0 then
			clearBuffer(s)
		end
	end

	local events: { Event } = {}
	if wrapped then
		table.insert(events, { kind = "Wrapped" })
	end
	if wasMoving and not s.moving then
		table.insert(events, { kind = "Stopped", x = s.tile.x, y = s.tile.y })
	end
	local after = Movement.occupied(m, s)
	if after.x ~= before.x or after.y ~= before.y then
		table.insert(events, { kind = "Entered", x = after.x, y = after.y })
	end
	return events
end

return Movement
