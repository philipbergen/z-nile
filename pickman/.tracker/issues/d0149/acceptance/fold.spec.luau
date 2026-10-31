--!strict
-- d0149 AC1: the touch controls' pure fold (Touch.track, Touch.zone, Touch.pull, Touch.quarters, Touch.knobs) and
-- where Touch.buttons puts the controls. The circles and buttons are hand-made here, so the fold's rules are pinned
-- apart from the layout.
local Pad = require("@logic/Pad")
local Touch: any = require("@logic/Touch")
local t = require("@tests/lib/t")

local STEER = { x = 100, y = 300, r = 50 }
local LOOK = { x = 500, y = 300, r = 50 }
local FIRE = { x = 400, y = 330, w = 44, h = 44 }
local PICK = { x = 340, y = 330, w = 44, h = 44 }
local CTX = { steer = STEER, look = LOOK, fire = FIRE, pick = PICK }

local function run(events: { any }, ctx: any?): ({ any }, any)
	local state = Touch.empty()
	local all: { any } = {}
	for _, e in events do
		local effects
		state, effects = Touch.track(state, e, ctx or CTX)
		for _, eff in effects do
			table.insert(all, eff)
		end
	end
	return all, state
end

local function kinds(effects: { any }, kind: string): { any }
	local out = {}
	for _, e in effects do
		if e.kind == kind then
			table.insert(out, e)
		end
	end
	return out
end

local function ev(id: number, phase: string, x: number, y: number, tm: number?): any
	return { id = id, phase = phase, x = x, y = y, t = tm }
end

