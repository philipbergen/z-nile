--!strict
-- f0145 AC1: Logic/Pay, paid play engine-free. One free run per player per rolling hour (FREE_SECONDS from the start
-- of the latest free one; a clock behind it waits), then a start uses a play bought and held, else "buy" with nothing
-- spent. A purchase is granted once by its receipt id (the latest RECEIPTS_KEPT kept), as one held play or one held
-- continue, and a held continue is used once. The mode is "live" only for exactly "live": anything else never
-- charges. A broken stored record is a new player's. Nothing here mutates the record it is given.
local Pay = require("@logic/Pay")
local t = require("@tests/lib/t")

local NOW = 1792108800 -- a whole unix instant

local function fresh(): Pay.Record
	return Pay.record(nil)
end

return t.spec("f0145 Pay", function(it)
	it("the constants: an hour, 1 Robux, the store's name, the receipts kept", function()
		t.expect(Pay.FREE_SECONDS).toBe(3600)
		t.expect(Pay.PRICE).toBe(1)
		t.expect(Pay.STORE).toBe("PaidPlay")
		t.expect(Pay.RECEIPTS_KEPT).toBe(50)
	end)

	it('the mode is live only for exactly "live"; anything else is test', function()
		t.expect(Pay.mode("live")).toBe("live")
		for _, raw in { false, "", "Live", "LIVE", "test", true, 1, {} } :: { any } do
			t.expect(Pay.mode(raw)).toBe("test")
		end
		t.expect(Pay.mode(nil)).toBe("test")
	end)

	it("a stored record is read defensively: nil or broken fields are a new player's", function()
		local r = fresh()
		t.expect(r.free).toBe(nil)
		t.expect(r.plays).toBe(0)
		t.expect(r.continues).toBe(0)
		t.expect(#r.receipts).toBe(0)
		local broken = Pay.record({ free = "x", plays = -2, continues = 1.5, receipts = { "a", 3, "", "b" } })
		t.expect(broken.free).toBe(nil)
		t.expect(broken.plays).toBe(0)
		t.expect(broken.continues).toBe(0)
		t.expect(broken.receipts).toEqual({ "a", "b" })
		local kept = Pay.record({ free = NOW, plays = 2, continues = 1, receipts = { "r1" } })
		t.expect(kept.free).toBe(NOW)
		t.expect(kept.plays).toBe(2)
		t.expect(kept.continues).toBe(1)
		t.expect(kept.receipts).toEqual({ "r1" })
		t.expect(Pay.record("a string").plays).toBe(0)
	end)

	it(
		"the first start is free and records its instant; the next is due a full hour later, not a second sooner",
		function()
			local how, r = Pay.start(fresh(), NOW)
			t.expect(how).toBe("free")
			t.expect(r.free).toBe(NOW)
			t.expect((Pay.start(r, NOW + Pay.FREE_SECONDS - 1))).toBe("buy")
			local again, r2 = Pay.start(r, NOW + Pay.FREE_SECONDS)
			t.expect(again).toBe("free")
			t.expect(r2.free).toBe(NOW + Pay.FREE_SECONDS)
			-- rolling from the free start, not a clock hour: a start at 0:59 is not followed by a free one at 1:00
			local _, early = Pay.start(fresh(), NOW + 59 * 60)
			t.expect((Pay.start(early, NOW + 3600))).toBe("buy")
		end
	)

	it(
		"a clock behind the recorded free start (another server's) waits; a non-whole instant never grants",
		function()
			local _, r = Pay.start(fresh(), NOW)
			t.expect(Pay.freeDue(r, NOW - 10)).toBe(false)
			t.expect(Pay.freeDue(fresh(), 0 / 0)).toBe(false)
			t.expect(Pay.freeDue(fresh(), NOW + 0.5)).toBe(false)
			t.expect((Pay.start(fresh(), 0 / 0))).toBe("buy")
		end
	)

	it(
		"with no free start due a held play is used, one at a time; with none the answer is buy and nothing changes",
		function()
			local _, r = Pay.start(fresh(), NOW)
			local held = (Pay.grant((Pay.grant(r, "play", "g1")), "play", "g2"))
			local how, r2 = Pay.start(held, NOW + 60)
			t.expect(how).toBe("credit")
			t.expect(r2.plays).toBe(1)
			t.expect(r2.free).toBe(NOW) -- a bought play does not move the free hour
			local _, r3 = Pay.start(r2, NOW + 61)
			t.expect(r3.plays).toBe(0)
			local buy, r4 = Pay.start(r3, NOW + 62)
			t.expect(buy).toBe("buy")
			t.expect(r4.plays).toBe(0)
			t.expect(r4.free).toBe(NOW)
			t.expect(held.plays).toBe(2) -- never mutated
		end
	)

	it("a free start due is used before a held play", function()
		local how, r = Pay.start((Pay.grant(fresh(), "play", "g1")), NOW)
		t.expect(how).toBe("free")
		t.expect(r.plays).toBe(1)
	end)

	it("a purchase is the play or the continue product by its configured id, and nothing else", function()
		local products = { play = 111, continue = 222 }
		t.expect(Pay.product(111, products)).toBe("play")
		t.expect(Pay.product(222, products)).toBe("continue")
		t.expect(Pay.product(333, products)).toBe(nil)
		t.expect(Pay.product("111", products)).toBe(nil)
		t.expect(Pay.product(111, {})).toBe(nil)
		t.expect(Pay.product(nil, {})).toBe(nil)
	end)

	it(
		"a receipt is granted once: the same id again grants nothing; each product adds its own credit",
		function()
			local r, ok = Pay.grant(fresh(), "play", "p1")
			t.expect(ok).toBe(true)
			t.expect(r.plays).toBe(1)
			t.expect(r.continues).toBe(0)
			local again, ok2 = Pay.grant(r, "play", "p1")
			t.expect(ok2).toBe(false)
			t.expect(again.plays).toBe(1)
			local c, ok3 = Pay.grant(r, "continue", "p2")
			t.expect(ok3).toBe(true)
			t.expect(c.continues).toBe(1)
			t.expect(c.plays).toBe(1)
			t.expect((select(2, Pay.grant(r, "play", "")))).toBe(false)
			t.expect(r.receipts).toEqual({ "p1" }) -- never mutated
		end
	)

	it("only the latest RECEIPTS_KEPT receipt ids are kept, oldest dropped first", function()
		local r = fresh()
		for i = 1, Pay.RECEIPTS_KEPT + 3 do
			r = (Pay.grant(r, "play", `p{i}`))
		end
		t.expect(#r.receipts).toBe(Pay.RECEIPTS_KEPT)
		t.expect(r.receipts[1]).toBe("p4")
		t.expect(r.receipts[#r.receipts]).toBe(`p{Pay.RECEIPTS_KEPT + 3}`)
		t.expect(r.plays).toBe(Pay.RECEIPTS_KEPT + 3)
	end)

	it("a held continue is used once; with none held nothing changes", function()
		local r = (Pay.grant(fresh(), "continue", "c1"))
		local ok, r2 = Pay.useContinue(r)
		t.expect(ok).toBe(true)
		t.expect(r2.continues).toBe(0)
		local ok2, r3 = Pay.useContinue(r2)
		t.expect(ok2).toBe(false)
		t.expect(r3.continues).toBe(0)
		t.expect(r.continues).toBe(1)
	end)

	it("the status says whether a free start is due, when the next one is, and the credits held", function()
		local s0 = Pay.status(fresh(), NOW)
		t.expect(s0.free).toBe(true)
		t.expect(s0.nextFree).toBe(nil)
		local _, r = Pay.start(fresh(), NOW)
		r = (Pay.grant((Pay.grant(r, "play", "a")), "continue", "b"))
		local s1 = Pay.status(r, NOW + 600)
		t.expect(s1.free).toBe(false)
		t.expect(s1.nextFree).toBe(NOW + Pay.FREE_SECONDS)
		t.expect(s1.plays).toBe(1)
		t.expect(s1.continues).toBe(1)
		t.expect(Pay.status(r, NOW + Pay.FREE_SECONDS).free).toBe(true)
	end)
end)
