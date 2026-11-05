--!strict
-- f0143 AC7 (design review 001 F3; runs once f0126, which f0143 depends on, has landed): f0126's pick stop caps the
-- step's speed at the distance to the centre beside a marked wall, and that cap applies after the boost
-- (Boost.speed first, then the cap), so a boosted player asking for a pick stops exactly on the centre and the pick
-- starts there, sooner than at the level's speed. Applying the boost after the cap would carry the player past.
--
-- f0126's corridor: west from the spawn (6, 2) to (1, 2), between two thick walls whose rows 1 and 3 can be picked.
local Boost = require("@logic/Boost")
local Maze = require("@logic/Maze")
local Movement = require("@logic/Movement")
local Session = require("@logic/Session")
local t = require("@tests/lib/t")

local CORRIDOR = Maze.parse({ "#########", "#########", "#.....P.#", "#########", "#########" }, "corridor")
local SPEED = Movement.DEFAULT_CONFIG.speed
local BOOSTED = Boost.speed(SPEED, true, Movement.UNITS)

local function marked(s: Session.Session, x: number): boolean
	for _, tile in ((Session.frame(s, "p") :: any).walls).marked do
		if tile.x == x and (tile.y == 1 or tile.y == 3) then
			return true
		end
	end
	return false
end

-- the first tile west from the spawn with a marked wall beside it
local function firstStop(s: Session.Session): number?
	for x = 6, 1, -1 do
		if marked(s, x) then
			return x
		end
	end
	return nil
end

local function new(seed: number): Session.Session
	local s = Session.new(CORRIDOR, seed)
	Session.join(s, "p")
	return s
end

return t.spec("f0143 the boost under f0126's pick stop", function(it)
	it(
		"a boosted player asking for a pick stops exactly on the centre beside the wall, and the pick starts",
		function()
			-- two tiles west of the spawn (240 units): not a whole number of boosted steps (45), so only the cap lands it
			local seed: number? = nil
			for k = 1, 2000 do
				if firstStop(new(k)) == 4 then
					seed = k
					break
				end
			end
			assert(seed, "a seed whose first marked wall is beside x = 4")
			t.expect((2 * Movement.UNITS) % BOOSTED ~= 0).toBe(true)
			local s = new(seed :: number)
			t.expect((Session.submit(s, "p", Boost.INTENT))).toBe(true)
			t.expect((Session.submit(s, "p", "Pick"))).toBe(true)
			local startedAt: number? = nil
			for _ = 1, 12 do
				for _, e in Session.step(s) do
					if e.kind == "PickStarted" and startedAt == nil then
						startedAt = s.tick
					end
				end
				if startedAt then
					break
				end
			end
			t.expect(startedAt).toBe(math.ceil(2 * Movement.UNITS / BOOSTED)) -- sooner than at the level's speed
			t.expect(Boost.active(Session.frame(s, "p").boosted, startedAt :: number)).toBe(true)
			local f = Session.frame(s, "p")
			t.expect(f.player.x).toBe(4)
			t.expect(f.player.moving).toBe(false)
		end
	)
end)
