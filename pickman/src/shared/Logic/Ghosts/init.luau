--!strict
-- Ghosts: the four classic ghosts of one maze instance as pure state. Navigation (the exit that minimises
-- the straight-line distance to a target, never reversing on its own), the scatter/chase schedule and
-- frightened mode, the ghost house and its release rules, and the contacts with the player.
-- Time and randomness come in as parameters; a set holds its own seeded generator state.
local Classic = require("@self/Classic")
local Levels = require("./Levels")
local Maze = require("./Maze")
local Movement = require("./Movement")
local Rng = require("@self/Rng")

export type Name = Classic.Name
export type Mode = "scatter" | "chase"
export type Status = "house" | "leaving" | "active" | "eyes"
export type Look = "normal" | "frightened" | "blinking" | "eyes"

export type Walker = { tile: Maze.Tile, heading: Maze.Heading, progress: number }
export type Ghost = {
	name: Name,
	tile: Maze.Tile,
	heading: Maze.Heading,
	progress: number, -- integer units 0..UNITS-1 from tile's centre toward its neighbour ahead
	status: Status,
	frightened: boolean, -- blue: set by a power pellet, cleared when eaten or when the power ends
	reverse: boolean, -- turn back at the next centre
}
export type House = {
	personal: { pinky: number, inky: number, clyde: number }, -- pellets eaten while each was next in line
	global: number?, -- after a death: pellets eaten since, instead of the personal counters
	idle: number, -- ticks since the last pellet
}
export type Set = {
	maze: Maze.Maze,
	level: number,
	rng: number,
	mode: Mode,
	phase: number, -- index into the level's schedule; past its end it is chase for good
	phaseTicks: number, -- ticks spent in this phase (the clock stops while frightened)
	frightened: number, -- ticks of power left
	chain: number, -- ghosts eaten in this power period
	ghosts: { Ghost }, -- always in NAMES order
	house: House,
	tuning: number,
	open: boolean, -- ghosts start in the house (false: all four start active, for tests)
}
export type Options = { start: ("house" | "active")?, level: number?, tuning: number? }
export type Chase = { player: Maze.Tile, heading: Maze.Heading, blinky: Maze.Tile, self: Maze.Tile }
export type Input = {
	player: Maze.Tile, -- the tile the player occupies
	heading: Maze.Heading,
	level: number,
	baseSpeed: number, -- level 1's player speed in units per tick
	tickRate: number,
	maze: Maze.Maze?, -- the maze to walk this tick (a copy with picked holes, f0126); nil keeps the set's
}
export type Event = { kind: string, ghost: Name?, mode: Mode?, ticks: number?, x: number?, y: number? }
export type Contact = { name: Name, kind: "kill" | "eat" }
export type Opts = { noUp: boolean?, house: boolean? }

local UNITS = Movement.UNITS
local NAMES: { Name } = { "blinky", "pinky", "inky", "clyde" }
local ORDER: { Maze.Heading } = { "N", "W", "S", "E" } -- ties go to up, left, down, right
local FLASH_TICKS = 14 -- one flash of the blinking: 7 ticks blue, 7 white
local EYES_SCORE = { 200, 400, 800, 1600 }

local Ghosts = {}
Ghosts.NAMES = table.freeze(NAMES)
Ghosts.FLASH_TICKS = FLASH_TICKS

local function fail(problem: string): never
	error(`ghosts: {problem}`, 0)
end

-- ---------------------------------------------------------------------------------------------
-- navigation (f0190)

function Ghosts.noUpTiles(m: Maze.Maze): { Maze.Tile }
	local data = Classic.of(m)
	return if data then data.noUp else {}
end

local function isNoUp(m: Maze.Maze, tile: Maze.Tile): boolean
	for _, t in Ghosts.noUpTiles(m) do
		if t.x == tile.x and t.y == tile.y then
			return true
		end
	end
	return false
end

-- Where a ghost scatters to: a corner outside the maze. Nil for a maze without ghosts.
function Ghosts.scatterTile(m: Maze.Maze, name: Name): Maze.Tile
	local data = Classic.of(m)
	if data == nil then
		fail(`maze '{m.id}' has no ghost data`)
	end
	return (data :: Classic.Data).corners[name]
end

local function ahead(tile: Maze.Tile, h: Maze.Heading, n: number): Maze.Tile
	local dx, dy = Maze.delta(h)
	return { x = tile.x + dx * n, y = tile.y + dy * n }
end

