--!strict
-- c0153: a frame is "plain data" when it is made of nil, booleans, finite numbers, strings and plain tables (no
-- functions, userdata, threads, metatables or cycles), and it survives a JSON round trip up to a number tolerance:
-- Lune's encoder keeps about 16 significant digits, so a position such as 13.783333333333333 comes back one ulp off.
-- `plain` (pickman/tests/lib/plain.luau) is the one helper for it, and f0032's frame case uses it.
local fs = require("@lune/fs")
local plain = require("@tests/lib/plain")
local t = require("@tests/lib/t")

local EPS = 1e-9

return t.spec("c0153 plain data and a JSON round trip within a tolerance", function(it)
	it("the value that came back one ulp off round-trips within the tolerance", function()
		local frame =
			{ ghosts = { { name = "blinky", x = 13.783333333333333, y = 11, flash = false } }, tick = 61 }
		t.expect((plain.roundTrip(frame, EPS))).toBe(true)
	end)

	it("equalWithin accepts numbers within the tolerance and refuses them beyond it", function()
		t.expect((plain.equalWithin({ x = 1 }, { x = 1 + 1e-12 }, EPS))).toBe(true)
		t.expect((plain.equalWithin({ x = 1 }, { x = 1 + 1e-6 }, EPS))).toBe(false)
		t.expect((plain.equalWithin({ x = 1 }, { x = 1 }, 0))).toBe(true)
	end)

	it("equalWithin refuses a missing key, an extra key, a changed type and a different array", function()
		t.expect((plain.equalWithin({ a = 1, b = 2 }, { a = 1 }, EPS))).toBe(false)
		t.expect((plain.equalWithin({ a = 1 }, { a = 1, b = 2 }, EPS))).toBe(false)
		t.expect((plain.equalWithin({ a = 1 }, { a = "1" }, EPS))).toBe(false)
		t.expect((plain.equalWithin({ 1, 2, 3 }, { 1, 2 }, EPS))).toBe(false)
		t.expect((plain.equalWithin({ a = { b = true } }, { a = { b = false } }, EPS))).toBe(false)
	end)

	it(
		"check refuses functions, threads, metatables, cycles and NaN or infinite numbers, and says where",
		function()
			local cyc: any = {}
			cyc.self = cyc
			local bads: { any } = {
				{ f = function() end } :: any,
				{ co = coroutine.create(function() end) } :: any,
				setmetatable({}, {}) :: any,
				cyc,
				{ nan = 0 / 0 } :: any,
				{ big = math.huge } :: any,
			}
			for _, bad in bads do
				local ok, why = plain.check(bad)
				t.expect(ok).toBe(false)
				t.expect(type(why)).toBe("string")
			end
			t.expect((plain.check({ a = 1, b = "x", c = { true, false }, d = nil }))).toBe(true)
		end
	)

	it("roundTrip refuses what is not plain data, even when the encoder would accept it", function()
		t.expect((plain.roundTrip({ big = math.huge }, EPS))).toBe(false)
		t.expect((plain.roundTrip(setmetatable({ a = 1 }, {}), EPS))).toBe(false)
	end)

	it("f0032's frame case uses the helper, not an exact comparison of the decoded frame", function()
		local src = fs.readFile("tests/acceptance/f0032/frame.spec.luau")
		t.expect(string.find(src, "plain.roundTrip(frame", 1, true) ~= nil).toBe(true)
		t.expect((string.find(src, 'serde.decode("json", text)).toEqual(frame)', 1, true))).toBe(nil)
	end)
end)
