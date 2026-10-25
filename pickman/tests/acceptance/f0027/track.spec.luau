--!strict
-- f0027 AC2: a touch is a pure fold. The zone is chosen at begin and locked.
-- A second finger in a zone that is already down is ignored. A look finger never turns.
local Touch = require("@logic/Touch")
local t = require("@tests/lib/t")

type Event = { id: number, phase: Touch.Phase, x: number, y: number }
type Rect = { x: number, y: number, w: number, h: number }

local function run(events: { Event }, width: number, snap: Rect?): ({ [number]: any }, { any })
	local state = Touch.empty()
	local out = {}
	for _, event in events do
		local effects
		state, effects = Touch.track(state, event, { width = width, snap = snap })
		for _, effect in effects do
			table.insert(out, effect)
		end
	end
	return state.fingers, out
end

return t.spec("f0027 touch fold", function(it)
	it("splits the viewport at x < width/2, and a bad width has no turn half", function()
		t.expect(Touch.zone(800, 399, 10, nil)).toBe("turn")
		t.expect(Touch.zone(800, 400, 10, nil)).toBe("look")
		t.expect(Touch.zone(390, 194, 0, nil)).toBe("turn")
		t.expect(Touch.zone(390, 195, 0, nil)).toBe("look")
		t.expect(Touch.zone(0, -10, 0, nil)).toBe("look")
		t.expect(Touch.zone(0 / 0, 0, 0, nil)).toBe("look")
		t.expect(Touch.zone(-20, 0, 0, nil)).toBe("look")
		t.expect(Touch.zone(math.huge, 0, 0, nil)).toBe("look")
	end)

	it("a snap rectangle wins, including on the left half, and its far edges are outside", function()
		local rect: Rect = { x = 10, y = 20, w = 44, h = 44 }
		t.expect(Touch.zone(800, 10, 20, rect)).toBe("snap")
		t.expect(Touch.zone(800, 53, 63, rect)).toBe("snap")
		t.expect(Touch.zone(800, 54, 30, rect)).toBe("turn")
		t.expect(Touch.zone(800, 30, 64, rect)).toBe("turn")
		t.expect(Touch.zone(200, 120, 40, { x = 100, y = 20, w = 44, h = 44 })).toBe("snap")
		t.expect(Touch.zone(200, 120, 40, nil)).toBe("look")
	end)

	it("locks the zone at begin, so a later width or a later x cannot reclassify the finger", function()
		local state = Touch.empty()
		local effects
		state, effects = Touch.track(
			state,
			{ id = 1, phase = "begin", x = 9, y = 40 },
			{ width = 20, snap = nil }
		)
		t.expect(#effects).toBe(0)
		t.expect(state.fingers[1].zone).toBe("turn")
		local _, ended = Touch.track(
			state,
			{ id = 1, phase = "end", x = 100, y = 40 },
			{ width = 10, snap = nil }
		)
		t.expect(ended).toEqual({ { kind = "turn", intent = "Right" } })
	end)

	it("does not mutate the state it was given", function()
		local original = Touch.empty()
		Touch.track(original, { id = 7, phase = "begin", x = 1, y = 2 }, { width = 100, snap = nil })
		t.expect(original.fingers[7]).toBe(nil)
	end)

	it("a move and an end leave the input finger unchanged and return a new table", function()
		local state = Touch.empty()
		state = Touch.track(state, { id = 1, phase = "begin", x = 500, y = 200 }, { width = 800, snap = nil })
		local finger = state.fingers[1]
		local moved, moveEffects = Touch.track(
			state,
			{ id = 1, phase = "move", x = 540, y = 210 },
			{ width = 800, snap = nil }
		)
		t.expect(moveEffects).toEqual({ { kind = "look", dx = 40, dy = 10 } })
		t.expect(finger.x).toBe(500)
		t.expect(finger.y).toBe(200)
		t.expect(finger.zone).toBe("look")
		t.expect(moved ~= state).toBe(true)
		local ended, endEffects = Touch.track(
			state,
			{ id = 1, phase = "end", x = 100, y = 200 },
			{ width = 800, snap = nil }
		)
		t.expect(endEffects).toEqual({})
		t.expect(finger.x).toBe(500)
		t.expect(finger.y).toBe(200)
		t.expect(finger.zone).toBe("look")
		t.expect(ended ~= state).toBe(true)
	end)

	it("two tracks of one begin state return the same look delta", function()
		local state = Touch.empty()
		state = Touch.track(state, { id = 1, phase = "begin", x = 500, y = 200 }, { width = 800, snap = nil })
		local _, first = Touch.track(
			state,
			{ id = 1, phase = "move", x = 530, y = 190 },
			{ width = 800, snap = nil }
		)
		local _, second = Touch.track(
			state,
			{ id = 1, phase = "move", x = 530, y = 190 },
			{ width = 800, snap = nil }
		)
		t.expect(first).toEqual({ { kind = "look", dx = 30, dy = -10 } })
		t.expect(second).toEqual(first)
	end)

	it(
		"emits one intent on finger-up from the straight line, not from the path and not from a move",
		function()
			local _, wandered = run({
				{ id = 1, phase = "begin", x = 40, y = 100 },
				{ id = 1, phase = "move", x = 400, y = 100 },
				{ id = 1, phase = "move", x = 400, y = 400 },
				{ id = 1, phase = "end", x = 50, y = 110 },
			}, 800, nil)
			t.expect(wandered).toEqual({})

			local _, slow = run({
				{ id = 1, phase = "begin", x = 100, y = 80 },
				{ id = 1, phase = "move", x = 80, y = 80 },
				{ id = 1, phase = "move", x = 60, y = 80 },
				{ id = 1, phase = "move", x = 40, y = 80 },
				{ id = 1, phase = "end", x = 20, y = 80 },
			}, 800, nil)
			local _, fast = run({
				{ id = 1, phase = "begin", x = 100, y = 80 },
				{ id = 1, phase = "end", x = 20, y = 80 },
			}, 800, nil)
			t.expect(slow).toEqual(fast)
			t.expect(fast).toEqual({ { kind = "turn", intent = "Left" } })
		end
	)

	it("ignores a second finger in a zone that is already down, and a look finger never turns", function()
		local _, turns = run({
			{ id = 1, phase = "begin", x = 20, y = 100 },
			{ id = 2, phase = "begin", x = 30, y = 100 },
			{ id = 2, phase = "end", x = 30, y = 400 },
			{ id = 1, phase = "end", x = 20, y = 10 },
		}, 800, nil)
		t.expect(turns).toEqual({ { kind = "turn", intent = "Forward" } })

		local fingers, looked = run({
			{ id = 1, phase = "begin", x = 500, y = 10 },
			{ id = 2, phase = "begin", x = 600, y = 10 },
			{ id = 2, phase = "move", x = 700, y = 80 },
			{ id = 1, phase = "move", x = 530, y = 16 },
			{ id = 1, phase = "end", x = 100, y = 16 },
		}, 800, nil)
		t.expect(looked).toEqual({ { kind = "look", dx = 30, dy = 6 } })
		t.expect(fingers[1]).toBe(nil)
		t.expect(fingers[2]).toBe(nil)
	end)

	it("a turn and a look finger can be down together, and a turn move is not a look", function()
		local _, both = run({
			{ id = 1, phase = "begin", x = 20, y = 50 },
			{ id = 2, phase = "begin", x = 500, y = 50 },
			{ id = 1, phase = "move", x = 80, y = 50 },
			{ id = 2, phase = "move", x = 510, y = 40 },
			{ id = 1, phase = "end", x = 100, y = 50 },
			{ id = 2, phase = "end", x = 200, y = 40 },
		}, 800, nil)
		local expected: { any } = {
			{ kind = "look", dx = 10, dy = -10 },
			{ kind = "turn", intent = "Right" },
		}
		t.expect(both).toEqual(expected)
	end)

	it(
		"ignores a repeated begin, an unknown phase, and a move or end for a finger that never began",
		function()
			local snap: Rect = { x = 300, y = 700, w = 44, h = 44 }
			local state = Touch.empty()
			local first
			state, first = Touch.track(
				state,
				{ id = 1, phase = "begin", x = 310, y = 710 },
				{ width = 800, snap = snap }
			)
			local _, second = Touch.track(
				state,
				{ id = 1, phase = "begin", x = 310, y = 710 },
				{ width = 800, snap = snap }
			)
			t.expect(first).toEqual({ { kind = "snap" } })
			t.expect(second).toEqual({})
			local _, ignored = run({
				{ id = 4, phase = "move", x = 10, y = 10 },
				{ id = 4, phase = "end", x = 200, y = 10 },
				{ id = 5, phase = "cancel" :: any, x = 10, y = 10 },
			}, 800, nil)
			t.expect(ignored).toEqual({})
		end
	)
end)
