--!strict
-- Mystery: the ship that crosses the far end of the field, engine-free (f0216). It appears `every` ticks after
-- the last one left (or the wave began), only while at least `minAliens` aliens live, alternating its side:
-- first from the left. Its value comes from the player's shot count, through a fixed table of 50, 100, 150
-- and 300. The caller ticks it only while the run is playing.
export type Config = {
	every: number, -- ticks without a ship before the next one appears
	speed: number,
	width: number,
	depth: number,
	lane: number, -- the ship's near edge depth
	fieldWidth: number,
	minAliens: number,
	values: { number },
}
export type Mystery = {
	config: Config,
	x: number?, -- the ship's left edge, nil when there is no ship
	dir: number, -- the ship's heading, +1 right
	nextDir: number, -- the side the next ship comes from: +1 from the left
	elapsed: number, -- ticks without a ship
}
export type Change = "appear" | "leave"

local Mystery = {}
Mystery.CLASSIC = table.freeze({
	every = 1500,
	speed = 1,
	width = 16,
	depth = 7,
	lane = 216,
	fieldWidth = 224,
	minAliens = 8,
	values = table.freeze({ 100, 50, 50, 100, 150, 100, 100, 50, 300, 100, 100, 100, 50, 150, 100 }),
} :: Config)

function Mystery.new(config: Config): Mystery
	return { config = config, x = nil, dir = 1, nextDir = 1, elapsed = 0 }
end

-- One playing tick, with `live` aliens alive. Returns "appear" or "leave" when the ship did.
function Mystery.tick(m: Mystery, live: number): Change?
	local c = m.config
	local x = m.x
	if x == nil then
		m.elapsed += 1
		if m.elapsed >= c.every and live >= c.minAliens then
			m.dir = m.nextDir
			m.nextDir = -m.nextDir
			m.x = if m.dir > 0 then -c.width else c.fieldWidth
			m.elapsed = 0
			return "appear"
		end
		return nil
	end
	x += m.dir * c.speed
	if (m.dir > 0 and x >= c.fieldWidth) or (m.dir < 0 and x + c.width <= 0) then
		m.x = nil
		m.elapsed = 0
		return "leave"
	end
	m.x = x
	return nil
end

-- Whether the ship's box holds the point (x, d).
function Mystery.hitAt(m: Mystery, x: number, d: number): boolean
	local sx = m.x
	if sx == nil then
		return false
	end
	local c = m.config
	return x >= sx and x < sx + c.width and d >= c.lane and d < c.lane + c.depth
end

-- The ship's value when hit by the player's `shots`-th shot.
function Mystery.value(m: Mystery, shots: number): number
	local values = m.config.values
	return values[shots % #values + 1]
end

-- The ship is gone (hit): the wait for the next one starts again.
function Mystery.remove(m: Mystery)
	m.x = nil
	m.elapsed = 0
end

return Mystery
