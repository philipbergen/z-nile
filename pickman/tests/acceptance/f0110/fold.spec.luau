--!strict
-- f0110 AC2: the fire and hop buttons in Touch's fold. A finger that goes down on the fire button is a fire finger
-- and emits one fire effect at once; on the hop button, one hop effect. Neither ever looks or turns, whatever it
-- does after. One finger per zone, as for every zone (f0027): a second finger on a held button is ignored, and a
-- new tap after the first finger lifts emits again. The snap control wins over the fire button, which wins over
-- the hop button, which win over both halves. Without the new rectangles the fold is f0027's.
local Touch = require("@logic/Touch")
local t = require("@tests/lib/t")

type Event = { id: number, phase: Touch.Phase, x: number, y: number }
type Rect = { x: number, y: number, w: number, h: number }

local Z = Touch.zone :: any -- the fire and hop arguments are added by this issue

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
	it("a point in the fire rectangle is the fire zone, its far edges outside, on either half", function()
		t.expect(Z(800, 600, 300, nil, FIRE, nil)).toBe("fire")
		t.expect(Z(800, 669, 369, nil, FIRE, nil)).toBe("fire")
		t.expect(Z(800, 670, 330, nil, FIRE, nil)).toBe("look")
		t.expect(Z(800, 630, 370, nil, FIRE, nil)).toBe("look")
		local left: Rect = { x = 10, y = 10, w = 50, h = 50 }
		t.expect(Z(800, 20, 20, nil, left, nil)).toBe("fire")
		t.expect(Z(800, 60, 20, nil, left, nil)).toBe("turn")
	end)

	it("a point in the hop rectangle is the hop zone, its far edges outside", function()
		t.expect(Z(800, 700, 320, nil, nil, HOP)).toBe("hop")
		t.expect(Z(800, 769, 389, nil, nil, HOP)).toBe("hop")
		t.expect(Z(800, 770, 330, nil, nil, HOP)).toBe("look")
		t.expect(Z(800, 720, 390, nil, nil, HOP)).toBe("look")
	end)

	it("snap wins over fire, fire over hop, where rectangles overlap", function()
		local all: Rect = { x = 100, y = 100, w = 50, h = 50 }
		t.expect(Z(800, 120, 120, all, all, all)).toBe("snap")
		t.expect(Z(800, 120, 120, nil, all, all)).toBe("fire")
		t.expect(Z(800, 120, 120, nil, nil, all)).toBe("hop")
	end)

	it("without the fire and hop rectangles those points are the halves, as before", function()
		t.expect(Z(800, 610, 310, SNAP, nil, nil)).toBe("look")
		t.expect(Touch.zone(800, 610, 310, SNAP)).toBe("look")
		local _, out = run(
			{ ev(1, "begin", 610, 310), ev(1, "move", 640, 320) },
			{ width = 800, snap = SNAP }
		)
		t.expect(out).toEqual({ { kind = "look", dx = 30, dy = 10 } })
	end)

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

	it("a finger down on the hop button hops once at once, and its moves and lift do nothing", function()
		local fingers, out = run({ ev(1, "begin", 710, 330) })
		t.expect(out).toEqual({ { kind = "hop" } })
		t.expect(fingers[1].zone).toBe("hop")
		local _, all = run({ ev(1, "begin", 710, 330), ev(1, "move", 760, 380), ev(1, "end", 200, 330) })
		t.expect(all).toEqual({ { kind = "hop" } })
	end)

	it("a second finger on a held button is ignored; a new tap after the lift fires again", function()
		local _, out = run({
			ev(1, "begin", 610, 310),
			ev(2, "begin", 650, 350), -- the fire zone is taken
			ev(2, "end", 650, 350),
			ev(1, "end", 610, 310),
			ev(3, "begin", 620, 320),
			ev(3, "end", 620, 320),
			ev(4, "begin", 710, 330),
			ev(5, "begin", 720, 340), -- the hop zone is taken
			ev(4, "end", 710, 330),
			ev(6, "begin", 710, 330),
		})
		t.expect(out).toEqual({ { kind = "fire" }, { kind = "fire" }, { kind = "hop" }, { kind = "hop" } })
	end)

	it("the buttons and the halves are separate zones: look, turn, fire and hop together", function()
		local _, out = run({
			ev(1, "begin", 450, 100), -- look
			ev(2, "begin", 100, 100), -- turn
			ev(3, "begin", 610, 310), -- fire, while the look finger is down
			ev(4, "begin", 710, 330), -- hop
			ev(1, "move", 470, 100),
			ev(2, "end", 20, 100),
		})
		t.expect(out).toEqual({
			{ kind = "fire" },
			{ kind = "hop" },
			{ kind = "look", dx = 20, dy = 0 },
			{ kind = "turn", intent = "Left" },
		})
	end)

	it("a button finger never takes the look zone: a look begun after it still looks", function()
		local _, out = run({ ev(1, "begin", 610, 310), ev(2, "begin", 450, 100), ev(2, "move", 450, 130) })
		t.expect(out).toEqual({ { kind = "fire" }, { kind = "look", dx = 0, dy = 30 } })
	end)

	it("the given state is never changed", function()
		local before = Touch.empty()
		local after = Touch.track(before, ev(1, "begin", 610, 310), { width = 800, fire = FIRE })
		t.expect(next(before.fingers)).toBe(nil)
		t.expect(after.fingers[1] ~= nil).toBe(true)
	end)
end)
