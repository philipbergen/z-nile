--!strict
-- Game: one player's run as a pure state machine, stepped once per tick and told what happened.
-- ready -> playing -> dying -> (ready | gameover), and playing -> levelclear -> ready for the next
-- level. It holds lives, level, score, the frightened counter and the extra-life rule; it never looks
-- at a maze. A pause of zero ticks is no pause.
local Levels = require("./Levels")

export type Phase = "ready" | "playing" | "dying" | "levelclear" | "gameover"
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
}

local Game = {}
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

function Game.new(config: Config?): Game
	local c = config or Game.CLASSIC_CONFIG
	validate(c)
	local g: Game = {
		config = c,
		phase = "ready",
		level = 1,
		score = 0,
		lives = c.lives,
		timer = 0,
		frightened = 0,
		extraLifeGiven = false,
	}
	ready(g)
	return g
end

function Game.canMove(g: Game): boolean
	return g.phase == "playing"
end

function Game.addScore(g: Game, points: number): { Event }
	g.score += points
	local c = g.config
	if c.extraLifeScore > 0 and not g.extraLifeGiven and g.score >= c.extraLifeScore then
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
	local ticks = Levels.frightenedTicks(g.level, g.config.tickRate) * (factor or 1)
	g.frightened = ticks
	return { { kind = "PowerStarted", ticks = ticks, level = g.level } }
end

function Game.playAgain(g: Game): ({ Event }, boolean)
	if g.phase ~= "gameover" then
		return {}, false
	end
	g.level, g.score, g.lives, g.frightened, g.extraLifeGiven = 1, 0, g.config.lives, 0, false
	ready(g)
	return { { kind = "Ready", reason = "again", level = 1 } }, true
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
			g.phase, g.timer = "gameover", 0
			return { { kind = "GameOver", score = g.score, level = g.level } }
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
