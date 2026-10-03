--!strict
-- Levels: the one table of per-level parameters, the classic values from Pittman's Pac-Man Dossier
-- (Table A.1). Speeds are factors of level 1's speed. Later rafts add ghost columns here.

export type Ghost = {
	speedFactor: number, -- a ghost's speed relative to level 1's player speed
	tunnelFactor: number, -- in the side tunnels
	frightFactor: number, -- while frightened
}
export type Release = { pinky: number, inky: number, clyde: number }
export type Row = {
	speedFactor: number, -- player speed relative to level 1
	frightSpeedFactor: number, -- player speed while a power pellet is active, relative to level 1
	frightenedSeconds: number,
	flashes: number,
	ghost: Ghost, -- R0100
	dotLimits: Release, -- pellets the player must eat before each ghost leaves the house (personal counters)
	idleSeconds: number, -- seconds without a pellet before the house releases the next ghost
	schedule: { number }, -- seconds of scatter, chase, scatter, ...; after the last one it is chase for good
}

-- Pittman's Table A.1 gives the ghost columns as a share of the arcade's maximum speed; level 1's
-- player runs at 80% of it, so each share is divided by 80.
local GHOST_L1: Ghost =
	table.freeze({ speedFactor = 0.75 / 0.8, tunnelFactor = 0.4 / 0.8, frightFactor = 0.5 / 0.8 })
local GHOST_L2: Ghost =
	table.freeze({ speedFactor = 0.85 / 0.8, tunnelFactor = 0.45 / 0.8, frightFactor = 0.55 / 0.8 })
local GHOST_L5: Ghost =
	table.freeze({ speedFactor = 0.95 / 0.8, tunnelFactor = 0.5 / 0.8, frightFactor = 0.6 / 0.8 })
-- Table A.2: scatter and chase seconds; the final chase never ends
local SCHEDULE_L1: { number } = table.freeze({ 7, 20, 7, 20, 5, 20, 5 })
local SCHEDULE_L2: { number } = table.freeze({ 7, 20, 7, 20, 5, 1033, 1 / 60 })
local SCHEDULE_L5: { number } = table.freeze({ 5, 20, 5, 20, 5, 1037, 1 / 60 })
-- the personal dot counters and the idle timer
local LIMITS_L1: Release = table.freeze({ pinky = 0, inky = 30, clyde = 60 })
local LIMITS_L2: Release = table.freeze({ pinky = 0, inky = 0, clyde = 50 })
local LIMITS_L3: Release = table.freeze({ pinky = 0, inky = 0, clyde = 0 })

local function row(speed: number, fright: number, seconds: number, flashes: number): Row
	return table.freeze({
		speedFactor = speed,
		frightSpeedFactor = fright,
		frightenedSeconds = seconds,
		flashes = flashes,
		ghost = GHOST_L1,
		dotLimits = LIMITS_L1,
		idleSeconds = 4,
		schedule = SCHEDULE_L1,
	})
end

-- the same row with the ghost columns of its level
local function withGhosts(r: Row, ghost: Ghost, limits: Release, idle: number, schedule: { number }): Row
	local copy = table.clone(r)
	copy.ghost, copy.dotLimits, copy.idleSeconds, copy.schedule = ghost, limits, idle, schedule
	return table.freeze(copy)
end

local BASE: { Row } = {
	row(1, 1.125, 6, 5),
	row(1.125, 1.1875, 5, 5),
	row(1.125, 1.1875, 4, 5),
	row(1.125, 1.1875, 3, 5),
	row(1.25, 1.25, 2, 5),
	row(1.25, 1.25, 5, 5),
	row(1.25, 1.25, 2, 5),
	row(1.25, 1.25, 2, 5),
	row(1.25, 1.25, 1, 3),
	row(1.25, 1.25, 5, 5),
	row(1.25, 1.25, 2, 5),
	row(1.25, 1.25, 1, 3),
	row(1.25, 1.25, 1, 3),
	row(1.25, 1.25, 3, 5),
	row(1.25, 1.25, 1, 3),
	row(1.25, 1.25, 1, 3),
	row(1.25, 1.25, 0, 0),
	row(1.25, 1.25, 1, 3),
	row(1.25, 1.25, 0, 0),
	row(1.25, 1.25, 0, 0),
	row(1.125, 1.125, 0, 0),
}
local ROWS: { Row } = {}
for level, r in BASE do
	if level == 1 then
		ROWS[level] = r
	elseif level == 2 then
		ROWS[level] = withGhosts(r, GHOST_L2, LIMITS_L2, 4, SCHEDULE_L2)
	elseif level <= 4 then
		ROWS[level] = withGhosts(r, GHOST_L2, LIMITS_L3, 4, SCHEDULE_L2)
	else
		ROWS[level] = withGhosts(r, GHOST_L5, LIMITS_L3, 3, SCHEDULE_L5)
	end
end

local Levels = {}
Levels.ROWS = table.freeze(ROWS)
Levels.COUNT = #ROWS

-- Levels past COUNT use the last row.
function Levels.row(level: number): Row
	if type(level) ~= "number" or level ~= level or level ~= math.floor(level) or level < 1 then
		error(`levels: level must be a whole number >= 1, got {level}`, 0)
	end
	return ROWS[math.min(level, Levels.COUNT)]
end

local function round(v: number): number
	return math.floor(v + 0.5)
end

-- Units per tick for the player on `level`, from level 1's base speed. `frightened` picks the column
-- for the time a power pellet is active.
function Levels.playerSpeed(baseSpeed: number, level: number, frightened: boolean?): number
	local r = Levels.row(level)
	return round(baseSpeed * (if frightened then r.frightSpeedFactor else r.speedFactor))
end

function Levels.frightenedTicks(level: number, tickRate: number): number
	return round(Levels.row(level).frightenedSeconds * tickRate)
end

-- The user's "slower ghosts" factor (R0100): 1 is the classic tables. It scales the speeds of hunting and
-- frightened ghosts, never the eyes returning to the house.
Levels.GHOST_TUNING = 1
Levels.EYES_FACTOR = 2 -- eyes run at this many times level 1's player speed

export type GhostSpeed = "normal" | "tunnel" | "frightened" | "eyes"

-- Units per tick for a ghost on `level`; `tuning` defaults to Levels.GHOST_TUNING. At least 1.
function Levels.ghostSpeed(baseSpeed: number, level: number, kind: GhostSpeed, tuning: number?): number
	local g = Levels.row(level).ghost
	local k = tuning or Levels.GHOST_TUNING
	if kind == "eyes" then
		return round(baseSpeed * Levels.EYES_FACTOR)
	end
	local factor = if kind == "normal"
		then g.speedFactor
		elseif kind == "tunnel" then g.tunnelFactor
		else g.frightFactor
	return math.max(1, round(baseSpeed * factor * k))
end

-- Phase lengths in ticks (scatter, chase, scatter, ...); the chase after the last one lasts forever.
function Levels.schedule(level: number, tickRate: number): { number }
	local out: { number } = {}
	for _, seconds in Levels.row(level).schedule do
		table.insert(out, math.max(1, round(seconds * tickRate)))
	end
	return out
end

return Levels
