--!strict
-- f0216 AC3: the shots. The cannon has one shot on the field at a time: a fire while it flies is ignored, and it
-- ends on a block, an alien, the mystery ship or the far end. The aliens have up to three at a time: slot 1 is
-- aimed (from the living column nearest the cannon), slots 2 and 3 from random living columns (the game's
-- seeded generator); each falls from its column's front-most living alien. They fire in turn, one per reload,
-- and the reload shortens as the score grows (48 ticks, then 16 from 200, 11 from 1,000, 8 from 2,000 and 7 from
-- 3,000). A shot that reaches the cannon costs a life.
local Classic = require("@logic/Classic")
local Formation = require("@logic/Formation")
local t = require("@tests/lib/t")

local CFG = Classic.CONFIG

local function run(g: Classic.Game, n: number, input: Classic.Input?): { Classic.Event }
	local all = {}
	for _ = 1, n do
		for _, e in Classic.step(g, input) do
			table.insert(all, e)
		end
	end
	return all
end

local function count(events: { Classic.Event }, kind: string): number
	local n = 0
	for _, e in events do
		if e.kind == kind then
			n += 1
		end
	end
	return n
end

local function columnX(g: Classic.Game, col: number): number
	local x0, _, x1 = Formation.box(g.formation, 1, col)
	return (x0 + x1) // 2
end

-- no alien fire and no march while the case runs
local function quiet(seed: number?): Classic.Game
	local g = Classic.new(seed or 1)
	g.reloadElapsed = -100000
	g.formation.elapsed = -100000
	return g
end