return t.spec("d0149 the touch circles' fold", function(it)
	it("the constants are the user's and prep's numbers", function()
		t.expect(Touch.CIRCLE_SHARE).toBe(0.3)
		t.expect(Touch.CIRCLE_MIN).toBe(96)
		t.expect(Touch.CIRCLE_MAX).toBe(160)
		t.expect(Touch.TAP_SECONDS).toBe(0.25)
		t.expect(Touch.TAP_SLOP).toBe(12)
		t.expect(Touch.MIN_TARGET).toBe(44)
		t.expect(Touch.LOOK_DEAD).toBe(0.25)
	end)

	it("zones: FIRE, then PICK, then the steer and look circles; anywhere else is no zone", function()
		t.expect(Touch.zone(400, 330, CTX)).toBe("fire")
		t.expect(Touch.zone(443.9, 373.9, CTX)).toBe("fire")
		t.expect(Touch.zone(444, 340, CTX)).toBe(nil) -- FIRE's far edge is outside, and no circle is there
		t.expect(Touch.zone(340, 330, CTX)).toBe("pick")
		t.expect(Touch.zone(100, 300, CTX)).toBe("steer")
		t.expect(Touch.zone(149, 300, CTX)).toBe("steer")
		t.expect(Touch.zone(150, 300, CTX)).toBe(nil) -- a circle's rim is outside
		t.expect(Touch.zone(135, 335, CTX)).toBe("steer") -- inside the disc
		t.expect(Touch.zone(140, 340, CTX)).toBe(nil) -- inside the bounding square, outside the disc
		t.expect(Touch.zone(500, 300, CTX)).toBe("look")
		t.expect(Touch.zone(300, 100, CTX)).toBe(nil) -- the old turn half: nothing
		t.expect(Touch.zone(600, 100, CTX)).toBe(nil) -- the old look half: nothing
		-- a button wins where it overlaps a circle
		local over = { steer = STEER, look = LOOK, fire = { x = 480, y = 280, w = 44, h = 44 } }
		t.expect(Touch.zone(490, 290, over)).toBe("fire")
		t.expect(Touch.zone(0 / 0, 300, CTX)).toBe(nil)
	end)

	it("a finger that lands on no control does nothing for its whole life", function()
		local effects, state = run({ ev(1, "begin", 300, 100), ev(1, "move", 100, 300), ev(1, "end", 100, 300) })
		t.expect(#effects).toBe(0)
		t.expect((next(state.fingers))).toBe(nil)
	end)

	it("a pull is a stick tilt: x right, y up, at most 1 long", function()
		local x, y = Touch.pull(STEER, 125, 300)
		t.expect(x).toBeNear(0.5, 1e-9)
		t.expect(y).toBeNear(0, 1e-9)
		x, y = Touch.pull(STEER, 100, 200) -- twice the radius up
		t.expect(x).toBeNear(0, 1e-9)
		t.expect(y).toBeNear(1, 1e-9)
		x, y = Touch.pull(STEER, 0 / 0, 300)
		t.expect(x).toBe(0)
		t.expect(y).toBe(0)
	end)

	it("the steer circle sends what Pad.steer emits for the pull: one turn a push, as the keys", function()
		-- up past STEER_ON: Forward once, however long it is held and moved within the sector
		local up = STEER.y - STEER.r * (Pad.STEER_ON + 0.1)
		local effects = run({
			ev(1, "begin", 100, 300),
			ev(1, "move", 100, up),
			ev(1, "move", 102, up - 5),
			ev(1, "move", 100, 250),
		})
		local turns = kinds(effects, "turn")
		t.expect(#turns).toBe(1)
		t.expect(turns[1].intent).toBe("Forward")
		-- left, down, right
		type Case = { x: number, y: number, intent: string }
		local cases: { Case } = {
			{ x = 60, y = 300, intent = "Left" },
			{ x = 100, y = 340, intent = "Back" },
			{ x = 140, y = 300, intent = "Right" },
		}
		for _, case in cases do
			local e = kinds(run({ ev(2, "begin", 100, 300), ev(2, "move", case.x, case.y) }), "turn")
			t.expect(#e).toBe(1)
			t.expect(e[1].intent).toBe(case.intent)
		end
	end)

	it("a pull short of STEER_ON sends nothing; back under STEER_OFF and out again is a second push", function()
		local short = STEER.y - STEER.r * (Pad.STEER_ON - 0.1)
		t.expect(#kinds(run({ ev(1, "begin", 100, 300), ev(1, "move", 100, short) }), "turn")).toBe(0)
		local far = STEER.y - STEER.r * 0.9
		local back = STEER.y - STEER.r * (Pad.STEER_OFF - 0.1)
		local effects = run({
			ev(1, "begin", 100, 300),
			ev(1, "move", 100, far),
			ev(1, "move", 100, back),
			ev(1, "move", 100, far),
		})
		local turns = kinds(effects, "turn")
		t.expect(#turns).toBe(2) -- two pulls up: what f0143's double-tap fold boosts on
		t.expect(turns[2].intent).toBe("Forward")
	end)

	it("a finger going down already pulled steers at once, and lifting a steer finger sends nothing", function()
		local effects = run({ ev(1, "begin", 60, 300), ev(1, "end", 60, 300) })
		local turns = kinds(effects, "turn")
		t.expect(#turns).toBe(1)
		t.expect(turns[1].intent).toBe("Left")
		t.expect(#effects).toBe(1)
	end)

	it("quarters: up 0, left 1, right -1, down 2, between in between; inside the dead zone none", function()
		t.expect(Touch.quarters(0, 1)).toBeNear(0, 1e-9)
		t.expect(Touch.quarters(-1, 0)).toBeNear(1, 1e-9)
		t.expect(Touch.quarters(1, 0)).toBeNear(-1, 1e-9)
		t.expect(Touch.quarters(0, -1)).toBeNear(2, 1e-9)
		t.expect(Touch.quarters(-0.5, 0.5)).toBeNear(0.5, 1e-9)
		t.expect(Touch.quarters(0.1, 0.1)).toBe(nil)
		t.expect(Touch.quarters(0, 0.249)).toBe(nil) -- inside LOOK_DEAD
		t.expect(Touch.quarters(0, 0.25)).toBeNear(0, 1e-9) -- on it: a direction
		t.expect(Touch.quarters(0 / 0, 1)).toBe(nil)
	end)

	it("the look circle points the view where it is pulled, and back to the heading when let go", function()
		local effects = run({
			ev(1, "begin", 500, 300, 0),
			ev(1, "move", 460, 300, 0.1), -- left
			ev(1, "move", 500, 340, 0.4), -- down: behind
			ev(1, "end", 500, 340, 0.5),
		})
		local points = kinds(effects, "point")
		t.expect(#points).toBe(3) -- going down pointed nothing: it might have been a tap
		t.expect(points[1].quarters).toBeNear(1, 1e-9)
		t.expect(points[2].quarters).toBeNear(2, 1e-9)
		t.expect(points[3].quarters).toBe(nil)
		t.expect(#kinds(effects, "hop")).toBe(0) -- a pull, not a tap
		t.expect(#kinds(effects, "turn")).toBe(0) -- the look circle never turns
	end)

	it("a tap off the look circle's centre only hops: the view never moves (review 001 F2)", function()
		for _, at in { { 530, 300 }, { 500, 330 }, { 470, 280 } } do
			local effects = run({ ev(1, "begin", at[1], at[2], 0), ev(1, "move", at[1] + 5, at[2], 0.05) })
			t.expect(#effects).toBe(0) -- down and a small move: undecided, nothing yet
			effects = run({
				ev(1, "begin", at[1], at[2], 0),
				ev(1, "move", at[1] + 5, at[2], 0.05),
				ev(1, "end", at[1] + 5, at[2], 0.1),
			})
			t.expect(#effects).toBe(1)
			t.expect(effects[1].kind).toBe("hop")
		end
	end)

	it(
		"a pull starts pointing on the move that takes it TAP_SLOP from where it went down, or once held TAP_SECONDS",
		function()
			local near = run({ ev(1, "begin", 530, 300, 0), ev(1, "move", 541, 300, 0.1) })
			t.expect(#kinds(near, "point")).toBe(0) -- 11 px, 0.1 s: still a tap
			local far = run({ ev(1, "begin", 530, 300, 0), ev(1, "move", 542, 300, 0.1) })
			t.expect(#kinds(far, "point")).toBe(1) -- 12 px: a pull
			local slow = run({ ev(1, "begin", 530, 300, 0), ev(1, "move", 531, 300, 0.25) })
			t.expect(#kinds(slow, "point")).toBe(1) -- held 0.25 s: a pull
			t.expect(kinds(slow, "point")[1].quarters).toBeNear(-1, 1e-9) -- where it rests: right
		end
	)

	it("a look finger held still starts pointing on the first tick TAP_SECONDS after it went down, once", function()
		local state = Touch.empty()
		local effects
		state = Touch.track(state, ev(1, "begin", 530, 300, 10), CTX)
		state, effects = Touch.tick(state, 10.2, CTX)
		t.expect(#effects).toBe(0)
		local before = state
		state, effects = Touch.tick(state, 10.25, CTX)
		t.expect(#effects).toBe(1)
		t.expect(effects[1].kind).toBe("point")
		t.expect(effects[1].quarters).toBeNear(-1, 1e-9)
		t.expect(before.fingers[1].looking).toBe(false) -- the given state is never changed
		state, effects = Touch.tick(state, 10.5, CTX)
		t.expect(#effects).toBe(0) -- once
		state, effects = Touch.track(state, ev(1, "end", 530, 300, 10.6), CTX)
		t.expect(#effects).toBe(1) -- let go: point nil, and no hop
		t.expect(effects[1].kind).toBe("point")
		t.expect(effects[1].quarters).toBe(nil)
	end)

	it("a tick points nothing for other controls, without a look circle, or at a bad time", function()
		local state = Touch.track(Touch.empty(), ev(1, "begin", 100, 300, 0), CTX)
		state = Touch.track(state, ev(2, "begin", 410, 340, 0), CTX)
		local _, effects = Touch.tick(state, 5, CTX)
		t.expect(#effects).toBe(0)
		local look = Touch.track(Touch.empty(), ev(1, "begin", 530, 300, 0), CTX)
		_, effects = Touch.tick(look, 5, { steer = STEER })
		t.expect(#effects).toBe(0)
		_, effects = Touch.tick(look, 0 / 0, CTX)
		t.expect(#effects).toBe(0)
	end)

	it("a short tap on the look circle hops when it lifts, once", function()
		local effects =
			run({ ev(1, "begin", 500, 300, 10), ev(1, "move", 505, 303, 10.1), ev(1, "end", 506, 304, 10.2) })
		local hops = kinds(effects, "hop")
		t.expect(#hops).toBe(1)
		t.expect(effects[#effects].kind).toBe("hop") -- on the lift, after the view is let go
		local early = run({ ev(1, "begin", 500, 300, 10) })
		t.expect(#kinds(early, "hop")).toBe(0) -- not when it goes down
	end)

	it("no hop for a finger held TAP_SECONDS or longer, or one that went TAP_SLOP from where it went down", function()
		t.expect(#kinds(run({ ev(1, "begin", 500, 300, 0), ev(1, "end", 500, 300, 0.25) }), "hop")).toBe(0)
		t.expect(#kinds(run({ ev(1, "begin", 500, 300, 0), ev(1, "end", 500, 300, 0.249) }), "hop")).toBe(1)
		t.expect(#kinds(run({ ev(1, "begin", 500, 300, 0), ev(1, "end", 512, 300, 0.1) }), "hop")).toBe(0)
		t.expect(#kinds(run({ ev(1, "begin", 500, 300, 0), ev(1, "end", 511, 300, 0.1) }), "hop")).toBe(1)
		-- went far and came back: still a pull
		local back = run({
			ev(1, "begin", 500, 300, 0),
			ev(1, "move", 520, 300, 0.05),
			ev(1, "end", 500, 300, 0.1),
		})
		t.expect(#kinds(back, "hop")).toBe(0)
	end)

	it("FIRE and PICK act once when the finger goes down; their moves and lift do nothing", function()
		local effects = run({ ev(1, "begin", 410, 340), ev(1, "move", 500, 300), ev(1, "end", 500, 300) })
		t.expect(#effects).toBe(1)
		t.expect(effects[1].kind).toBe("fire")
		effects = run({ ev(1, "begin", 350, 340), ev(1, "move", 100, 300), ev(1, "end", 100, 300) })
		t.expect(#effects).toBe(1)
		t.expect(effects[1].kind).toBe("pick")
	end)

	it("one finger a control: a second finger on a held control is ignored, other controls work together", function()
		local effects = run({
			ev(1, "begin", 100, 300),
			ev(2, "begin", 60, 300), -- a second finger on the steer circle
			ev(2, "move", 140, 300),
			ev(3, "begin", 500, 300, 0),
			ev(3, "move", 460, 300, 0.1),
			ev(4, "begin", 410, 340),
		})
		t.expect(#kinds(effects, "turn")).toBe(0)
		t.expect(kinds(effects, "point")[1].quarters).toBeNear(1, 1e-9)
		t.expect(#kinds(effects, "fire")).toBe(1)
	end)

	it("a finger keeps its control when it slides off it, and a control's absence makes its place nothing", function()
		local effects = run({ ev(1, "begin", 500, 300, 0), ev(1, "move", 100, 300, 0.1) }) -- onto the steer circle
		t.expect(#kinds(effects, "turn")).toBe(0)
		t.expect(kinds(effects, "point")[1].quarters).toBeNear(1, 1e-9) -- still the look circle, pulled hard left
		t.expect(#run({ ev(1, "begin", 410, 340) }, { steer = STEER, look = LOOK })).toBe(0)
	end)

	it("the given state is never changed", function()
		local s0 = Touch.empty()
		local s1 = Touch.track(s0, ev(1, "begin", 100, 300), CTX)
		t.expect((next(s0.fingers))).toBe(nil)
		local before = s1.fingers[1].x
		Touch.track(s1, ev(1, "move", 60, 300), CTX)
		t.expect(s1.fingers[1].x).toBe(before)
	end)

	it("knobs: each held circle's finger, held inside the circle; none when not held", function()
		local _, state = run({ ev(1, "begin", 100, 300), ev(1, "move", 100, 200), ev(2, "begin", 500, 300) })
		local k = Touch.knobs(state, CTX)
		t.expect(k.steer.x).toBeNear(100, 1e-9)
		t.expect(k.steer.y).toBeNear(250, 1e-9) -- on the rim, not at the finger
		t.expect(k.look.x).toBeNear(500, 1e-9)
		t.expect(k.look.y).toBeNear(300, 1e-9)
		t.expect((next(Touch.knobs(Touch.empty(), CTX)))).toBe(nil)
	end)

	it(
		"Touch.buttons: circles of 30% of the safe short side (96 to 160), FIRE and PICK left of the look circle",
		function()
			local function box(w: number, h: number, m: number, icon: number, barH: number): any
				return {
					margin = m,
					iconSize = icon,
					textSize = icon,
					barWidth = 100,
					barHeight = barH,
					safeX = 10,
					safeY = 20,
					safeW = w,
					safeH = h,
				}
			end
			local b = Touch.buttons(box(800, 400, 9, 18, 7))
			t.expect(b.look.r).toBe(60) -- 0.3 x 400
			t.expect(b.steer.r).toBe(60)
			t.expect(b.look.x + b.look.r).toBe(10 + 800 - 9) -- right edge one margin in
			t.expect(b.look.y + b.look.r).toBe(20 + 400 - 9 - 7) -- bottom on the power bar's top
			t.expect(b.steer.x - b.steer.r).toBe(10 + 9) -- left edge one margin in
			t.expect(b.steer.y + b.steer.r).toBe(20 + 400 - 2 * 9 - 18) -- bottom one margin above the lives row
			t.expect(b.fire.w).toBe(54) -- 0.45 x 120
			t.expect(b.fire.h).toBe(54)
			t.expect(b.fire.x + b.fire.w).toBe(b.look.x - b.look.r - 9)
			t.expect(b.fire.y + b.fire.h).toBe(b.steer.y + b.steer.r) -- the row's bottom
			t.expect(b.pick.x + b.pick.w).toBe(b.fire.x - 9)
			t.expect(b.pick.y).toBe(b.fire.y)
			t.expect(b.pick.w).toBe(b.fire.w)
			t.expect(Touch.buttons(box(1000, 300, 9, 18, 7)).look.r).toBe(48) -- 90 clamps up to 96
			t.expect(Touch.buttons(box(2000, 1000, 9, 18, 7)).look.r).toBe(80) -- 300 clamps down to 160
			t.expect(Touch.buttons(box(1000, 320, 7, 14, 6)).fire.w).toBe(44) -- 43 rounds up to MIN_TARGET
			t.expect(Touch.buttons(box(1000, 375, 9, 17, 7)).look.r).toBe(56.5) -- 112.5 rounds half up to 113
		end
	)
end)
