--!strict
-- Session: one maze with its players, a validated and rate-limited intent queue per player, a
-- fixed-tick step, versioned snapshots for replication, and the server's fixed-step clock.
--
-- Tick contract: step k takes time k to k + 1. Intents submitted before step k act in step k, and
-- the events it returns are visible at time k + 1, which is the new `tick`.
--
-- Order inside one step, per player (a contract): Game.step (a Ready event resets the ghosts), then, if the run
-- is in play, the player's movement and eating, then the ghosts (the pellets eaten reach the house, the ghosts
-- walk, then a power pellet eaten this tick turns them blue, so their blue clock equals the run's), then, only
-- if the run is still in play (a cleared level wins), the contacts: a kill beats an eating, and eatings pay along
-- the chain.
--
-- A fire intent (Blaster.intent) shares the Intent queue's per-tick limit, at most one per tick. It is taken at the
-- start of the player's play in the step, before the player moves: one shot is spent, and the first active ghost
-- along that heading from the player's tile is eaten on the chain, as if it had been eaten on contact. A fire in a
-- pause, with no shots, or in a session without ghosts does nothing and spends nothing. Each ghost eaten on
-- contact rolls for a dropped shot (Blaster.drop); a shot ghost does not.
--
-- A hop intent (Hop.INTENT, f0101) shares that limit too, at most one per tick. It starts a hop at the start of
-- the player's play in the step, if the run is in play and the last hop has landed and cooled down (Hop.canStart);
-- otherwise it does nothing. While the player is airborne (Hop.airborne) they eat no pellet and meet no ghost:
-- no catch, and a frightened ghost is passed over. The rail movement goes on underneath. A hop that leaves play
-- before its second step is forgotten, so a death or a level clear on the ground does not play the arc. The last
-- tick that was in play decides: this step's tick when the step began in play, and the previous tick when it
-- began already paused (Session.kill happens between steps, after Session.step has moved the clock). A hop that
-- has reached step 2 keeps its tick, so the descent still shows.
local Blaster = require("./Blaster")
local Game = require("./Game")
local Ghosts = require("./Ghosts")
local Hop = require("./Hop")
local Levels = require("./Levels")
local Maze = require("./Maze")
local Movement = require("./Movement")
local Pellets = require("./Pellets")
local Picks = require("./Picks")

export type PlayerId = string
export type Config = {
	movement: Movement.Config,
	maxIntentsPerTick: number,
	play: Game.Config?, -- the run's rules; nil means no pauses (a run in play from tick 0)
	eatSlowdown: boolean?, -- eating stops the player for a moment, as in the arcade
	ghosts: boolean?, -- the four ghosts hunt the player (mazes with ghost data only)
}
export type PlayerSnapshot = {
	x: number,
	y: number, -- Movement.position: continuous tile coordinates
	heading: Maze.Heading,
	moving: boolean,
	jumpTick: number, -- tick of the latest position discontinuity, -1 if none
}
export type Look = Ghosts.Look
export type GhostSnapshot = {
	name: Ghosts.Name,
	x: number,
	y: number, -- continuous tile coordinates
	heading: Maze.Heading,
	look: Look,
	flash: boolean, -- the white half of a blinking flash
	jumpTick: number, -- tick of the latest position discontinuity, -1 if none
}
export type Snapshot = {
	v: number,
	tick: number,
	maze: string,
	player: PlayerSnapshot,
	ghosts: { GhostSnapshot }?, -- present when the session has ghosts
}
export type PlayFrame = {
	phase: Game.Phase,
	level: number,
	score: number,
	lives: number,
	timer: number,
	frightened: number,
}
export type Frame = {
	v: number,
	tick: number,
	maze: string,
	player: PlayerSnapshot,
	play: PlayFrame,
	pellets: string, -- Pellets.encode of what the player has left to eat
	ghosts: { GhostSnapshot }?, -- the ghosts of a session that has them
	shots: number?, -- blaster shots held, 0..Blaster.MAX_SHOTS (always set by Session.frame)
	shot: Shot?, -- the latest shot taken (one that spent a shot), nil before any
	hopped: number?, -- the tick the latest hop started (f0101), nil before any
	hopTicks: number?, -- that hop's length in steps (Hop.TICKS, or Hop.LONG_TICKS with the jumps boon), f0126
	walls: Walls?, -- the picked holes and the marked walls (f0126; always set by Session.frame)
	pick: Pick?, -- the pick under way, nil when none
	boon: BoonGrant?, -- the latest boon a finished pick granted, nil before any
}
-- f0126: `opened` are the walls picked open since the maze was fresh, in the order they opened; `marked` the walls
-- that can be picked now.
export type Walls = { opened: { Maze.Tile }, marked: { Maze.Tile } }
-- wall: the marked wall being picked; started: the step that began it; ticks: steps it needs after that one
export type Pick = { wall: Maze.Tile, started: number, ticks: number, fast: boolean }
export type BoonGrant = { tick: number, kind: Picks.Boon }
-- tick: the tick whose step took it; from: the tile the shot started from (the player's, before that step's move)
export type Shot = { tick: number, heading: Maze.Heading, from: Maze.Tile }
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
	ghost: Ghosts.Name?,
	heading: Maze.Heading?,
}
export type Clock = { rate: number, maxSteps: number, acc: number }