return t.spec("f0216 shots", function(it)
	it("fires one shot from the cannon, and ignores a fire while it flies", function()
		local g = quiet()
		g.cannon = 10 -- left of every bunker and every alien column
		local e = run(g, 1, { fire = true })
		t.expect(count(e, "PlayerFire")).toBe(1)
		t.expect(g.shot ~= nil).toBe(true)
		t.expect((g.shot :: Classic.Shot).x).toBe(10)
		local d1 = (g.shot :: Classic.Shot).d
		t.expect(d1).toBe(CFG.cannonDepth - 1 + CFG.shotSpeed)
		e = run(g, 10, { fire = true })
		t.expect(count(e, "PlayerFire")).toBe(0)
		t.expect(g.shotsFired).toBe(1)
		t.expect((g.shot :: Classic.Shot).d).toBe(d1 + 10 * CFG.shotSpeed)
	end)

	it("does not remember a fire made while the shot flies", function()
		local g = quiet()
		g.cannon = 10
		run(g, 1, { fire = true })
		local held = 0
		while g.shot ~= nil do
			run(g, 1, { fire = true })
			held += 1
			t.expect(held < 200).toBe(true)
		end
		t.expect(held > 10).toBe(true)
		local e = run(g, 5)
		t.expect(count(e, "PlayerFire")).toBe(0)
		t.expect(g.shot).toBe(nil)
		t.expect(g.shotsFired).toBe(1)
	end)

	it("ends the shot at the far end, and then a fire works again", function()
		local g = quiet()
		g.cannon = 10
		run(g, 1, { fire = true })
		local ticks = 1
		while g.shot ~= nil do
			run(g, 1)
			ticks += 1
			t.expect(ticks < 200).toBe(true)
		end
		t.expect(ticks).toBe(math.ceil((CFG.fieldDepth - CFG.cannonDepth + 1) / CFG.shotSpeed))
		local e = run(g, 1, { fire = true })
		t.expect(count(e, "PlayerFire")).toBe(1)
		t.expect(g.shotsFired).toBe(2)
	end)

	it("kills the first alien it reaches, scores it and ends", function()
		local g = quiet()
		g.cannon = columnX(g, 6)
		run(g, 1, { fire = true })
		local e = run(g, 60)
		t.expect(count(e, "AlienHit")).toBe(1)
		t.expect(g.formation.live).toBe(54)
		t.expect(Formation.isAlive(g.formation, 1, 6)).toBe(false)
		t.expect(Formation.isAlive(g.formation, 2, 6)).toBe(true)
		t.expect(g.score).toBe(10)
		t.expect(g.shot).toBe(nil)
		-- the next shot up the same column reaches row 2
		run(g, 1, { fire = true })
		run(g, 60)
		t.expect(Formation.isAlive(g.formation, 2, 6)).toBe(false)
		t.expect(g.score).toBe(20)
	end)

	it("moves the cannon one unit a tick, only by -1, 0 or 1, and keeps it on the field", function()
		local g = quiet()
		local x = g.cannon
		run(g, 5, { move = 1 })
		t.expect(g.cannon).toBe(x + 5 * CFG.cannonSpeed)
		run(g, 3, { move = -1 })
		t.expect(g.cannon).toBe(x + 2 * CFG.cannonSpeed)
		for _, bad in { 2, -5, 0.5, math.huge, -math.huge, math.huge - math.huge } do
			local before = g.cannon
			run(g, 1, { move = bad })
			t.expect(g.cannon).toBe(before)
		end
		run(g, 1, ({ move = "1" } :: any) :: Classic.Input)
		t.expect(g.cannon).toBe(x + 2 * CFG.cannonSpeed)
		run(g, 400, { move = -1 })
		t.expect(g.cannon).toBe(CFG.cannonHalf)
		run(g, 400, { move = 1 })
		t.expect(g.cannon).toBe(CFG.fieldWidth - 1 - CFG.cannonHalf)
	end)

	it("fires only on a fire of exactly true", function()
		local g = quiet()
		for _, bad: any in { 1, "true", {} } :: { any } do
			run(g, 1, ({ fire = bad } :: any) :: Classic.Input)
		end
		run(g, 1, ("fire" :: any) :: Classic.Input)
		run(g, 1, nil)
		t.expect(g.shotsFired).toBe(0)
		t.expect(g.shot).toBe(nil)
	end)

	it("fires the aliens' shots in turn, aimed then random then random, at most three at a time", function()
		local g = Classic.new(3)
		g.formation.elapsed = -100000
		g.cannon = columnX(g, 9)
		local fires = {}
		for _ = 1, 48 * 6 do
			for _, e in Classic.step(g, nil) do
				if e.kind == "AlienFire" then
					table.insert(fires, { slot = e.slot, col = e.col })
				end
			end
			t.expect(#g.bombs <= 3).toBe(true)
			local aimed = 0
			for _, b in g.bombs do
				if b.slot == 1 then
					aimed += 1
				end
			end
			t.expect(aimed <= 1).toBe(true)
			if g.phase ~= "playing" then
				break
			end
		end
		t.expect(#fires >= 3).toBe(true)
		t.expect(fires[1].slot).toBe(1)
		t.expect(fires[1].col).toBe(9)
		t.expect(fires[2].slot).toBe(2)
		t.expect(fires[3].slot).toBe(3)
	end)

	it("keeps the turn after a free slot: a slot freed early waits for its turn", function()
		local g = Classic.new(1)
		g.formation.elapsed = -100000
		g.cannon = 10
		g.reloadElapsed = 1000
		run(g, 1) -- slot 1
		g.reloadElapsed = 1000
		run(g, 1) -- slot 2
		t.expect(#g.bombs).toBe(2)
		-- slot 1's shot is gone; the next turn is slot 3's, then slot 1's
		for i = #g.bombs, 1, -1 do
			if g.bombs[i].slot == 1 then
				table.remove(g.bombs, i)
			end
		end
		g.reloadElapsed = 1000
		local e = run(g, 1)
		t.expect(e[#e].kind).toBe("AlienFire")
		t.expect(e[#e].slot).toBe(3)
		g.reloadElapsed = 1000
		e = run(g, 1)
		t.expect(e[#e].slot).toBe(1)
		-- all three out: no fourth, however long the reload has run
		g.reloadElapsed = 1000
		t.expect(#run(g, 1)).toBe(0)
		t.expect(#g.bombs).toBe(3)
	end)

	it("waits one reload between alien shots, 48 ticks at the start", function()
		local g = Classic.new(1)
		g.formation.elapsed = -100000
		g.cannon = 10
		local at = {}
		for tick = 1, 200 do
			for _, e in Classic.step(g, nil) do
				if e.kind == "AlienFire" then
					table.insert(at, tick)
				end
			end
		end
		t.expect(at[1]).toBe(48)
		t.expect(at[2]).toBe(96)
		t.expect(at[3]).toBe(144)
	end)

	it("shortens the reload as the score grows", function()
		t.expect(Classic.reloadTicks(0)).toBe(48)
		t.expect(Classic.reloadTicks(199)).toBe(48)
		t.expect(Classic.reloadTicks(200)).toBe(16)
		t.expect(Classic.reloadTicks(999)).toBe(16)
		t.expect(Classic.reloadTicks(1000)).toBe(11)
		t.expect(Classic.reloadTicks(2000)).toBe(8)
		t.expect(Classic.reloadTicks(2999)).toBe(8)
		t.expect(Classic.reloadTicks(3000)).toBe(7)
		t.expect(Classic.reloadTicks(99990)).toBe(7)
		-- read from the live score: a game at 1,000 fires 11 ticks after its last shot
		local g = Classic.new(1)
		g.formation.elapsed = -100000
		g.cannon = 10
		g.score = 1000
		local at = {}
		for tick = 1, 40 do
			for _, e in Classic.step(g, nil) do
				if e.kind == "AlienFire" then
					table.insert(at, tick)
				end
			end
		end
		t.expect(at[1]).toBe(11)
		t.expect(at[2]).toBe(22)
	end)

	it("aims slot 1 at the living column nearest the cannon, from its front-most living alien", function()
		local g = Classic.new(1)
		g.formation.elapsed = -100000
		g.reloadElapsed = 1000
		g.cannon = columnX(g, 4) + 3
		Formation.kill(g.formation, 1, 4)
		Formation.kill(g.formation, 2, 4)
		local e = run(g, 1)
		t.expect(count(e, "AlienFire")).toBe(1)
		local b = g.bombs[1]
		t.expect(b.slot).toBe(1)
		t.expect(b.x).toBe(columnX(g, 4))
		local _, d0 = Formation.box(g.formation, 3, 4)
		t.expect(b.d).toBe(d0) -- it starts at the alien's near edge and falls from the next tick
		-- with column 4 cleared, the nearest living column is 5 (to the right of the cannon) or 3
		local h = Classic.new(1)
		h.formation.elapsed = -100000
		h.reloadElapsed = 1000
		h.cannon = columnX(h, 4) + 3
		for row = 1, 5 do
			Formation.kill(h.formation, row, 4)
		end
		run(h, 1)
		t.expect(h.bombs[1].x).toBe(columnX(h, 5))
	end)

	it("aims at the lower column when the cannon is midway between two", function()
		local g = Classic.new(1)
		g.formation.elapsed = -100000
		g.reloadElapsed = 1000
		g.cannon = (columnX(g, 1) + columnX(g, 2)) // 2
		t.expect(g.cannon - columnX(g, 1)).toBe(columnX(g, 2) - g.cannon)
		run(g, 1)
		t.expect(g.bombs[1].slot).toBe(1)
		t.expect(g.bombs[1].x).toBe(columnX(g, 1))
	end)

	it("takes slots 2 and 3 from living columns only, chosen by the seed", function()
		local function randomCols(seed: number, cleared: { number }): string
			local g = Classic.new(seed)
			g.formation.elapsed = -100000
			g.cannon = 10
			for _, col in cleared do
				for row = 1, 5 do
					Formation.kill(g.formation, row, col)
				end
			end
			local out = {}
			for _ = 1, 4000 do
				for _, e in Classic.step(g, nil) do
					if e.kind == "AlienFire" and e.slot ~= 1 then
						table.insert(out, e.col :: number)
					end
				end
			end
			return table.concat(out, ",")
		end
		local function list(s: string): { number }
			local out = {}
			for _, v in string.split(s, ",") do
				table.insert(out, tonumber(v) :: number)
			end
			return out
		end
		local a = list(randomCols(11, {}))
		t.expect(#a >= 20).toBe(true)
		t.expect(randomCols(11, {})).toBe(randomCols(11, {}))
		t.expect(randomCols(12, {}) ~= randomCols(11, {})).toBe(true)
		local seen = {}
		for _, col in a do
			seen[col] = true
		end
		local distinct = 0
		for _ in seen do
			distinct += 1
		end
		t.expect(distinct >= 5).toBe(true) -- random, not one fixed column
		for _, col in list(randomCols(5, { 1, 2, 3, 5, 7, 8, 9, 10 })) do
			t.expect(col == 4 or col == 6 or col == 11).toBe(true)
		end
	end)

	it("costs a life when an alien's shot reaches the cannon, and misses beside it", function()
		local g = quiet()
		g.cannon = 10
		table.insert(g.bombs, { x = 10 + CFG.cannonHalf + 1, d = 20, slot = 2 }) -- just right of the cannon
		run(g, 30)
		t.expect(g.lives).toBe(3)
		t.expect(#g.bombs).toBe(0)
		table.insert(g.bombs, { x = 10 + CFG.cannonHalf, d = 20, slot = 2 }) -- its right edge
		local e = run(g, 30)
		t.expect(count(e, "CannonHit")).toBe(1)
		t.expect(g.lives).toBe(2)
		t.expect(g.phase).toBe("dying")
		-- and on the left: its left edge is hit, one unit beyond it is not
		local h = quiet()
		h.cannon = 10
		table.insert(h.bombs, { x = 10 - CFG.cannonHalf - 1, d = 20, slot = 2 })
		run(h, 30)
		t.expect(h.lives).toBe(3)
		table.insert(h.bombs, { x = 10 - CFG.cannonHalf, d = 20, slot = 2 })
		run(h, 30)
		t.expect(h.lives).toBe(2)
	end)

	it("hits the cannon where it stands after this tick's move", function()
		local g = quiet()
		g.cannon = 10
		table.insert(g.bombs, { x = 30, d = CFG.cannonDepth + 3, slot = 2 })
		run(g, 3)
		t.expect(g.bombs[1].d).toBe(CFG.cannonDepth)
		-- the cannon steps under it as it lands
		g.cannon = 30 - CFG.cannonHalf - 1
		run(g, 1, { move = 1 })
		t.expect(g.lives).toBe(2)
	end)
end)
