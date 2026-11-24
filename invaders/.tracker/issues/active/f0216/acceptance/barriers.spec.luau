--!strict
-- f0216 AC2: the barriers. Four bunkers between the cannon and the formation, each a grid of 8 x 6 blocks. A
-- shot erodes from the side it comes from (the cannon's shot from the near side, an alien's from the far side):
-- the block it reaches, its two neighbours across and the one beyond. A shot never passes a block, however fast
-- it moves. Aliens marching through erase every block their boxes overlap.
local Barriers = require("@logic/Barriers")
local Classic = require("@logic/Classic")
local Formation = require("@logic/Formation")
local t = require("@tests/lib/t")

local L = Barriers.CLASSIC

local function blockX(bunker: number, col: number): number
	return L.lefts[bunker] + (col - 1) * L.block
end
local function blockD(row: number): number
	return L.near + (row - 1) * L.block
end

local function present(b: Barriers.Barriers, bunker: number): string
	local out = {}
	for row = L.rows, 1, -1 do
		local line = {}
		for col = 1, L.cols do
			table.insert(line, if Barriers.present(b, bunker, col, row) then "#" else ".")
		end
		table.insert(out, table.concat(line))
	end
	return table.concat(out, "/")
end

-- present blocks that overlap a living alien's box (reads only)
local function underAliens(g: Classic.Game): number
	local f = g.formation
	local n = 0
	for row = 1, f.config.rows do
		for col = 1, f.config.cols do
			if Formation.isAlive(f, row, col) then
				local x0, d0, x1, d1 = Formation.box(f, row, col)
				for i, left in L.lefts do
					for r = 1, L.rows do
						for c = 1, L.cols do
							local bx, bd = left + (c - 1) * L.block, L.near + (r - 1) * L.block
							if
								Barriers.present(g.barriers, i, c, r)
								and bx < x1
								and bx + L.block > x0
								and bd < d1
								and bd + L.block > d0
							then
								n += 1
							end
						end
					end
				end
			end
		end
	end
	return n
end

-- a quiet game: no bombs fire and the formation does not move while the case runs
local function quiet(): Classic.Game
	local g = Classic.new(1)
	g.reloadElapsed = -100000
	g.formation.elapsed = -100000
	return g
end

local function run(g: Classic.Game, n: number, input: Classic.Input?): { Classic.Event }
	local all = {}
	for _ = 1, n do
		for _, e in Classic.step(g, input) do
			table.insert(all, e)
		end
	end
	return all
end

