--!strict
-- f0027 AC1: one straight-line swipe is one of the four existing intents, or nothing.
-- Time is not an input. The cone is 30 degrees around a screen axis, including the boundary.
local Movement = require("@logic/Movement")
local Touch = require("@logic/Touch")
local View = require("@logic/View")
local t = require("@tests/lib/t")

local function vec(degrees: number, distance: number): (number, number)
	local a = math.rad(degrees)
	return distance * math.cos(a), distance * math.sin(a)
end

return t.spec("f0027 swipe", function(it)
	it("pins the swipe at 48 px and 30 degrees, and the four intents stay exactly those", function()
		t.expect(Touch.MIN_SWIPE).toBe(48)
		t.expect(Touch.AXIS_DEGREES).toBe(30)
		local names = {}
		for _, intent in Movement.INTENTS do
			table.insert(names, intent)
		end
		table.sort(names)
		t.expect(names).toEqual({ "Back", "Forward", "Left", "Right" })
	end)

	it("maps the screen axes through the key map: left, right, down, up", function()
		t.expect(Touch.swipe(-80, 0)).toBe(View.action("A"))
		t.expect(Touch.swipe(80, 0)).toBe(View.action("D"))
		t.expect(Touch.swipe(0, 80)).toBe(View.action("S"))
		t.expect(Touch.swipe(0, -80)).toBe(View.action("W"))
		t.expect(View.action("A")).toBe("Left")
		t.expect(View.action("D")).toBe("Right")
		t.expect(View.action("S")).toBe("Back")
		t.expect(View.action("W")).toBe("Forward")
		for _, intent in { Touch.swipe(-80, 0), Touch.swipe(80, 0), Touch.swipe(0, 80), Touch.swipe(0, -80) } do
			t.expect(Movement.isIntent(intent)).toBe(true)
			t.expect(intent == "Snap").toBe(false)
		end
	end)

	it(
		"includes a 48 px axis swipe and rejects one just under, a short drag, and a non-finite delta",
		function()
			t.expect(Touch.swipe(48, 0)).toBe("Right")
			t.expect(Touch.swipe(-48, 0)).toBe("Left")
			t.expect(Touch.swipe(0, 48)).toBe("Back")
			t.expect(Touch.swipe(0, -48)).toBe("Forward")
			t.expect(Touch.swipe(47.999, 0)).toBe(nil)
			t.expect(Touch.swipe(-10, 0)).toBe(nil)
			t.expect(Touch.swipe(0 / 0, 80)).toBe(nil)
			t.expect(Touch.swipe(math.huge, 0)).toBe(nil)
			t.expect(Touch.swipe(0, -math.huge)).toBe(nil)
		end
	)

	it("accepts 29 and 60 degrees and the tangent boundary, and rejects 31, 45 and just outside", function()
		local dx29, dy29 = vec(29, 80)
		local dx31, dy31 = vec(31, 80)
		local dx45, dy45 = vec(45, 100)
		local dx60, dy60 = vec(60, 80)
		local dx61, dy61 = vec(61, 80)
		t.expect(Touch.swipe(dx29, dy29)).toBe("Right")
		t.expect(Touch.swipe(-dx29, -dy29)).toBe("Left")
		t.expect(Touch.swipe(dx60, dy60)).toBe("Back")
		t.expect(Touch.swipe(-dx61, -dy61)).toBe("Forward")
		t.expect(Touch.swipe(dx31, dy31)).toBe(nil)
		t.expect(Touch.swipe(dx45, dy45)).toBe(nil)
		local tan = math.tan(math.rad(30))
		t.expect(Touch.swipe(100, 100 * tan)).toBe("Right")
		t.expect(Touch.swipe(-(100 * tan), -100)).toBe("Forward")
		t.expect(Touch.swipe(100, 100 * tan + 1)).toBe(nil)
	end)

	it("the same deltas always classify the same way", function()
		t.expect(Touch.swipe(-90, 5)).toBe(Touch.swipe(-90, 5))
		t.expect(Touch.swipe(-90, 5)).toBe("Left")
	end)
end)