type Member = {
	move: Movement.State,
	queue: { Movement.Intent },
	jumpTick: number,
	play: Game.Game,
	pellets: Pellets.Pellets,
	stall: number, -- units of eating pause still owed
	ghosts: Ghosts.Set?,
	ghostJump: { [string]: number }, -- per ghost: tick of its latest position discontinuity
	blaster: Blaster.Blaster,
	fire: Maze.Heading?, -- the shot asked for this tick
	shot: Shot?, -- the latest shot taken
	hop: boolean, -- a hop asked for this tick
	hopped: number?, -- the tick the latest hop started
	hopTicks: number, -- the latest hop's length
	opened: { Maze.Tile }, -- the one record of this member's holes: the maze it plays in is derived from it
	cache: { list: { Maze.Tile }, n: number, maze: Maze.Maze }, -- mazeOf's last answer
	picks: Picks.Picks,
	armed: number, -- steps a pick request stays pending (0: none)
	pick: Pick?,
	longHops: boolean, -- the jumps boon, until the maze is fresh again
	boon: BoonGrant?,
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
	ghosts = true,
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
		ghosts = if s.config.ghosts and Ghosts.available(s.maze) then Ghosts.new(s.maze, s.seed) else nil,
		ghostJump = {},
		blaster = Blaster.new(s.seed),
		fire = nil,
		hop = false,
		hopTicks = Hop.TICKS,
		opened = {},
		cache = { list = {}, n = -1, maze = s.maze },
		picks = Picks.new(s.seed),
		armed = 0,
		pick = nil,
		longHops = false,
		boon = nil,
	}
	Picks.reset(s.members[id].picks, s.maze)
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
	local fire: Maze.Heading? = Blaster.heading(raw)
	local hop = Hop.isIntent(raw)
	local pick = Picks.isIntent(raw)
	if fire == nil and not hop and not pick and not Movement.isIntent(raw) then
		return false, "invalid intent"
	end
	if pick then
		-- a pick request, pending like a buffered turn; a repeat only restarts it, and one during a pick is ignored.
		-- It holds no queue slot, so it neither counts toward the per-tick limit nor is refused by it.
		if member.pick == nil then
			member.armed = s.config.movement.turnBufferTicks
		end
		return true, nil
	end
	local pending = #member.queue + (if member.fire then 1 else 0) + (if member.hop then 1 else 0)
	if pending >= s.config.maxIntentsPerTick then
		return false, "rate limited"
	end
	if hop then
		if member.hop then
			return false, "rate limited" -- one hop a tick
		end
		member.hop = true
		return true, nil
	end
	if fire then
		if member.fire then
			return false, "rate limited" -- one shot a tick
		end
		member.fire = fire
		return true, nil
	end
	table.insert(member.queue, raw)
	return true, nil
end

