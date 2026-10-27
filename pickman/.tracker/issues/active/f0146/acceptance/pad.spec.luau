--!strict
-- f0146 AC1 and AC2: Logic/Pad. The map: the bottom face button (ButtonA) jumps, R2 fires, R3 snaps the look, the
-- D-pad turns; ButtonA also continues at game over. The left stick folds into turn
-- intents relative to the heading: the dominant axis picks the sector (a tie goes vertical), a tilt of STEER_ON
-- engages it and emits once, another sector at STEER_ON moves at once, below STEER_OFF releases, between keeps;
-- holding emits nothing more; a non-finite tilt releases. The right stick's look: a radial dead zone, a squared
-- response, right turns right and up looks up, scaled by dt, in View.look's units. Only Gamepad1 to Gamepad8 are pads.
local Pad = require("@logic/Pad")
local View = require("@logic/View")
local t = require("@tests/lib/t")

local NAN = 0 / 0
local K = View.MOUSE_RADIANS_PER_PIXEL

local function near(a: number, b: number)
	t.expect(math.abs(a - b) < 1e-9).toBe(true)
end

return t.spec("f0146 Pad", function(it)
	it("the constants and the button map", function()
		-- each entry of this issue's map, not its size: later features add rows (f0126's ButtonY = "Pick")
		local want: { [string]: string } = {
			ButtonA = "Jump",
			ButtonR2 = "Fire",
			ButtonR3 = "Snap",
			DPadUp = "Forward",
			DPadDown = "Back",
			DPadLeft = "Left",
			DPadRight = "Right",
		}
		for key, action in want do
			t.expect(Pad.BUTTONS[key]).toBe(action)
		end
		t.expect(Pad.CONTINUE).toBe("ButtonA")
		t.expect(Pad.STEER_ON).toBe(0.6)
		t.expect(Pad.STEER_OFF).toBe(0.4)
		t.expect(Pad.STEER_MARGIN).toBe(15) -- degrees past the diagonal (decided with the user, 2026-10-25)
		t.expect(Pad.LOOK_DEAD).toBe(0.15)
		t.expect(Pad.LOOK_YAW).toBe(3)
		t.expect(Pad.LOOK_PITCH).toBe(2)
		t.expect(Pad.INVERT).toBe(false)
		t.expect(Pad.action("ButtonA")).toBe("Jump")
		t.expect(Pad.action("ButtonX")).toBe(nil)
		t.expect(Pad.action("W")).toBe(nil) -- the keys stay View's
		for key in Pad.BUTTONS do
			t.expect(View.action(key)).toBe(nil) -- no overlap with View.KEYS
		end
	end)

	it("a push engages a sector once, heading-relative, ties vertical", function()
		type Case = { x: number, y: number, want: string }
		local cases: { Case } = {
			{ x = 0, y = 1, want = "Forward" },
			{ x = 0, y = -1, want = "Back" },
			{ x = -1, y = 0, want = "Left" },
			{ x = 1, y = 0, want = "Right" },
			{ x = 0.5, y = 0.5, want = "Forward" }, -- a tie goes vertical
			{ x = -0.5, y = -0.5, want = "Back" },
			{ x = 0.7, y = 0.3, want = "Right" },
		}
		for _, case in cases do
			local _, intent = Pad.steer(Pad.steerStart(), case.x, case.y)
			t.expect(intent).toBe(case.want)
		end
		local s, intent = Pad.steer(Pad.steerStart(), 0, Pad.STEER_ON - 0.01)
		t.expect(intent).toBe(nil)
		t.expect(s.held).toBe(nil)
		s, intent = Pad.steer(s, 0, Pad.STEER_ON)
		t.expect(intent).toBe("Forward")
		t.expect(s.held).toBe("Forward")
	end)

	it(
		"holding emits nothing more; a push into another sector moves at once; between the thresholds keeps the sector",
		function()
			local s, intent = Pad.steer(Pad.steerStart(), -1, 0)
			t.expect(intent).toBe("Left")
			for _ = 1, 5 do
				s, intent = Pad.steer(s, -0.9, 0.1)
				t.expect(intent).toBe(nil)
			end
			s, intent = Pad.steer(s, 0, 0.9)
			t.expect(intent).toBe("Forward")
			s, intent = Pad.steer(s, 0.5, 0) -- between STEER_OFF and STEER_ON: keeps Forward, emits nothing
			t.expect(intent).toBe(nil)
			t.expect(s.held).toBe("Forward")
		end
	)

	it("below STEER_OFF releases, and the next push emits again; non-finite releases", function()
		local s, intent = Pad.steer(Pad.steerStart(), 1, 0)
		s, intent = Pad.steer(s, Pad.STEER_OFF - 0.01, 0)
		t.expect(intent).toBe(nil)
		t.expect(s.held).toBe(nil)
		s, intent = Pad.steer(s, 1, 0)
		t.expect(intent).toBe("Right")
		s, intent = Pad.steer(s, NAN, 0)
		t.expect(intent).toBe(nil)
		t.expect(s.held).toBe(nil)
		s, intent = Pad.steer(s, 1, 0)
		t.expect(intent).toBe("Right")
	end)

	it("look: the dead zone, the squared response, the directions, dt, non-finite", function()
		local dx, dy = Pad.look(0.1, 0.1, 1 / 60) -- r 0.14 < 0.15
		t.expect(dx).toBe(0)
		t.expect(dy).toBe(0)
		dx, dy = Pad.look(1, 0, 0.5) -- full right
		near(dx, Pad.LOOK_YAW * 0.5 / K)
		near(dy, 0)
		dx, dy = Pad.look(0, 1, 0.5) -- full up: dy negative, so View.look raises the pitch
		near(dx, 0)
		near(dy, -Pad.LOOK_PITCH * 0.5 / K)
		local after = View.look({ yaw = 0, pitch = 0 }, Pad.look(0, 1, 0.1))
		t.expect(after.pitch > 0).toBe(true)
		local right = View.look({ yaw = 0, pitch = 0 }, Pad.look(1, 0, 0.1))
		t.expect(right.yaw < 0).toBe(true) -- a negative yaw turns right (View's convention)
		-- squared: half way past the dead zone gives a quarter of the rate
		local half = Pad.LOOK_DEAD + (1 - Pad.LOOK_DEAD) / 2
		dx = Pad.look(half, 0, 1)
		near(dx, 0.25 * Pad.LOOK_YAW / K)
		-- dt scales it
		local one = Pad.look(1, 0, 0.1)
		local two = Pad.look(1, 0, 0.2)
		near(two, 2 * one)
		-- a tilt past 1 counts as 1
		near((Pad.look(2, 0, 0.1)), one)
		local bad: { { number } } =
			{ { NAN, 0, 0.1 }, { 1, 0, NAN }, { 1, 0, 0 }, { 1, 0, -0.1 }, { 1, math.huge, 0.1 } }
		for _, b in bad do
			local bx, by = Pad.look(b[1], b[2], b[3])
			t.expect(bx).toBe(0)
			t.expect(by).toBe(0)
		end
	end)

	it(
		"an engaged stick leaves its sector only 15 degrees past the diagonal: a wobble on it emits once",
		function()
			local function at(deg: number): (number, number)
				return 0.9 * math.cos(math.rad(deg)), 0.9 * math.sin(math.rad(deg))
			end
			-- from rest, just past the up-left diagonal (136 degrees): Left, then a +-1 degree wobble emits nothing more
			local s, intent = Pad.steer(Pad.steerStart(), at(136))
			t.expect(intent).toBe("Left")
			local more = 0
			for i = 1, 12 do
				local x, y = at(if i % 2 == 0 then 136 else 134)
				s, intent = Pad.steer(s, x, y)
				if intent then
					more += 1
				end
			end
			t.expect(more).toBe(0)
			t.expect(s.held).toBe("Left")
			-- a sweep from up toward left: Left only past 90 + 45 + 15 = 150 degrees, and once
			s, intent = Pad.steer(Pad.steerStart(), at(90))
			t.expect(intent).toBe("Forward")
			local emitted: { string } = {}
			for deg = 91, 179 do
				s, intent = Pad.steer(s, at(deg))
				if intent then
					table.insert(emitted, `{intent}@{deg}`)
				end
			end
			t.expect(emitted).toEqual({ "Left@151" })
			-- from rest, an exact diagonal still goes vertical
			local _, tie = Pad.steer(Pad.steerStart(), at(135))
			t.expect(tie).toBe("Forward")
		end
	)

	it(
		"track: a controller's button or a stick past STEER_OFF takes over; drift, keys and touches keep the one before",
		function()
			t.expect(Pad.track(nil, "Gamepad1", 1)).toBe("Gamepad1")
			t.expect(Pad.track("Gamepad1", "Gamepad2", 1)).toBe("Gamepad2") -- another controller's button
			t.expect(Pad.track("Gamepad1", "Gamepad2", Pad.STEER_OFF)).toBe("Gamepad2") -- its stick, just enough
			t.expect(Pad.track("Gamepad1", "Gamepad2", Pad.STEER_OFF - 0.01)).toBe("Gamepad1") -- drift
			t.expect(Pad.track("Gamepad1", "Gamepad2", 0 / 0)).toBe("Gamepad1")
			t.expect(Pad.track("Gamepad2", "Keyboard", 1)).toBe("Gamepad2") -- a key keeps the controller
			t.expect(Pad.track("Gamepad2", "Touch", 1)).toBe("Gamepad2")
			t.expect(Pad.track(nil, "MouseMovement", 1)).toBe(nil)
			t.expect(Pad.track("Gamepad3", "GamepadX", 1)).toBe("Gamepad3")
		end
	)

	it("isPad names the gamepads only", function()
		for i = 1, 8 do
			t.expect(Pad.isPad(`Gamepad{i}`)).toBe(true)
		end
		for _, v in { "Gamepad0", "Gamepad9", "GamepadX", "Gamepad", "Keyboard", "Touch", "MouseButton1", "" } do
			t.expect(Pad.isPad(v)).toBe(false)
		end
	end)
end)
