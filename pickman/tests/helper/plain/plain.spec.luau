--!strict
-- R0059 code review 001 F1: the cases c0153's sequestered plain.spec leaves out. Negative infinity is not plain (as
-- positive infinity and NaN are not), and equalWithin compares strings exactly at any tolerance, so a round trip that
-- changed a string is a difference.
local plain = require("@tests/lib/plain")
local t = require("@tests/lib/t")

return t.spec("plain: negative infinity and strings", function(it)
	it("negative infinity is not plain, and says where", function()
		local ok, why = plain.check({ x = -math.huge })
		t.expect(ok).toBe(false)
		t.expect(why).toBe("value.x: -inf is not a finite number")
		t.expect((plain.roundTrip({ x = -math.huge }, 1e-9))).toBe(false)
	end)

	it("two different strings differ at any tolerance, and equal strings match at none", function()
		local same, why = plain.equalWithin({ name = "blinky" }, { name = "inky" }, 1e9)
		t.expect(same).toBe(false)
		t.expect(why).toBe("value.name: blinky against inky")
		t.expect({ plain.equalWithin({ name = "blinky" }, { name = "blinky" }, 0) }).toEqual({ true })
		local diff, says = plain.equalWithin("a", "b", 1)
		t.expect(diff).toBe(false)
		t.expect(says).toBe("value: a against b")
	end)
end)