-- The maze this member plays in: the session's with the member's holes open (f0126). Derived from `opened`, the one
-- record of the holes, and kept for as long as `opened` is the same list of the same length.
local function mazeOf(s: Session, member: Member): Maze.Maze
	local c = member.cache
	if c.list ~= member.opened or c.n ~= #member.opened then
		member.cache = { list = member.opened, n = #member.opened, maze = Maze.opened(s.maze, member.opened) }
	end
	return member.cache.maze
end

-- the player back at the spawn: a teleport, so the camera cuts at `jumpTick`
local function teleport(s: Session, member: Member, jumpTick: number)
	member.move = Movement.spawn(mazeOf(s, member))
	member.queue = {}
	member.fire = nil
	member.hop = false
	member.hopped = nil
	member.jumpTick = jumpTick
	member.stall = 0
	member.armed = 0
	member.pick = nil
end

-- The member's maze fresh again (a new level, a new run): the holes close, new walls are marked, the long hops end.
local function freshMaze(s: Session, member: Member)
	member.opened = {}
	member.longHops = false
	Picks.reset(member.picks, mazeOf(s, member))
end

-- A hop that has not reached its second step is still on the ground, with the rise ahead of it. Leaving play
-- there forgets it, and drops a Hopped event from this same step, so the pause does not play the arc. `tick` is
-- the last tick that was in play: this step when the step began in play, the previous tick when it began already
-- paused. A hop whose last in-play tick has reached step 2 keeps its tick: the landing blend is the descent.
local function forgetYoungHop(member: Member, id: PlayerId, tick: number, out: { Event })
	local started = member.hopped
	if started == nil or tick >= started + 2 or Game.canMove(member.play) then
		return
	end
	member.hopped = nil
	for i = #out, 1, -1 do
		local e = out[i]
		if e.kind == "Hopped" and e.player == id then
			table.remove(out, i)
		end
	end
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

-- Every ghost back at its start (and a camera cut for each): after a death, on a new level, on a new run.
local function resetGhosts(member: Member, reason: string?, tick: number)
	local set = member.ghosts
	if set == nil then
		return
	end
	local why: "respawn" | "level" | "run" = if reason == "respawn"
		then "respawn"
		elseif reason == "again" then "run"
		else "level"
	Ghosts.reset(set, why, member.play.level)
	for _, name: Ghosts.Name in Ghosts.NAMES do
		member.ghostJump[name] = tick
	end
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

-- A wasted pick: the player may go on (Forward alone never restarts a stopped player).
local function stopPick(s: Session, member: Member, id: PlayerId, reason: string, out: { Event })
	if member.pick then
		member.pick = nil
		table.insert(out, { kind = "PickStopped", player = id, reason = reason })
		Movement.resume(mazeOf(s, member), member.move)
	end
end

-- The ghosts take their step after the player, then meet the player. A pellet eaten this tick counts for the
-- house first; a power pellet turns the ghosts blue after they have moved (so the clock matches the run's).
local function stepGhosts(
	s: Session,
	id: PlayerId,
	member: Member,
	playerPrev: Maze.Tile,
	ghostsPrev: { Maze.Tile },
	from: number,
	out: { Event }
)
	local set = member.ghosts :: Ghosts.Set
	local power: number? = nil
	for i = from + 1, #out do
		local e = out[i]
		if e.kind == "PelletEaten" then
			for _, g in Ghosts.pelletEaten(set) do
				local kind: string = g.kind
				table.insert(out, { kind = kind, player = id, ghost = g.ghost })
			end
		elseif e.kind == "PowerStarted" then
			power = e.ticks
		end
	end
	local playerNow = Movement.occupied(mazeOf(s, member), member.move)
	local input: Ghosts.Input = {
		player = playerNow,
		heading = member.move.heading,
		level = member.play.level,
		baseSpeed = s.config.movement.speed,
		tickRate = Session.TICK_RATE,
		maze = mazeOf(s, member), -- the ghosts walk the member's maze, holes and all
	}
	for _, g in Ghosts.step(set, input) do
		local kind: string = g.kind
		if kind == "Wrapped" and g.ghost then
			member.ghostJump[g.ghost] = s.tick
		elseif kind ~= "Entered" then
			local event: Event = { kind = kind, player = id, ghost = g.ghost }
			table.insert(out, event)
		end
	end
	if power then
		Ghosts.power(set, power)
	end
	-- the last pellet clearing the level this very tick wins over a ghost that arrives at the same time; an
	-- airborne player meets no ghost at all
	if not Game.canMove(member.play) or Hop.airborne(member.hopped, s.tick, member.hopTicks) then
		return
	end
	local kill = false
	local eaten: { Ghosts.Name } = {}
	for _, c in Ghosts.contacts(set, ghostsPrev, playerPrev, playerNow) do
		if c.kind == "kill" then
			kill = true
			table.insert(out, { kind = "Caught", player = id, ghost = c.name })
		else
			table.insert(eaten, c.name)
		end
	end
	if kill then
		stopPick(s, member, id, "caught", out) -- caught while picking: the pick is wasted
		member.armed = 0
		for _, e in Game.died(member.play) do
			table.insert(out, tagged(id, e))
		end
		return
	end
	for _, name: Ghosts.Name in eaten do
		local points = Ghosts.eat(set, name)
		local event: Event = { kind = "GhostEaten", player = id, ghost = name, points = points }
		table.insert(out, event)
		for _, e in Game.addScore(member.play, points) do
			table.insert(out, tagged(id, e))
		end
		if Blaster.drop(member.blaster) then
			table.insert(out, { kind = "ShotGained", player = id, ghost = name })
		end
	end
end

-- The shot asked for this tick, taken before the player moves: one shot spent, and the first active ghost along
-- the heading from the player's tile eaten on the chain. Nothing happens, and nothing is spent, without ghosts or
-- without a shot.
local function shoot(s: Session, id: PlayerId, member: Member, heading: Maze.Heading, out: { Event })
	local set = member.ghosts
	if set == nil or not Blaster.spend(member.blaster) then
		return
	end
	local from = Movement.occupied(mazeOf(s, member), member.move)
	member.shot = { tick = s.tick, heading = heading, from = { x = from.x, y = from.y } }
	local targets: { Blaster.Target } = {}
	for i, tile in Ghosts.occupiedTiles(set) do
		table.insert(targets, { tile = tile, active = set.ghosts[i].status == "active" })
	end
	local hit = Blaster.target(mazeOf(s, member), from, heading, targets)
	if hit == nil then
		table.insert(out, { kind = "Shot", player = id, heading = heading })
		return
	end
	local name: Ghosts.Name = set.ghosts[hit].name
	local points = Ghosts.eat(set, name)
	table.insert(out, { kind = "Shot", player = id, heading = heading, ghost = name, points = points })
	for _, e in Game.addScore(member.play, points) do
		table.insert(out, tagged(id, e))
	end
end

-- A finished pick: the wall opens (for the player and the ghosts), the next wall is marked, the boon is rolled and
-- granted, and the player may go on.
local function finishPick(s: Session, id: PlayerId, member: Member, out: { Event })
	local pick = member.pick :: Pick
	member.pick = nil
	table.insert(member.opened, { x = pick.wall.x, y = pick.wall.y })
	Picks.unmark(member.picks, pick.wall)
	Picks.mark(member.picks, mazeOf(s, member))
	if pick.fast then
		member.picks.fast -= 1
	end
	local boon: Picks.Boon = Picks.roll(member.picks)
	member.boon = { tick = s.tick, kind = boon }
	local item: string = boon
	table.insert(out, { kind = "WallPicked", player = id, x = pick.wall.x, y = pick.wall.y, item = item })
	if boon == "jumps" then
		member.longHops = true
	elseif boon == "fastpick" then
		member.picks.fast += 1
	elseif boon == "pill" or boon == "longpill" then
		for _, e in Game.power(member.play, if boon == "longpill" then Picks.LONG_PILL_FACTOR else 1) do
			table.insert(out, tagged(id, e))
		end
	elseif boon == "shot" then
		if Blaster.gain(member.blaster) then
			table.insert(out, { kind = "ShotGained", player = id })
		end
	else
		Pellets.reset(member.pellets)
		table.insert(out, { kind = "PelletsBack", player = id })
	end
	Movement.resume(mazeOf(s, member), member.move)
end

-- The pick starts where the player stands on a tile centre next to a marked wall.
local function startPick(s: Session, id: PlayerId, member: Member, wall: Maze.Tile, out: { Event })
	Movement.halt(member.move)
	local fast = member.picks.fast > 0
	-- ten paces of this member's own ghosts: their tuning (f0125's slower ghosts) included
	local tuning = if member.ghosts then member.ghosts.tuning else nil
	local ghost = Levels.ghostSpeed(s.config.movement.speed, member.play.level, "normal", tuning)
	local ticks = Picks.ticks(ghost, fast)
	member.armed = 0
	member.pick = { wall = { x = wall.x, y = wall.y }, started = s.tick, ticks = ticks, fast = fast }
	table.insert(out, { kind = "PickStarted", player = id, x = wall.x, y = wall.y, ticks = ticks })
end

function Session.step(s: Session): { Event }
	s.tick += 1
	local out: { Event } = {}
	for _, id in Session.players(s) do
		local member = s.members[id]
		local queue = member.queue
		member.queue = {}
		local fire: Maze.Heading? = member.fire
		member.fire = nil
		local hop = member.hop
		member.hop = false
		-- whether the player moves this tick is decided before the run's phase changes
		local moving = Game.canMove(member.play)
		local frightened = member.play.frightened > 0
		for _, e in Game.step(member.play) do
			table.insert(out, tagged(id, e))
			if e.kind == "Ready" then
				if e.reason ~= "respawn" then
					Pellets.reset(member.pellets) -- a new level or a new run: every pellet is back
					freshMaze(s, member)
				end
				teleport(s, member, s.tick)
				resetGhosts(member, e.reason, s.tick)
			end
		end
		if not moving then
			forgetYoungHop(member, id, s.tick - 1, out) -- already out of play; the last in-play tick is the previous one
			stopPick(s, member, id, "pause", out)
			member.armed = 0
			continue
		end
		local before = #out
		-- a pick that has stood its time finishes first, before this step's keys can waste it
		local pick = member.pick
		if pick and s.tick >= pick.started + pick.ticks then
			finishPick(s, id, member, out)
		end
		if fire then
			shoot(s, id, member, fire, out)
		end
		if hop and Hop.canStart(member.hopped, s.tick, member.hopTicks) then
			member.hopped = s.tick
			member.hopTicks = if member.longHops then Hop.LONG_TICKS else Hop.TICKS
			table.insert(out, { kind = "Hopped", player = id })
			stopPick(s, member, id, "hopped", out)
		end
		if member.pick and #queue > 0 then
			stopPick(s, member, id, "moved", out) -- any movement key leaves the wall
		end
		local airborne = Hop.airborne(member.hopped, s.tick, member.hopTicks)
		local speed = Levels.playerSpeed(s.config.movement.speed, member.play.level, frightened)
		-- an eating pause is owed distance: this step covers what is left of the speed
		local owed = math.min(member.stall, speed)
		member.stall -= owed
		local config: Movement.Config =
			{ speed = speed - owed, turnBufferTicks = s.config.movement.turnBufferTicks }
		-- a pending pick stops the player on the next centre beside a marked wall: this step goes no further
		local target: Maze.Tile? = nil
		local wall: Maze.Tile? = nil
		-- no pick starts while a hop is under way (from its take-off step until it lands), nor with keys this step
		local hopping = member.hopped ~= nil and s.tick < (member.hopped :: number) + member.hopTicks
		if member.armed > 0 and member.pick == nil and not hopping and #queue == 0 then
			local distance, centre = Movement.nextCentre(mazeOf(s, member), member.move)
			local beside = Picks.wallBeside(member.picks, mazeOf(s, member), centre, member.move.heading)
			if beside and distance <= config.speed then
				target, wall = centre, beside
				config.speed = distance
			end
		end
		local playerPrev = Movement.occupied(mazeOf(s, member), member.move)
		local ghostsPrev = if member.ghosts then Ghosts.occupiedTiles(member.ghosts) else {}
		for _, e in Movement.step(mazeOf(s, member), member.move, queue, config) do
			local event: Event = { kind = e.kind, player = id }
			if e.kind == "Entered" or e.kind == "Stopped" then
				event.x, event.y = e.x, e.y
			elseif e.kind == "Wrapped" then
				member.jumpTick = s.tick
			end
			table.insert(out, event)
			if e.kind == "Entered" and not airborne then
				eat(s, id, member, { x = e.x, y = e.y }, speed, out)
			end
		end
		if target and wall and Game.canMove(member.play) then
			local here = member.move
			if here.progress == 0 and here.tile.x == target.x and here.tile.y == target.y then
				startPick(s, id, member, wall, out)
			end
		elseif member.armed > 0 then
			member.armed -= 1
		end
		if member.ghosts then
			stepGhosts(s, id, member, playerPrev, ghostsPrev, before, out)
		end
		forgetYoungHop(member, id, s.tick, out) -- this step began in play
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

-- Whether this player's run is over (the results are up). A player the session doesn't know has no run.
function Session.isOver(s: Session, id: PlayerId): boolean
	local member = s.members[id]
	return member ~= nil and member.play.phase == "gameover"
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
		freshMaze(s, member)
		member.picks.fast = 0
		member.boon = nil
		teleport(s, member, s.tick + 1)
		Pellets.reset(member.pellets)
		resetGhosts(member, "again", s.tick + 1)
		Blaster.reset(member.blaster)
	end
	return out, ok
end

local function ghostSnapshots(member: Member): { GhostSnapshot }?
	local set = member.ghosts
	if set == nil then
		return nil
	end
	local out: { GhostSnapshot } = {}
	local flash = Ghosts.flash(set)
	for _, g in set.ghosts do
		local x, y = Ghosts.position(g)
		table.insert(out, {
			name = g.name,
			x = x,
			y = y,
			heading = g.heading,
			look = Ghosts.look(set, g),
			flash = flash and Ghosts.look(set, g) == "blinking",
			jumpTick = member.ghostJump[g.name] or -1,
		})
	end
	return out
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
		ghosts = ghostSnapshots(member),
	}
