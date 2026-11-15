--!strict
-- f0203 AC2: arcade's gamepad folds (the stick's sector fold, the look stick's rate, the driving controller).
local Pad = require("@logic/Pad")
local t = require("@tests/lib/t")

local function at(deg: number, r: number?): (number, number)
	local k = r or 1
	return k * math.cos(math.rad(deg)), k * math.sin(math.rad(deg))
end

return t.spec("f0203 Pad", function(it)
	it("the defaults are pickman's accepted gamepad tuning (f0146)", function()
		t.expect(Pad.DEFAULT).toEqual({
			on = 0.6,
			off = 0.4,
			margin = 15,
			axes = "both",
			lookDead = 0.15,
			lookYaw = 3,
			lookPitch = 2,
			invert = false,
		})
		t.expect(table.isfrozen(Pad.DEFAULT)).toBe(true)
	end)

	it("a push past the on tilt sends its direction once, and holds it", function()
		local s, dir = Pad.steer(Pad.steerStart(), -1, 0)
		t.expect(dir).toBe("left")
		t.expect(s.held).toBe("left")
		s, dir = Pad.steer(s, -1, 0)
		t.expect(dir).toBe(nil)
		t.expect(s.held).toBe("left")
	end)

	it("a tilt short of the on tilt never engages", function()
		local s, dir = Pad.steer(Pad.steerStart(), 0.59, 0)
		t.expect(dir).toBe(nil)
		t.expect(s.held).toBe(nil)
		s, dir = Pad.steer(s, 0.6, 0)
		t.expect(dir).toBe("right")
	end)

	it(
		"an engaged stick stays engaged down to the off tilt, and a new push after release sends again",
		function()
			local s = Pad.steer(Pad.steerStart(), -1, 0)
			local dir
			s, dir = Pad.steer(s, -0.45, 0)
			t.expect(dir).toBe(nil)
			t.expect(s.held).toBe("left")
			s, dir = Pad.steer(s, -0.4, 0)
			t.expect(s.held).toBe("left")
			s, dir = Pad.steer(s, -0.39, 0)
			t.expect(dir).toBe(nil)
			t.expect(s.held).toBe(nil)
			s, dir = Pad.steer(s, -0.7, 0)
			t.expect(dir).toBe("left")
		end
	)

	it("each sector is the dominant axis, a tie going vertical (x right, y up)", function()
		local cases: { { number } } =
			{ { 0, 1 }, { 0, -1 }, { 1, 0 }, { -1, 0 }, { 0.7, 0.7 }, { -0.7, -0.7 }, { 0.8, -0.3 } }
		local want = { "up", "down", "right", "left", "up", "down", "right" }
		for i, c in cases do
			local _, dir = Pad.steer(Pad.steerStart(), c[1], c[2])
			t.expect(dir).toBe(want[i])
		end
	end)

	it("an engaged stick changes sector only past the diagonal by the margin", function()
		local s = Pad.steer(Pad.steerStart(), at(0))
		local dir
		s, dir = Pad.steer(s, at(59))
		t.expect(dir).toBe(nil)
		t.expect(s.held).toBe("right")
		s, dir = Pad.steer(s, at(60))
		t.expect(dir).toBe(nil)
		s, dir = Pad.steer(s, at(61))
		t.expect(dir).toBe("up")
		-- a wobble across the next diagonal never flips it back and forth
		for _, deg in { 134, 136, 134, 136 } do
			s, dir = Pad.steer(s, at(deg))
			t.expect(dir).toBe(nil)
			t.expect(s.held).toBe("up")
		end
		s, dir = Pad.steer(s, at(151))
		t.expect(dir).toBe("left")
	end)

	it("an engaged stick turned past the margin while short of the on tilt keeps its sector", function()
		local s = Pad.steer(Pad.steerStart(), 1, 0)
		local dir
		s, dir = Pad.steer(s, 0, 0.5)
		t.expect(dir).toBe(nil)
		t.expect(s.held).toBe("right")
	end)

	it("a reading that is not a number releases the stick", function()
		local s = Pad.steer(Pad.steerStart(), 1, 0)
		local dir
		s, dir = Pad.steer(s, 0 / 0, 0)
		t.expect(dir).toBe(nil)
		t.expect(s.held).toBe(nil)
		s, dir = Pad.steer(Pad.steer(Pad.steerStart(), 1, 0), 1, math.huge)
		t.expect(s.held).toBe(nil)
	end)

	it("a tuning's on tilt and margin are the ones the fold uses", function()
		local tight = Pad.tune({ on = 0.9, off = 0.5, margin = 5 })
		local s, dir = Pad.steer(Pad.steerStart(), 0.85, 0, tight)
		t.expect(dir).toBe(nil)
		s, dir = Pad.steer(s, 0.95, 0, tight)
		t.expect(dir).toBe("right")
		s, dir = Pad.steer(s, 0.45, 0, tight)
		t.expect(s.held).toBe(nil)
		s = Pad.steer(Pad.steerStart(), 1, 0, tight)
		local x, y = at(51)
		s, dir = Pad.steer(s, x, y, tight)
		t.expect(dir).toBe("up")
	end)

	it("a horizontal fold reads the x tilt alone: left and right, never up or down", function()
		local h = Pad.tune({ axes = "horizontal" })
		local s, dir = Pad.steer(Pad.steerStart(), 0, 1, h)
		t.expect(dir).toBe(nil)
		t.expect(s.held).toBe(nil)
		s, dir = Pad.steer(s, -0.65, 0.9, h)
		t.expect(dir).toBe("left")
		s, dir = Pad.steer(s, -0.45, 0.9, h)
		t.expect(dir).toBe(nil)
		t.expect(s.held).toBe("left")
		-- the other side at once: no diagonal to pass
		s, dir = Pad.steer(s, 0.7, 0, h)
		t.expect(dir).toBe("right")
		s, dir = Pad.steer(s, 0.3, 0.9, h)
		t.expect(s.held).toBe(nil)
	end)

	it(
		"a horizontal fold never holds the side the stick is not on: short of on across the centre, it releases",
		function()
			local h = Pad.tune({ axes = "horizontal" })
			local s, dir = Pad.steer(Pad.steerStart(), -1, 0, h)
			t.expect(s.held).toBe("left")
			-- a flick past the centre between two frames, short of the on tilt: released, nothing sent
			s, dir = Pad.steer(s, 0.5, 0, h)
			t.expect(dir).toBe(nil)
			t.expect(s.held).toBe(nil)
			s, dir = Pad.steer(s, 0.6, 0, h)
			t.expect(dir).toBe("right")
			t.expect(s.held).toBe("right")
			-- on the same side, the band between off and on keeps it
			s, dir = Pad.steer(s, 0.5, 0, h)
			t.expect(dir).toBe(nil)
			t.expect(s.held).toBe("right")
		end
	)

	it("the look stick turns at its rate: full tilt right turns right, full tilt up looks up", function()
		local dyaw, dpitch = Pad.look(1, 0, 0.5)
		t.expect(dyaw).toBeNear(-1.5, 1e-12)
		t.expect(dpitch).toBeNear(0, 1e-12)
		dyaw, dpitch = Pad.look(0, 1, 0.5)
		t.expect(dyaw).toBeNear(0, 1e-12)
		t.expect(dpitch).toBeNear(1, 1e-12)
		dyaw, dpitch = Pad.look(-1, -1, 0.25)
		t.expect(dyaw).toBeNear(3 * 0.25 / math.sqrt(2), 1e-12)
		t.expect(dpitch).toBeNear(-2 * 0.25 / math.sqrt(2), 1e-12)
	end)

	it("the look stick has a radial dead zone and a squared response past it", function()
		local dyaw, dpitch = Pad.look(0.1, -0.1, 0.016)
		t.expect(dyaw).toBe(0)
		t.expect(dpitch).toBe(0)
		dyaw = Pad.look(0.149, 0, 1)
		t.expect(dyaw).toBe(0)
		dyaw = Pad.look(0.575, 0, 1) -- half way from the dead zone to full tilt
		t.expect(dyaw).toBeNear(-0.25 * 3, 1e-12)
		local over, full = Pad.look(2, 0, 1), Pad.look(1, 0, 1)
		t.expect(over).toBeNear(full, 1e-12)
	end)

	it("the look is frame-rate independent: two half frames turn as far as one frame", function()
		local a1, b1 = Pad.look(0.8, 0.3, 0.008)
		local a2, b2 = Pad.look(0.8, 0.3, 0.016)
		t.expect(a1 + a1).toBeNear(a2, 1e-12)
		t.expect(b1 + b1).toBeNear(b2, 1e-12)
	end)

	it("invert flips the pitch alone, and a tuning's rates and dead zone are the ones used", function()
		local inv = Pad.tune({ invert = true })
		local dyaw, dpitch = Pad.look(0.6, 0.8, 0.1, inv)
		local y0, p0 = Pad.look(0.6, 0.8, 0.1)
		t.expect(dyaw).toBeNear(y0, 1e-12)
		t.expect(dpitch).toBeNear(-p0, 1e-12)
		local fast = Pad.tune({ lookYaw = 6, lookPitch = 1, lookDead = 0 })
		dyaw, dpitch = Pad.look(0, 0.5, 1, fast)
		t.expect(dpitch).toBeNear(0.25, 1e-12)
		dyaw = Pad.look(1, 0, 1, fast)
		t.expect(dyaw).toBeNear(-6, 1e-12)
	end)

	it("a resting look stick turns nothing, even with no dead zone", function()
		local dyaw, dpitch = Pad.look(0, 0, 0.1, Pad.tune({ lookDead = 0 }))
		t.expect(dyaw).toBe(0)
		t.expect(dpitch).toBe(0)
		dyaw, dpitch = Pad.look(0.15, 0, 0.1)
		t.expect(dyaw).toBe(0)
		t.expect(dpitch).toBe(0)
	end)

	it("the look turns nothing for a dt or reading that is not a positive finite number", function()
		for _, c in { { 1, 0, 0 }, { 1, 0, -0.1 }, { 1, 0, 0 / 0 }, { 0 / 0, 1, 0.1 }, { 1, math.huge, 0.1 } } do
			local dyaw, dpitch = Pad.look(c[1], c[2], c[3])
			t.expect(dyaw).toBe(0)
			t.expect(dpitch).toBe(0)
		end
	end)

	it(
		"the most recently used gamepad drives; drift below the off tilt and other devices never take over",
		function()
			t.expect(Pad.track(nil, "Gamepad1", 1)).toBe("Gamepad1")
			t.expect(Pad.track("Gamepad1", "Gamepad2", 1)).toBe("Gamepad2")
			t.expect(Pad.track("Gamepad1", "Gamepad2", 0.39)).toBe("Gamepad1")
			t.expect(Pad.track("Gamepad1", "Gamepad2", 0.4)).toBe("Gamepad2")
			t.expect(Pad.track("Gamepad1", "Keyboard", 1)).toBe("Gamepad1")
			t.expect(Pad.track("Gamepad1", "Gamepad2", math.huge)).toBe("Gamepad1")
			t.expect(Pad.track("Gamepad1", "Gamepad2", 0 / 0)).toBe("Gamepad1")
			t.expect(Pad.track("Gamepad1", "Gamepad2", 0.45, Pad.tune({ on = 0.8, off = 0.5 })))
				.toBe("Gamepad1")
		end
	)

	it("only Gamepad1 to Gamepad8 are gamepads", function()
		for n = 1, 8 do
			t.expect(Pad.isPad(`Gamepad{n}`)).toBe(true)
		end
		for _, name in
			{ "Gamepad0", "Gamepad9", "Gamepad10", "Keyboard", "MouseButton1", "Touch", "gamepad1" }
		do
			t.expect(Pad.isPad(name)).toBe(false)
		end
	end)

	it("tune fills from the defaults, freezes, and refuses a tuning that cannot work", function()
		local t1 = Pad.tune({ margin = 10 })
		t.expect(t1.margin).toBe(10)
		t.expect(t1.on).toBe(0.6)
		t.expect(table.isfrozen(t1)).toBe(true)
		t.expect(Pad.tune()).toEqual(Pad.DEFAULT)
		local bads: { { any } } = {
			{ "off", 0.6 },
			{ "on", 0.3 },
			{ "on", 1.2 },
			{ "off", 0 },
			{ "margin", 45 },
			{ "margin", -1 },
			{ "axes", "diagonal" },
			{ "lookDead", 1 },
			{ "lookYaw", -1 },
			{ "lookPitch", 0 / 0 },
			{ "invert", 1 },
			{ "lookPitch", -1 },
			{ "lookDead", -0.1 },
			{ "on", 0 / 0 },
			{ "margin", math.huge },
			{ "lookYaw", math.huge },
		}
		for _, bad in bads do
			local over: any = { [bad[1]] = bad[2] }
			t.expect(function()
				Pad.tune(over)
			end).toThrow("Pad.tune")
		end
	end)
end)
