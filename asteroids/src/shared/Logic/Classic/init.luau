--!strict
-- Classic: one player's run of Asteroids as plain data, stepped once per tick with the player's input, and
-- told what happened. The run is itself the player's Pilot (its ship, shots, lives and score), and owns the
-- rocks, the saucer, the waves and the order of a tick; the field, the ship's flight and life, the rocks and
-- the saucers are leaves.
local Field = require("./Field")
local Pilot = require("./Pilot")
local Rng = require("@self/Rng")
local Rocks = require("./Rocks")
local Saucers = require("./Saucers")
local Ship = require("./Ship")

export type Phase = "playing" | "gameover"
export type ShipState = Pilot.State
export type Cause = Pilot.Cause
export type By = "shot" | "ship"
export type Shot = Pilot.Shot
export type Input = { turn: number?, thrust: boolean?, fire: boolean?, hyperspace: boolean? }
export type Event = {
	kind: string,
	points: number?,
	id: number?,
	size: Rocks.SizeName?,
	saucer: Saucers.Kind?,
	by: By?,
	cause: Cause?,
	lives: number?,
	wave: number?,
	x: number?,
	y: number?,
}
export type Config = {
	tickRate: number,
	field: Field.Field,
	ship: Ship.Config,
	saucers: Saucers.Config,
	lives: number,
	extraLifeEvery: number,
	shotLimit: number,
	shotSpeed: number,
	shotLife: number,
	hyperspaceTicks: number,
	hyperspaceOdds: number,
	respawnTicks: number,
	clearRadius: number,
	protectTicks: number,
	firstRocks: number,
	rocksStep: number,
	maxRocks: number,
	waveTicks: number,
	spawnClear: number,
}
export type Game = {
	config: Config,
	phase: Phase,
	wave: number,
	score: number,
	lives: number,
	nextExtra: number,
	rng: number,
	nextId: number,
	ship: Ship.Ship,
	shipState: ShipState,
	timer: number,
	protect: number,
	shots: { Shot },
	rocks: { Rocks.Rock },
	saucer: Saucers.Saucer?,
	saucerShots: { Shot },
	saucerElapsed: number,
	waveTimer: number,
}

local Classic = {}

Classic.TICK_RATE = 60
Classic.CONFIG = table.freeze({
	tickRate = 60,
	field = Field.CLASSIC,
	ship = Ship.CLASSIC,
	saucers = Saucers.CLASSIC,
	lives = 3,
	extraLifeEvery = 10000,
	shotLimit = 4,
	shotSpeed = 8,
	shotLife = 60,
	hyperspaceTicks = 30,
	hyperspaceOdds = 6,
	respawnTicks = 120,
	clearRadius = 80,
	protectTicks = 120,
	firstRocks = 4,
	rocksStep = 2,
	maxRocks = 11,
	waveTicks = 120,
	spawnClear = 160,
} :: Config)

local function drawer(g: Game): Rocks.Draw
	return function(n: number): number
		local v
		g.rng, v = Rng.next(g.rng, n)
		return v
	end
end

-- the large rocks a wave starts with
function Classic.rockCount(c: Config, wave: number): number
	return math.min(c.maxRocks, c.firstRocks + c.rocksStep * (wave - 1))
end

-- The wave's rocks, each on the field's edge (draw(width + height) - 1 runs along the bottom edge, then up the
-- left one), moved half that edge along when it would start within spawnClear of the ship, then launched.
local function spawnWave(g: Game)
	local c, f = g.config, g.config.field
	local draw = drawer(g)
	for _ = 1, Classic.rockCount(c, g.wave) do
		local at = draw(f.width + f.height) - 1
		local x, y = at, 0
		if at >= f.width then
			x, y = 0, at - f.width
		end
		if Field.distance(f, x, y, g.ship.x, g.ship.y) < c.spawnClear then
			if at < f.width then
				x = (x + f.width / 2) % f.width
			else
				y = (y + f.height / 2) % f.height
			end
		end
		table.insert(g.rocks, Rocks.launch(g.nextId, "large", x, y, draw))
		g.nextId += 1
	end
end

