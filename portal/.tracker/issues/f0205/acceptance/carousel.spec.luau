--!strict
-- f0205 AC1: the carousel's rules (Logic/Carousel). One row of cards, the first in front; A, Left and the left
-- shoulder move it back, D, Right and the right shoulder forward, Enter, KeypadEnter and ButtonA play, and nothing else
-- does; the row wraps round at both ends. The wheel moves one card per roll (up back, down forward), only after it has
-- rested WHEEL_GAP; a swipe to the left brings the next card, to the right the previous one. The front card is centred
-- in the safe area and fits it on every screen shape; its two neighbours sit smaller and dimmed either side, clear of
-- it; every other card is hidden. The bindings sit below the test purchase screen's priority (f0201).
local Carousel = require("@logic/Carousel")
local t = require("@tests/lib/t")

-- the screens the layout must hold on, in the safe area's pixels: desktop, laptop, tablet, phone both ways, a small one
local SCREENS =
	{ { 1920, 1080 }, { 1280, 720 }, { 1024, 768 }, { 844, 390 }, { 390, 844 }, { 320, 480 }, { 2560, 1080 } }

local function moved(c: Carousel.Carousel, intents: { number }): number
	for _, by in intents do
		c = Carousel.step(c, by)
	end
	return c.index
end

local function overlap(a: Carousel.Box, b: Carousel.Box): boolean
	return a.x < b.x + b.width and b.x < a.x + a.width and a.y < b.y + b.height and b.y < a.y + a.height
end

