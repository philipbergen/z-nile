--!strict
-- f0104 AC2: the arrow look, pure. View.press tracks which arrows are held; View.arrowQuarters says where they look
-- in quarter turns from the heading (up 0, left 1, right -1, down 2, two together the half quarters between,
-- opposite arrows cancel); View.steer is one frame of the look. While an arrow is held the look turns toward it,
-- pitch level, at View.turnRate() (a quarter turn in View.TURN_SECONDS), and the mouse is ignored. Let go, it springs
-- back to the heading at the same rate until the mouse moves, which takes over from wherever the look is.
local View = require("@logic/View")
local t = require("@tests/lib/t")

local PI = math.pi
local DT = 1 / 60
local NONE: View.Arrows = { up = false, down = false, left = false, right = false }

local function arrows(keys: string): View.Arrows
	return {
		up = string.find(keys, "U", 1, true) ~= nil,
		down = string.find(keys, "D", 1, true) ~= nil,
		left = string.find(keys, "L", 1, true) ~= nil,
		right = string.find(keys, "R", 1, true) ~= nil,
	}
end

local function steer(yaw: number, pitch: number, spring: boolean?): View.Steer
	return { look = { yaw = yaw, pitch = pitch }, spring = spring == true }
end

-- frames of `a` held from `s` until the look stops changing; returns the frames taken and the final steer
local function settle(s: View.Steer, a: View.Arrows, dx: number?, dy: number?): (number, View.Steer)
	local frames = 0
	local cur = s
	while true do
		local nextSteer = View.steer(cur, a, dx or 0, dy or 0, DT)
		frames += 1
		assert(frames < 1000, "settles")
		if nextSteer.look.yaw == cur.look.yaw and nextSteer.look.pitch == cur.look.pitch then
			return frames - 1, nextSteer
		end
		cur = nextSteer
	end
end