end

local function copyTiles(tiles: { Maze.Tile }): { Maze.Tile }
	local out: { Maze.Tile } = {}
	for i, tile in tiles do
		out[i] = { x = tile.x, y = tile.y }
	end
	return out
end

local function wallsOf(member: Member): Walls
	return { opened = copyTiles(member.opened), marked = copyTiles(member.picks.marked) }
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
		ghosts = snap.ghosts,
		play = {
			phase = play.phase,
			level = play.level,
			score = play.score,
			lives = play.lives,
			timer = play.timer,
			frightened = play.frightened,
		},
		pellets = Pellets.encode(s.members[id].pellets),
		shots = s.members[id].blaster.shots,
		shot = if s.members[id].shot
			then {
				tick = (s.members[id].shot :: Shot).tick,
				heading = (s.members[id].shot :: Shot).heading,
				from = { x = (s.members[id].shot :: Shot).from.x, y = (s.members[id].shot :: Shot).from.y },
			}
			else nil,
		hopped = s.members[id].hopped,
		hopTicks = s.members[id].hopTicks,
		walls = wallsOf(s.members[id]),
		pick = if s.members[id].pick
			then {
				wall = { x = (s.members[id].pick :: Pick).wall.x, y = (s.members[id].pick :: Pick).wall.y },
				started = (s.members[id].pick :: Pick).started,
				ticks = (s.members[id].pick :: Pick).ticks,
				fast = (s.members[id].pick :: Pick).fast,
			}
			else nil,
		boon = if s.members[id].boon
			then {
				tick = (s.members[id].boon :: BoonGrant).tick,
				kind = (s.members[id].boon :: BoonGrant).kind,
			}
			else nil,
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