-- The tile a ghost aims at while chasing: Blinky the player's tile; Pinky 4 tiles ahead of the player;
-- Inky twice the vector from Blinky to the tile 2 ahead of the player; Clyde the player's tile when more
-- than 8 tiles away, else his scatter corner.
function Ghosts.chaseTarget(m: Maze.Maze, name: Name, c: Chase): Maze.Tile
	if name == "blinky" then
		return { x = c.player.x, y = c.player.y }
	elseif name == "pinky" then
		return ahead(c.player, c.heading, 4)
	elseif name == "inky" then
		local pivot = ahead(c.player, c.heading, 2)
		return { x = pivot.x + (pivot.x - c.blinky.x), y = pivot.y + (pivot.y - c.blinky.y) }
	end
	local dx, dy = c.player.x - c.self.x, c.player.y - c.self.y
	if dx * dx + dy * dy > 64 then
		return { x = c.player.x, y = c.player.y }
	end
	return Ghosts.scatterTile(m, "clyde")
end

local function allowed(m: Maze.Maze, tile: Maze.Tile, opts: Opts): boolean
	if not Maze.passable(m, tile, "ghost") then
		return false
	end
	if opts.house then
		return true
	end
	local kind = Maze.kind(m, tile)
	return kind ~= "door" and kind ~= "house"
end

-- The headings a ghost on `tile`, arrived heading `heading`, may leave by, in tie-break order. It never
-- turns back unless nothing else is open; it may not go up on a no-up tile; the door and the house are
-- closed unless `opts.house`.
local function exitsOf(m: Maze.Maze, tile: Maze.Tile, heading: Maze.Heading, opts: Opts): { Maze.Heading }
	local out: { Maze.Heading } = {}
	local back: Maze.Heading = Maze.opposite(heading)
	for _, h: Maze.Heading in ORDER do
		if h ~= back and allowed(m, (Maze.neighbor(m, tile, h)), opts) then
			if not (h == "N" and opts.noUp and isNoUp(m, tile)) then
				table.insert(out, h)
			end
		end
	end
	if #out == 0 and allowed(m, (Maze.neighbor(m, tile, back)), opts) then
		table.insert(out, back)
	end
	return out
end

-- The exit that brings the ghost closest, in a straight line, to `target`.
function Ghosts.pickExit(
	m: Maze.Maze,
	tile: Maze.Tile,
	heading: Maze.Heading,
	target: Maze.Tile,
	opts: Opts?
): Maze.Heading
	local o: Opts = opts or {}
	local best: Maze.Heading? = nil
	local bestDistance = math.huge
	for _, h: Maze.Heading in exitsOf(m, tile, heading, o) do
		local dx, dy = Maze.delta(h)
		local nx, ny = tile.x + dx - target.x, tile.y + dy - target.y
		local d = nx * nx + ny * ny
		if d < bestDistance then
			best, bestDistance = h, d
		end
	end
	return best or heading
end

function Ghosts.walker(tile: Maze.Tile, heading: Maze.Heading): Walker
	return { tile = { x = tile.x, y = tile.y }, heading = heading, progress = 0 }
end

function Ghosts.occupied(w: Walker): Maze.Tile
	if w.progress * 2 < UNITS then
		return { x = w.tile.x, y = w.tile.y }
	end
	local dx, dy = Maze.delta(w.heading)
	return { x = w.tile.x + dx, y = w.tile.y + dy }
end

local function occupiedWrapped(m: Maze.Maze, w: Walker): Maze.Tile
	if w.progress * 2 < UNITS then
		return { x = w.tile.x, y = w.tile.y }
	end
	return (Maze.neighbor(m, w.tile, w.heading))
end

function Ghosts.position(w: Walker): (number, number)
	local dx, dy = Maze.delta(w.heading)
	local f = w.progress / UNITS
	return w.tile.x + dx * f, w.tile.y + dy * f
end

-- Advances `speed` units along the rails. `decide` is asked for the heading each time the walker is on a
-- tile centre, with the heading it arrived by. Returns Entered (tile occupied changes) and Wrapped events.
function Ghosts.walk(
	m: Maze.Maze,
	w: Walker,
	speed: number,
	decide: (tile: Maze.Tile, heading: Maze.Heading) -> Maze.Heading
): { Event }
	local before = occupiedWrapped(m, w)
	local wraps = 0
	local remaining = speed
	while remaining > 0 do
		if w.progress == 0 then
			w.heading = decide(w.tile, w.heading)
		end
		local d = math.min(remaining, UNITS - w.progress)
		w.progress += d
		remaining -= d
		if w.progress == UNITS then
			local n, wrapped = Maze.neighbor(m, w.tile, w.heading)
			w.tile = n
			w.progress = 0
			if wrapped then
				wraps += 1
			end
		end
	end
	local events: { Event } = {}
	for _ = 1, wraps do
		table.insert(events, { kind = "Wrapped" })
	end
	local after = occupiedWrapped(m, w)
	if after.x ~= before.x or after.y ~= before.y then
		table.insert(events, { kind = "Entered", x = after.x, y = after.y })
	end
	return events