return t.spec("f0104 arrow look", function(it)
	it("pressing and letting go of an arrow sets and clears just that arrow", function()
		local a = View.press(NONE, "LookUp", true)
		t.expect(a).toEqual({ up = true, down = false, left = false, right = false })
		a = View.press(a, "LookLeft", true)
		t.expect(a).toEqual({ up = true, down = false, left = true, right = false })
		a = View.press(a, "LookUp", false)
		t.expect(a).toEqual({ up = false, down = false, left = true, right = false })
		t.expect(View.press(a, "LookDown", true).down).toBe(true)
		t.expect(View.press(a, "LookRight", true).right).toBe(true)
		-- letting go of one arrow leaves the others held
		t.expect(View.press(arrows("UL"), "LookLeft", false))
			.toEqual({ up = true, down = false, left = false, right = false })
		t.expect(View.press(arrows("DR"), "LookUp", true))
			.toEqual({ up = true, down = true, left = false, right = true })
	end)

	it("other actions leave the arrows alone, and the result is a fresh table", function()
		local a = arrows("UL")
		local others: { View.Action } = { "Forward", "Jump", "Fire", "Left" }
		for _, action: View.Action in others do
			local b = View.press(a, action, false)
			t.expect(b).toEqual(a)
			t.expect(b ~= a).toBe(true)
		end
		t.expect(View.press(a, nil, true)).toEqual(a)
	end)

	it("where the arrows look, in quarter turns from the heading", function()
		local want: { [string]: number } = {
			U = 0,
			L = 1,
			R = -1,
			D = 2,
			UL = 0.5,
			UR = -0.5,
			DL = 1.5,
			DR = -1.5,
			UD = 0,
			LR = 0,
			UDL = 1,
			ULR = 0,
			DLR = 2,
			UDLR = 0,
		}
		for keys, q in want do
			t.expect(View.arrowQuarters(arrows(keys))).toBe(q)
		end
		t.expect(View.arrowQuarters(NONE)).toBe(nil)
	end)

	it(
		"a held arrow turns the look to it at the camera's turn rate: a quarter turn in TURN_SECONDS",
		function()
			local frames, final = settle(steer(0, 0), arrows("L"))
			t.expect(final.look.yaw).toBeNear(PI / 2, 1e-12)
			t.expect(final.look.pitch).toBe(0)
			t.expect(math.abs(frames * DT - View.TURN_SECONDS) <= DT + 1e-9).toBe(true)
			local first = View.steer(steer(0, 0), arrows("L"), 0, 0, DT)
			t.expect(first.look.yaw).toBeNear(View.turnRate() * DT, 1e-12)
			t.expect(first.spring).toBe(true)
		end
	)

	it("behind is the shorter way round, and up-and-left is 45 degrees", function()
		local _, back = settle(steer(PI / 2, 0), arrows("D"))
		t.expect(back.look.yaw).toBeNear(PI, 1e-12)
		local one = View.steer(steer(-PI / 2, 0), arrows("D"), 0, 0, DT)
		t.expect(one.look.yaw < -PI / 2).toBe(true) -- from the right it turns on round to the right
		local _, diag = settle(steer(0, 0), arrows("UL"))
		t.expect(diag.look.yaw).toBeNear(PI / 4, 1e-12)
	end)

	it(
		"pressing an arrow drops the mouse's look: the pitch levels and the mouse is ignored while held",
		function()
			local s = steer(-1.2, 0.6)
			local _, final = settle(s, arrows("U"), 40, -30)
			t.expect(final.look.yaw).toBeNear(0, 1e-12)
			t.expect(final.look.pitch).toBeNear(0, 1e-12)
			local held = View.steer(steer(0, 0), arrows("U"), 500, 500, DT)
			t.expect(held.look).toEqual({ yaw = 0, pitch = 0 })
		end
	)

	it("let go, the look springs back to the heading at the same rate, and stops springing there", function()
		local s = steer(PI / 2, 0, true)
		local frames, final = settle(s, NONE)
		t.expect(final.look).toEqual({ yaw = 0, pitch = 0 })
		t.expect(final.spring).toBe(false)
		t.expect(math.abs(frames * DT - View.TURN_SECONDS) <= DT + 1e-9).toBe(true)
	end)

	it("the mouse takes over from a spring, from wherever the look is", function()
		local s = View.steer(steer(PI / 2, 0, true), NONE, 0, 0, DT)
		t.expect(s.spring).toBe(true)
		local moved = View.steer(s, NONE, 10, 0, DT)
		t.expect(moved.spring).toBe(false)
		t.expect(moved.look).toEqual(View.look(s.look, 10, 0))
		local still = View.steer(moved, NONE, 0, 0, DT)
		t.expect(still.look).toEqual(moved.look) -- no spring any more
	end)

	it("without arrows or a spring, the mouse looks exactly as View.look", function()
		local s = steer(0.3, -0.2)
		t.expect(View.steer(s, NONE, 7, -4, DT).look).toEqual(View.look(s.look, 7, -4))
		t.expect(View.steer(s, NONE, 0, 0, DT).look).toEqual(s.look)
		t.expect(View.steer(s, NONE, 0, 0, DT).spring).toBe(false)
	end)

	it("a frame time that is not a positive number moves nothing, and a NaN mouse is ignored", function()
		for _, dt in { 0, -1, 0 / 0, math.huge } do
			t.expect(View.steer(steer(0, 0), arrows("L"), 0, 0, dt).look.yaw).toBe(0)
		end
		t.expect(View.steer(steer(0.5, 0), NONE, 0 / 0, 0, DT).look).toEqual({ yaw = 0.5, pitch = 0 })
	end)

	it("the steer it returns is a fresh table, and the given one is untouched", function()
		local s = steer(0.1, 0.2, true)
		local out = View.steer(s, arrows("R"), 0, 0, DT)
		t.expect(out ~= s and out.look ~= s.look).toBe(true)
		t.expect(s.look).toEqual({ yaw = 0.1, pitch = 0.2 })
		t.expect(s.spring).toBe(true)
	end)
end)
