--!strict
-- f0217 AC1: the two-player field. One field twice the solo depth: player 1 at its near end (d = 0), player 2 at
-- its far end, turned half a turn to face player 1. Each player's run is a Classic run in their own frame (x
-- across as they see it, d from their own base line), with their own cannon, 3 lives, four full bunkers in front
-- and a group of 5 x 8 aliens; every other solo number is the same. A point (x, d) of player 2's frame is
-- (W - 1 - x, D - 1 - d) in the field's frame, which is player 1's.
local Barriers = require("@logic/Barriers")
local Classic = require("@logic/Classic")
local Formation = require("@logic/Formation")
local TwoPlayer = require("@logic/TwoPlayer")
local t = require("@tests/lib/t")

local CFG = TwoPlayer.CONFIG
local C = Classic.CONFIG
local W = C.fieldWidth
local D = CFG.fieldDepth

local function pair(a: number, b: number): { number }
	return { a, b }
end

local function quad(a: number, b: number, c: number, d: number): { number }
	return { a, b, c, d }
end

return t.spec("f0217 field", function(it)
	it("is one field twice the solo depth, with player 2 at the far end, turned to face player 1", function()
		t.expect(D).toBe(2 * C.fieldDepth)
		t.expect(D).toBe(464)
		local g = TwoPlayer.new(1)
		-- player 1's frame is the field's
		t.expect(pair(TwoPlayer.toField(g, 1, 30, 5))).toEqual({ 30, 5 })
		-- player 2's base line is the field's far end, and their left is the field's right
		t.expect(pair(TwoPlayer.toField(g, 2, 0, 0))).toEqual({ W - 1, D - 1 })
		t.expect(pair(TwoPlayer.toField(g, 2, 30, 5))).toEqual({ W - 31, D - 6 })
		-- the same call maps a field point back into player 2's frame
		t.expect(pair(TwoPlayer.toField(g, 2, TwoPlayer.toField(g, 2, 30, 5)))).toEqual({ 30, 5 })
		-- a half-open box turns with it
		t.expect(quad(TwoPlayer.fieldBox(g, 2, 28, 24, 31, 27))).toEqual({ W - 31, D - 27, W - 28, D - 24 })
		t.expect(quad(TwoPlayer.fieldBox(g, 1, 28, 24, 31, 27))).toEqual({ 28, 24, 31, 27 })
	end)

	it("gives each player their own run: a cannon at the centre, 3 lives, no score and no revives", function()
		local g = TwoPlayer.new(1)
		t.expect(g.wave).toBe(1)
		t.expect(g.phase).toBe("flyin")
		t.expect(#g.sides).toBe(2)
		t.expect(g.sides[1].run == g.sides[2].run).toBe(false)
		for p = 1, 2 do
			local side = g.sides[p]
			local run = side.run
			t.expect(side.out).toBe(false)
			t.expect(TwoPlayer.phaseOf(g, p)).toBe("playing")
			t.expect(run.phase).toBe("playing")
			t.expect(run.lives).toBe(3)
			t.expect(run.score).toBe(0)
			t.expect(run.revives).toBe(0)
			t.expect(run.shotsFired).toBe(0)
			t.expect(run.cannon).toBe(C.cannonStart)
			t.expect(run.shot).toBe(nil)
			t.expect(#run.bombs).toBe(0)
			t.expect(run.wave).toBe(1)
		end
	end)

	it(
		"puts four full bunkers in front of each player, at the solo depth from their own base line",
		function()
			local g = TwoPlayer.new(1)
			for p = 1, 2 do
				local b = g.sides[p].run.barriers
				t.expect(#b.layout.lefts).toBe(4)
				t.expect(b.layout.near).toBe(Barriers.CLASSIC.near)
				t.expect(Barriers.count(b)).toBe(4 * 8 * 6)
			end
			-- player 1's at the near end of the field
			t.expect({ Barriers.blockAt(g.sides[1].run.barriers, 29, 24) }).toEqual({ 1, 1, 1 })
			-- player 2's at the far end: field (29, D - 25) is their (W - 30, 24), bunker 4's last column, near row
			t.expect({ Barriers.blockAt(g.sides[2].run.barriers, TwoPlayer.toField(g, 2, 29, D - 25)) })
				.toEqual({ 4, 8, 1 })
			t.expect((Barriers.blockAt(g.sides[1].run.barriers, 29, D - 25))).toBe(nil)
		end
	)

	it(
		"gives each player a group of 5 rows of 8, centred, its front row at the solo wave depth from them",
		function()
			t.expect(TwoPlayer.PAIR.rows).toBe(5)
			t.expect(TwoPlayer.PAIR.cols).toBe(8)
			for k, v in Formation.CLASSIC :: any do
				if k ~= "cols" then
					t.expect((TwoPlayer.PAIR :: any)[k]).toEqual(v)
				end
			end
			local g = TwoPlayer.new(1)
			for p = 1, 2 do
				local f = g.sides[p].run.formation
				t.expect(f.config.rows).toBe(5)
				t.expect(f.config.cols).toBe(8)
				t.expect(f.live).toBe(40)
				t.expect(f.d).toBe(Classic.waveDepth(1))
				t.expect(f.x).toBe((W - (7 * 16 + 12)) // 2)
			end
			-- player 2's group in the field: its front row is the one nearest the far end
			local _, d0, _, d1 = TwoPlayer.fieldBox(g, 2, Formation.box(g.sides[2].run.formation, 1, 1))
			t.expect(d0).toBe(D - Classic.waveDepth(1) - 8)
			t.expect(d1).toBe(D - Classic.waveDepth(1))
		end
	)

	it("keeps every solo number for each player but the field's depth and the formation", function()
		t.expect(CFG.pair.formation).toBe(TwoPlayer.PAIR)
		t.expect(CFG.lone.formation).toBe(Formation.CLASSIC)
		for _, rc in { CFG.pair, CFG.lone } do
			for k, v in C :: any do
				if k == "fieldDepth" then
					t.expect(rc.fieldDepth).toBe(D)
				elseif k ~= "formation" then
					t.expect((rc :: any)[k]).toEqual(v)
				end
			end
		end
	end)

	it("reads player 2's moves from their own seat: their left is the field's right", function()
		local g = TwoPlayer.new(1)
		local before = TwoPlayer.toField(g, 2, g.sides[2].run.cannon, 0)
		TwoPlayer.step(g, { {}, { move = -1 } })
		t.expect(g.sides[2].run.cannon).toBe(C.cannonStart - 1)
		t.expect(g.sides[1].run.cannon).toBe(C.cannonStart)
		t.expect((TwoPlayer.toField(g, 2, g.sides[2].run.cannon, 0))).toBe(before + 1)
		TwoPlayer.step(g, { { move = -1 } })
		t.expect(g.sides[1].run.cannon).toBe(C.cannonStart - 1)
		t.expect(g.sides[2].run.cannon).toBe(C.cannonStart - 1)
	end)
end)