end

-- Is the tile in a side tunnel, where ghosts slow down: the six tiles at each edge of a row that wraps.
function Ghosts.tunnel(m: Maze.Maze, tile: Maze.Tile): boolean
	if
		not Maze.passable(m, { x = 0, y = tile.y }, "ghost")
		and not Maze.passable(m, { x = m.width - 1, y = tile.y }, "ghost")
	then
		return false
	end
	return tile.x <= 5 or tile.x >= m.width - 6
end

-- ---------------------------------------------------------------------------------------------
-- the set

local function newGhost(name: Name, data: Classic.Data, start: "house" | "active"): Ghost
	local s = data.starts[name]
	local status: Status = if s.inHouse and start == "house" then "house" else "active"
	local tile = { x = s.tile.x, y = s.tile.y }
	if status == "active" and s.inHouse then
		-- tests only: park the house ghosts on the open tile above the door
		tile = {
			x = data.exitX + (if name == "pinky" then -1 elseif name == "inky" then 0 else 1),
			y = data.doorY - 1,
		}
	end
	return {
		name = name,
		tile = tile,
		heading = s.heading,
		progress = 0,
		status = status,
		frightened = false,
		reverse = false,
	}
end

local function place(set: Set)
	local data = Classic.of(set.maze) :: Classic.Data
	set.ghosts = {}
	for _, name: Name in NAMES do
		table.insert(set.ghosts, newGhost(name, data, if set.open then "house" else "active"))
	end
end

function Ghosts.new(m: Maze.Maze, seed: number, opts: Options?): Set
	if Classic.of(m) == nil then
		fail(`maze '{m.id}' has no ghost data`)
	end
	local o: Options = opts or {}
	local set: Set = {
		maze = m,
		level = o.level or 1,
		rng = Rng.seed(seed),
		mode = "scatter",
		phase = 1,
		phaseTicks = 0,
		frightened = 0,
		chain = 0,
		ghosts = {},
		house = { personal = { pinky = 0, inky = 0, clyde = 0 }, global = nil, idle = 0 },
		tuning = o.tuning or Levels.GHOST_TUNING,
		open = (o.start or "house") == "house",
	}
	place(set)
	return set
end

-- The ghosts walk a changed copy of their maze from now on (a picked hole, f0126). Refuses a maze of another
-- layout or size.
function Ghosts.useMaze(set: Set, m: Maze.Maze)
	if m.id ~= set.maze.id or m.width ~= set.maze.width or m.height ~= set.maze.height then
		fail(`maze '{m.id}' is not a copy of '{set.maze.id}'`)
	end
	set.maze = m
end

-- Does the maze have ghosts at all?
function Ghosts.available(m: Maze.Maze): boolean
	return Classic.of(m) ~= nil
end

function Ghosts.ghost(set: Set, name: Name): Ghost
	for _, g in set.ghosts do
		if g.name == name then
			return g
		end
	end
	error(`ghosts: unknown ghost {name}`, 0)
end

-- The tiles the ghosts occupy now, in NAMES order.
function Ghosts.occupiedTiles(set: Set): { Maze.Tile }
	local out: { Maze.Tile } = {}
	for _, g in set.ghosts do
		table.insert(out, (occupiedWrapped(set.maze, g)))
	end
	return out
end

-- the look: how the ghost is drawn
function Ghosts.look(set: Set, g: Ghost): Look
	if g.status == "eyes" then
		return "eyes"
	end
	if not g.frightened then
		return "normal"
	end
	if set.frightened > 0 and set.frightened <= Levels.row(set.level).flashes * FLASH_TICKS then
		return "blinking"
	end
	return "frightened"
end

-- While blinking: is this the white half of the flash?
function Ghosts.flash(set: Set): boolean
	if set.frightened <= 0 or set.frightened > Levels.row(set.level).flashes * FLASH_TICKS then
		return false
	end
	return math.floor((set.frightened - 1) / (FLASH_TICKS / 2)) % 2 == 0
end

-- ---------------------------------------------------------------------------------------------
-- modes (f0200)

local function reverseAll(set: Set)
	for _, g in set.ghosts do
		if g.status == "active" then
			g.reverse = true
		end
	end
end

