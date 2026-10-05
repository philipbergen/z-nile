--!strict
-- f0110 AC7: random play on the classic maze. The player stays on corridor centrelines between
-- walkable tiles, moves exactly its speed per tick while moving, reports each tile entry once, and
-- the same seed gives the same run.
local Maze = require("@logic/Maze")
local Movement = require("@logic/Movement")
local sim = require("@tests/lib/sim")
local t = require("@tests/lib/t")

local maze = Maze.layout("classic")
local CFG = { speed = 30, turnBufferTicks = 24 }
local TICKS = 900
local INTENTS: { Movement.Intent } = { "Left", "Right", "Left", "Right", "Forward", "Back" }

local MODEL: sim.Model<Movement.State> = {
	name = "movement",
	tickRate = 30,
	new = function(_seed: number): Movement.State
		return Movement.spawn(maze)
	end,
	step = function(s: Movement.State, intents: { any }, _k: number): { sim.Event }?
		return Movement.step(maze, s, intents, CFG) :: any
	end,
	observe = function(s: Movement.State): any
		local x, y = Movement.position(s)
		local o = Movement.occupied(maze, s)
		return { x = x, y = y, heading = s.heading, moving = s.moving, ox = o.x, oy = o.y }
	end,
}

-- A deterministic script: roughly one intent every eight ticks, chosen by a seeded LCG.
local function script(seed: number): { sim.Item }
	local state = seed * 7919 + 17
	local function nextInt(n: number): number
		state = (state * 1103515245 + 12345) % 2147483648
		return state % n
	end
	local out: { sim.Item } = {}
	for k = 0, TICKS - 1 do
		if nextInt(8) == 0 then
			table.insert(out, sim.intent(k, INTENTS[nextInt(#INTENTS) + 1]))
		end
	end
	return out
end

local function walkable(x: number, y: number): boolean
	return Maze.passable(maze, { x = x % maze.width, y = y % maze.height }, "player")
end

return t.spec("f0110 invariants under random play", function(it)
	for _, seed in sim.seeds(20) do
		it(`seed {seed}: centreline, speed, tile entry and determinism`, function()
			local trace =
				sim.assertDeterministic(MODEL, { seed = seed, ticks = TICKS, script = script(seed) })
			local wrapped: { [number]: boolean } = {}
			local entered: { [number]: { x: number, y: number } } = {}
			for _, e in trace.events do
				if e.event.kind == "Wrapped" then
					wrapped[e.tick] = true
				elseif e.event.kind == "Entered" then
					t.expect(entered[e.tick]).toBe(nil)
					entered[e.tick] = { x = e.event.x, y = e.event.y }
				end
			end
			local speed = CFG.speed / Movement.UNITS
			local moved = false
			for tk = 0, trace.steps do
				local o = sim.state(trace, tk)
				-- on a centreline: one coordinate is a whole tile
				if o.x ~= math.floor(o.x) and o.y ~= math.floor(o.y) then
					error(`tick {tk}: off the centreline at ({o.x}, {o.y})`)
				end
				-- between two walkable tiles
				if
					not (
						walkable(math.floor(o.x), math.floor(o.y))
						and walkable(math.ceil(o.x), math.ceil(o.y))
					)
				then
					error(`tick {tk}: inside a wall at ({o.x}, {o.y})`)
				end
				-- the occupied tile is walkable and contains the centre point
				t.expect(walkable(o.ox, o.oy)).toBe(true)
				local dx = math.abs(o.x - o.ox) % maze.width
				local dy = math.abs(o.y - o.oy) % maze.height
				if math.min(dx, maze.width - dx) > 0.5 or math.min(dy, maze.height - dy) > 0.5 then
					error(`tick {tk}: occupied ({o.ox}, {o.oy}) does not contain ({o.x}, {o.y})`)
				end
				if tk > 0 then
					local p = sim.state(trace, tk - 1)
					local changed = p.ox ~= o.ox or p.oy ~= o.oy
					local e = entered[tk]
					if changed ~= (e ~= nil) or (e and (e.x ~= o.ox or e.y ~= o.oy)) then
						error(
							`tick {tk}: occupied ({p.ox},{p.oy}) -> ({o.ox},{o.oy}) but Entered = {e and `({e.x},{e.y})` or "none"}`
						)
					end
					if not wrapped[tk] then
						local dist = math.abs(o.x - p.x) + math.abs(o.y - p.y)
						-- a cornering-grace turn (AC9) cuts the corner from `off` PAST the centre just left:
						-- the player ends `off + speed` along the new heading, so it moves 2 * off + speed.
						-- (A turn taken while approaching a centre is an ordinary L-shaped move of `speed`.)
						local cx, cy = math.floor(p.x + 0.5), math.floor(p.y + 0.5)
						local hx, hy = Maze.delta(p.heading)
						local past = (p.x - cx) * hx + (p.y - cy) * hy
						local quarter = p.heading ~= o.heading and Maze.opposite(p.heading) ~= o.heading
						local off = if quarter and past > 1e-9 then past else 0
						local expected = 2 * off + speed
						if off > speed + 1e-9 then
							error(`tick {tk}: turned {off} tiles past a centre, more than one step`)
						end
						if p.moving and o.moving and math.abs(dist - expected) > 1e-9 then
							error(`tick {tk}: moved {dist} tiles, expected {expected}`)
						end
						if dist > expected + 1e-9 then
							error(`tick {tk}: moved {dist} tiles, more than {expected}`)
						end
						moved = moved or dist > 0
					end
				end
			end
			t.expect(moved).toBe(true)
		end)
	end
end)
