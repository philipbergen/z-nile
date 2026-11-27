--!strict
-- Narrowed by c0182: dropped the old Touch.zone, hop-button and half-split cases (replaced by d0149's circles in
-- d0149/acceptance/fold.spec). Keeps FIRE acting once on press and state immutability.
-- f0110 AC2: the fire and hop buttons in Touch's fold. A finger that goes down on the fire button is a fire finger
-- and emits one fire effect at once; on the hop button, one hop effect. Neither ever looks or turns, whatever it
-- does after. One finger per zone, as for every zone (f0027): a second finger on a held button is ignored, and a
-- new tap after the first finger lifts emits again. The snap control wins over the fire button, which wins over
-- the hop button, which win over both halves. Without the new rectangles the fold is f0027's.
local Touch = require("@logic/Touch")
local t = require("@tests/lib/t")

type Event = { id: number, phase: Touch.Phase, x: number, y: number }
type Rect = { x: number, y: number, w: number, h: number }

local FIRE: Rect = { x = 600, y = 300, w = 70, h = 70 }
local HOP: Rect = { x = 700, y = 320, w = 70, h = 70 }
local SNAP: Rect = { x = 500, y = 350, w = 44, h = 44 }

-- Runs the events through the fold on an 800 px wide screen with the given rectangles (all three by default).
local function run(events: { Event }, ctx: any?): ({ [number]: any }, { any })
	local c = ctx or { width = 800, snap = SNAP, fire = FIRE, hop = HOP }
	local state = Touch.empty()
	local out = {}
	for _, event in events do
		local effects
		state, effects = Touch.track(state, event, c)
		for _, effect in effects do
			table.insert(out, effect)
		end
	end
	return state.fingers, out
end

local function ev(id: number, phase: Touch.Phase, x: number, y: number): Event
	return { id = id, phase = phase, x = x, y = y }
end

return t.spec("f0110 touch fold", function(it)
	it("a finger down on the fire button fires once at once, and its moves and lift do nothing", function()
		local fingers, out = run({ ev(1, "begin", 610, 310) })
		t.expect(out).toEqual({ { kind = "fire" } })
		t.expect(fingers[1].zone).toBe("fire")
		local _, all = run({
			ev(1, "begin", 610, 310),
			ev(1, "move", 300, 310),
			ev(1, "move", 100, 900),
			ev(1, "end", 100, 310),
		})
		t.expect(all).toEqual({ { kind = "fire" } })
	end)

	it("the given state is never changed", function()
		local before = Touch.empty()
		local after = Touch.track(before, ev(1, "begin", 610, 310), { width = 800, fire = FIRE })
		t.expect((next(before.fingers))).toBe(nil)
		t.expect(after.fingers[1] ~= nil).toBe(true)
	end)
end)
