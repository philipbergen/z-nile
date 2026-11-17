--!strict
-- Game: one player's run as a pure state machine, stepped once per tick and told what happened.
-- ready -> playing -> dying -> (ready | gameover), and playing -> levelclear -> ready for the next
-- level. With the continue offer switched on for the run (f0145), the last life's dying pause ends in the offer
-- (offer -> ready on a continue, offer -> gameover when it runs out or is declined). It holds lives, level, score, the frightened counter and the extra-life rule; it never looks
-- at a maze. A pause of zero ticks is no pause.
local Levels = require("./Levels")

export type Phase = "ready" | "playing" | "dying" | "levelclear" | "offer" | "gameover"
export type Config = {
	lives: number,
	extraLifeScore: number, -- 0 means never
	readyTicks: number,
	dyingTicks: number,
	levelClearTicks: number,
	tickRate: number,
}
export type Event = {
	kind: string,
	points: number?,
	lives: number?,
	level: number?,
	score: number?,
	ticks: number?,
	reason: string?,
}
export type Game = {
	config: Config,
	phase: Phase,
	level: number,
	score: number,
	lives: number,
	timer: number, -- ticks left in a pause, 0 while playing
	frightened: number, -- ticks of power left
	extraLifeGiven: boolean,
	ramp: Levels.Ramp?, -- levels by picked walls (f0147): level 1's rules, the ramp's speeds, points times the level
	start: number, -- the level the run started on: the extra life comes at extraLifeScore times it (f0147)
	lost: number, -- f0145: lives lost in the run, every death (continues included); GameOver carries it
	offer: number, -- f0145: the continue offer's length in steps for this run; 0 is no offer
	held: boolean, -- f0145: the offer's countdown is held (a purchase screen is open, or a receipt awaited)
	waiting: number, -- f0145: steps left to wait for a bought continue's receipt
}

local Game = {}
Game.OFFER_TICKS = 150 -- f0145 (G7): the continue offer, 10 s of real time at the server's 15 steps a second
Game.CONTINUE_LIVES = 3 -- f0145: the lives a continue gives
Game.RECEIPT_WAIT_TICKS = 450 -- f0145: 30 s of real time to wait for a bought continue's receipt
Game.CLASSIC_CONFIG = table.freeze({
	lives = 3,
	extraLifeScore = 10000,
	readyTicks = 60,
	dyingTicks = 45,
	levelClearTicks = 60,
	tickRate = 30,
} :: Config)
Game.IMMEDIATE_CONFIG = table.freeze({
	lives = 3,
	extraLifeScore = 10000,
	readyTicks = 0,
	dyingTicks = 0,
	levelClearTicks = 0,
	tickRate = 30,
} :: Config)

local function isWhole(v: any): boolean
	return type(v) == "number" and v == v and v == math.floor(v)
end

local function validate(c: Config)
	if not isWhole(c.lives) or c.lives < 1 then
		error(`rules: lives must be a whole number >= 1, got {c.lives}`, 0)
	end
	if not isWhole(c.extraLifeScore) or c.extraLifeScore < 0 then
		error(`rules: extraLifeScore must be a whole number >= 0, got {c.extraLifeScore}`, 0)
	end
	for _, field in { "readyTicks", "dyingTicks", "levelClearTicks" } do
		local v = (c :: any)[field]
		if not isWhole(v) or v < 0 then
			error(`rules: {field} must be a whole number >= 0, got {v}`, 0)
		end
	end
	if type(c.tickRate) ~= "number" or c.tickRate ~= c.tickRate or c.tickRate <= 0 then
		error(`rules: tickRate must be > 0, got {c.tickRate}`, 0)
	end
end

-- enters the ready phase of a new attempt; with no ready pause the run goes straight to play
local function ready(g: Game)
	if g.config.readyTicks > 0 then
		g.phase, g.timer = "ready", g.config.readyTicks
	else
		g.phase, g.timer = "playing", 0
	end
end

function Game.new(config: Config?, ramp: Levels.Ramp?, start: number?): Game
	local c = config or Game.CLASSIC_CONFIG
	validate(c)
	if ramp then
		Levels.validateRamp(ramp)
	end
	local first = start or 1
	if not isWhole(first) or first < 1 or first == math.huge then
		error(`rules: start must be a whole number >= 1, got {first}`, 0)
	end
	local g: Game = {
		config = c,
		phase = "ready",
		level = first,
		score = 0,
		lives = c.lives,
		timer = 0,
		frightened = 0,
		extraLifeGiven = false,
		ramp = ramp,
		start = first, -- f0148: the level the player chose in the lobby
		lost = 0,
		offer = 0,
		held = false,
		waiting = 0,
	}
	ready(g)
	return g
end

-- What `points` scored now are worth: with a ramp, times the level (f0147); else as they are.
function Game.points(g: Game, points: number): number
	return if g.ramp then points * g.level else points
end

function Game.canMove(g: Game): boolean
	return g.phase == "playing"
end

function Game.addScore(g: Game, points: number): { Event }
	g.score += points
	local c = g.config
	if c.extraLifeScore > 0 and not g.extraLifeGiven and g.score >= c.extraLifeScore * g.start then
		g.extraLifeGiven = true
		g.lives += 1
		return { { kind = "ExtraLife", lives = g.lives } }
	end
	return {}
