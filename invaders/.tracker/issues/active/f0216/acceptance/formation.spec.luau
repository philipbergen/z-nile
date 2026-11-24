--!strict
-- f0216 AC1: the formation. 5 rows x 11 aliens, worth 30 at the back, 20 in the middle two rows and 10 in the
-- front two; it steps sideways as one block, and when its living extent would cross a side it advances one row
-- toward the base line and reverses; the wait between steps is the live count in ticks (read live, so a kill
-- shortens the wait already running), down to one tick for the last alien.
local Formation = require("@logic/Formation")
local t = require("@tests/lib/t")

local C = Formation.CLASSIC

local function ticksToMove(f: Formation.Formation): (number, Formation.Move?)
	for n = 1, 1000 do
		local m: Formation.Move? = Formation.tick(f)
		if m then
			return n, m
		end
	end
	error("the formation never moved")
end

local function killColumn(f: Formation.Formation, col: number)
	for row = 1, C.rows do
		Formation.kill(f, row, col)
	end
end

return t.spec("f0216 formation", function(it)
	it("is 5 rows of 11, all alive, centred across, its front row at the given depth", function()
		t.expect(C.rows).toBe(5)
		t.expect(C.cols).toBe(11)
		local f = Formation.new(C, 120)
		t.expect(f.live).toBe(55)
		t.expect(#Formation.columns(f)).toBe(11)
		local left, right, near = Formation.extent(f)
		t.expect(near).toBe(120)
		t.expect(left :: number).toBe(C.fieldWidth - (right :: number))
		t.expect(f.dir).toBe(1)
	end)

	it("scores 10 for the front two rows, 20 for the middle two and 30 for the back row", function()
		local f = Formation.new(C, 120)
		local got = {}
		for row = 1, 5 do
			table.insert(got, Formation.kill(f, row, 3))
		end
		t.expect(got).toEqual({ 10, 10, 20, 20, 30 })
		t.expect(f.live).toBe(50)
		-- a dead alien is worth nothing a second time and does not count down twice
		t.expect(Formation.kill(f, 5, 3)).toBe(0)
		t.expect(f.live).toBe(50)
		t.expect(Formation.kill(f, 6, 3)).toBe(0)
		t.expect(Formation.kill(f, 1, 12)).toBe(0)
		t.expect(f.live).toBe(50)
	end)

	it("waits one tick per living alien between steps", function()
		local f = Formation.new(C, 120)
		local n, m = ticksToMove(f)
		t.expect(n).toBe(55)
		t.expect(m).toBe("step")
		for col = 1, 11 do
			Formation.kill(f, 5, col)
		end
		t.expect(Formation.interval(f)).toBe(44)
		t.expect((ticksToMove(f))).toBe(44)
	end)

	it("reads the live count while it waits: a kill shortens the wait already running", function()
		local f = Formation.new(C, 120)
		for _ = 1, 30 do
			t.expect(Formation.tick(f)).toBe(nil)
		end
		-- 55 -> 30 alive: the wait is now 30, and 30 ticks have passed
		for i = 1, 25 do
			Formation.kill(f, (i - 1) // 11 + 1, (i - 1) % 11 + 1)
		end
		t.expect(f.live).toBe(30)
		t.expect(Formation.tick(f)).toBe("step")
	end)

	it("moves the last alien every tick", function()
		local f = Formation.new(C, 120)
		for row = 1, 5 do
			for col = 1, 11 do
				if not (row == 3 and col == 6) then
					Formation.kill(f, row, col)
				end
			end
		end
		t.expect(f.live).toBe(1)
		t.expect(Formation.interval(f)).toBe(1)
		t.expect(Formation.tick(f) ~= nil).toBe(true)
		t.expect(Formation.tick(f) ~= nil).toBe(true)
	end)

	it("steps sideways by stepX, then advances one row and reverses instead of crossing the side", function()
		local f = Formation.new(C, 120)
		local x0 = f.x
		local steps = 0
		local m
		repeat
			local _
			_, m = ticksToMove(f)
			if m == "step" then
				steps += 1
				t.expect(f.x).toBe(x0 + steps * C.stepX)
				t.expect(f.d).toBe(120)
			end
		until m == "advance"
		local _, right = Formation.extent(f)
		-- it went as far as it could: one more step would have crossed the right margin
		t.expect((right :: number) <= C.fieldWidth - C.margin).toBe(true)
		t.expect((right :: number) + C.stepX > C.fieldWidth - C.margin).toBe(true)
		t.expect(steps).toBe(9)
		t.expect(f.d).toBe(120 - C.rowStep)
		t.expect(f.dir).toBe(-1)
		t.expect(f.x).toBe(x0 + steps * C.stepX) -- the advance does not also step sideways
		local _, m2 = ticksToMove(f)
		t.expect(m2).toBe("step")
		t.expect(f.x).toBe(x0 + (steps - 1) * C.stepX)
	end)

	it("turns at the margin on the left too", function()
		local f = Formation.new(C, 120)
		f.dir = -1
		local m
		repeat
			local _
			_, m = ticksToMove(f)
		until m == "advance"
		local left = Formation.extent(f)
		t.expect((left :: number) >= C.margin).toBe(true)
		t.expect((left :: number) - C.stepX < C.margin).toBe(true)
		t.expect(f.dir).toBe(1)
	end)

	it("turns on its living extent: with the outer columns cleared it marches further", function()
		local full = Formation.new(C, 120)
		local thin = Formation.new(C, 120)
		killColumn(thin, 10)
		killColumn(thin, 11)
		local function stepsToAdvance(f: Formation.Formation): number
			local s = 0
			while true do
				local _, m = ticksToMove(f)
				if m == "advance" then
					return s
				end
				s += 1
			end
		end
		t.expect(stepsToAdvance(full)).toBe(9)
		t.expect(stepsToAdvance(thin)).toBe(9 + 2 * C.colSpacing // C.stepX)
	end)

	it("hits only a living alien, inside its box", function()
		local f = Formation.new(C, 120)
		local x0, d0, x1, d1 = Formation.box(f, 2, 4)
		local row, col = Formation.hitAt(f, x0, d0)
		t.expect(row).toBe(2)
		t.expect(col).toBe(4)
		row, col = Formation.hitAt(f, x1 - 1, d1 - 1)
		t.expect(row).toBe(2)
		t.expect(col).toBe(4)
		t.expect((Formation.hitAt(f, x1, d0))).toBe(nil) -- the gap between columns
		t.expect((Formation.hitAt(f, x0, d1))).toBe(nil) -- the gap between rows
		t.expect((Formation.hitAt(f, x0 - 1, d0))).toBe(nil)
		Formation.kill(f, 2, 4)
		t.expect((Formation.hitAt(f, x0, d0))).toBe(nil)
	end)

	it("names a column's front-most living alien, and the living columns", function()
		local f = Formation.new(C, 120)
		t.expect(Formation.front(f, 7)).toBe(1)
		Formation.kill(f, 1, 7)
		Formation.kill(f, 2, 7)
		t.expect(Formation.front(f, 7)).toBe(3)
		killColumn(f, 7)
		t.expect(Formation.front(f, 7)).toBe(nil)
		t.expect(Formation.columns(f)).toEqual({ 1, 2, 3, 4, 5, 6, 8, 9, 10, 11 })
	end)

	it("never moves once empty", function()
		local f = Formation.new(C, 120)
		for col = 1, 11 do
			killColumn(f, col)
		end
		t.expect(f.live).toBe(0)
		for _ = 1, 100 do
			t.expect(Formation.tick(f)).toBe(nil)
		end
		t.expect((Formation.extent(f))).toBe(nil)
	end)
end)