return t.spec("f0216 barriers", function(it)
	it("are four bunkers of 8 x 6 blocks, all present, between the cannon and the formation", function()
		t.expect(#L.lefts).toBe(4)
		t.expect(L.cols).toBe(8)
		t.expect(L.rows).toBe(6)
		local b = Barriers.new(L)
		t.expect(Barriers.count(b)).toBe(4 * 48)
		for i = 1, 4 do
			t.expect(Barriers.count(b, i)).toBe(48)
		end
		t.expect(L.near > Classic.CONFIG.cannonDepth).toBe(true)
		t.expect(blockD(L.rows) + L.block <= Classic.waveDepth(8)).toBe(true)
		-- they do not overlap, and sit inside the field
		for i = 2, 4 do
			t.expect(L.lefts[i] >= L.lefts[i - 1] + L.cols * L.block).toBe(true)
		end
		t.expect(L.lefts[1] >= 0 and L.lefts[4] + L.cols * L.block <= Classic.CONFIG.fieldWidth).toBe(true)
	end)

	it("finds the present block holding a point, and nothing in a gap or a hole", function()
		local b = Barriers.new(L)
		local i, col, row = Barriers.blockAt(b, blockX(2, 5) + 2, blockD(3))
		t.expect(i).toBe(2)
		t.expect(col).toBe(5)
		t.expect(row).toBe(3)
		t.expect((Barriers.blockAt(b, blockX(2, 8) + L.block, blockD(1)))).toBe(nil) -- right of bunker 2
		t.expect((Barriers.blockAt(b, blockX(1, 1), blockD(1) - 1))).toBe(nil) -- in front of it
		t.expect((Barriers.blockAt(b, blockX(1, 1), blockD(6) + L.block))).toBe(nil) -- behind it
		Barriers.erode(b, 2, 5, 3, 1)
		t.expect((Barriers.blockAt(b, blockX(2, 5), blockD(3)))).toBe(nil)
	end)

	it("erodes the hit block, its neighbours across and the one beyond, along the shot's travel", function()
		local b = Barriers.new(L)
		t.expect(Barriers.erode(b, 1, 4, 1, 1)).toBe(4) -- from the near side: beyond is row 2
		t.expect(present(b, 1)).toBe("########/########/########/########/###.####/##...###")
		local c = Barriers.new(L)
		t.expect(Barriers.erode(c, 1, 4, 6, -1)).toBe(4) -- from the far side: beyond is row 5
		t.expect(present(c, 1)).toBe("##...###/###.####/########/########/########/########")
		-- at the edge of a bunker, and over blocks already gone: only present blocks count
		local e = Barriers.new(L)
		t.expect(Barriers.erode(e, 3, 1, 1, 1)).toBe(3)
		t.expect(Barriers.erode(e, 3, 1, 1, 1)).toBe(0) -- all three are gone already: nothing more is removed
		t.expect(Barriers.count(e, 3)).toBe(48 - 3)
		t.expect(Barriers.count(e, 2)).toBe(48)
	end)

	it("erases every block a box overlaps, and none it only touches", function()
		local b = Barriers.new(L)
		-- a box over bunker 4's columns 2..3 (partly) and rows 5..6, touching column 4's edge without overlapping it
		local removed =
			Barriers.eraseBox(b, blockX(4, 2) + 1, blockD(5) + 1, blockX(4, 4), blockD(6) + L.block + 5)
		t.expect(removed).toBe(4)
		t.expect(present(b, 4)).toBe("#..#####/#..#####/########/########/########/########")
		t.expect(Barriers.eraseBox(b, -50, -50, -10, -10)).toBe(0)
	end)

	it("stops the cannon's shot at the first block it reaches, from the near side", function()
		local g = quiet()
		-- the cannon under bunker 2's column 3
		g.cannon = blockX(2, 3) + 1
		run(g, 1, { fire = true })
		local events = run(g, 20)
		t.expect(g.shot).toBe(nil)
		local hits = 0
		for _, e in events do
			if e.kind == "BarrierHit" then
				hits += 1
			end
			t.expect(e.kind ~= "AlienHit").toBe(true)
		end
		t.expect(hits).toBe(1)
		t.expect(present(g.barriers, 2)).toBe("########/########/########/########/##.#####/#...####")
		t.expect(g.formation.live).toBe(55)
	end)

	it("never lets a shot jump a block, at any speed: each unit it moves is checked", function()
		-- the shot moves 4 units a tick, a block is 3 deep: leave one block in its column and fire at it
		t.expect(Classic.CONFIG.shotSpeed > L.block).toBe(true)
		for row = 1, L.rows do
			local g = quiet()
			for r = 1, L.rows do
				for c = 1, L.cols do
					if not (r == row and c == 6) then
						g.barriers.blocks[1][(r - 1) * L.cols + c] = false
					end
				end
			end
			g.cannon = blockX(1, 6) + 1
			run(g, 1, { fire = true })
			run(g, 20)
			t.expect(Barriers.present(g.barriers, 1, 6, row)).toBe(false)
			t.expect(g.formation.live).toBe(55)
		end
	end)

	it("lets an alien's shot erode from the far side, and stop there", function()
		local g = quiet()
		g.cannon = 10
		table.insert(g.bombs, { x = blockX(3, 5) + 1, d = 60, slot = 2 })
		run(g, 30)
		t.expect(#g.bombs).toBe(0)
		t.expect(present(g.barriers, 3)).toBe("###...##/####.###/########/########/########/########")
		t.expect(g.lives).toBe(3)
	end)

	it("lets an alien's shot past a cleared column of a bunker", function()
		local g = quiet()
		for r = 1, L.rows do
			g.barriers.blocks[3][(r - 1) * L.cols + 5] = false
		end
		g.cannon = blockX(3, 5) + 1
		table.insert(g.bombs, { x = blockX(3, 5) + 1, d = 60, slot = 2 })
		run(g, 60)
		t.expect(g.lives).toBe(2)
		t.expect(Barriers.count(g.barriers, 3)).toBe(48 - 6)
	end)

	it("is erased where marching aliens overlap it, on an advance and on every sideways step", function()
		local g = Classic.new(1)
		g.reloadElapsed = -100000
		-- bring the formation down to just above the bunkers, then let it advance into them
		g.formation.d = L.near + L.rows * L.block + 1
		local before = Barriers.count(g.barriers)
		local function untilMove(kind: string): boolean
			for _ = 1, 5000 do
				for _, e in Classic.step(g, nil) do
					if e.kind == kind then
						return true
					end
				end
			end
			return false
		end
		t.expect(untilMove("Advance")).toBe(true)
		local afterAdvance = Barriers.count(g.barriers)
		t.expect(afterAdvance < before).toBe(true)
		t.expect(underAliens(g)).toBe(0)
		-- the next sideways step moves the aliens over blocks no alien covered: those go too
		t.expect(untilMove("March")).toBe(true)
		t.expect(Barriers.count(g.barriers) < afterAdvance).toBe(true)
		t.expect(underAliens(g)).toBe(0)
	end)

	it("tells which shot hit it: the cannon's has no slot, an alien's its slot", function()
		local g = quiet()
		g.cannon = blockX(2, 3) + 1
		table.insert(g.bombs, { x = blockX(3, 5) + 1, d = L.near + L.rows * L.block, slot = 3 })
		local e = run(g, 1, { fire = true })
		for _, ev in run(g, 10) do
			table.insert(e, ev)
		end
		local slots = {}
		for _, ev in e do
			if ev.kind == "BarrierHit" then
				table.insert(slots, ev.slot or 0)
			end
		end
		table.sort(slots)
		t.expect(slots).toEqual({ 0, 3 })
	end)
end)
