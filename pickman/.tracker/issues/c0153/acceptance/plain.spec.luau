--!strict
-- c0153 AC1: `plain` (pickman/tests/lib/plain.luau) is the one helper for "plain data that survives a JSON round
-- trip". Plain data is nil, booleans, finite numbers, strings, and tables without a metatable or a cycle that are a
-- sequence (number keys exactly 1..n) or a map (string keys only). Lune's JSON decoder can return a number one ulp
-- off (it reads 13.783333333333333, as the encoder writes it, as 13.783333333333331): numbers are compared within a
-- tolerance, and NaN (or a NaN tolerance) is never within it. Every refusal says where, and roundTrip returns false, never raises.
local plain = require("@tests/lib/plain")
local t = require("@tests/lib/t")

local EPS = 1e-9

local function starts(text: string?, prefix: string): boolean
	return type(text) == "string" and string.sub(text, 1, #prefix) == prefix
end

return t.spec("c0153 plain data and a JSON round trip within a tolerance", function(it)
	it(
		"the value that came back one ulp off round-trips within the tolerance, and differs with none",
		function()
			local frame =
				{ ghosts = { { name = "blinky", x = 13.783333333333333, y = 11, flash = false } }, tick = 61 }
			t.expect({ plain.roundTrip(frame, EPS) }).toEqual({ true })
			-- and the round trip really compares what came back: with no tolerance, the lost ulp is a difference
			-- this depends on Lune 0.10.5's decoder (rokit.toml) losing that ulp: if an upgrade decodes it exactly, update this
			-- subcase to another lossy value; it is not a regression
			local exact, why = plain.roundTrip(frame, 0)
			t.expect(exact).toBe(false)
			t.expect(starts(why, "value.ghosts.1.x: ")).toBe(true)
		end
	)

	it("equalWithin accepts numbers within the tolerance and refuses them beyond it", function()
		t.expect((plain.equalWithin({ x = 1 }, { x = 1 + 1e-12 }, EPS))).toBe(true)
		t.expect((plain.equalWithin({ x = 1 }, { x = 1 + 1e-6 }, EPS))).toBe(false)
		t.expect((plain.equalWithin({ x = 1 }, { x = 1 }, 0))).toBe(true)
	end)

	it("NaN is never within the tolerance, and a NaN tolerance accepts nothing", function()
		t.expect((plain.equalWithin(0 / 0, 0 / 0, EPS))).toBe(false)
		t.expect((plain.equalWithin(0 / 0, 5, EPS))).toBe(false)
		t.expect((plain.equalWithin(5, 0 / 0, EPS))).toBe(false)
		t.expect((plain.equalWithin(1, 2, 0 / 0))).toBe(false)
		t.expect((plain.equalWithin(1, 1, 0 / 0))).toBe(false)
	end)

	it(
		"equalWithin refuses a missing key, an extra key, a changed type and a different array, and says where",
		function()
			local _, missing = plain.equalWithin({ a = 1, b = 2 }, { a = 1 }, EPS)
			t.expect(missing).toBe("value.b: number against nil")
			local _, extra = plain.equalWithin({ a = 1 }, { a = 1, b = 2 }, EPS)
			t.expect(extra).toBe("value.b: missing on the left")
			t.expect((plain.equalWithin({ a = 1 }, { a = "1" }, EPS))).toBe(false)
			t.expect((plain.equalWithin({ 1, 2, 3 }, { 1, 2 }, EPS))).toBe(false)
			local _, deep = plain.equalWithin({ a = { b = true } }, { a = { b = false } }, EPS)
			t.expect(deep).toBe("value.a.b: true against false")
		end
	)

	it(
		"check refuses functions, threads, metatables, cycles and NaN or infinite numbers, and says where",
		function()
			local cyc: any = {}
			cyc.self = cyc
			local bads: { { value: any, says: string } } = {
				{ value = { f = function() end }, says = "value.f: a function" },
				{ value = { co = coroutine.create(function() end) }, says = "value.co: a thread" },
				{ value = setmetatable({}, {}), says = "value: a table with a metatable" },
				{ value = cyc, says = "value.self: a cycle" },
				{ value = { nan = 0 / 0 }, says = "value.nan: " },
				{
					value = { ghosts = { { x = math.huge } } },
					says = "value.ghosts.1.x: inf is not a finite number",
				},
			}
			for _, bad in bads do
				local ok, why = plain.check(bad.value)
				t.expect(ok).toBe(false)
				t.expect(starts(why, bad.says)).toBe(true)
			end
			local _, nan = plain.check({ nan = 0 / 0 })
			t.expect(type(nan) == "string" and string.find(nan, "is not a finite number", 1, true) ~= nil)
				.toBe(true)
		end
	)

	it(
		"a table is a sequence 1..n or a string-keyed map: holes, sparse, odd number keys and mixed tables are refused",
		function()
			local holed: { [number]: number } = {}
			holed[1] = 1
			holed[3] = 3
			local bads: { { value: any, says: string } } = {
				{ value = { ghosts = holed }, says = "value.ghosts: a hole at 2" },
				{ value = { [1] = "a", [3] = "b" }, says = "value: a hole at 2" },
				{ value = { [2] = "x" }, says = "value: a hole at 1" },
				{ value = { [0] = "x" }, says = "value: a hole at 1" },
				{ value = { [-1] = "x" }, says = "value: a hole at 1" },
				{ value = { [1.5] = "x" }, says = "value: a hole at 1" },
				-- selene: allow(mixed_table) -- a mixed table is the value this case refuses
				{ value = { 1, 2, a = 3 }, says = "value: a table with both string and number keys" },
				{ value = { [true :: any] = 1 }, says = "value: a boolean key" },
			}
			for _, bad in bads do
				local ok, why = plain.check(bad.value)
				t.expect(ok).toBe(false)
				t.expect(starts(why, bad.says)).toBe(true)
				local done, trip = pcall(plain.roundTrip :: any, bad.value, EPS)
				t.expect(done).toBe(true)
				t.expect(trip).toBe(false)
			end
		end
	)

	it(
		"plain data is accepted: empty tables, sequences, maps, their nesting, and a table reached twice (not a cycle)",
		function()
			t.expect({ plain.check({}) }).toEqual({ true })
			t.expect({ plain.check({ a = {}, b = { {}, {} } }) }).toEqual({ true })
			local shared = { x = 1 }
			t.expect({ plain.check({ a = shared, b = { shared, shared } }) }).toEqual({ true })
			t.expect({ plain.roundTrip({ a = shared, b = { shared, shared } }, EPS) }).toEqual({ true })
			t.expect({ plain.check({ a = 1, b = "x", c = { true, false }, d = nil }) }).toEqual({ true })
			t.expect({ plain.roundTrip({ ghosts = { { x = 1.5 }, { x = 2 } }, play = { lives = 3 } }, EPS) })
				.toEqual({ true })
		end
	)

	it("roundTrip refuses what is not plain data, and what the encoder refuses, without raising", function()
		t.expect((plain.roundTrip({ big = math.huge }, EPS))).toBe(false)
		t.expect((plain.roundTrip(setmetatable({ a = 1 }, {}), EPS))).toBe(false)
		local done, ok, why = pcall(plain.roundTrip :: any, { a = "\xff" }, EPS)
		t.expect(done).toBe(true)
		t.expect(ok).toBe(false)
		t.expect(starts(why, "value: the JSON round trip failed")).toBe(true)
	end)
end)
