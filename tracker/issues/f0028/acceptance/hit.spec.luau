--!strict
-- f0028 AC2: the snap control is a hit test. It is not a turn and not a look drag.
local Touch = require("@logic/Touch")
local t = require("@tests/lib/t")

local SNAP = { x = 300, y = 700, w = 44, h = 44 }

return t.spec("f0028 snap hit test", function(it)
	it("a finger that begins inside the button is snap, even on the right half, and only on begin", function()
		t.expect(Touch.zone(390, 320, 720, SNAP)).toBe("snap")
		t.expect(Touch.zone(390, 320, 720, nil)).toBe("look")
		local state = Touch.empty()
		local began
		state, began = Touch.track(
			state,
			{ id = 1, phase = "begin", x = 320, y = 720 },
			{ width = 390, snap = SNAP }
		)
		local _, moved = Touch.track(
			state,
			{ id = 1, phase = "move", x = 20, y = 720 },
			{ width = 390, snap = SNAP }
		)
		local _, ended = Touch.track(
			state,
			{ id = 1, phase = "end", x = 20, y = 400 },
			{ width = 390, snap = SNAP }
		)
		t.expect(began).toEqual({ { kind = "snap" } })
		t.expect(moved).toEqual({})
		t.expect(ended).toEqual({})
	end)

	it("the button's minimum corner is inside and the far edges follow the half", function()
		t.expect(Touch.zone(800, 300, 700, SNAP)).toBe("snap")
		t.expect(Touch.zone(800, 343, 743, SNAP)).toBe("snap")
		t.expect(Touch.zone(800, 344, 720, SNAP)).toBe("turn")
		t.expect(Touch.zone(800, 320, 744, SNAP)).toBe("turn")
		t.expect(Touch.zone(390, 300, 700, SNAP)).toBe("snap")
		t.expect(Touch.zone(390, 344, 720, SNAP)).toBe("look")
		t.expect(Touch.zone(390, 320, 744, SNAP)).toBe("look")
	end)

	it("a look finger that slides onto the button stays a look, and releasing it does not turn", function()
		local state = Touch.empty()
		local began
		state, began = Touch.track(
			state,
			{ id = 1, phase = "begin", x = 500, y = 100 },
			{ width = 800, snap = SNAP }
		)
		t.expect(began).toEqual({})
		t.expect(state.fingers[1].zone).toBe("look")
		local _, moved = Touch.track(
			state,
			{ id = 1, phase = "move", x = 320, y = 720 },
			{ width = 800, snap = SNAP }
		)
		local _, ended = Touch.track(
			state,
			{ id = 1, phase = "end", x = 10, y = 720 },
			{ width = 800, snap = nil }
		)
		t.expect(moved).toEqual({ { kind = "look", dx = 320 - 500, dy = 720 - 100 } })
		t.expect(ended).toEqual({})
	end)

	it("a second snap begin adds nothing to the returned state", function()
		local state = Touch.empty()
		state = Touch.track(
			state,
			{ id = 1, phase = "begin", x = 310, y = 710 },
			{ width = 800, snap = SNAP }
		)
		local returned, again = Touch.track(
			state,
			{ id = 2, phase = "begin", x = 312, y = 712 },
			{ width = 800, snap = SNAP }
		)
		t.expect(again).toEqual({})
		t.expect(returned.fingers[1].zone).toBe("snap")
		t.expect(returned.fingers[1].x).toBe(310)
		t.expect(returned.fingers[2]).toBe(nil)
		local afterTwo, endedTwo = Touch.track(
			returned,
			{ id = 2, phase = "end", x = 10, y = 712 },
			{ width = 800, snap = SNAP }
		)
		t.expect(endedTwo).toEqual({})
		t.expect(afterTwo.fingers[1].zone).toBe("snap")
		t.expect(afterTwo.fingers[1].x).toBe(310)
		t.expect(afterTwo.fingers[2]).toBe(nil)
		local left, endedOne = Touch.track(
			afterTwo,
			{ id = 1, phase = "end", x = 10, y = 710 },
			{ width = 800, snap = SNAP }
		)
		t.expect(endedOne).toEqual({})
		t.expect(left.fingers[1]).toBe(nil)
		t.expect(left.fingers[2]).toBe(nil)
	end)
end)
