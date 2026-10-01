--!strict
-- Levels: the one table of per-level parameters, the classic values from Pittman's Pac-Man Dossier
-- (Table A.1). Speeds are factors of level 1's speed. Later rafts add ghost columns here.

export type Row = {
	speedFactor: number, -- player speed relative to level 1
	frightSpeedFactor: number, -- player speed while a power pellet is active, relative to level 1
	frightenedSeconds: number,
	flashes: number,
}

local function row(speed: number, fright: number, seconds: number, flashes: number): Row
	return table.freeze({
		speedFactor = speed,
		frightSpeedFactor = fright,
		frightenedSeconds = seconds,
		flashes = flashes,
	})
end

local ROWS: { Row } = {
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

return Levels
