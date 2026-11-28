--!strict
-- Maps unit specs: turn, step, wallTiles, spawnTiles, wallCount, wallMax, nearMiddle, and argument validation.
local Maps = require("@logic/Maps")
local t = require("@tests/lib/t")

local function fixedDraw(n: number): number
	return if n >= 1 then 1 else error("bad n")
end

return t.spec("Maps unit", function(it)
	it("maps all four headings to step vectors", function()
		t.expect(Maps.step("N")).toEqual({ x = 0, y = -1 })
		t.expect(Maps.step("E")).toEqual({ x = 1, y = 0 })
		t.expect(Maps.step("S")).toEqual({ x = 0, y = 1 })
		t.expect(Maps.step("W")).toEqual({ x = -1, y = 0 })
	end)

	it("turns all eight heading and side pairs", function()
		t.expect(Maps.turn("N", "Left")).toBe("W")
		t.expect(Maps.turn("N", "Right")).toBe("E")
		t.expect(Maps.turn("E", "Left")).toBe("N")
		t.expect(Maps.turn("E", "Right")).toBe("S")
		t.expect(Maps.turn("S", "Left")).toBe("E")
		t.expect(Maps.turn("S", "Right")).toBe("W")
		t.expect(Maps.turn("W", "Left")).toBe("S")
		t.expect(Maps.turn("W", "Right")).toBe("N")
	end)

	it("expands horizontal and vertical wallTiles in order", function()
		t.expect(Maps.wallTiles({ x = 3, y = 4, dir = "H", length = 3 })).toEqual({
			{ x = 3, y = 4 },
			{ x = 4, y = 4 },
			{ x = 5, y = 4 },
		})
		t.expect(Maps.wallTiles({ x = 3, y = 4, dir = "V", length = 3 })).toEqual({
			{ x = 3, y = 4 },
			{ x = 3, y = 5 },
			{ x = 3, y = 6 },
		})
	end)

	it("expands all seven spawnTiles across all four headings", function()
		t.expect(Maps.spawnTiles({ x = 5, y = 5, heading = "N" })).toEqual({
			{ x = 5, y = 5 },
			{ x = 5, y = 6 },
			{ x = 5, y = 7 },
			{ x = 5, y = 8 },
			{ x = 5, y = 4 },
			{ x = 5, y = 3 },
			{ x = 5, y = 2 },
		})
		t.expect(Maps.spawnTiles({ x = 5, y = 5, heading = "E" })).toEqual({
			{ x = 5, y = 5 },
			{ x = 4, y = 5 },
			{ x = 3, y = 5 },
			{ x = 2, y = 5 },
			{ x = 6, y = 5 },
			{ x = 7, y = 5 },
			{ x = 8, y = 5 },
		})
		t.expect(Maps.spawnTiles({ x = 5, y = 5, heading = "S" })).toEqual({
			{ x = 5, y = 5 },
			{ x = 5, y = 4 },
			{ x = 5, y = 3 },
			{ x = 5, y = 2 },
			{ x = 5, y = 6 },
			{ x = 5, y = 7 },
			{ x = 5, y = 8 },
		})
		t.expect(Maps.spawnTiles({ x = 5, y = 5, heading = "W" })).toEqual({
			{ x = 5, y = 5 },
			{ x = 6, y = 5 },
			{ x = 7, y = 5 },
			{ x = 8, y = 5 },
			{ x = 4, y = 5 },
			{ x = 3, y = 5 },
			{ x = 2, y = 5 },
		})
	end)

	it("computes wallCount and wallMax", function()
		t.expect(Maps.wallCount(1)).toBe(0)
		t.expect(Maps.wallCount(2)).toBe(1)
		t.expect(Maps.wallCount(6)).toBe(5)
		t.expect(Maps.wallMax(9)).toBe(4)
		t.expect(Maps.wallMax(11)).toBe(4)
		t.expect(Maps.wallMax(20)).toBe(6)
		t.expect(Maps.wallMax(79)).toBe(26)
	end)

	it("checks nearMiddle for H and V walls on even and odd sides", function()
		-- Even side = 20 -> center = 10.5, reach = 2
		t.expect(Maps.nearMiddle({ x = 8, y = 10, dir = "H", length = 3 }, 20)).toBe(true)
		t.expect(Maps.nearMiddle({ x = 7, y = 10, dir = "H", length = 3 }, 20)).toBe(false)
		t.expect(Maps.nearMiddle({ x = 9, y = 8, dir = "H", length = 3 }, 20)).toBe(false)
		t.expect(Maps.nearMiddle({ x = 10, y = 8, dir = "V", length = 3 }, 20)).toBe(true)
		t.expect(Maps.nearMiddle({ x = 8, y = 9, dir = "V", length = 3 }, 20)).toBe(false)
		t.expect(Maps.nearMiddle({ x = 10, y = 7, dir = "V", length = 3 }, 20)).toBe(false)
		-- Odd side = 21 -> center = 11, reach = 2
		t.expect(Maps.nearMiddle({ x = 8, y = 9, dir = "H", length = 3 }, 21)).toBe(true)
		t.expect(Maps.nearMiddle({ x = 7, y = 11, dir = "H", length = 3 }, 21)).toBe(false)
		t.expect(Maps.nearMiddle({ x = 10, y = 8, dir = "H", length = 3 }, 21)).toBe(false)
		t.expect(Maps.nearMiddle({ x = 13, y = 12, dir = "V", length = 3 }, 21)).toBe(true)
		t.expect(Maps.nearMiddle({ x = 14, y = 10, dir = "V", length = 3 }, 21)).toBe(false)
		t.expect(Maps.nearMiddle({ x = 11, y = 13, dir = "V", length = 3 }, 21)).toBe(false)
	end)

	it("rejects invalid counts on all six validated functions", function()
		local bad: { any } = { 0, -1, 1.5, 0 / 0, math.huge, "1" }
		for _, v in bad do
			t.expect(function()
				Maps.side(v)
			end).toThrow("Maps.side")
			t.expect(function()
				Maps.speed(v)
			end).toThrow("Maps.speed")
			t.expect(function()
				Maps.goal(v)
			end).toThrow("Maps.goal")
			t.expect(function()
				Maps.wallCount(v)
			end).toThrow("Maps.wallCount")
			t.expect(function()
				Maps.spawns(v, 1)
			end).toThrow("Maps.spawns")
			t.expect(function()
				Maps.spawns(20, v)
			end).toThrow("Maps.spawns")
			t.expect(function()
				Maps.roll(v, 1, fixedDraw)
			end).toThrow("Maps.roll")
			t.expect(function()
				Maps.roll(1, v, fixedDraw)
			end).toThrow("Maps.roll")
		end
	end)
end)
