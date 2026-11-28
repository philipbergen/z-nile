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
	player: number?, -- the player's slot in a two-player match; nil in a solo run
	shooter: number?, -- the slot whose shot destroyed a ship (two players, friendly fire)
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
export type Home = Pilot.Home
export type Rock = Rocks.Rock
export type Saucer = Saucers.Saucer
-- one player on a run's field: a Pilot (every field of Pilot.Pilot), whether their run is over, and their slot
export type Player = {
	ship: Ship.Ship,
	shipState: ShipState,
	timer: number,
	protect: number,
	shots: { Shot },
	lives: number,
	score: number,
	nextExtra: number,
	home: Pilot.Home?,
	phase: Phase,
	slot: number?, -- set by a two-player match; nil in a solo run
}
-- the field's side of a run: what every player on it shares
export type Run = {
	config: Config,
	wave: number,
	rng: number,
	nextId: number,
	rocks: { Rocks.Rock },
	saucer: Saucers.Saucer?,
	saucerShots: { Shot },
	saucerElapsed: number,
	waveTimer: number,
}
-- a solo run: one table that is both the Run and its one Player
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
	home: Pilot.Home?,
	slot: number?,
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

-- every draw a rule makes, from the run's own generator
function Classic.draw(g: Run): Rocks.Draw
	return function(n: number): number
		local v
		g.rng, v = Rng.next(g.rng, n)
		return v
	end
end

-- the generator's first state for a seed (a fraction floored; not a finite number: 0)
function Classic.seed(seed: number): number
	return Rng.seed(seed)
end

-- the large rocks a wave starts with
function Classic.rockCount(c: Config, wave: number): number
	return math.min(c.maxRocks, c.firstRocks + c.rocksStep * (wave - 1))
end

local function nearest(f: Field.Field, x: number, y: number, ships: { Ship.Ship }): number
	local best = math.huge
	for _, s in ships do
		best = math.min(best, Field.distance(f, x, y, s.x, s.y))
	end
	return best
end

-- The wave's rocks, each on the field's edge (draw(width + height) - 1 runs along the bottom edge, then up the
-- left one). A point closer than spawnClear to one of the ships moves half that edge along, unless that puts it
-- nearer a ship than it was. Then launched.
function Classic.spawnWave(g: Run, ships: { Ship.Ship })
	local c, f = g.config, g.config.field
	local draw = Classic.draw(g)
	for _ = 1, Classic.rockCount(c, g.wave) do
		local at = draw(f.width + f.height) - 1
		local x, y = at, 0
		if at >= f.width then
			x, y = 0, at - f.width
		end
		local near = nearest(f, x, y, ships)
		if near < c.spawnClear then
			local mx, my = x, y
			if at < f.width then
				mx = (x + f.width / 2) % f.width
			else
				my = (y + f.height / 2) % f.height
			end
			if nearest(f, mx, my, ships) >= near then
				x, y = mx, my
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
	Classic.spawnWave(g, { g.ship })
	return g
end

-- a player's pilot events, copied into the run's with the player's slot (and a loss's shooter)
local function emitter(events: { Event }, p: Player, shooter: number?): (Pilot.Event) -> ()
	return function(e: Pilot.Event)
		table.insert(events, {
			kind = e.kind,
			lives = e.lives,
			cause = e.cause,
			x = e.x,
			y = e.y,
			player = p.slot,
			shooter = shooter,
		})
	end
end

-- the player's last life lost ends their run
local function endIfOut(p: Player, out: boolean, events: { Event }): boolean
	if out then
		p.phase = "gameover"
		table.insert(events, { kind = "GameOver", player = p.slot })
	end
	return out
end

-- the player's ship is lost (shooter: the slot whose shot it was, with friendly fire)
local function lose(g: Run, p: Player, cause: Cause, events: { Event }, shooter: number?)
	endIfOut(p, Pilot.lose(p, g.config, cause, emitter(events, p, shooter)), events)
end

