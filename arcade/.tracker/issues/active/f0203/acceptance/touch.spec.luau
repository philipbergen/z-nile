--!strict
-- f0203 AC3: arcade's touch fold (named buttons, the two halves' swipes and look, one finger a zone).
local Touch = require("@logic/Touch")
local t = require("@tests/lib/t")

local FIRE: Touch.Button = { name = "fire", rect = { x = 700, y = 500, w = 60, h = 60 } }
local HOP: Touch.Button = { name = "hop", rect = { x = 620, y = 500, w = 60, h = 60 } }
local CTX: Touch.Context = { width = 800, buttons = { FIRE, HOP }, left = "swipe", right = "look" }

-- folds the events in order and returns the state and every effect, in order
local function run(
	events: { Touch.Event },
	ctx: Touch.Context?,
	from: Touch.State?
): (Touch.State, { Touch.Effect })
	local s = from or Touch.empty()
	local all: { Touch.Effect } = {}
	for _, e in events do
		local fx
		s, fx = Touch.track(s, e, ctx or CTX)
		for _, f in fx do
			table.insert(all, f)
		end
	end
	return s, all
end

local function count(s: Touch.State): number
	local n = 0
	for _ in s.fingers do
		n += 1
	end
	return n
end

local function ev(id: number, phase: Touch.Phase, x: number, y: number): Touch.Event
	return { id = id, phase = phase, x = x, y = y }
end

local function swipe(dx: number, dy: number): { Touch.Effect }
	local _, fx = run({
		ev(1, "begin", 200, 300),
		ev(1, "move", 200 + dx / 2, 300 + dy / 2),
		ev(1, "end", 200 + dx, 300 + dy),
	})
	return fx
end

