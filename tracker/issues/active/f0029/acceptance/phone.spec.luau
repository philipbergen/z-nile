--!strict
-- f0029 AC4 / R0012 RC1: one synthetic phone session across the three issues.
local Hud = require("@logic/Hud")
local Movement = require("@logic/Movement")
local Touch = require("@logic/Touch")
local View = require("@logic/View")
local t = require("@tests/lib/t")

local function laidOut(width: number, height: number, inset: any?): any
	return (Hud.layout :: any)(width, height, inset)
end

return t.spec("f0029 phone session", function(it)
	it(
		"1920x1080 with no inset is still today's HUD, and a notched phone moves only the safe rect",
		function()
			local desk = laidOut(1920, 1080, { top = 0, bottom = 0, left = 0, right = 0 })
			t.expect({ desk.textSize, desk.margin, desk.iconSize, desk.barWidth, desk.barHeight }).toEqual({
				40,
				20,
				40,
				400,
				16,
			})
			t.expect(desk.safeX).toBe(0)
			t.expect(desk.safeY).toBe(0)
			local phone = laidOut(390, 844, { top = 47, bottom = 0, left = 0, right = 0 })
			t.expect(phone.textSize).toBe(18)
			t.expect(phone.safeY).toBe(47)
			t.expect(phone.textSize >= Hud.MIN_TEXT).toBe(true)
			local land = laidOut(844, 390, { top = 0, bottom = 0, left = 47, right = 0 })
			t.expect(land.barWidth).toBe(199)
			t.expect(Hud.layout(844, 390).barWidth).toBe(211)
		end
	)

	it(
		"a left-half swipe is one existing intent, a diagonal is not, and a right-half drag clamps pitch",
		function()
			local state = Touch.empty()
			local effects
			state, effects = Touch.track(
				state,
				{ id = 1, phase = "begin", x = 40, y = 200 },
				{ width = 390, snap = nil }
			)
			t.expect(effects).toEqual({})
			local _, ended = Touch.track(
				state,
				{ id = 1, phase = "end", x = 40 - 80, y = 200 },
				{ width = 390, snap = nil }
			)
			t.expect(ended[1].kind).toBe("turn")
			t.expect(ended[1].intent).toBe("Left")
			t.expect(Movement.isIntent(ended[1].intent)).toBe(true)
			local diagonal = Touch.swipe(70, 70)
			t.expect(diagonal).toBe(nil)

			local look = Touch.empty()
			look, _ = Touch.track(
				look,
				{ id = 2, phase = "begin", x = 300, y = 200 },
				{ width = 390, snap = nil }
			)
			local _, moved = Touch.track(
				look,
				{ id = 2, phase = "move", x = 300, y = 10200 },
				{ width = 390, snap = nil }
			)
			t.expect(moved[1].kind).toBe("look")
			t.expect(moved[1].dy).toBe(10000)
			t.expect(View.look({ yaw = 0, pitch = 0 }, moved[1].dx, moved[1].dy).pitch).toBe(-View.MAX_PITCH)
		end
	)

	it("the phone's snap button is a 44 px snap zone and not a turn", function()
		local row = laidOut(390, 844, { top = 47, bottom = 0, left = 0, right = 0 })
		local button = Touch.snapRect({
			textSize = row.textSize,
			margin = row.margin,
			iconSize = row.iconSize,
			barWidth = row.barWidth,
			barHeight = row.barHeight,
			safeX = row.safeX,
			safeY = row.safeY,
			safeW = row.safeW,
			safeH = row.safeH,
		})
		t.expect(button.w >= 44 and button.h >= 44).toBe(true)
		t.expect(Touch.zone(390, button.x + 1, button.y + 1, button)).toBe("snap")
		local state = Touch.empty()
		local began
		state, began = Touch.track(
			state,
			{ id = 3, phase = "begin", x = button.x + 1, y = button.y + 1 },
			{ width = 390, snap = button }
		)
		local _, finished = Touch.track(
			state,
			{ id = 3, phase = "end", x = 10, y = button.y },
			{ width = 390, snap = button }
		)
		t.expect(began).toEqual({ { kind = "snap" } })
		t.expect(finished).toEqual({})
	end)
end)
