--!strict
-- Session: one maze with its players, a validated and rate-limited intent queue per player, a
-- fixed-tick step, versioned snapshots for replication, and the server's fixed-step clock.
--
-- Tick contract: step k takes time k to k + 1. Intents submitted before step k act in step k, and
-- the events it returns are visible at time k + 1, which is the new `tick`.
local Game = require("./Game")
local Levels = require("./Levels")
local Maze = require("./Maze")
local Movement = require("./Movement")
local Pellets = require("./Pellets")

export type PlayerId = string
export type Config = {
	movement: Movement.Config,
	maxIntentsPerTick: number,
	play: Game.Config?, -- the run's rules; nil means no pauses (a run in play from tick 0)
	eatSlowdown: boolean?, -- eating stops the player for a moment, as in the arcade
}
export type PlayerSnapshot = {
	x: number,
	y: number, -- Movement.position: continuous tile coordinates
	heading: Maze.Heading,
	moving: boolean,
	jumpTick: number, -- tick of the latest position discontinuity, -1 if none
}
export type Snapshot = { v: number, tick: number, maze: string, player: PlayerSnapshot }
export type PlayFrame = {
	phase: Game.Phase,
	level: number,
	score: number,
	lives: number,
	timer: number,
	frightened: number,
}
export type Frame = { v: number, tick: number, maze: string, player: PlayerSnapshot, play: PlayFrame }
export type Event = {
	kind: string,
	player: PlayerId,
	x: number?,
	y: number?,
	points: number?,
	lives: number?,
	level: number?,
	score: number?,
	ticks: number?,
	reason: string?,
	item: string?,
}
export type Clock = { rate: number, maxSteps: number, acc: number }

type Member = {
	move: Movement.State,
	queue: { Movement.Intent },
	jumpTick: number,
	play: Game.Game,
	pellets: Pellets.Pellets,
	stall: number, -- units of eating pause still owed
}
export type Session = {
	tick: number, -- steps completed
	maze: Maze.Maze,
	seed: number,
	config: Config,
	members: { [PlayerId]: Member },
}

local Session = {}
Session.TICK_RATE = 30 -- ticks per second of play: every rule counts these
Session.GAME_SPEED = 0.5 -- play runs at half speed in real time (user, 2026-10-01)
Session.STEP_RATE = Session.TICK_RATE * Session.GAME_SPEED -- steps per real second: what the clock and the client use
Session.SNAPSHOT_VERSION = 1
Session.MAX_STEPS_PER_ADVANCE = 5

local DEFAULT_CONFIG: Config = {
	movement = Movement.DEFAULT_CONFIG,
	maxIntentsPerTick = 4,
}
Session.DEFAULT_CONFIG = table.freeze(DEFAULT_CONFIG)

-- the real rules: the classic pauses and the eating slowdown
local GAME_CONFIG: Config = {
	movement = Movement.DEFAULT_CONFIG,
	maxIntentsPerTick = 4,
	play = Game.CLASSIC_CONFIG,
	eatSlowdown = true,
}
Session.GAME_CONFIG = table.freeze(GAME_CONFIG)

-- a speed that would cover more than one tile in a tick on some level is refused up front
local function checkLevelSpeeds(base: number)
	for level = 1, Levels.COUNT do
		for _, frightened in { false, true } do
			local speed = Levels.playerSpeed(base, level, frightened)
			if speed > Movement.UNITS then
				error(
					`session: speed {base} is too fast: level {level} would be {speed} > {Movement.UNITS}`,
					0
				)
			end
		end
	end
end

function Session.new(maze: Maze.Maze, seed: number, config: Config?): Session
	local c = config or Session.DEFAULT_CONFIG
	Movement.validateConfig(c.movement)
	if type(c.maxIntentsPerTick) ~= "number" or c.maxIntentsPerTick < 1 then
		error(`session: maxIntentsPerTick must be >= 1, got {c.maxIntentsPerTick}`, 0)
	end
	if c.play and c.play.tickRate ~= Session.TICK_RATE then
		error(`session: play.tickRate must be {Session.TICK_RATE}, got {c.play.tickRate}`, 0)
	end
	checkLevelSpeeds(c.movement.speed)
	return { tick = 0, maze = maze, seed = seed, config = c, members = {} }
end

function Session.join(s: Session, id: PlayerId)
	if s.members[id] then
		error(`session: player {id} already joined`, 0)
	end
	s.members[id] = {
		move = Movement.spawn(s.maze),
		queue = {},
		jumpTick = -1,
		play = Game.new(s.config.play or Game.IMMEDIATE_CONFIG),
		pellets = Pellets.new(s.maze),
		stall = 0,
	}
end

function Session.leave(s: Session, id: PlayerId)
	s.members[id] = nil
end

function Session.players(s: Session): { PlayerId }
	local ids: { PlayerId } = {}
	for id in s.members do
		table.insert(ids, id)
	end
	table.sort(ids)
	return ids
end

function Session.submit(s: Session, id: PlayerId, raw: any): (boolean, string?)
	local member = s.members[id]
	if member == nil then
		return false, "unknown player"
	end
	if not Movement.isIntent(raw) then
		return false, "invalid intent"
	end
	if #member.queue >= s.config.maxIntentsPerTick then
		return false, "rate limited"
	end
	table.insert(member.queue, raw)
	return true, nil
end

-- the player back at the spawn: a teleport, so the camera cuts at `jumpTick`
local function teleport(s: Session, member: Member, jumpTick: number)
	member.move = Movement.spawn(s.maze)
	member.queue = {}
	member.jumpTick = jumpTick
	member.stall = 0
end