return t.spec("f0203 Touch", function(it)
	it("its sizes are pickman's: a 48 px swipe, a 30 degree cone, a 44 px target", function()
		t.expect(Touch.MIN_SWIPE).toBe(48)
		t.expect(Touch.AXIS_DEGREES).toBe(30)
		t.expect(Touch.MIN_TARGET).toBe(44)
	end)

	it("a finger on a button presses it when it goes down and releases it when it comes up", function()
		local s, fx = run({ ev(4, "begin", 710, 510) })
		t.expect(fx).toEqual({ { kind = "press", name = "fire" } })
		s, fx = run({ ev(4, "move", 650, 400), ev(4, "move", 100, 100) }, CTX, s)
		t.expect(fx).toEqual({})
		s, fx = run({ ev(4, "end", 100, 100) }, CTX, s)
		t.expect(fx).toEqual({ { kind = "release", name = "fire" } })
		t.expect(count(s)).toBe(0)
	end)

	it("buttons are half-open rectangles, checked in the context's order", function()
		t.expect(Touch.inside(FIRE.rect, 700, 500)).toBe(true)
		t.expect(Touch.inside(FIRE.rect, 759, 559)).toBe(true)
		t.expect(Touch.inside(FIRE.rect, 760, 510)).toBe(false)
		t.expect(Touch.inside(FIRE.rect, 710, 560)).toBe(false)
		t.expect(Touch.inside(nil, 0, 0)).toBe(false)
		local over: Touch.Context = {
			width = 800,
			buttons = {
				{ name = "a", rect = { x = 0, y = 0, w = 100, h = 100 } },
				{ name = "b", rect = { x = 50, y = 50, w = 100, h = 100 } },
			},
			left = "swipe",
			right = "look",
		}
		local _, fx = run({ ev(1, "begin", 60, 60) }, over)
		t.expect(fx).toEqual({ { kind = "press", name = "a" } })
		_, fx = run({ ev(1, "begin", 120, 120) }, over)
		t.expect(fx).toEqual({ { kind = "press", name = "b" } })
	end)

	it("a swipe on the swipe half sends its direction once, on release; screen-down is down", function()
		t.expect(swipe(60, 0)).toEqual({ { kind = "swipe", dir = "right" } })
		t.expect(swipe(-60, 0)).toEqual({ { kind = "swipe", dir = "left" } })
		t.expect(swipe(0, 60)).toEqual({ { kind = "swipe", dir = "down" } })
		t.expect(swipe(0, -60)).toEqual({ { kind = "swipe", dir = "up" } })
	end)

	it("a swipe counts from finger-down to finger-up, whatever the path between", function()
		local _, fx = run({ ev(1, "begin", 200, 300), ev(1, "move", 400, 300), ev(1, "end", 200, 240) })
		t.expect(fx).toEqual({ { kind = "swipe", dir = "up" } })
	end)

	it("a swipe shorter than MIN_SWIPE or outside the cone round an axis sends nothing", function()
		t.expect(swipe(47, 0)).toEqual({})
		t.expect(Touch.swipe(48, 0)).toBe("right")
		t.expect(Touch.swipe(60, 60)).toBe(nil)
		t.expect(Touch.swipe(100 * math.cos(math.rad(30)), 100 * math.sin(math.rad(30)))).toBe("right")
		t.expect(Touch.swipe(100 * math.cos(math.rad(31)), 100 * math.sin(math.rad(31)))).toBe(nil)
		t.expect(Touch.swipe(100 * math.cos(math.rad(60)), -100 * math.sin(math.rad(60)))).toBe("up")
		t.expect(Touch.swipe(0 / 0, 60)).toBe(nil)
		t.expect(Touch.swipe(math.huge, 0)).toBe(nil)
	end)

	it("a finger on the look half sends its pixel steps as it moves, and nothing when it lifts", function()
		local _, fx = run({
			ev(2, "begin", 500, 200),
			ev(2, "move", 510, 200),
			ev(2, "move", 515, 205),
			ev(2, "end", 515, 205),
		})
		t.expect(fx).toEqual({ { kind = "look", dx = 10, dy = 0 }, { kind = "look", dx = 5, dy = 5 } })
	end)

	it("each half's use comes from the context, and a half used for nothing takes no finger", function()
		local flipped: Touch.Context = { width = 800, buttons = {}, left = "look", right = "swipe" }
		local _, fx =
			run({ ev(1, "begin", 100, 100), ev(1, "move", 110, 90), ev(1, "end", 110, 90) }, flipped)
		t.expect(fx).toEqual({ { kind = "look", dx = 10, dy = -10 } })
		_, fx = run({ ev(1, "begin", 500, 100), ev(1, "end", 600, 100) }, flipped)
		t.expect(fx).toEqual({ { kind = "swipe", dir = "right" } })
		local off: Touch.Context = { width = 800, buttons = { FIRE }, left = "none", right = "none" }
		local s
		s, fx = run({ ev(1, "begin", 100, 100), ev(1, "move", 300, 100), ev(1, "end", 300, 100) }, off)
		t.expect(fx).toEqual({})
		t.expect(count(s)).toBe(0)
		s, fx = run({ ev(1, "begin", 100, 100), ev(2, "begin", 710, 510) }, off)
		t.expect(fx).toEqual({ { kind = "press", name = "fire" } })
		t.expect(count(s)).toBe(1) -- the finger on the half used for nothing is not held
		t.expect(s.fingers[1]).toBe(nil)
	end)

	it(
		"the halves split at width / 2, and a width that is not a positive number makes every point the right half",
		function()
			local _, side, use = Touch.zone(CTX, 399, 10)
			t.expect(side).toBe("left")
			t.expect(use).toBe("swipe")
			_, side, use = Touch.zone(CTX, 400, 10)
			t.expect(side).toBe("right")
			t.expect(use).toBe("look")
			local name = Touch.zone(CTX, 710, 510)
			t.expect(name).toBe("fire")
			for _, w in { 0, -5, 0 / 0, math.huge } do
				local _, s2 = Touch.zone({ width = w, buttons = {}, left = "swipe", right = "look" }, 1, 1)
				t.expect(s2).toBe("right")
			end
		end
	)

	it(
		"one finger holds a zone: a second finger on the same button or half is ignored, down and up",
		function()
			local s, fx = run({ ev(1, "begin", 710, 510), ev(2, "begin", 720, 520) })
			t.expect(fx).toEqual({ { kind = "press", name = "fire" } })
			s, fx = run({ ev(2, "end", 720, 520) }, CTX, s)
			t.expect(fx).toEqual({})
			s, fx = run({ ev(1, "end", 710, 510) }, CTX, s)
			t.expect(fx).toEqual({ { kind = "release", name = "fire" } })
			s, fx = run({
				ev(1, "begin", 500, 100),
				ev(2, "begin", 600, 100),
				ev(2, "move", 650, 100),
				ev(1, "move", 505, 100),
			})
			t.expect(fx).toEqual({ { kind = "look", dx = 5, dy = 0 } })
		end
	)

	it("fingers on different zones work at once", function()
		local _, fx = run({
			ev(1, "begin", 200, 300),
			ev(2, "begin", 710, 510),
			ev(3, "begin", 630, 510),
			ev(4, "begin", 500, 100),
			ev(4, "move", 503, 104),
			ev(2, "end", 710, 510),
			ev(1, "end", 140, 300),
			ev(3, "end", 630, 510),
		})
		local want: { any } = {
			{ kind = "press", name = "fire" },
			{ kind = "press", name = "hop" },
			{ kind = "look", dx = 3, dy = 4 },
			{ kind = "release", name = "fire" },
			{ kind = "swipe", dir = "left" },
			{ kind = "release", name = "hop" },
		}
		t.expect(fx).toEqual(want)
	end)

	it("a begin for a finger already down, and a move or end for one never seen, change nothing", function()
		local s, fx = run({ ev(1, "begin", 710, 510), ev(1, "begin", 500, 100) })
		t.expect(fx).toEqual({ { kind = "press", name = "fire" } })
		t.expect(s.fingers[1].button).toBe("fire")
		s, fx = run({ ev(9, "move", 10, 10), ev(9, "end", 10, 10) }, CTX, s)
		t.expect(fx).toEqual({})
		t.expect(s.fingers[1].button).toBe("fire")
	end)

	it("the given state is never changed", function()
		local s0 = Touch.empty()
		local s1 = Touch.track(s0, ev(1, "begin", 710, 510), CTX)
		t.expect(count(s0)).toBe(0)
		local s2 = Touch.track(s1, ev(1, "move", 720, 520), CTX)
		t.expect(s1.fingers[1].x).toBe(710)
		Touch.track(s2, ev(1, "end", 720, 520), CTX)
		t.expect(s2.fingers[1] ~= nil).toBe(true)
	end)

	it(
		"a begin or move at a point that is not a number is dropped; an end always lifts its finger",
		function()
			local s, fx = run({ ev(1, "begin", 0 / 0, 10), ev(2, "begin", math.huge, 10) })
			t.expect(fx).toEqual({})
			t.expect(count(s)).toBe(0)
			s, fx = run({ ev(3, "begin", 500, 100), ev(3, "move", 0 / 0, 100), ev(3, "move", 501, 100) })
			t.expect(fx).toEqual({ { kind = "look", dx = 1, dy = 0 } })
			s, fx = run({ ev(4, "begin", 710, 510), ev(4, "end", 0 / 0, 0 / 0) })
			t.expect(fx).toEqual({ { kind = "press", name = "fire" }, { kind = "release", name = "fire" } })
			t.expect(count(s)).toBe(0)
			s, fx = run({ ev(5, "begin", 200, 300), ev(5, "end", 0 / 0, 300) })
			t.expect(fx).toEqual({})
			t.expect(count(s)).toBe(0)
		end
	)

	it(
		"a finger keeps the zone it went down in, so its lift releases even after the buttons change",
		function()
			local s = run({ ev(1, "begin", 710, 510) })
			local _, fx = run(
				{ ev(1, "end", 710, 510) },
				{ width = 800, buttons = {}, left = "swipe", right = "look" },
				s
			)
			t.expect(fx).toEqual({ { kind = "release", name = "fire" } })
		end
	)

	it("reset lifts every finger: a release for each held button in finger order, and no swipe", function()
		local s = run({
			ev(7, "begin", 630, 510),
			ev(3, "begin", 710, 510),
			ev(5, "begin", 200, 300),
			ev(5, "move", 400, 300),
		})
		local after, fx = Touch.reset(s)
		t.expect(fx).toEqual({ { kind = "release", name = "fire" }, { kind = "release", name = "hop" } })
		t.expect(count(after)).toBe(0)
		t.expect(s.fingers[3] ~= nil).toBe(true)
	end)

	it(
		"toScreen moves an input position by the inset's origin, and screenSize falls back while the area is bad",
		function()
			local area = { Min = { X = 0, Y = 36 }, Max = { X = 800, Y = 636 } }
			local x, y = Touch.toScreen(area, 10, 50)
			t.expect(x).toBe(10)
			t.expect(y).toBe(14)
			x, y = Touch.toScreen(nil, 10, 50)
			t.expect(x).toBe(10)
			t.expect(y).toBe(50)
			x, y = Touch.toScreen({ Min = { X = 3, Y = 0 / 0 }, Max = { X = 1, Y = 1 } }, 10, 50)
			t.expect(x).toBe(7)
			t.expect(y).toBe(50)
			local w, h = Touch.screenSize(area, 1, 1)
			t.expect(w).toBe(800)
			t.expect(h).toBe(600)
			w, h = Touch.screenSize({ Min = { X = 0, Y = 0 }, Max = { X = 0, Y = 0 } }, 320, 240)
			t.expect(w).toBe(320)
			t.expect(h).toBe(240)
			w = Touch.screenSize(nil, 320, 240)
			t.expect(w).toBe(320)
		end
	)
end)
