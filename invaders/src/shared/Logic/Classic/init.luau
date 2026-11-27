--!strict
-- Classic: one player's Space Invaders as a pure state machine (f0216), stepped once per tick (TICK_RATE a
-- second) and told the player's input. It owns the cannon, the shots, lives, score, waves and the revive, and
-- composes Formation, Barriers and Mystery. Phases: playing -> dying -> playing, playing -> waveclear ->
-- playing (the next wave), and playing -> gameover (out of lives, or invasion at once). The field is 2-D: x
-- across, d the depth from the base line (the cannon's line, d = 0) to the far end.
local Barriers = require("./Barriers")
local Formation = require("./Formation")
local Mystery = require("./Mystery")
local Rng = require("@self/Rng")

export type Phase = "playing" | "dying" | "waveclear" | "gameover"
export type Reason = "lives" | "invasion"
export type Slot = "aimed" | "random"
export type Bomb = { x: number, d: number, slot: number } -- slot 1 is aimed, 2 and 3 random
export type Shot = { x: number, d: number }
export type Input = { move: number?, fire: boolean? }
export type Event = {
	kind: string,
	points: number?,
	row: number?,
	col: number?,
	slot: number?,
	lives: number?,
	wave: number?,
	reason: Reason?,
	interval: number?,
}
export type Config = {
	tickRate: number,
	fieldWidth: number,
	fieldDepth: number,
	lives: number,
	reviveLives: number,
	extraLifeScore: number,
	cannonHalf: number, -- the cannon spans [x - half, x + half]
	cannonDepth: number, -- the cannon spans [0, cannonDepth) in depth; its shot starts there
	cannonSpeed: number,
	cannonStart: number,
	shotSpeed: number,
	bombSpeed: number,
	reload: { { score: number, ticks: number } }, -- the aliens' wait between shots, by score
	firstDepth: number, -- wave 1's front row near edge
	waveCycle: number, -- waves after this many repeat the depths
	invasionDepth: number, -- a living alien's near edge at or below this is an invasion
	dyingTicks: number,
	waveClearTicks: number,
	formation: Formation.Config,
	barriers: Barriers.Layout,
	mystery: Mystery.Config,
}
export type Game = {
	config: Config,
	phase: Phase,
	timer: number, -- ticks left in a pause
	reason: Reason?, -- why the run ended
	wave: number,
	score: number,
	lives: number,
	revives: number,
	extraLifeGiven: boolean,
	shotsFired: number,
	cannon: number, -- the cannon's centre x
	shot: Shot?,
	bombs: { Bomb },
	reloadElapsed: number,
	nextSlot: number,
	rng: number,
	formation: Formation.Formation,
	barriers: Barriers.Barriers,
	mystery: Mystery.Mystery,
}

local Classic = {}
Classic.TICK_RATE = 60
Classic.CONFIG = table.freeze({
	tickRate = 60,
	fieldWidth = 224,
	fieldDepth = 232,
	lives = 3,
	reviveLives = 3,
	extraLifeScore = 1500,
	cannonHalf = 6,
	cannonDepth = 8,
	cannonSpeed = 1,
	cannonStart = 112,
	shotSpeed = 4,
	bombSpeed = 1,
	reload = table.freeze({
		table.freeze({ score = 0, ticks = 48 }),
		table.freeze({ score = 200, ticks = 16 }),
		table.freeze({ score = 1000, ticks = 11 }),
		table.freeze({ score = 2000, ticks = 8 }),
		table.freeze({ score = 3000, ticks = 7 }),
	}),
	firstDepth = 120,
	waveCycle = 8,
	invasionDepth = 8,
	dyingTicks = 120,
	waveClearTicks = 120,
	formation = Formation.CLASSIC,
	barriers = Barriers.CLASSIC,
	mystery = Mystery.CLASSIC,
} :: Config)

-- The front row's starting depth for a wave: one row closer each wave, repeating after waveCycle waves.
function Classic.waveDepth(wave: number): number
	local c = Classic.CONFIG
	return c.firstDepth - c.formation.rowStep * ((wave - 1) % c.waveCycle)
end

-- The aliens' wait between shots at a score.
function Classic.reloadTicks(score: number): number
	local ticks = 0
	for _, r in Classic.CONFIG.reload do
		if score >= r.score then
			ticks = r.ticks
		end
	end
	return ticks
end

local function startWave(g: Game)
	local c = g.config
	g.formation = Formation.new(c.formation, Classic.waveDepth(g.wave))
	g.barriers = Barriers.new(c.barriers)
	g.mystery = Mystery.new(c.mystery)
	g.shot = nil
	g.bombs = {}
	g.reloadElapsed = 0
	g.nextSlot = 1
	g.cannon = c.cannonStart
	g.phase = "playing"
	g.timer = 0
end

function Classic.new(seed: number): Game
	local c = Classic.CONFIG
	local g: Game = {
		config = c,
		phase = "playing",
		timer = 0,
		reason = nil,
		wave = 1,
		score = 0,
		lives = c.lives,
		revives = 0,
		extraLifeGiven = false,
		shotsFired = 0,
		cannon = c.cannonStart,
		shot = nil,
		bombs = {},
		reloadElapsed = 0,
		nextSlot = 1,
		rng = Rng.seed(seed),
		formation = Formation.new(c.formation, c.firstDepth),
		barriers = Barriers.new(c.barriers),
		mystery = Mystery.new(c.mystery),
	}
	return g
end

local function addScore(g: Game, points: number, events: { Event })
	g.score += points
	if not g.extraLifeGiven and g.score >= g.config.extraLifeScore then
		g.extraLifeGiven = true
		g.lives += 1
		table.insert(events, { kind = "ExtraLife", lives = g.lives })
	end
end

local function endGame(g: Game, reason: Reason, events: { Event })
	g.phase = "gameover"
	g.reason = reason
	g.shot = nil
	g.bombs = {}
	table.insert(events, { kind = "GameOver", reason = reason })
end

-- The player's shot, unit by unit. True when the wave was cleared.
local function moveShot(g: Game, events: { Event }): boolean
	local shot = g.shot
	if shot == nil then
		return false
	end
	local c = g.config
	for _ = 1, c.shotSpeed do
		shot.d += 1
		if shot.d >= c.fieldDepth then
			g.shot = nil
			return false
		end
		local bunker, col, row = Barriers.blockAt(g.barriers, shot.x, shot.d)
		if bunker and col and row then
			Barriers.erode(g.barriers, bunker, col, row, 1)
			g.shot = nil
			table.insert(events, { kind = "BarrierHit" })
			return false
		end
		local arow, acol = Formation.hitAt(g.formation, shot.x, shot.d)
		if arow and acol then
			local points = Formation.kill(g.formation, arow, acol)
			g.shot = nil
			table.insert(events, { kind = "AlienHit", row = arow, col = acol, points = points })
			addScore(g, points, events)
			return g.formation.live == 0
		end
		if Mystery.hitAt(g.mystery, shot.x, shot.d) then
			local points = Mystery.value(g.mystery, g.shotsFired)
			Mystery.remove(g.mystery)
			g.shot = nil
			table.insert(events, { kind = "MysteryHit", points = points })
			addScore(g, points, events)
			return false
		end
	end
	return false
end

-- The aliens' bombs, unit by unit. True when one hit the cannon.
local function moveBombs(g: Game, events: { Event }): boolean
	local c = g.config
	local kept = {}
	local hit = false
	for _, bomb in g.bombs do
		local alive = true
		for _ = 1, c.bombSpeed do
			bomb.d -= 1
			if bomb.d < 0 then
				alive = false
				break
			end
			local bunker, col, row = Barriers.blockAt(g.barriers, bomb.x, bomb.d)
			if bunker and col and row then
				Barriers.erode(g.barriers, bunker, col, row, -1)
				table.insert(events, { kind = "BarrierHit", slot = bomb.slot })
				alive = false
				break
			end
			if
				bomb.d < c.cannonDepth
				and bomb.x >= g.cannon - c.cannonHalf
				and bomb.x <= g.cannon + c.cannonHalf
			then
				hit = true
				alive = false
				break
			end
		end
		if alive then
			table.insert(kept, bomb)
		end
		if hit then
			break
		end
	end
	g.bombs = kept
	return hit
end

local function eraseUnder(g: Game)
	local f = g.formation
	for row = 1, f.config.rows do
		for col = 1, f.config.cols do
			if Formation.isAlive(f, row, col) then
				local x0, d0, x1, d1 = Formation.box(f, row, col)
				Barriers.eraseBox(g.barriers, x0, d0, x1, d1)
			end
		end
	end
end

local function slotTaken(g: Game, slot: number): boolean
	for _, b in g.bombs do
		if b.slot == slot then
			return true
		end
	end
	return false
end

local function fireBomb(g: Game, events: { Event })
	local f = g.formation
	g.reloadElapsed += 1
	if f.live == 0 or g.reloadElapsed < Classic.reloadTicks(g.score) then
		return
	end
	local slot = nil
	for i = 0, 2 do
		local s = (g.nextSlot - 1 + i) % 3 + 1
		if not slotTaken(g, s) then
			slot = s
			break
		end
	end
	if slot == nil then
		return
	end
	local columns = Formation.columns(f)
	local col
	if slot == 1 then
		local best = math.huge
		for _, cc in columns do
			local x0, _, x1 = Formation.box(f, 1, cc)
			local dist = math.abs((x0 + x1) // 2 - g.cannon)
			if dist < best then
				best, col = dist, cc
			end
		end
	else
		local pick
		g.rng, pick = Rng.next(g.rng, #columns)
		col = columns[pick]
	end
	local row = Formation.front(f, col)
	assert(row, "a living column has a front")
	local x0, d0, x1 = Formation.box(f, row, col)
	table.insert(g.bombs, { x = (x0 + x1) // 2, d = d0, slot = slot })
	g.nextSlot = slot % 3 + 1
	g.reloadElapsed = 0
	table.insert(events, { kind = "AlienFire", slot = slot, col = col })
end

local function sanitize(input: Input?): (number, boolean)
	if type(input) ~= "table" then
		return 0, false
	end
	local move = input.move
	local m = if move == -1 then -1 elseif move == 1 then 1 else 0
	return m, input.fire == true
end

-- One tick. Returns what happened, in order.
function Classic.step(g: Game, input: Input?): { Event }
	local events: { Event } = {}
	local c = g.config
	if g.phase == "gameover" then
		return events
	end
	if g.phase == "dying" or g.phase == "waveclear" then
		g.timer -= 1
		if g.timer > 0 then
			return events
		end
		if g.phase == "waveclear" then
			g.wave += 1
			startWave(g)
			table.insert(events, { kind = "WaveStart", wave = g.wave })
		else
			g.phase = "playing"
			g.cannon = c.cannonStart
			table.insert(events, { kind = "Respawn", lives = g.lives })
		end
		return events
	end
	local move, fire = sanitize(input)
	g.cannon = math.clamp(g.cannon + move * c.cannonSpeed, c.cannonHalf, c.fieldWidth - 1 - c.cannonHalf)
	if fire and g.shot == nil then
		g.shot = { x = g.cannon, d = c.cannonDepth - 1 }
		g.shotsFired += 1
		table.insert(events, { kind = "PlayerFire" })
	end
	local before = #events
	local cleared = moveShot(g, events)
	local shipHit = false
	for i = before + 1, #events do
		if events[i].kind == "MysteryHit" then
			shipHit = true
		end
	end
	if cleared then
		g.phase = "waveclear"
		g.timer = c.waveClearTicks
		g.shot = nil
		g.bombs = {}
		Mystery.remove(g.mystery)
		table.insert(events, { kind = "WaveClear", wave = g.wave })
		return events
	end
	if moveBombs(g, events) then
		g.lives -= 1
		g.shot = nil
		g.bombs = {}
		table.insert(events, { kind = "CannonHit", lives = g.lives })
		if g.lives <= 0 then
			endGame(g, "lives", events)
		else
			g.phase = "dying"
			g.timer = c.dyingTicks
		end
		return events
	end
	local moved = Formation.tick(g.formation)
	if moved then
		eraseUnder(g)
		table.insert(events, {
			kind = if moved == "advance" then "Advance" else "March",
			interval = Formation.interval(g.formation),
		})
		if moved == "advance" then
			local _, _, near = Formation.extent(g.formation)
			if near and near <= c.invasionDepth then
				endGame(g, "invasion", events)
				return events
			end
		end
	end
	fireBomb(g, events)
	if shipHit then
		return events -- the wait for the next ship starts on the next tick, as it does after one leaves
	end
	local change = Mystery.tick(g.mystery, g.formation.live)
	if change == "appear" then
		table.insert(events, { kind = "MysteryAppear" })
	elseif change == "leave" then
		table.insert(events, { kind = "MysteryLeave" })
	end
	return events
end

-- A revive (f0219 makes the offer): only at run over. The player gets reviveLives lives and the wave restarts
-- from its starting state; score, wave and the extra life already given stay. False when not at run over.
function Classic.revive(g: Game): boolean
	if g.phase ~= "gameover" then
		return false
	end
	g.lives = g.config.reviveLives
	g.revives += 1
	g.reason = nil
	startWave(g)
	return true
end

return Classic