-- A power pellet was eaten: `ticks` of fright (0 on levels without any: the ghosts still turn back).
function Ghosts.power(set: Set, ticks: number)
	set.frightened = ticks
	set.chain = 0
	for _, g in set.ghosts do
		if g.status ~= "eyes" then
			g.frightened = ticks > 0
		end
	end
	reverseAll(set)
end

local function speedOf(set: Set, g: Ghost, input: Input): number
	if g.status == "eyes" then
		return Levels.ghostSpeed(input.baseSpeed, input.level, "eyes", set.tuning)
	end
	if Ghosts.tunnel(set.maze, Ghosts.occupied(g)) then
		return Levels.ghostSpeed(input.baseSpeed, input.level, "tunnel", set.tuning)
	end
	local kind: Levels.GhostSpeed = if g.frightened then "frightened" else "normal"
	return Levels.ghostSpeed(input.baseSpeed, input.level, kind, set.tuning)
end

local function tickMode(set: Set, input: Input, out: { Event })
	if set.frightened > 0 then
		set.frightened -= 1
		if set.frightened == 0 then
			set.chain = 0 -- the power period is over: a shot after it starts a chain of its own
			for _, g in set.ghosts do
				g.frightened = false
			end
			table.insert(out, { kind = "FrightenedEnded" })
		end
		return -- the schedule clock stops while the ghosts are blue
	end
	local schedule = Levels.schedule(input.level, input.tickRate)
	local length = schedule[set.phase]
	set.phaseTicks += 1
	if length ~= nil and set.phaseTicks >= length then
		set.phase += 1
		set.phaseTicks = 0
		set.mode = if set.mode == "scatter" then "chase" else "scatter"
		reverseAll(set)
		table.insert(out, { kind = "ModeChanged", mode = set.mode })
	end
end

-- ---------------------------------------------------------------------------------------------
-- the house (f0210)

local QUEUE: { Name } = { "pinky", "inky", "clyde" }
local GLOBAL_LIMITS: { [string]: number } = { pinky = 7, inky = 17, clyde = 32 }

local function waiting(set: Set): Name?
	for _, name: Name in QUEUE do
		if Ghosts.ghost(set, name).status == "house" then
			return name
		end
	end
	return nil
end

local function release(set: Set, name: Name, out: { Event })
	local g = Ghosts.ghost(set, name)
	g.status = "leaving"
	g.reverse = false
	set.house.idle = 0
	table.insert(out, { kind = "GhostReleased", ghost = name })
end

-- Personal counters: the ghost next in line leaves when its counter reaches the level's limit.
local function releaseByCounters(set: Set, out: { Event })
	while set.house.global == nil do
		local name = waiting(set)
		if name == nil then
			return
		end
		local limit = (Levels.row(set.level).dotLimits :: any)[name]
		local personal: { [string]: number } = set.house.personal :: any
		if personal[name] < limit then
			return
		end
		release(set, name :: Name, out)
	end
end

-- The player ate a pellet.
function Ghosts.pelletEaten(set: Set): { Event }
	local out: { Event } = {}
	local house = set.house
	house.idle = 0
	if house.global ~= nil then
		local count = (house.global :: number) + 1
		house.global = count
		for _, name: Name in QUEUE do
			if count == GLOBAL_LIMITS[name] and Ghosts.ghost(set, name).status == "house" then
				release(set, name :: Name, out)
			end
		end
		if count >= GLOBAL_LIMITS.clyde and Ghosts.ghost(set, "clyde").status ~= "house" then
			house.global = nil -- the personal counters take over again
		end
	else
		local name = waiting(set)
		if name ~= nil then
			local personal: { [string]: number } = house.personal :: any
			personal[name] += 1
		end
		releaseByCounters(set, out)
	end
	return out
end

-- ---------------------------------------------------------------------------------------------
-- stepping