local function breakRock(g: Run, p: Player, index: number, by: By, events: { Event })
	local r = table.remove(g.rocks, index) :: Rocks.Rock
	local points = Rocks.SIZES[r.size].points
	table.insert(
		events,
		{ kind = "RockHit", id = r.id, size = r.size, points = points, by = by, player = p.slot }
	)
	Pilot.award(p, g.config, points, emitter(events, p))
	local pieces = Rocks.split(r, g.nextId, Classic.draw(g))
	for _, piece in pieces do
		table.insert(g.rocks, piece)
	end
	g.nextId += #pieces
end

local function breakSaucer(g: Run, p: Player, by: By, events: { Event })
	local s = g.saucer :: Saucers.Saucer
	local points = g.config.saucers[s.kind].points
	g.saucer = nil
	g.saucerElapsed = 0
	table.insert(events, { kind = "SaucerHit", saucer = s.kind, points = points, by = by, player = p.slot })
	Pilot.award(p, g.config, points, emitter(events, p))
end

-- no rock or saucer comes within clearRadius (beyond its own radius) of the point
function Classic.clearAt(g: Run, x: number, y: number): boolean
	local c, f = g.config, g.config.field
	for _, r in g.rocks do
		if Field.distance(f, x, y, r.x, r.y) < Rocks.SIZES[r.size].radius + c.clearRadius then
			return false
		end
	end
	local s = g.saucer
	if s and Field.distance(f, x, y, s.x, s.y) < c.saucers[s.kind].radius + c.clearRadius then
		return false
	end
	return true
end

-- 1. the player's ship's clocks (Pilot.clock), its home judged clear by the rocks and the saucer. True when it
-- was lost on its last life (their run is then over).
function Classic.clock(g: Run, p: Player, events: { Event }): boolean
	local hx, hy = Pilot.home(p, g.config)
	local out = Pilot.clock(p, g.config, Classic.draw(g), function()
		return Classic.clearAt(g, hx, hy)
	end, emitter(events, p))
	return endIfOut(p, out, events)
end

-- 2. the player's controls (Pilot.control)
function Classic.control(g: Run, p: Player, input: Input?, events: { Event })
	Pilot.control(p, g.config, Pilot.controls(input), Classic.draw(g), emitter(events, p))
end

-- 3. the rocks drift
function Classic.moveRocks(g: Run)
	for _, r in g.rocks do
		Rocks.move(r, g.config.field)
	end
end

-- 4. the saucer: its clock while there is none, else its move, its leaving and its fire at the target (a player
-- whose ship is on the field, aimed from their score; nil holds its fire)
function Classic.saucerStep(g: Run, target: Player?, events: { Event })
	local f, sc = g.config.field, g.config.saucers
	local s = g.saucer
	if s == nil then
		g.saucerElapsed += 1
		if g.saucerElapsed >= Saucers.wait(sc, g.wave) then
			g.saucerElapsed = 0
			local new = Saucers.appear(sc, f, g.wave, Classic.draw(g))
			g.saucer = new
			table.insert(events, { kind = "SaucerAppear", saucer = new.kind })
		end
		return
	end
	if Saucers.move(s, sc, f, Classic.draw(g)) then
		g.saucer = nil
		g.saucerElapsed = 0
		table.insert(events, { kind = "SaucerLeave", saucer = s.kind })
		return
	end
	s.fireElapsed += 1
	if s.fireElapsed >= sc[s.kind].fireTicks and target then
		s.fireElapsed = 0
		local h = Saucers.aim(s, sc, f, target.score, target.ship.x, target.ship.y, Classic.draw(g))
		local ux, uy = Field.unit(h)
		table.insert(
			g.saucerShots,
			{ x = s.x, y = s.y, vx = ux * sc.shotSpeed, vy = uy * sc.shotSpeed, life = sc.shotLife }
		)
		table.insert(events, { kind = "SaucerFire", saucer = s.kind })
	end
end

