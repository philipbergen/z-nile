--!strict
-- f0201 AC1: PaidPlay's rules, pure. One free start per rolling hour per title and player, recorded at the claim;
-- else one held play; else "buy" with nothing changed. A receipt id grants once and the last RECEIPTS_KEPT are kept,
-- the oldest dropped first; a refund is its own credit outside the receipts; a held revive is used once. A stored
-- record is read defensively and stored in f0145's shape (its `continues` are the revives). An arrival plays when charged or when the claim's
-- write failed, and a "buy" plays only with the portal's pass. Nothing mutates the record it is given.
local PaidPlay = require("@logic/PaidPlay")
local t = require("@tests/lib/t")

local NOW = 1792108800

-- a record as PaidPlay works on it (not as stored: see PaidPlay.stored)
local function rec(fields: { [string]: any }?): PaidPlay.Record
	local f: { [string]: any } = fields or {}
	return { free = f.free, plays = f.plays or 0, revives = f.revives or 0, receipts = f.receipts or {} }
end

return t.spec("f0201 PaidPlay rules", function(it)
	it("the constants: a rolling hour, 1 R$, 50 receipts kept, live is exactly 'live'", function()
		t.expect(PaidPlay.FREE_SECONDS).toBe(3600)
		t.expect(PaidPlay.PRICE).toBe(1)
		t.expect(PaidPlay.RECEIPTS_KEPT).toBe(50)
		t.expect(PaidPlay.LIVE).toBe("live")
	end)

	it("a stored record is read defensively: nil or broken fields are a new player's", function()
		t.expect(PaidPlay.record(nil)).toEqual({ plays = 0, revives = 0, receipts = {} })
		t.expect(PaidPlay.record("x")).toEqual({ plays = 0, revives = 0, receipts = {} })
		local r =
			PaidPlay.record({ free = -5, plays = 1.5, continues = -1, receipts = { "a", 3 :: any, "", "b" } })
		t.expect(r.free).toBe(nil)
		t.expect(r.plays).toBe(0)
		t.expect(r.revives).toBe(0)
		t.expect(r.receipts).toEqual({ "a", "b" })
		t.expect(PaidPlay.record({ free = 0 / 0, plays = math.huge }).plays).toBe(0)
		t.expect(PaidPlay.record({ free = 0 / 0 }).free).toBe(nil)
		local good = PaidPlay.record({ free = NOW, plays = 2, continues = 3, receipts = { "r1" } })
		t.expect(good).toEqual({ free = NOW, plays = 2, revives = 3, receipts = { "r1" } })
	end)

	it(
		"the stored shape is f0145's: revives stored as continues, exactly four fields, read back as they were",
		function()
			local r = rec({ free = NOW, plays = 1, revives = 2, receipts = { "a" } })
			local stored = PaidPlay.stored(r)
			t.expect(stored).toEqual({ free = NOW, plays = 1, continues = 2, receipts = { "a" } })
			local keys = {}
			for k in stored :: any do
				table.insert(keys, k)
			end
			table.sort(keys)
			t.expect(keys).toEqual({ "continues", "free", "plays", "receipts" })
			t.expect(PaidPlay.record(stored)).toEqual(r)
			local f0145 = { free = NOW - 10, plays = 3, continues = 1, receipts = { "x", "y" } }
			t.expect(PaidPlay.stored(PaidPlay.record(f0145))).toEqual(f0145)
			t.expect(PaidPlay.record({ revives = 4 }).revives).toBe(0) -- only continues are read
			t.expect(PaidPlay.stored(r).receipts == r.receipts).toBe(false)
		end
	)

	it(
		"the first start is free and records its instant; the next is due a full hour later, not a second sooner",
		function()
			local s, r = PaidPlay.start(rec(), NOW)
			t.expect(s).toBe("free")
			t.expect(r.free).toBe(NOW)
			t.expect(PaidPlay.freeDue(r, NOW + 3599)).toBe(false)
			t.expect(PaidPlay.freeDue(r, NOW + 3600)).toBe(true)
			local s2, r2 = PaidPlay.start(r, NOW + 3599)
			t.expect(s2).toBe("buy")
			t.expect(r2).toEqual(r)
			local s3, r3 = PaidPlay.start(r, NOW + 3600)
			t.expect(s3).toBe("free")
			t.expect(r3.free).toBe(NOW + 3600)
		end
	)

	it("a clock behind the recorded free start waits; an instant that is not whole never grants", function()
		local r = rec({ free = NOW })
		t.expect(PaidPlay.freeDue(r, NOW - 7200)).toBe(false)
		t.expect(PaidPlay.freeDue(rec(), NOW + 0.5)).toBe(false)
		t.expect(PaidPlay.freeDue(rec(), 0 / 0)).toBe(false)
		t.expect((PaidPlay.start(rec(), NOW + 0.5))).toBe("buy")
	end)

	it(
		"with no free start due a held play is used, one at a time; with none the answer is buy and nothing changes",
		function()
			local r = rec({ free = NOW, plays = 2 })
			local s, r2 = PaidPlay.start(r, NOW + 10)
			t.expect(s).toBe("credit")
			t.expect(r2.plays).toBe(1)
			t.expect(r2.free).toBe(NOW)
			local s3, r3 = PaidPlay.start(r2, NOW + 11)
			t.expect(s3).toBe("credit")
			t.expect(r3.plays).toBe(0)
			local s4, r4 = PaidPlay.start(r3, NOW + 12)
			t.expect(s4).toBe("buy")
			t.expect(r4).toEqual(r3)
		end
	)

	it("a free start due is used before a held play", function()
		local s, r = PaidPlay.start(rec({ plays = 1 }), NOW)
		t.expect(s).toBe("free")
		t.expect(r.plays).toBe(1)
	end)

	it("nothing mutates the record it is given", function()
		local r = rec({ free = NOW, plays = 1, revives = 1, receipts = { "a" } })
		local before =
			rec({ free = r.free, plays = r.plays, revives = r.revives, receipts = table.clone(r.receipts) })
		PaidPlay.start(r, NOW + 10)
		PaidPlay.start(r, NOW + 7200)
		PaidPlay.grant(r, "play", "b")
		PaidPlay.refund(r, "revive")
		PaidPlay.useRevive(r)
		t.expect(r).toEqual(before)
	end)

	it(
		"a receipt is granted once: the same id again grants nothing; each kind adds its own credit",
		function()
			local r1, fresh1 = PaidPlay.grant(rec(), "play", "p1")
			t.expect(fresh1).toBe(true)
			t.expect(r1.plays).toBe(1)
			t.expect(r1.revives).toBe(0)
			local r2, fresh2 = PaidPlay.grant(r1, "play", "p1")
			t.expect(fresh2).toBe(false)
			t.expect(r2.plays).toBe(1)
			local r3, fresh3 = PaidPlay.grant(r2, "revive", "p2")
			t.expect(fresh3).toBe(true)
			t.expect(r3.revives).toBe(1)
			t.expect(r3.plays).toBe(1)
			t.expect(r3.receipts).toEqual({ "p1", "p2" })
			local r4, fresh4 = PaidPlay.grant(r3, "play", "")
			t.expect(fresh4).toBe(false)
			t.expect(r4.plays).toBe(1)
		end
	)

	it("only the latest RECEIPTS_KEPT receipt ids are kept, oldest dropped first", function()
		local r = rec()
		for i = 1, PaidPlay.RECEIPTS_KEPT + 2 do
			r = PaidPlay.grant(r, "play", `r{i}`)
		end
		t.expect(#r.receipts).toBe(PaidPlay.RECEIPTS_KEPT)
		t.expect(r.receipts[1]).toBe("r3")
		t.expect(r.receipts[PaidPlay.RECEIPTS_KEPT]).toBe(`r{PaidPlay.RECEIPTS_KEPT + 2}`)
		t.expect(r.plays).toBe(PaidPlay.RECEIPTS_KEPT + 2)
	end)

	it("a refund is its own credit: each one counts, and none takes a receipt slot", function()
		local r = PaidPlay.refund(PaidPlay.refund(rec({ receipts = { "a" } }), "revive"), "revive")
		t.expect(r.revives).toBe(2)
		t.expect(r.receipts).toEqual({ "a" })
		t.expect(PaidPlay.refund(rec(), "play").plays).toBe(1)
	end)

	it("a held revive is used once; with none held nothing changes", function()
		local used, r = PaidPlay.useRevive(rec({ revives = 1 }))
		t.expect(used).toBe(true)
		t.expect(r.revives).toBe(0)
		local again, r2 = PaidPlay.useRevive(r)
		t.expect(again).toBe(false)
		t.expect(r2).toEqual(r)
	end)

	it("the status says whether a free start is due, when the next is, and the credits held", function()
		t.expect(PaidPlay.status(rec({ plays = 1 }), NOW)).toEqual({ free = true, plays = 1, revives = 0 })
		t.expect(PaidPlay.status(rec({ free = NOW, revives = 2 }), NOW + 60)).toEqual({
			free = false,
			nextFree = NOW + 3600,
			plays = 0,
			revives = 2,
		})
	end)

	it(
		"an arrival plays when charged or when the claim failed; a buy plays only with the portal's pass",
		function()
			t.expect(PaidPlay.arrive("free", false)).toBe("play")
			t.expect(PaidPlay.arrive("credit", false)).toBe("play")
			t.expect(PaidPlay.arrive(nil, false)).toBe("play")
			t.expect(PaidPlay.arrive("buy", false)).toBe("back")
			t.expect(PaidPlay.arrive("buy", true)).toBe("play")
		end
	)
end)