function Classic.new(seed: number, config: Config?): Game
	local c = config or Classic.CONFIG
	local p = Pilot.new(c, c.field.width / 2, c.field.height / 2)
	local g: Game = {
		config = c,
		phase = "playing",
		wave = 1,
		score = p.score,
		lives = p.lives,
		nextExtra = p.nextExtra,
		rng = Rng.seed(seed),
		nextId = 1,
		ship = p.ship,
		shipState = p.shipState,
		timer = p.timer,
		protect = p.protect,
		shots = p.shots,
		rocks = {},
		saucer = nil,
		saucerShots = {},
		saucerElapsed = 0,
		waveTimer = 0,
	}
	spawnWave(g)
	return g
end

-- a pilot's events, copied into the run's
local function emitter(events: { Event }): (Pilot.Event) -> ()
	return function(e: Pilot.Event)
		table.insert(events, { kind = e.kind, lives = e.lives, cause = e.cause, x = e.x, y = e.y })
	end
end

local function endIfOut(g: Game, out: boolean, events: { Event }): boolean
	if out then
		g.phase = "gameover"
		table.insert(events, { kind = "GameOver" })
	end
	return out
end

local function breakRock(g: Game, index: number, by: By, events: { Event })
	local r = table.remove(g.rocks, index) :: Rocks.Rock
	local points = Rocks.SIZES[r.size].points
	table.insert(events, { kind = "RockHit", id = r.id, size = r.size, points = points, by = by })
	Pilot.award(g, g.config, points, emitter(events))
	local pieces = Rocks.split(r, g.nextId, drawer(g))
	for _, p in pieces do
		table.insert(g.rocks, p)
	end
	g.nextId += #pieces
end

local function breakSaucer(g: Game, by: By, events: { Event })
	local s = g.saucer :: Saucers.Saucer
	local points = g.config.saucers[s.kind].points
	g.saucer = nil
	g.saucerElapsed = 0
	table.insert(events, { kind = "SaucerHit", saucer = s.kind, points = points, by = by })
	Pilot.award(g, g.config, points, emitter(events))
end

local function centreClear(g: Game): boolean
	local c, f = g.config, g.config.field
	local cx, cy = f.width / 2, f.height / 2
	for _, r in g.rocks do
		if Field.distance(f, cx, cy, r.x, r.y) < Rocks.SIZES[r.size].radius + c.clearRadius then
			return false
		end
	end
	local s = g.saucer
	if s and Field.distance(f, cx, cy, s.x, s.y) < c.saucers[s.kind].radius + c.clearRadius then
		return false
	end
	return true
end

-- 4. the saucer: its clock while there is none, else its move, its leaving and its fire
local function saucerStep(g: Game, events: { Event })
	local f, sc = g.config.field, g.config.saucers
	local s = g.saucer
	if s == nil then
		g.saucerElapsed += 1
		if g.saucerElapsed >= Saucers.wait(sc, g.wave) then
			g.saucerElapsed = 0
			local new = Saucers.appear(sc, f, g.wave, drawer(g))
			g.saucer = new
			table.insert(events, { kind = "SaucerAppear", saucer = new.kind })
		end
		return
	end
	if Saucers.move(s, sc, f, drawer(g)) then
		g.saucer = nil
		g.saucerElapsed = 0
		table.insert(events, { kind = "SaucerLeave", saucer = s.kind })
		return
	end
	s.fireElapsed += 1
	if s.fireElapsed >= sc[s.kind].fireTicks and g.shipState == "alive" then
		s.fireElapsed = 0
		local h = Saucers.aim(s, sc, f, g.score, g.ship.x, g.ship.y, drawer(g))
		local ux, uy = Field.unit(h)
		table.insert(
			g.saucerShots,
			{ x = s.x, y = s.y, vx = ux * sc.shotSpeed, vy = uy * sc.shotSpeed, life = sc.shotLife }
		)
		table.insert(events, { kind = "SaucerFire", saucer = s.kind })
	end
end

