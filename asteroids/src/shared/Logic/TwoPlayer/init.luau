--!strict
-- TwoPlayer: two ships on one field, a match as plain data stepped once per tick with both players' inputs. The
-- rocks, the saucer and the waves are shared; each player has their own ship, shots, score, lives and revives,
-- through Pilot's and Classic's own steps. The ships start on opposite sides, the waves have 1.5 x the rocks, shots pass
-- through the other ship and the ships bounce off each other (two switches), and a lone survivor plays on.
local Classic = require("./Classic")
local Field = require("./Field")
local Ship = require("./Ship")

export type Phase = "playing" | "gameover"
export type Config = {
	classic: Classic.Config, -- every solo rule's numbers, with 1.5 x the rocks
	homes: { Classic.Home }, -- where each player's ship starts and respawns
	friendlyFire: boolean, -- a shot can destroy the other player's exposed ship
	shipsBounce: boolean, -- two ships on the field bounce off each other
}
-- a player's side: Classic's player (every field of Classic.Player), their revives, and whether they have left
export type Pilot = {
	ship: Ship.Ship,
	shipState: Classic.ShipState,
	timer: number,
	protect: number,
	shots: { Classic.Shot },
	lives: number,
	score: number,
	nextExtra: number,
	home: Classic.Home?,
	phase: Classic.Phase,
	slot: number?,
	revives: number,
	left: boolean,
}
-- the field's side is Classic's run (every field of Classic.Run); the match adds its switches, its phase, the
-- tick's lead and the two pilots
export type Match = {
	config: Classic.Config,
	wave: number,
	rng: number,
	nextId: number,
	rocks: { Classic.Rock },
	saucer: Classic.Saucer?,
	saucerShots: { Classic.Shot },
	saucerElapsed: number,
	waveTimer: number,
	pair: Config,
	phase: Phase,
	lead: number,
	pilots: { Pilot },
}

local TwoPlayer = {}

local function frozenCopy<T>(base: T, changes: { [string]: any }): T
	local out = table.clone(base :: any)
	for k, v in changes do
		out[k] = v
	end
	return table.freeze(out) :: any
end

local SOLO = Classic.CONFIG
local W, H = SOLO.field.width, SOLO.field.height

TwoPlayer.CONFIG = table.freeze({
	-- 1.5 x the solo count, rounded down: 6, 9, 12, 15, then 16
	classic = frozenCopy(SOLO, { firstRocks = 6, rocksStep = 3, maxRocks = 16 }),
	homes = table.freeze({
		table.freeze({ x = W / 4, y = H / 2 }),
		table.freeze({ x = 3 * W / 4, y = H / 2 }),
	}),
	friendlyFire = false,
	shipsBounce = true,
} :: Config)

local function pilot(c: Config, slot: number): Pilot
	local home = c.homes[slot]
	return {
		phase = "playing",
		score = 0,
		lives = c.classic.lives,
		nextExtra = c.classic.extraLifeEvery,
		ship = Ship.new(c.classic.ship, home.x, home.y),
		shipState = "alive",
		timer = 0,
		protect = 0,
		shots = {},
		slot = slot,
		home = { x = home.x, y = home.y },
		revives = 0,
		left = false,
	}
end

local function playing(p: Pilot): boolean
	return p.phase == "playing"
end

-- the ships the next wave's rocks keep clear of: every player still playing
local function ships(m: Match): { Ship.Ship }
	local out = {}
	for _, p in m.pilots do
		if playing(p) then
			table.insert(out, p.ship)
		end
	end
	return out
end

function TwoPlayer.new(seed: number, config: Config?): Match
	local c = config or TwoPlayer.CONFIG
	local m: Match = {
		config = c.classic,
		wave = 1,
		rng = Classic.seed(seed),
		nextId = 1,
		rocks = {},
		saucer = nil,
		saucerShots = {},
		saucerElapsed = 0,
		waveTimer = 0,
		pair = c,
		phase = "playing",
		lead = 1,
		pilots = { pilot(c, 1), pilot(c, 2) },
	}
	Classic.spawnWave(m, ships(m))
	return m
end

local function inputOf(inputs: any, slot: number): Classic.Input?
	if type(inputs) ~= "table" then
		return nil
	end
	return inputs[slot]
end

-- An elastic bounce of two equal ships on the field whose centres are closer than their two radii: each moves
-- half the overlap apart along the line of centres, and, if they are closing, they swap their speeds along it.
local function bounce(m: Match, a: Pilot, b: Pilot, events: { Classic.Event })
	local c, f = m.config, m.config.field
	local reach = 2 * c.ship.radius
	local dx, dy = Field.delta(f, a.ship.x, a.ship.y, b.ship.x, b.ship.y)
	local d = math.sqrt(dx * dx + dy * dy)
	if d >= reach then
		return
	end
	local nx, ny = 1, 0
	if d > 0 then
		nx, ny = dx / d, dy / d
	end
	local push = (reach - d) / 2
	a.ship.x, a.ship.y = Field.wrap(f, a.ship.x - nx * push, a.ship.y - ny * push)
	b.ship.x, b.ship.y = Field.wrap(f, b.ship.x + nx * push, b.ship.y + ny * push)
	local closing = (b.ship.vx - a.ship.vx) * nx + (b.ship.vy - a.ship.vy) * ny
	if closing < 0 then
		a.ship.vx += nx * closing
		a.ship.vy += ny * closing
		b.ship.vx -= nx * closing
		b.ship.vy -= ny * closing
	end
	for _, s in { a.ship, b.ship } do
		local speed = math.sqrt(s.vx * s.vx + s.vy * s.vy)
		if speed > c.ship.maxSpeed then
			s.vx = s.vx * c.ship.maxSpeed / speed
			s.vy = s.vy * c.ship.maxSpeed / speed
		end
	end
	table.insert(events, { kind = "Bounce" })
