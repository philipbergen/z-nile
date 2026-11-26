--!strict
-- f0203 AC1: arcade's seeded Rng (Park-Miller over a plain-data generator; a stream picks the sequence).
local Rng = require("@logic/Rng")
local t = require("@tests/lib/t")

local M = 2147483647

local function draws(g: Rng.Generator, n: number, count: number): { number }
	local out = {}
	for _ = 1, count do
		table.insert(out, Rng.int(g, n))
	end
	return out
end

return t.spec("f0203 Rng", function(it)
	it("the default stream from seed 42 gives the minimal-standard sequence", function()
		local g = Rng.new(42)
		t.expect(g.state).toBe(43)
		t.expect(draws(g, 1000, 8)).toEqual({ 654, 202, 924, 806, 237, 194, 690, 717 })
		t.expect(Rng.MODULUS).toBe(M)
		t.expect(Rng.STREAM).toEqual({ multiplier = 48271, mix = 1, offset = 0 })
	end)

	it(
		"a stream's multiplier, mix and offset pick the sequence (pickman's ghosts, picks and blaster streams)",
		function()
			local ghosts = Rng.new(2024, { multiplier = 16807, mix = 1, offset = 0 })
			t.expect(ghosts.state).toBe(2025)
			t.expect(draws(ghosts, 97, 6)).toEqual({ 77, 13, 52, 19, 55, 50 })
			local picks = Rng.new(2024, { multiplier = 48271, mix = 69621, offset = 7 })
			t.expect(picks.state).toBe(140912912)
			t.expect(draws(picks, 97, 6)).toEqual({ 62, 10, 55, 43, 7, 10 })
			local blaster = Rng.new(2024, { multiplier = 16807, mix = 48271, offset = 11 })
			t.expect(blaster.state).toBe(97700516)
			t.expect(draws(blaster, 97, 6)).toEqual({ 22, 64, 13, 26, 46, 87 })
		end
	)

	it("the same seed and stream give the same sequence; another seed gives another", function()
		t.expect(draws(Rng.new(9), 50, 40)).toEqual(draws(Rng.new(9), 50, 40))
		local a, b = draws(Rng.new(9), 1000, 10), draws(Rng.new(10), 1000, 10)
		local same = 0
		for i = 1, 10 do
			same += if a[i] == b[i] then 1 else 0
		end
		t.expect(same < 10).toBe(true)
	end)

	it("int draws whole numbers in 1..n and reaches every one of them", function()
		local g = Rng.new(5)
		for n = 1, 12 do
			local seen: { [number]: boolean } = {}
			for _ = 1, 400 do
				local k = Rng.int(g, n)
				t.expect(k >= 1 and k <= n and k == math.floor(k)).toBe(true)
				seen[k] = true
			end
			for k = 1, n do
				t.expect(seen[k]).toBe(true)
			end
		end
	end)

	it("int refuses an n that is not a whole number of at least 1", function()
		local g = Rng.new(1)
		for _, n in { 0, -3, 2.5, 0 / 0, math.huge } do
			t.expect(function()
				Rng.int(g, n)
			end).toThrow("Rng.int")
		end
	end)

	it("float is the advanced state scaled into [0, 1)", function()
		local g = Rng.new(42)
		t.expect(Rng.float(g)).toBe((2075653 - 1) / (M - 1))
		t.expect(g.state).toBe(2075653)
		for _ = 1, 2000 do
			local f = Rng.float(g)
			t.expect(f >= 0 and f < 1).toBe(true)
		end
	end)

	it("draw hands out a function that draws from, and advances, the same generator", function()
		local g, twin = Rng.new(77), Rng.new(77)
		local draw = Rng.draw(g)
		for i = 1, 30 do
			local n = (i % 7) + 1
			t.expect(draw(n)).toBe(Rng.int(twin, n))
		end
		t.expect(g.state).toBe(twin.state)
		t.expect(Rng.int(g, 1000)).toBe(Rng.int(twin, 1000))
	end)

	it("a generator is plain data: a copy continues the same sequence", function()
		local g = Rng.new(31)
		Rng.int(g, 10)
		for _, v in g :: any do
			t.expect(type(v)).toBe("number")
		end
		local copy = table.clone(g)
		t.expect(draws(copy, 1000, 12)).toEqual(draws(g, 1000, 12))
	end)

	it("a seed that is not a finite number counts as 0, and a fraction is floored", function()
		t.expect(Rng.new(0 / 0).state).toBe(Rng.new(0).state)
		t.expect(Rng.new(math.huge).state).toBe(1)
		t.expect(Rng.new(-math.huge).state).toBe(1)
		t.expect(draws(Rng.new(4.6), 100, 10)).toEqual(draws(Rng.new(4), 100, 10))
	end)

	it("a negative seed and a huge seed land in 1..MODULUS-1, exactly", function()
		t.expect(Rng.new(-7).state).toBe(2147483640)
		-- the seed is reduced before it is mixed, so a product past 2^53 never loses precision
		t.expect(Rng.new(2 ^ 40 + 3, { multiplier = 48271, mix = 69621, offset = 7 }).state).toBe(71500775)
	end)

	it("the state stays in 1..MODULUS-1 and whole on every stream", function()
		for _, st in
			{
				Rng.STREAM,
				{ multiplier = 16807, mix = 1, offset = 0 },
				{ multiplier = 2 ^ 21 - 1, mix = 2 ^ 21 - 1, offset = -(M - 1) },
			}
		do
			local g = Rng.new(123456789, st)
			for _ = 1, 3000 do
				Rng.int(g, 6)
				t.expect(g.state >= 1 and g.state <= M - 1 and g.state == math.floor(g.state)).toBe(true)
			end
		end
	end)

	it(
		"new refuses a stream that is not whole or whose products could leave a double's exact range",
		function()
			local bads: { { number } } = {
				{ 16807.5, 1, 0 }, -- the multiplier is not whole
				{ 1, 1, 0 }, -- the multiplier is below 2
				{ 2 ^ 21, 1, 0 }, -- the multiplier is 2^21 or more
				{ 16807, 1.5, 0 }, -- the mix is not whole
				{ 16807, 0, 0 }, -- the mix is below 1 (every seed would give one sequence)
				{ 16807, -1, 0 },
				{ 16807, 2 ^ 21, 0 }, -- the mix is 2^21 or more
				{ 16807, 1, 0.5 }, -- the offset is not whole
				{ 16807, 1, M }, -- the offset is not below the modulus in size
				{ 16807, 1, -M },
				{ 0 / 0, 1, 0 },
			}
			for _, b in bads do
				t.expect(function()
					Rng.new(1, { multiplier = b[1], mix = b[2], offset = b[3] })
				end).toThrow("Rng.new")
			end
			t.expect(Rng.new(1, { multiplier = 2 ^ 21 - 1, mix = 1, offset = -(M - 1) }).state >= 1)
				.toBe(true)
		end
	)
end)