-- 5. the player's shots, oldest first: each hits the first rock, saucer or (friendly fire: foe given) exposed foe
-- ship along its move, or flies on. A tie goes to the rock, then the saucer.
function Classic.moveShots(g: Run, p: Player, foe: Player?, events: { Event })
	local c, f = g.config, g.config.field
	local kept = {}
	for _, shot in p.shots do
		local best, bestRock = nil :: number?, nil :: number?
		for i, r in g.rocks do
			local t = Field.sweep(f, shot.x, shot.y, shot.vx, shot.vy, r.x, r.y, Rocks.SIZES[r.size].radius)
			if t and (best == nil or t < best) then
				best, bestRock = t, i
			end
		end
		local s = g.saucer
		local st = s and Field.sweep(f, shot.x, shot.y, shot.vx, shot.vy, s.x, s.y, c.saucers[s.kind].radius)
		local ft = nil :: number?
		if foe and Pilot.exposed(foe) then
			ft = Field.sweep(f, shot.x, shot.y, shot.vx, shot.vy, foe.ship.x, foe.ship.y, c.ship.radius)
		end
		if ft and (best == nil or ft < best) and (st == nil or ft < st) then
			lose(g, foe :: Player, "shot", events, p.slot)
		elseif st and (best == nil or st < best) then
			breakSaucer(g, p, "shot", events)
		elseif bestRock then
			breakRock(g, p, bestRock, "shot", events)
		else
			shot.x, shot.y = Field.wrap(f, shot.x + shot.vx, shot.y + shot.vy)
			shot.life -= 1
			if shot.life > 0 then
				table.insert(kept, shot)
			end
		end
	end
	p.shots = kept
end

-- 6. the saucer's shots: each hits the exposed ship it reaches first along its move (a tie to the earlier
-- listed player), or flies on
function Classic.moveSaucerShots(g: Run, players: { Player }, events: { Event })
	local c, f = g.config, g.config.field
	local kept = {}
	for _, shot in g.saucerShots do
		local best, hit = nil :: number?, nil :: Player?
		for _, p in players do
			if Pilot.exposed(p) then
				local t = Field.sweep(f, shot.x, shot.y, shot.vx, shot.vy, p.ship.x, p.ship.y, c.ship.radius)
				if t and (best == nil or t < best) then
					best, hit = t, p
				end
			end
		end
		if hit then
			lose(g, hit, "saucershot", events)
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

-- 7. the player's exposed ship against the rocks (the first it overlaps), then the saucer: both break, and the
-- ship is lost
function Classic.collide(g: Run, p: Player, events: { Event })
	if not Pilot.exposed(p) then
		return
	end
	local c, f = g.config, g.config.field
	local sx, sy = p.ship.x, p.ship.y
	for i, r in g.rocks do
		if Field.distance(f, sx, sy, r.x, r.y) < Rocks.SIZES[r.size].radius + c.ship.radius then
			breakRock(g, p, i, "ship", events)
			lose(g, p, "rock", events)
			return
		end
	end
	local s = g.saucer
	if s and Field.distance(f, sx, sy, s.x, s.y) < c.saucers[s.kind].radius + c.ship.radius then
		breakSaucer(g, p, "ship", events)
		lose(g, p, "saucer", events)
	end
end

-- 8. the waves: the last rock gone starts the clock, and the next wave comes waveTicks later, clear of the ships
function Classic.waveClock(g: Run, ships: { Ship.Ship }, events: { Event })
	if g.waveTimer > 0 then
		g.waveTimer -= 1
		if g.waveTimer == 0 then
			g.wave += 1
			Classic.spawnWave(g, ships)
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
	if Classic.clock(g, g, events) then
		return events
	end
	Classic.control(g, g, input, events)
	Classic.moveRocks(g)
	Classic.saucerStep(g, if g.shipState == "alive" then g else nil, events)
	Classic.moveShots(g, g, nil, events)
	Classic.moveSaucerShots(g, { g }, events)
	if over(g) then
		return events
	end
	Classic.collide(g, g, events)
	if over(g) then
		return events
	end
	Classic.waveClock(g, { g.ship }, events)
	return events
end

return Classic