end

-- the ship the saucer aims at: the nearest on the field, the tick's lead on a tie
local function target(m: Match, order: { Pilot }): Pilot?
	local s = m.saucer
	if s == nil then
		return nil
	end
	local best, bestD = nil :: Pilot?, math.huge
	for _, p in order do
		if playing(p) and p.shipState == "alive" then
			local d = Field.distance(m.config.field, s.x, s.y, p.ship.x, p.ship.y)
			if d < bestD then
				best, bestD = p, d
			end
		end
	end
	return best
end

-- after a stage: a player out has no shots; both out ends the match (true: the rest of the tick is skipped)
local function settle(m: Match, events: { Classic.Event }): boolean
	local left = 0
	for _, p in m.pilots do
		if playing(p) then
			left += 1
		else
			p.shots = {}
		end
	end
	if left == 0 then
		m.phase = "gameover"
		table.insert(events, { kind = "MatchOver" })
		return true
	end
	return false
end

-- read through a call, so the checks after each stage are not narrowed away
local function over(m: Match): boolean
	return m.phase == "gameover"
end

-- One tick; the events in the order they happened. The tick's lead (player 1 on the first tick, then turn about)
-- goes first at every stage and wins every tie. A finished match (gameover) changes no more until a revive.
function TwoPlayer.step(m: Match, inputs: { Classic.Input? }?): { Classic.Event }
	local events: { Classic.Event } = {}
	if over(m) then
		return events
	end
	local order = { m.pilots[m.lead], m.pilots[3 - m.lead] }
	m.lead = 3 - m.lead
	-- 1. each ship's clocks
	for _, p in order do
		if playing(p) then
			Classic.clock(m, p, events)
		end
	end
	if settle(m, events) then
		return events
	end
	-- 2. each player's input
	for _, p in order do
		if playing(p) then
			Classic.control(m, p, inputOf(inputs, p.slot :: number), events)
		end
	end
	-- 3. the ships bounce
	local a, b = order[1], order[2]
	if
		m.pair.shipsBounce
		and playing(a)
		and playing(b)
		and a.shipState == "alive"
		and b.shipState == "alive"
	then
		bounce(m, m.pilots[1], m.pilots[2], events)
	end
	-- 4. the rocks, 5. the saucer
	Classic.moveRocks(m)
	Classic.saucerStep(m, target(m, order), events)
	-- 6. each player's shots
	for i, p in order do
		if playing(p) then
			local foe = order[3 - i]
			Classic.moveShots(m, p, if m.pair.friendlyFire and playing(foe) then foe else nil, events)
		end
	end
	if settle(m, events) then
		return events
	end
	-- 7. the saucer's shots
	local live: { Classic.Player } = {}
	for _, p in order do
		if playing(p) then
			table.insert(live, p)
		end
	end
	Classic.moveSaucerShots(m, live, events)
	if settle(m, events) then
		return events
	end
	-- 8. each ship's collisions
	for _, p in order do
		if playing(p) then
			Classic.collide(m, p, events)
		end
	end
	if settle(m, events) then
		return events
	end
	-- 9. the waves
	Classic.waveClock(m, ships(m), events)
	return events
end

-- Player slot's run is over: 3 new lives, keeping their score; their ship comes back at its home once that is
-- clear, protected. False (and nothing changes) unless their run is over and they have not left.
function TwoPlayer.revive(m: Match, slot: number): boolean
	local p = m.pilots[slot]
	if p == nil or p.left or p.phase ~= "gameover" then
		return false
	end
	p.phase = "playing"
	p.lives = m.config.lives
	p.revives += 1
	p.shipState = "dead"
	p.timer = 0
	p.protect = 0
	p.shots = {}
	m.phase = "playing"
	return true
end

-- Player slot leaves the match: out at once, for good (no revive), their ship and shots gone; the other plays on.
-- False if they have already left.
function TwoPlayer.leave(m: Match, slot: number): boolean
	local p = m.pilots[slot]
	if p == nil or p.left then
		return false
	end
	p.left = true
	p.phase = "gameover"
	local home = p.home :: Classic.Home
	p.ship = Ship.new(m.config.ship, home.x, home.y)
	p.shipState = "dead"
	p.timer = 0
	p.protect = 0
	p.shots = {}
	local any = false
	for _, q in m.pilots do
		any = any or playing(q)
	end
	if not any then
		m.phase = "gameover"
	end
	return true
end

return TwoPlayer