local function randomExit(set: Set, tile: Maze.Tile, heading: Maze.Heading): Maze.Heading
	local exits = exitsOf(set.maze, tile, heading, {})
	if #exits == 0 then
		return heading
	end
	local state, pick = Rng.next(set.rng, #exits)
	set.rng = state
	return exits[pick]
end

local function targetOf(set: Set, g: Ghost, input: Input): Maze.Tile
	if set.mode == "scatter" then
		return Ghosts.scatterTile(set.maze, g.name)
	end
	local blinky = Ghosts.ghost(set, "blinky")
	return Ghosts.chaseTarget(set.maze, g.name, {
		player = input.player,
		heading = input.heading,
		blinky = Ghosts.occupied(blinky),
		self = Ghosts.occupied(g),
	})
end

local function decider(
	set: Set,
	g: Ghost,
	input: Input,
	out: { Event }
): (Maze.Tile, Maze.Heading) -> Maze.Heading
	local data = Classic.of(set.maze) :: Classic.Data
	return function(tile: Maze.Tile, heading: Maze.Heading): Maze.Heading
		if g.status == "leaving" then
			if tile.x ~= data.exitX then
				return if tile.x < data.exitX then "E" else "W"
			end
			if tile.y > data.doorY - 1 then
				return "N"
			end
			-- out above the door: hunt from here
			g.status = "active"
			table.insert(out, { kind = "GhostLeft", ghost = g.name })
			return "W"
		elseif g.status == "eyes" then
			local home = { x = data.exitX, y = data.doorY - 1 }
			local kind = Maze.kind(set.maze, tile)
			if kind == "door" or kind == "house" then
				if tile.y >= data.doorY + 2 then
					g.status = "leaving"
					g.frightened = false
					table.insert(out, { kind = "GhostRevived", ghost = g.name })
					return "N"
				end
				return "S"
			end
			if tile.x == home.x and tile.y == home.y then
				return "S"
			end
			return Ghosts.pickExit(set.maze, tile, heading, home, { house = true })
		end
		-- active
		if g.reverse then
			g.reverse = false
			return Maze.opposite(heading)
		end
		if g.frightened then
			return randomExit(set, tile, heading)
		end
		return Ghosts.pickExit(set.maze, tile, heading, targetOf(set, g, input), { noUp = true })
	end
end

-- One tick. Ghosts in the house wait; the rest walk.
function Ghosts.step(set: Set, input: Input): { Event }
	local out: { Event } = {}
	set.level = input.level
	if input.maze then
		Ghosts.useMaze(set, input.maze)
	end
	tickMode(set, input, out)
	-- idle release and zero-limit release
	local house = set.house
	house.idle += 1
	releaseByCounters(set, out)
	if house.idle >= math.floor(Levels.row(input.level).idleSeconds * input.tickRate) then
		local name = waiting(set)
		if name ~= nil then
			release(set, name :: Name, out)
		end
		house.idle = 0
	end
	for _, g in set.ghosts do
		if g.status ~= "house" then
			local events = Ghosts.walk(set.maze, g, speedOf(set, g, input), decider(set, g, input, out))
			for _, e in events do
				e.ghost = g.name
				table.insert(out, e)
			end
		end
	end
	return out
end

-- ---------------------------------------------------------------------------------------------
-- contacts (f0220)

-- Where the player and the ghosts met this tick: sharing a tile, or swapping tiles within the tick.
-- `prev` holds the tiles the ghosts occupied before the step (Ghosts.occupiedTiles).
function Ghosts.contacts(
	set: Set,
	prev: { Maze.Tile },
	playerPrev: Maze.Tile,
	playerNow: Maze.Tile
): { Contact }
	local out: { Contact } = {}
	local now = Ghosts.occupiedTiles(set)
	for i, g in set.ghosts do
		if g.status == "active" then
			local same = now[i].x == playerNow.x and now[i].y == playerNow.y
			local swapped = now[i].x == playerPrev.x
				and now[i].y == playerPrev.y
				and prev[i].x == playerNow.x
				and prev[i].y == playerNow.y
			if same or swapped then
				table.insert(out, { name = g.name, kind = if g.frightened then "eat" else "kill" })
			end
		end
	end
	return out
end

-- The player eats a ghost (on contact a frightened one, or any active one with a blaster shot): it becomes eyes and
-- the chain pays 200, 400, 800, 1600. The chain restarts with every power pellet and when the power runs out.
function Ghosts.eat(set: Set, name: Name): number
	local g = Ghosts.ghost(set, name)
	g.status = "eyes"
	g.frightened = false
	g.reverse = false -- a pending turn-back dies with the ghost's old life
	set.chain += 1
	return EYES_SCORE[math.min(set.chain, #EYES_SCORE)]
end

-- ---------------------------------------------------------------------------------------------
-- resets

-- Back to the starts. "respawn" after a death keeps the counters and starts the global counter;
-- "level" and "run" begin afresh (a run also starts at level 1).
function Ghosts.reset(set: Set, reason: "respawn" | "level" | "run", level: number)
	set.level = level
	set.mode, set.phase, set.phaseTicks = "scatter", 1, 0
	set.frightened, set.chain = 0, 0
	set.house.idle = 0
	if reason == "respawn" then
		set.house.global = 0
	else
		set.house.personal = { pinky = 0, inky = 0, clyde = 0 }
		set.house.global = nil
	end
	place(set)
end

return Ghosts