-- 5. the player's shots, oldest first: each hits the first rock or saucer along its move, or flies on
local function moveShots(g: Game, events: { Event })
	local f = g.config.field
	local kept = {}
	for _, shot in g.shots do
		local best, bestRock = nil :: number?, nil :: number?
		for i, r in g.rocks do
			local t = Field.sweep(f, shot.x, shot.y, shot.vx, shot.vy, r.x, r.y, Rocks.SIZES[r.size].radius)
			if t and (best == nil or t < best) then
				best, bestRock = t, i
			end
		end
		local s = g.saucer
		local st = s
			and Field.sweep(f, shot.x, shot.y, shot.vx, shot.vy, s.x, s.y, g.config.saucers[s.kind].radius)
		if st and (best == nil or st < best) then
			breakSaucer(g, "shot", events)
		elseif bestRock then
			breakRock(g, bestRock, "shot", events)
		else
			shot.x, shot.y = Field.wrap(f, shot.x + shot.vx, shot.y + shot.vy)
			shot.life -= 1
			if shot.life > 0 then
				table.insert(kept, shot)
			end
		end
	end
	g.shots = kept
end

-- 6. the saucer's shots: each hits an exposed ship along its move, or flies on
local function moveSaucerShots(g: Game, events: { Event })
	local c, f = g.config, g.config.field
	local kept = {}
	for _, shot in g.saucerShots do
		local hit = Pilot.exposed(g)
			and Field.sweep(f, shot.x, shot.y, shot.vx, shot.vy, g.ship.x, g.ship.y, c.ship.radius) ~= nil
		if hit then
			endIfOut(g, Pilot.lose(g, c, "saucershot", emitter(events)), events)
		else
			shot.x, shot.y = Field.wrap(f, shot.x + shot.vx, shot.y + shot.vy)
			shot.life -= 1
			if shot.life > 0 then
				table.insert(kept, shot)
			end
		end
	end
	g.saucerShots = kept
end

-- 7. the exposed ship against the rocks (the first it overlaps), then the saucer: both break, and the ship is lost
local function collide(g: Game, events: { Event })
	if not Pilot.exposed(g) then
		return
	end
	local c, f = g.config, g.config.field
	local sx, sy = g.ship.x, g.ship.y
	for i, r in g.rocks do
		if Field.distance(f, sx, sy, r.x, r.y) < Rocks.SIZES[r.size].radius + c.ship.radius then
			breakRock(g, i, "ship", events)
			endIfOut(g, Pilot.lose(g, c, "rock", emitter(events)), events)
			return
		end
	end
	local s = g.saucer
	if s and Field.distance(f, sx, sy, s.x, s.y) < c.saucers[s.kind].radius + c.ship.radius then
		breakSaucer(g, "ship", events)
		endIfOut(g, Pilot.lose(g, c, "saucer", emitter(events)), events)
	end
end

-- 8. the waves: the last rock gone starts the clock, and the next wave comes waveTicks later
local function waveClock(g: Game, events: { Event })
	if g.waveTimer > 0 then
		g.waveTimer -= 1
		if g.waveTimer == 0 then
			g.wave += 1
			spawnWave(g)
			table.insert(events, { kind = "WaveStart", wave = g.wave })
		end
	elseif #g.rocks == 0 then
		g.waveTimer = g.config.waveTicks
		table.insert(events, { kind = "WaveClear", wave = g.wave })
	end
end

-- read through a call, so the checks after each stage are not narrowed away
local function over(g: Game): boolean
	return g.phase == "gameover"
end

-- One tick; the events in the order they happened. A finished run (gameover) changes no more.
function Classic.step(g: Game, input: Input?): { Event }
	local events: { Event } = {}
	if over(g) then
		return events
	end
	local out = Pilot.clock(g, g.config, drawer(g), function()
		return centreClear(g)
	end, emitter(events))
	if endIfOut(g, out, events) then
		return events
	end
	Pilot.control(g, g.config, Pilot.controls(input), drawer(g), emitter(events))
	for _, r in g.rocks do
		Rocks.move(r, g.config.field)
	end
	saucerStep(g, events)
	moveShots(g, events)
	moveSaucerShots(g, events)
	if over(g) then
		return events
	end
	collide(g, events)
	if over(g) then
		return events
	end
	waveClock(g, events)
	return events
end

return Classic
