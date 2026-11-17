--!strict
local Pay = require("@logic/Pay")
local t = require("@tests/lib/t")

local NOW = 1792108800

return t.spec("Pay", function(it)
	it("a new player's first start is free, the next within the hour is a purchase", function()
		local how, r = Pay.start(Pay.record(nil), NOW)
		t.expect(how).toBe("free")
		t.expect((Pay.start(r, NOW + 60))).toBe("buy")
	end)

	it("a play bought is held and then used by a start", function()
		local _, r = Pay.start(Pay.record(nil), NOW)
		local held = (Pay.grant(r, "play", "R1"))
		local how, used = Pay.start(held, NOW + 60)
		t.expect(how).toBe("credit")
		t.expect(used.plays).toBe(0)
	end)

	it("a continue is used once, and a refund gives one back outside the receipts", function()
		local r = (Pay.grant(Pay.record(nil), "continue", "C1"))
		local ok, after = Pay.useContinue(r)
		t.expect(ok).toBe(true)
		local back = Pay.refund(after)
		t.expect(back.continues).toBe(1)
		t.expect(back.receipts).toEqual({ "C1" })
	end)

	it("the modes and their stores", function()
		t.expect(Pay.mode("live", { play = 1, continue = 2 })).toBe("live")
		t.expect(Pay.mode("live", { play = 1 })).toBe("closed")
		t.expect(Pay.mode(nil, nil)).toBe("test")
		t.expect(Pay.store("closed")).toBe(Pay.STORE)
		t.expect(Pay.store("test")).toBe(Pay.TEST_STORE)
	end)
end)
