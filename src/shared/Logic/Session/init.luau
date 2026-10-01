--!strict
-- Session: one maze with its players, a validated and rate-limited intent queue per player, a
-- fixed-tick step, versioned snapshots for replication, and the server's fixed-step clock.
--
-- Tick contract: step k takes time k to k + 1. Intents submitted before step k act in step k, and
-- the events it returns are visible at time k + 1, which is the new `tick`.
local Maze = require("./Maze")
local Movement = require("./Movement")

export type PlayerId = string
export type Config = { movement: Movement.Config, maxIntentsPerTick: number }
export type PlayerSnapshot = {
	x: number,
	y: number, -- Movement.position: continuous tile coordinates
	heading: Maze.Heading,
	moving: boolean,
	jumpTick: number, -- tick of the latest position discontinuity, -1 if none
}
export type Snapshot = { v: number, tick: number, maze: string, player: PlayerSnapshot }
export type Event = { kind: string, player: PlayerId, x: number?, y: number? }
export type Clock = { rate: number, maxSteps: number, acc: number }

type Member = {
	move: Movement.State,
	queue: { Movement.Intent },
	jumpTick: number,
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

function Session.new(maze: Maze.Maze, seed: number, config: Config?): Session
	local c = config or Session.DEFAULT_CONFIG
	Movement.validateConfig(c.movement)
	if type(c.maxIntentsPerTick) ~= "number" or c.maxIntentsPerTick < 1 then
		error(`session: maxIntentsPerTick must be >= 1, got {c.maxIntentsPerTick}`, 0)
	end
	return { tick = 0, maze = maze, seed = seed, config = c, members = {} }
end

function Session.join(s: Session, id: PlayerId)
	if s.members[id] then
		error(`session: player {id} already joined`, 0)
	end
	s.members[id] = { move = Movement.spawn(s.maze), queue = {}, jumpTick = -1 }
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

function Session.step(s: Session): { Event }
	s.tick += 1
	local out: { Event } = {}
	for _, id in Session.players(s) do
		local member = s.members[id]
		local queue = member.queue
		member.queue = {}
		for _, e in Movement.step(s.maze, member.move, queue, s.config.movement) do
			local event: Event = { kind = e.kind, player = id }
			if e.kind == "Entered" or e.kind == "Stopped" then
				event.x, event.y = e.x, e.y
			elseif e.kind == "Wrapped" then
				member.jumpTick = s.tick
			end
			table.insert(out, event)
		end
	end
	return out
end

function Session.snapshot(s: Session, id: PlayerId): Snapshot
	local member = s.members[id]
	if member == nil then
		error(`session: unknown player {id}`, 0)
	end
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