local function tagged(id: PlayerId, e: Game.Event): Event
	return {
		kind = e.kind,
		player = id,
		points = e.points,
		lives = e.lives,
		level = e.level,
		score = e.score,
		ticks = e.ticks,
		reason = e.reason,
	}
end

-- The player entered a tile: eat what is on it, score it, owe the eating pause, and clear the level
-- when the last pellet goes. Appends to `out`.
local function eat(s: Session, id: PlayerId, member: Member, tile: Maze.Tile, speed: number, out: { Event })
	local eaten: Pellets.Kind? = Pellets.eat(member.pellets, tile)
	if eaten == nil then
		return
	end
	local kind: Pellets.Kind = eaten :: Pellets.Kind
	local points = Pellets.points(kind)
	local event: Event =
		{ kind = "PelletEaten", player = id, x = tile.x, y = tile.y, item = kind, points = points }
	table.insert(out, event)
	for _, e in Game.addScore(member.play, points) do
		table.insert(out, tagged(id, e))
	end
	if s.config.eatSlowdown then
		member.stall += Pellets.stallUnits(kind, speed, Session.TICK_RATE)
	end
	if kind == "power" then
		for _, e in Game.power(member.play) do
			table.insert(out, tagged(id, e))
		end
	end
	if Pellets.remaining(member.pellets) == 0 then
		for _, e in Game.cleared(member.play) do
			table.insert(out, tagged(id, e))
		end
	end
end

function Session.step(s: Session): { Event }
	s.tick += 1
	local out: { Event } = {}
	for _, id in Session.players(s) do
		local member = s.members[id]
		local queue = member.queue
		member.queue = {}
		-- whether the player moves this tick is decided before the run's phase changes
		local moving = Game.canMove(member.play)
		local frightened = member.play.frightened > 0
		for _, e in Game.step(member.play) do
			table.insert(out, tagged(id, e))
			if e.kind == "Ready" then
				teleport(s, member, s.tick)
				if e.reason ~= "respawn" then
					Pellets.reset(member.pellets) -- a new level or a new run: every pellet is back
				end
			end
		end
		if not moving then
			continue
		end
		local speed = Levels.playerSpeed(s.config.movement.speed, member.play.level, frightened)
		-- an eating pause is owed distance: this step covers what is left of the speed
		local owed = math.min(member.stall, speed)
		member.stall -= owed
		local config: Movement.Config =
			{ speed = speed - owed, turnBufferTicks = s.config.movement.turnBufferTicks }
		for _, e in Movement.step(s.maze, member.move, queue, config) do
			local event: Event = { kind = e.kind, player = id }
			if e.kind == "Entered" or e.kind == "Stopped" then
				event.x, event.y = e.x, e.y
			elseif e.kind == "Wrapped" then
				member.jumpTick = s.tick
			end
			table.insert(out, event)
			if e.kind == "Entered" then
				eat(s, id, member, { x = e.x, y = e.y }, speed, out)
			end
		end
	end
	return out
end

local function memberOf(s: Session, id: PlayerId): Member
	local member = s.members[id]
	if member == nil then
		error(`session: unknown player {id}`, 0)
	end
	return member
end

-- The server ends a life (a ghost caught the player). Only a run in play loses one.
function Session.kill(s: Session, id: PlayerId): { Event }
	local member = memberOf(s, id)
	local out: { Event } = {}
	for _, e in Game.died(member.play) do
		table.insert(out, tagged(id, e))
	end
	return out
end

-- A new run, only once the run is over. Made between steps, so the first frame at the spawn is the next tick's.
function Session.playAgain(s: Session, id: PlayerId): ({ Event }, boolean)
	local member = memberOf(s, id)
	local events, ok = Game.playAgain(member.play)
	local out: { Event } = {}
	for _, e in events do
		table.insert(out, tagged(id, e))
	end
	if ok then
		teleport(s, member, s.tick + 1)
		Pellets.reset(member.pellets)
	end
	return out, ok
end

function Session.snapshot(s: Session, id: PlayerId): Snapshot
	local member = memberOf(s, id)
	local x, y = Movement.position(member.move)
	return {
		v = Session.SNAPSHOT_VERSION,
		tick = s.tick,
		maze = s.maze.id,
		player = {
			x = x,
			y = y,
			heading = member.move.heading,
			moving = member.move.moving,
			jumpTick = member.jumpTick,
		},
	}
end

-- What the server replicates: the v1 snapshot plus the run's state. Later issues add fields beside
-- `play`; a client ignores fields it doesn't know.
function Session.frame(s: Session, id: PlayerId): Frame
	local snap = Session.snapshot(s, id)
	local play = s.members[id].play
	return {
		v = snap.v,
		tick = snap.tick,
		maze = snap.maze,
		player = snap.player,
		play = {
			phase = play.phase,
			level = play.level,
			score = play.score,
			lives = play.lives,
			timer = play.timer,
			frightened = play.frightened,
		},
	}
end

function Session.newClock(rate: number?, maxSteps: number?): Clock
	return {
		rate = rate or Session.TICK_RATE,
		maxSteps = maxSteps or Session.MAX_STEPS_PER_ADVANCE,
		acc = 0,
	}
end

-- Whole steps to run for a frame of dt seconds. A frame too long to catch up drops its backlog.
function Session.advance(c: Clock, dt: number): number
	if dt ~= dt or dt <= 0 then
		return 0
	end
	c.acc += dt
	-- the epsilon makes sixty frames of 1/60 s give exactly thirty steps
	local n = math.floor(c.acc * c.rate + 1e-9)
	if n > c.maxSteps then
		c.acc = 0
		return c.maxSteps
	end
	c.acc = math.max(0, c.acc - n / c.rate)
	return n
end

return Session