return t.spec("f0205 carousel", function(it)
	it("a new row has the first card in front", function()
		local c = Carousel.new(4)
		t.expect(c.index).toBe(1)
		t.expect(c.count).toBe(4)
		t.expect(Carousel.new(1).index).toBe(1)
	end)

	it("a row needs a whole number of cards, at least one", function()
		for _, bad in { 0, -1, 2.5, 0 / 0, math.huge } :: { any } do
			t.expect(function()
				Carousel.new(bad)
			end).toThrow("count")
		end
	end)

	it("steps forward and back one card at a time", function()
		local c = Carousel.new(4)
		t.expect(moved(c, { 1 })).toBe(2)
		t.expect(moved(c, { 1, 1 })).toBe(3)
		t.expect(moved(c, { 1, 1, -1 })).toBe(2)
	end)

	it("wraps round at both ends", function()
		local c = Carousel.new(4)
		t.expect(moved(c, { -1 })).toBe(4)
		t.expect(moved(c, { 1, 1, 1, 1 })).toBe(1)
		t.expect(moved(c, { 1, 1, 1 })).toBe(4)
		t.expect(moved(c, { -1, -1, -1, -1, -1 })).toBe(4)
		t.expect(moved(Carousel.new(3), { 1, 1, 1 })).toBe(1)
		t.expect(moved(Carousel.new(1), { 1, -1, 1 })).toBe(1)
	end)

	it("a step by anything but a whole number leaves the row as it was", function()
		local c = Carousel.step(Carousel.new(4), 1)
		for _, bad in { 0.5, 0 / 0, math.huge } :: { any } do
			t.expect(Carousel.step(c, bad).index).toBe(2)
		end
	end)

	it("a step makes a new row and leaves the one it was given alone", function()
		local c = Carousel.new(4)
		local d = Carousel.step(c, 1)
		t.expect(c.index).toBe(1)
		t.expect(d.index).toBe(2)
		t.expect(d.count).toBe(4)
	end)

	it("A, Left and the left shoulder go back; D, Right and the right shoulder go forward", function()
		for _, k in { "A", "Left", "ButtonL1" } do
			t.expect(Carousel.key(k)).toBe("prev")
		end
		for _, k in { "D", "Right", "ButtonR1" } do
			t.expect(Carousel.key(k)).toBe("next")
		end
	end)

	it("Enter, KeypadEnter and the gamepad's A play", function()
		for _, k in { "Return", "KeypadEnter", "ButtonA" } do
			t.expect(Carousel.key(k)).toBe("play")
		end
	end)

	it("no other key does anything, and the key table holds exactly those nine", function()
		for _, k in
			{ "W", "S", "Space", "Up", "Down", "ButtonB", "ButtonX", "ButtonL2", "ButtonR2", "a", "d", "" }
		do
			t.expect(Carousel.key(k)).toBe(nil)
		end
		local names = {}
		for k, v in Carousel.KEYS do
			table.insert(names, `{k}={v}`)
		end
		table.sort(names)
		t.expect(table.concat(names, " ")).toBe(
			"A=prev ButtonA=play ButtonL1=prev ButtonR1=next D=next KeypadEnter=play Left=prev Return=play Right=next"
		)
		t.expect(table.isfrozen(Carousel.KEYS)).toBe(true)
	end)

	it(
		"its bindings sit below the test purchase screen's priority, 3000 (f0201), under one action name",
		function()
			t.expect(type(Carousel.PRIORITY)).toBe("number")
			t.expect(Carousel.PRIORITY < 3000).toBe(true)
			t.expect(Carousel.PRIORITY > 0).toBe(true)
			t.expect(Carousel.ACTION).toBe("PortalCarousel")
		end
	)

	it("the wheel rolled down goes forward, rolled up goes back", function()
		local c = Carousel.new(4)
		local _, down = Carousel.wheel(c, -1, 10)
		local _, up = Carousel.wheel(c, 1, 10)
		local _, big = Carousel.wheel(c, -3, 10)
		t.expect(down).toBe("next")
		t.expect(up).toBe("prev")
		t.expect(big).toBe("next")
	end)

	it("one roll moves one card: the wheel must rest WHEEL_GAP before it moves the row again", function()
		t.expect(Carousel.WHEEL_GAP).toBe(0.25)
		local c = Carousel.new(4)
		local i1, i2, i3, i4
		c, i1 = Carousel.wheel(c, -1, 10)
		c, i2 = Carousel.wheel(c, -1, 10.125)
		c, i3 = Carousel.wheel(c, -1, 10.25) -- 0.125 after the last event: still rolling, though WHEEL_GAP after the step
		c, i4 = Carousel.wheel(c, -1, 10.5) -- exactly WHEEL_GAP after the last event
		t.expect(i1).toBe("next")
		t.expect(i2).toBe(nil)
		t.expect(i3).toBe(nil)
		t.expect(i4).toBe("next")
		local _, i5 = Carousel.wheel(c, 1, 10.625)
		t.expect(i5).toBe(nil)
	end)

	it("a wheel event of no movement moves nothing, but still counts as rolling", function()
		local c = Carousel.new(4)
		local i1, i2
		c, i1 = Carousel.wheel(c, 0, 10)
		t.expect(i1).toBe(nil)
		c, i2 = Carousel.wheel(c, -1, 10.1)
		t.expect(i2).toBe(nil)
		local _, nan = Carousel.wheel(Carousel.new(4), 0 / 0, 10)
		t.expect(nan).toBe(nil)
	end)

	it("the wheel never moves the row itself, and keeps the index it was given", function()
		local c = Carousel.step(Carousel.new(4), 2)
		local after = Carousel.wheel(c, -1, 10)
		t.expect(after.index).toBe(3)
		t.expect(c.wheelAt).toBe(nil)
	end)

	it("a wheel event at a time that is not a finite number is dropped and changes nothing", function()
		local c = Carousel.wheel(Carousel.new(4), -1, 10)
		local after, intent = Carousel.wheel(c, -1, 0 / 0)
		t.expect(intent).toBe(nil)
		t.expect(after.wheelAt).toBe(10)
		local _, later = Carousel.wheel(after, -1, 10.3)
		t.expect(later).toBe("next")
	end)

	it("a clock that went back counts as rested", function()
		local c = Carousel.wheel(Carousel.new(4), -1, 10)
		local _, intent = Carousel.wheel(c, -1, 9)
		t.expect(intent).toBe("next")
	end)

	it(
		"a swipe to the left brings the next card, to the right the previous one; up and down do nothing",
		function()
			t.expect(Carousel.swipe("Left")).toBe("next")
			t.expect(Carousel.swipe("Right")).toBe("prev")
			t.expect(Carousel.swipe("Up")).toBe(nil)
			t.expect(Carousel.swipe("Down")).toBe(nil)
			t.expect(Carousel.swipe("None")).toBe(nil)
		end
	)

	it("each card's place is its offset from the front card, the short way round", function()
		local c = Carousel.new(4)
		t.expect(Carousel.offset(c, 1)).toBe(0)
		t.expect(Carousel.offset(c, 2)).toBe(1)
		t.expect(Carousel.offset(c, 3)).toBe(2)
		t.expect(Carousel.offset(c, 4)).toBe(-1)
		local d = Carousel.step(c, -1) -- the fourth in front: the first is to its right
		t.expect(Carousel.offset(d, 4)).toBe(0)
		t.expect(Carousel.offset(d, 1)).toBe(1)
		t.expect(Carousel.offset(d, 3)).toBe(-1)
		t.expect(Carousel.offset(d, 2)).toBe(2)
		local five = Carousel.step(Carousel.new(5), 1)
		t.expect(Carousel.offset(five, 1)).toBe(-1)
		t.expect(Carousel.offset(five, 4)).toBe(2)
		t.expect(Carousel.offset(five, 5)).toBe(-2)
	end)

	it("the front card is centred, fills HEIGHT of the area, and fits inside it on every screen", function()
		for _, s in SCREENS do
			local w, h = s[1], s[2]
			local b = Carousel.box(0, w, h)
			t.expect(b.shown).toBe(true)
			t.expect(b.dim).toBe(0)
			t.expect(b.x + b.width / 2).toBeNear(w / 2, 1e-9)
			t.expect(b.y + b.height / 2).toBeNear(h / 2, 1e-9)
			t.expect(b.x >= 0 and b.y >= 0 and b.x + b.width <= w and b.y + b.height <= h).toBe(true)
			t.expect(b.height).toBeNear(h * Carousel.HEIGHT, 1e-9)
			t.expect(b.width <= w * Carousel.MAX_WIDTH + 1e-9).toBe(true)
			t.expect(b.width <= b.height * Carousel.ASPECT + 1e-9).toBe(true)
		end
	end)

	it("the front card is as wide as ASPECT allows, or MAX_WIDTH of a narrow screen", function()
		local wide = Carousel.box(0, 1920, 1080)
		t.expect(wide.width).toBeNear(1080 * 0.9 * 0.6, 1e-9)
		local tall = Carousel.box(0, 390, 844)
		t.expect(tall.width).toBeNear(390 * 0.8, 1e-9)
	end)

	it("its neighbours sit either side, smaller, dimmed and clear of it, partly on screen", function()
		for _, s in SCREENS do
			local w, h = s[1], s[2]
			local front = Carousel.box(0, w, h)
			local left, right = Carousel.box(-1, w, h), Carousel.box(1, w, h)
			for _, b in { left, right } do
				t.expect(b.shown).toBe(true)
				t.expect(b.dim).toBe(Carousel.SIDE_DIM)
				t.expect(b.width).toBeNear(front.width * Carousel.SIDE_SCALE, 1e-9)
				t.expect(b.height).toBeNear(front.height * Carousel.SIDE_SCALE, 1e-9)
				t.expect(overlap(b, front)).toBe(false)
				t.expect(b.y + b.height / 2).toBeNear(h / 2, 1e-9)
				t.expect(b.x < w and b.x + b.width > 0).toBe(true)
			end
			t.expect(left.x + left.width <= front.x).toBe(true)
			t.expect(right.x >= front.x + front.width).toBe(true)
			t.expect(front.x - (left.x + left.width)).toBeNear(w * Carousel.GAP, 1e-9)
			t.expect(right.x - (front.x + front.width)).toBeNear(w * Carousel.GAP, 1e-9)
		end
	end)

	it("a neighbour is dimmed, and the front card is not", function()
		t.expect(Carousel.SIDE_DIM > 0 and Carousel.SIDE_DIM < 1).toBe(true)
		t.expect(Carousel.box(0, 1280, 720).dim).toBe(0)
		t.expect(Carousel.box(1, 1280, 720).dim > 0).toBe(true)
	end)

	it("every card further than one from the front is hidden", function()
		for _, s in SCREENS do
			for _, off in { 2, -2, 3, -3 } do
				t.expect(Carousel.box(off, s[1], s[2]).shown).toBe(false)
			end
		end
	end)
end)
