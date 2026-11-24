--!strict
-- f0235 AC2: when the beacons show. View.elevated(eye) is the drawn eye above the wall tops (strictly), false for no
-- eye or one that is not a finite number. Over a hop and a long hop, drawn at any fractional tick, it is exactly the
-- span where Hop.rise is over Hop.CLEARANCE (the window Hop.airborne samples), and an eye held at a jump's top (f0234's
-- wait) is elevated. View.beacons(slots, present, elevated, pose) keys every power slot and only those, each true
-- exactly when that pellet is present, the eye elevated, and the eye's place (tile coordinates) not strictly within
-- View.BEACON.clear tiles of it; a nil pose is near nothing.
local Hop = require("@logic/Hop")
local Maze = require("@logic/Maze")
local Pellets = require("@logic/Pellets")
local View = require("@logic/View")
local t = require("@tests/lib/t")

local V = View :: any
local m = Maze.layout("classic")
local STAND = View.SCALE.eyeHeight
local WALL = View.SCALE.wallHeight

local function count(map: { [number]: boolean }): number
	local n = 0
	for _ in map do
		n += 1
	end
	return n
end

return t.spec("f0235 when the beacons show", function(it)
	it("the standing eye is not elevated; a jump's top is, and stays so while it is held there", function()
		t.expect(V.elevated(STAND)).toBe(false)
		for _ = 1, 3 do
			t.expect(V.elevated(STAND + Hop.RISE)).toBe(true)
		end
	end)

	it("strictly above the wall tops: at them is not, a hair over is", function()
		t.expect(V.elevated(WALL)).toBe(false)
		t.expect(V.elevated(WALL - 0.01)).toBe(false)
		t.expect(V.elevated(WALL + 0.01)).toBe(true)
		t.expect(V.elevated(1000)).toBe(true)
	end)

	it("no eye yet, or an eye that is not a finite number, is not elevated", function()
		t.expect(V.elevated(nil)).toBe(false)
		t.expect(V.elevated(0 / 0)).toBe(false)
		t.expect(V.elevated(math.huge)).toBe(false)
		t.expect(V.elevated(-math.huge)).toBe(false)
	end)

	it("over a hop and a long hop it is exactly where the rise clears the walls", function()
		local lengths: { number? } = { Hop.TICKS, Hop.LONG_TICKS }
		for _, ticks in lengths do
			local on = 0
			for k = -20, 500 do
				local at = k / 20
				local rise = Hop.rise(0, at, ticks)
				local want = rise > Hop.CLEARANCE
				t.expect(V.elevated(STAND + rise)).toBe(want)
				if want then
					on += 1
				end
			end
			t.expect(on > 0).toBe(true)
		end
	end)

	it("keys every power slot and only those", function()
		local slots = Pellets.slots(m)
		local present: { boolean } = Pellets.decode(m, Pellets.encode(Pellets.new(m)))
		for _, elevated in { true, false } do
			local map = V.beacons(slots, present, elevated)
			local powers = 0
			for i, slot in slots do
				if slot.kind == "power" then
					powers += 1
					t.expect(map[i]).toBe(elevated)
				else
					t.expect(map[i]).toBe(nil)
				end
			end
			t.expect(count(map)).toBe(powers)
		end
	end)

	it("an eaten power pellet has no beacon, elevated or not; the others keep theirs", function()
		local p = Pellets.new(m)
		local power = Pellets.tiles(p, "power")
		t.expect(#power).toBe(4)
		Pellets.eat(p, power[2])
		Pellets.eat(p, { x = 1, y = 1 }) -- a dot too: nothing of a beacon's
		local slots = Pellets.slots(m)
		local present = Pellets.decode(m, Pellets.encode(p))
		local up = V.beacons(slots, present, true)
		local down = V.beacons(slots, present, false)
		local shown = 0
		for i, slot in slots do
			if slot.kind == "power" then
				local eaten = slot.x == power[2].x and slot.y == power[2].y
				t.expect(up[i]).toBe(not eaten)
				t.expect(down[i]).toBe(false)
				if up[i] then
					shown += 1
				end
			end
		end
		t.expect(shown).toBe(3)
	end)

	it(
		"a beacon near the eye is not shown: strictly within BEACON.clear tiles, the others unaffected",
		function()
			local slots = Pellets.slots(m)
			local present = Pellets.decode(m, Pellets.encode(Pellets.new(m)))
			local clear = V.BEACON.clear
			t.expect(type(clear)).toBe("number")
			t.expect(clear >= 1 and clear <= 2).toBe(true) -- off its own tile and the next, and no farther than two
			local target: number? = nil
			for i, slot in slots do
				if slot.kind == "power" then
					target = target or i
				end
			end
			local ti = target :: number
			local ts = slots[ti]
			local cases: { { pose: View.Pose, near: boolean } } = {
				{ pose = { x = ts.x, y = ts.y }, near = true },
				{ pose = { x = ts.x + clear - 0.01, y = ts.y }, near = true },
				{ pose = { x = ts.x, y = ts.y + clear }, near = false },
				{ pose = { x = ts.x + clear * 0.6, y = ts.y + clear * 0.81 }, near = false }, -- just past clear, diagonally
				{ pose = { x = ts.x + clear * 0.6, y = ts.y + clear * 0.79 }, near = true },
				{ pose = { x = ts.x - clear - 0.01, y = ts.y }, near = false },
			}
			for _, case in cases do
				local map = V.beacons(slots, present, true, case.pose)
				t.expect(map[ti]).toBe(not case.near)
				for i, on in map do
					if i ~= ti then
						t.expect(on).toBe(true)
					end
				end
			end
		end
	)

	it(
		"a nil pose is near nothing, and the pose never shows a beacon that is not elevated or eaten",
		function()
			local slots = Pellets.slots(m)
			local p = Pellets.new(m)
			local power = Pellets.tiles(p, "power")
			Pellets.eat(p, power[1])
			local present = Pellets.decode(m, Pellets.encode(p))
			local up = V.beacons(slots, present, true, nil)
			local shown = 0
			for _, on in up do
				if on then
					shown += 1
				end
			end
			t.expect(shown).toBe(3)
			local far: View.Pose = { x = 13.5, y = 14 }
			for _, on in V.beacons(slots, present, false, far) do
				t.expect(on).toBe(false)
			end
			for i, slot in slots do
				if slot.x == power[1].x and slot.y == power[1].y then
					t.expect(V.beacons(slots, present, true, far)[i]).toBe(false)
				end
			end
		end
	)

	it("a presence list missing an entry shows no beacon for it", function()
		local slots = Pellets.slots(m)
		local map = V.beacons(slots, {}, true)
		for _, on in map do
			t.expect(on).toBe(false)
		end
		t.expect(count(map)).toBe(4)
	end)
end)
