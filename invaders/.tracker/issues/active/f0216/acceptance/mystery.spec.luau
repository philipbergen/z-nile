--!strict
-- f0216 AC4: the mystery ship. It crosses the far end of the field 1,500 playing ticks (25 s) after the last one
-- left or the wave began, alternating sides (the first from the left), only while at least 8 aliens live. Hit
-- by the cannon's shot it scores 50, 100, 150 or 300: the value table indexed by the player's shot count, so
-- the 23rd shot (and every 15th after it) is worth 300.
local Classic = require("@logic/Classic")
local Formation = require("@logic/Formation")
local Mystery = require("@logic/Mystery")
local t = require("@tests/lib/t")

local M = Mystery.CLASSIC

local function untilChange(m: Mystery.Mystery, live: number, limit: number): (number?, Mystery.Change?)
	for n = 1, limit do
		local c: Mystery.Change? = Mystery.tick(m, live)
		if c then
			return n, c
		end
	end
	return nil, nil
end

return t.spec("f0216 mystery", function(it)
	it("appears 1,500 ticks (25 s) after the wave begins, from the left, and crosses the far end", function()
		t.expect(M.every).toBe(25 * Classic.TICK_RATE)
		t.expect(M.lane >= Classic.waveDepth(1) + 4 * Formation.CLASSIC.rowSpacing + Formation.CLASSIC.depth)
			.toBe(true)
		t.expect(M.lane + M.depth <= Classic.CONFIG.fieldDepth).toBe(true)
		local m = Mystery.new(M)
		local n, c = untilChange(m, 55, 5000)
		t.expect(n).toBe(1500)
		t.expect(c).toBe("appear")
		t.expect(m.dir).toBe(1)
		t.expect(m.x).toBe(-M.width)
		local crossing, c2 = untilChange(m, 55, 5000)
		t.expect(c2).toBe("leave")
		t.expect(crossing).toBe((M.fieldWidth + M.width) // M.speed)
		t.expect(m.x).toBe(nil)
	end)

	it("alternates sides, and waits 1,500 ticks after each one leaves", function()
		local m = Mystery.new(M)
		untilChange(m, 55, 5000)
		untilChange(m, 55, 5000)
		local n, c = untilChange(m, 55, 5000)
		t.expect(n).toBe(1500)
		t.expect(c).toBe("appear")
		t.expect(m.dir).toBe(-1)
		t.expect(m.x).toBe(M.fieldWidth)
		local _, c2 = untilChange(m, 55, 5000)
		t.expect(c2).toBe("leave")
		local _, c3 = untilChange(m, 55, 5000)
		t.expect(c3).toBe("appear")
		t.expect(m.dir).toBe(1)
	end)

	it("does not appear while fewer than 8 aliens live, and appears once 8 do again", function()
		t.expect(M.minAliens).toBe(8)
		local m = Mystery.new(M)
		t.expect((untilChange(m, 7, 4000))).toBe(nil)
		t.expect(Mystery.tick(m, 8)).toBe("appear")
	end)

	it(
		"is worth 50, 100, 150 or 300 by the shot count: the 23rd shot and every 15th after it score 300",
		function()
			local m = Mystery.new(M)
			local seen = {}
			for shots = 1, 60 do
				local v = Mystery.value(m, shots)
				t.expect(v == 50 or v == 100 or v == 150 or v == 300).toBe(true)
				seen[v] = true
			end
			t.expect(seen[50] and seen[100] and seen[150] and seen[300]).toBe(true)
			t.expect(Mystery.value(m, 23)).toBe(300)
			t.expect(Mystery.value(m, 38)).toBe(300)
			t.expect(Mystery.value(m, 53)).toBe(300)
			t.expect(Mystery.value(m, 22)).toBe(50)
			t.expect(Mystery.value(m, 24)).toBe(100)
			t.expect(Mystery.value(m, 1)).toBe(50)
		end
	)

	it("is hit only inside its box", function()
		local m = Mystery.new(M)
		t.expect(Mystery.hitAt(m, 0, M.lane)).toBe(false)
		m.x = 100
		t.expect(Mystery.hitAt(m, 100, M.lane)).toBe(true)
		t.expect(Mystery.hitAt(m, 100 + M.width - 1, M.lane + M.depth - 1)).toBe(true)
		t.expect(Mystery.hitAt(m, 100 + M.width, M.lane)).toBe(false)
		t.expect(Mystery.hitAt(m, 99, M.lane)).toBe(false)
		t.expect(Mystery.hitAt(m, 100, M.lane - 1)).toBe(false)
		t.expect(Mystery.hitAt(m, 100, M.lane + M.depth)).toBe(false)
	end)

	it("in the game: the cannon's 23rd shot hits it for 300, and the next ship waits again", function()
		local g = Classic.new(1)
		g.reloadElapsed = -100000
		g.formation.elapsed = -100000
		g.cannon = 56 -- in the gaps between bunkers 1 and 2 and between columns 2 and 3
		g.shotsFired = 22
		g.mystery.elapsed = M.every - 1
		local hit = nil
		for _ = 1, 400 do
			local fire = g.mystery.x == -10 and g.shot == nil -- 53 ticks of flight to the lane: the ship is then over x = 56
			for _, e in Classic.step(g, { fire = fire }) do
				if e.kind == "MysteryHit" then
					hit = e.points
				end
			end
			if hit then
				break
			end
		end
		t.expect(hit).toBe(300)
		t.expect(g.shotsFired).toBe(23)
		t.expect(g.score).toBe(300)
		t.expect(g.mystery.x).toBe(nil)
		t.expect(g.mystery.elapsed).toBe(0)
		-- the next ship comes 1,500 playing ticks after the hit, as after one that left
		local n = 0
		local next = false
		while not next and n < 5000 do
			n += 1
			for _, e in Classic.step(g, nil) do
				if e.kind == "MysteryAppear" then
					next = true
				end
			end
		end
		t.expect(n).toBe(M.every)
		t.expect(g.mystery.dir).toBe(-1)
	end)

	it("in the game: does not count while the game is not playing", function()
		local g = Classic.new(1)
		g.reloadElapsed = -100000
		g.formation.elapsed = -100000
		g.phase = "dying"
		g.timer = 100000
		for _ = 1, 2000 do
			Classic.step(g, nil)
		end
		t.expect(g.mystery.elapsed).toBe(0)
		t.expect(g.mystery.x).toBe(nil)
	end)
end)