end

function Game.cleared(g: Game): { Event }
	if g.phase ~= "playing" then
		return {}
	end
	g.phase, g.timer, g.frightened = "levelclear", g.config.levelClearTicks, 0
	return { { kind = "LevelCleared", level = g.level, score = g.score } }
end

function Game.died(g: Game): { Event }
	if g.phase ~= "playing" then
		return {}
	end
	g.lives -= 1
	g.lost += 1
	g.phase, g.timer, g.frightened = "dying", g.config.dyingTicks, 0
	return { { kind = "LifeLost", lives = g.lives } }
end

-- A power pellet was eaten: the level's frightened period starts over (it never adds). Only a run in
-- play has one, so the counter is 0 in every other phase. Where the level has no frightened time the
-- event still reports it, with `ticks = 0`.
-- `factor` (default 1) lengthens it: f0126's long ghost pill is a power pellet of twice the level's time.
function Game.power(g: Game, factor: number?): { Event }
	if g.phase ~= "playing" then
		return {}
	end
	local ticks = Levels.frightenedTicks(g.level, g.config.tickRate, g.ramp) * (factor or 1)
	g.frightened = ticks
	return { { kind = "PowerStarted", ticks = ticks, level = g.level } }
end

function Game.playAgain(g: Game): ({ Event }, boolean)
	if g.phase ~= "gameover" then
		return {}, false
	end
	g.level, g.score, g.lives, g.frightened, g.extraLifeGiven = g.start, 0, g.config.lives, 0, false
	g.lost, g.held, g.waiting = 0, false, 0
	ready(g)
	return { { kind = "Ready", reason = "again", level = g.level } }, true
end

-- f0145: switch the continue offer on for this run (ticks > 0), or off (0); any other length changes nothing
function Game.allowOffer(g: Game, ticks: number)
	if isWhole(ticks) and ticks >= 0 then
		g.offer = ticks
	end
end

-- f0145: hold or release the offer's countdown (a purchase screen is open); only during the offer
function Game.hold(g: Game, on: boolean)
	if g.phase == "offer" then
		g.held = on
		if not on then
			g.waiting = 0
		end
	end
end

-- f0145: the purchase screen closed bought before its receipt came: hold the countdown for at most
-- RECEIPT_WAIT_TICKS steps, then let it run again
function Game.awaitReceipt(g: Game)
	if g.phase == "offer" then
		g.held, g.waiting = true, Game.RECEIPT_WAIT_TICKS
	end
end

-- f0145: end the offer at the next step (so GameOver still comes out of a step); false outside the offer
function Game.decline(g: Game): boolean
	if g.phase ~= "offer" then
		return false
	end
	g.timer, g.held, g.waiting = 1, false, 0
	return true
end

-- f0145: during the offer, `lives` new lives and a respawn; the score, the level, the extra life's flag and the
-- lives lost are kept. Outside the offer it does nothing.
function Game.continue(g: Game, lives: number): ({ Event }, boolean)
	if g.phase ~= "offer" or not isWhole(lives) or lives < 1 then
		return {}, false
	end
	g.lives, g.held, g.waiting = lives, false, 0
	ready(g)
	return { { kind = "Ready", reason = "continue", level = g.level } }, true
end

-- f0145: the run is refused (a player sent back to the lobby): over at once, with no GameOver event
function Game.refuse(g: Game)
	g.phase, g.offer, g.held, g.waiting = "gameover", 0, false, 0
	g.timer = 0
end

function Game.step(g: Game): { Event }
	local phase = g.phase
	if phase == "ready" then
		g.timer -= 1
		if g.timer <= 0 then
			g.phase, g.timer = "playing", 0
			return { { kind = "Playing", level = g.level } }
		end
	elseif phase == "playing" then
		if g.frightened > 0 then
			g.frightened -= 1
			if g.frightened == 0 then
				return { { kind = "PowerEnded", level = g.level } }
			end
		end
	elseif phase == "dying" then
		g.timer -= 1
		if g.timer <= 0 then
			if g.lives > 0 then
				ready(g)
				return { { kind = "Ready", reason = "respawn", level = g.level } }
			end
			if g.offer > 0 then
				g.phase, g.timer, g.held, g.waiting = "offer", g.offer, false, 0
				return { { kind = "Offer", ticks = g.offer } }
			end
			g.phase, g.timer = "gameover", 0
			return { { kind = "GameOver", score = g.score, level = g.level, lives = g.lost } }
		end
	elseif phase == "offer" then
		if g.waiting > 0 then
			g.waiting -= 1
			if g.waiting == 0 then
				g.held = false
			end
		elseif not g.held then
			g.timer -= 1
			if g.timer <= 0 then
				g.phase, g.timer = "gameover", 0
				return { { kind = "GameOver", score = g.score, level = g.level, lives = g.lost } }
			end
		end
	elseif phase == "levelclear" then
		g.timer -= 1
		if g.timer <= 0 then
			g.level += 1
			ready(g)
			return { { kind = "Ready", reason = "level", level = g.level } }
		end
	end
	return {}
end

return Game
