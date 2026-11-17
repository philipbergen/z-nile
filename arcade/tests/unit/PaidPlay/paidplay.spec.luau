--!strict
-- PaidPlay's unit spec (f0201): the cost model's rules, pure, through the feature's public API. The free hour, the
-- held plays, the receipt ledger, refunds and revives (AC1); the mode, the stores, the catalog's product map, the
-- test screen's lines and keys (AC2). The acceptance specs pin the same rules from the issue's side; these cases are
-- the feature's own.
local PaidPlay = require("@logic/PaidPlay")
local t = require("@tests/lib/t")

local T0 = 1800000000

local function rec(free: number?, plays: number?, revives: number?, receipts: { string }?): PaidPlay.Record
	return { free = free, plays = plays or 0, revives = revives or 0, receipts = receipts or {} }
end

local function entry(name: string): PaidPlay.Entry
	return {
		name = name,
		title = string.upper(name),
		store = name .. "Live",
		testStore = name .. "Test",
		play = name .. "Play",
		revive = name .. "Revive",
	}
end

local function reader(values: { [string]: any }): (string) -> any
	return function(attribute: string): any
		return values[attribute]
	end
end

return t.spec("PaidPlay", function(it)
	it("a new player's first start is free and records the instant", function()
		local s, r = PaidPlay.start(PaidPlay.record(nil), T0)
		t.expect(s).toBe("free")
		t.expect(r.free).toBe(T0)
	end)

	it("the next free start is due exactly FREE_SECONDS after the last, not a second sooner", function()
		local r = rec(T0)
		t.expect(PaidPlay.freeDue(r, T0 + PaidPlay.FREE_SECONDS - 1)).toBe(false)
		t.expect(PaidPlay.freeDue(r, T0 + PaidPlay.FREE_SECONDS)).toBe(true)
		t.expect(PaidPlay.freeDue(r, T0 + 10 * PaidPlay.FREE_SECONDS)).toBe(true)
	end)

	it("a clock behind the recorded start waits, and a non-whole or broken instant never grants", function()
		local r = rec(T0)
		t.expect(PaidPlay.freeDue(r, T0 - 5000)).toBe(false)
		t.expect(PaidPlay.freeDue(rec(nil), T0 + 0.5)).toBe(false)
		t.expect(PaidPlay.freeDue(rec(nil), 0 / 0)).toBe(false)
		t.expect(PaidPlay.freeDue(rec(nil), math.huge)).toBe(false)
		t.expect((PaidPlay.start(rec(nil), T0 + 0.5))).toBe("buy")
	end)

	it("within the hour a held play is used, one per start, and then the answer is buy", function()
		local s1, r1 = PaidPlay.start(rec(T0, 2), T0 + 10)
		t.expect(s1).toBe("credit")
		t.expect(r1.plays).toBe(1)
		t.expect(r1.free).toBe(T0)
		local s2, r2 = PaidPlay.start(r1, T0 + 20)
		t.expect(s2).toBe("credit")
		t.expect(r2.plays).toBe(0)
		local s3, r3 = PaidPlay.start(r2, T0 + 30)
		t.expect(s3).toBe("buy")
		t.expect(r3).toEqual(r2)
	end)

	it("a free start due is taken before a held play, which stays held", function()
		local s, r = PaidPlay.start(rec(T0, 3), T0 + PaidPlay.FREE_SECONDS)
		t.expect(s).toBe("free")
		t.expect(r.plays).toBe(3)
		t.expect(r.free).toBe(T0 + PaidPlay.FREE_SECONDS)
	end)

	it("no function changes the record it is given", function()
		local r = rec(T0, 1, 1, { "a" })
		local before = PaidPlay.stored(r)
		PaidPlay.start(r, T0 + 5)
		PaidPlay.start(r, T0 + PaidPlay.FREE_SECONDS)
		PaidPlay.grant(r, "play", "b")
		PaidPlay.refund(r, "revive")
		PaidPlay.useRevive(r)
		PaidPlay.stored(r)
		t.expect(PaidPlay.stored(r)).toEqual(before)
		t.expect(r.receipts).toEqual({ "a" })
	end)

	it("a receipt grants one credit of its kind, once per id; an empty id grants nothing", function()
		local r1, new1 = PaidPlay.grant(rec(), "play", "p1")
		t.expect(new1).toBe(true)
		t.expect(r1.plays).toBe(1)
		t.expect(r1.revives).toBe(0)
		local r2, new2 = PaidPlay.grant(r1, "play", "p1")
		t.expect(new2).toBe(false)
		t.expect(r2.plays).toBe(1)
		local r3, new3 = PaidPlay.grant(r2, "revive", "v1")
		t.expect(new3).toBe(true)
		t.expect(r3.revives).toBe(1)
		t.expect(r3.plays).toBe(1)
		local _, new4 = PaidPlay.grant(r3, "play", "")
		t.expect(new4).toBe(false)
	end)

	it("the ledger keeps the latest RECEIPTS_KEPT ids, dropping the oldest first", function()
		local r = rec()
		for i = 1, PaidPlay.RECEIPTS_KEPT + 2 do
			r = (PaidPlay.grant(r, "play", `id{i}`))
		end
		t.expect(#r.receipts).toBe(PaidPlay.RECEIPTS_KEPT)
		t.expect(r.receipts[1]).toBe("id3")
		t.expect(r.receipts[PaidPlay.RECEIPTS_KEPT]).toBe(`id{PaidPlay.RECEIPTS_KEPT + 2}`)
		t.expect(r.plays).toBe(PaidPlay.RECEIPTS_KEPT + 2)
		-- a dropped id is no longer remembered: that is the ledger's bound
		local _, again = PaidPlay.grant(r, "play", "id1")
		t.expect(again).toBe(true)
		local _, kept = PaidPlay.grant(r, "play", "id3")
		t.expect(kept).toBe(false)
	end)

	it("each refund is one more credit and never touches the ledger", function()
		local r = PaidPlay.refund(PaidPlay.refund(rec(nil, 0, 0, { "a" }), "revive"), "revive")
		t.expect(r.revives).toBe(2)
		t.expect(PaidPlay.refund(r, "play").plays).toBe(1)
		t.expect(r.receipts).toEqual({ "a" })
	end)

	it("a held revive is used once; with none held nothing changes", function()
		local used, r = PaidPlay.useRevive(rec(nil, 0, 1))
		t.expect(used).toBe(true)
		t.expect(r.revives).toBe(0)
		local again, r2 = PaidPlay.useRevive(r)
		t.expect(again).toBe(false)
		t.expect(r2).toEqual(r)
	end)

	it("a stored value is read defensively and round-trips through f0145's shape", function()
		t.expect(PaidPlay.record(42)).toEqual(rec())
		t.expect(PaidPlay.record({ plays = -2, continues = 1.5, free = "x" })).toEqual(rec())
		local stored = { free = T0, plays = 4, continues = 2, receipts = { "a", "b" } }
		local r = PaidPlay.record(stored)
		t.expect(r).toEqual(rec(T0, 4, 2, { "a", "b" }))
		t.expect(PaidPlay.stored(r)).toEqual(stored)
		t.expect(PaidPlay.record({ revives = 9 }).revives).toBe(0)
	end)

	it("the status names a free start due, or the instant the next one is, and the credits held", function()
		t.expect(PaidPlay.status(rec(nil, 1, 2), T0)).toEqual({ free = true, plays = 1, revives = 2 })
		t.expect(PaidPlay.status(rec(T0, 0, 0), T0 + 60)).toEqual({
			free = false,
			nextFree = T0 + PaidPlay.FREE_SECONDS,
			plays = 0,
			revives = 0,
		})
	end)

	it(
		"an arrival plays when charged or when the claim failed; a buy goes back unless it holds a pass",
		function()
			t.expect(PaidPlay.arrive("free", false)).toBe("play")
			t.expect(PaidPlay.arrive("credit", false)).toBe("play")
			t.expect(PaidPlay.arrive(nil, false)).toBe("play")
			t.expect(PaidPlay.arrive("buy", false)).toBe("back")
			t.expect(PaidPlay.arrive("buy", true)).toBe("play")
		end
	)

	it(
		"the mode is live only for exactly 'live' with both ids, closed with one missing, else test",
		function()
			local both = { play = 1, revive = 2 }
			t.expect(PaidPlay.mode("live", both)).toBe("live")
			t.expect(PaidPlay.mode("live", { play = 1 })).toBe("closed")
			t.expect(PaidPlay.mode("live", { revive = 2 })).toBe("closed")
			t.expect(PaidPlay.mode("Live", both)).toBe("test")
			t.expect(PaidPlay.mode(nil, both)).toBe("test")
			t.expect(PaidPlay.mode(true, {})).toBe("test")
		end
	)

	it("test mode keeps its own store; live and closed keep the live one", function()
		local e = entry("alpha")
		t.expect(PaidPlay.store(e, "test")).toBe("alphaTest")
		t.expect(PaidPlay.store(e, "live")).toBe("alphaLive")
		t.expect(PaidPlay.store(e, "closed")).toBe("alphaLive")
	end)

	it("configure reads whole positive ids per title and maps each product to its title and kind", function()
		local c = PaidPlay.configure(
			{ entry("alpha"), entry("beta") },
			"live",
			reader({ alphaPlay = 11, alphaRevive = 12, betaPlay = "13", betaRevive = 14.5 })
		)
		t.expect(c.titles.alpha.mode).toBe("live")
		t.expect(c.titles.alpha.ids).toEqual({ play = 11, revive = 12 })
		t.expect(c.titles.beta.mode).toBe("closed")
		t.expect(c.titles.beta.ids).toEqual({})
		t.expect(c.products[11]).toEqual({ name = "alpha", kind = "play" })
		t.expect(c.products[12]).toEqual({ name = "alpha", kind = "revive" })
		t.expect(c.products[13]).toBe(nil)
	end)

	it("an id two products share belongs to neither, so both titles are closed in live mode", function()
		local c = PaidPlay.configure(
			{ entry("alpha"), entry("beta") },
			"live",
			reader({ alphaPlay = 1, alphaRevive = 7, betaPlay = 7, betaRevive = 3 })
		)
		t.expect(c.products[7]).toBe(nil)
		t.expect(c.titles.alpha.mode).toBe("closed")
		t.expect(c.titles.beta.mode).toBe("closed")
		t.expect(c.products[1]).toEqual({ name = "alpha", kind = "play" })
		t.expect(c.products[3]).toEqual({ name = "beta", kind = "revive" })
	end)

	it("products map in test mode too, so a charged receipt is always recognised", function()
		local c = PaidPlay.configure({ entry("alpha") }, nil, reader({ alphaPlay = 5, alphaRevive = 6 }))
		t.expect(c.titles.alpha.mode).toBe("test")
		t.expect(c.products[5]).toEqual({ name = "alpha", kind = "play" })
	end)

	it("a catalog name is lowercase letters and appears once", function()
		t.expect(function()
			PaidPlay.configure({ entry("Alpha") }, nil, reader({}))
		end).toThrow("lowercase")
		t.expect(function()
			PaidPlay.configure({ entry("a/b") }, nil, reader({}))
		end).toThrow("lowercase")
		t.expect(function()
			PaidPlay.configure({ entry("alpha"), entry("alpha") }, nil, reader({}))
		end).toThrow("twice")
	end)

	-- f0395: the lines are rich text. A play's price line strikes the struck price; a revive's is its own price.
	local PRICES: PaidPlay.Prices = { struck = "9 X", price = "2 X", sale = "DEAL", revive = "3 Y" }

	it("testLines strikes a play's struck price, then the price and the sale", function()
		t.expect(PaidPlay.testLines("ALPHA", "play", PRICES)).toEqual({
			"ALPHA: " .. PaidPlay.KIND_TEXT.play,
			"<s>9 X</s> 2 X DEAL",
			PaidPlay.TEST_NOTE,
		})
	end)

	it("testLines gives a revive its own price, nothing struck", function()
		local lines = PaidPlay.testLines("ALPHA", "revive", PRICES)
		t.expect(lines).toEqual({ "ALPHA: " .. PaidPlay.KIND_TEXT.revive, "3 Y", PaidPlay.TEST_NOTE })
		for _, line in lines do
			t.expect((string.find(line, "<s>", 1, true))).toBe(nil)
		end
	end)

	it("testLines escapes every &, < and > in every text", function()
		-- each character at least twice in each text, so an escaper that replaces only the first one fails
		local odd: PaidPlay.Prices =
			{ struck = "<<9&&>>", price = "&&<<2>>", sale = "D>>L<<&&", revive = "&&<<3>>" }
		t.expect(PaidPlay.testLines("A&&B<<C>>", "play", odd)).toEqual({
			"A&amp;&amp;B&lt;&lt;C&gt;&gt;: " .. PaidPlay.KIND_TEXT.play,
			"<s>&lt;&lt;9&amp;&amp;&gt;&gt;</s> &amp;&amp;&lt;&lt;2&gt;&gt; D&gt;&gt;L&lt;&lt;&amp;&amp;",
			PaidPlay.TEST_NOTE,
		})
		t.expect(PaidPlay.testLines("A&&B<<C>>", "revive", odd)[2]).toBe("&amp;&amp;&lt;&lt;3&gt;&gt;")
		-- "&" first: an entity typed into a text shows as typed
		t.expect(PaidPlay.testLines("&gt;", "play", PRICES)[1]).toBe("&amp;gt;: " .. PaidPlay.KIND_TEXT.play)
	end)

	it("the test screen's keys: three buy, two cancel, any other none", function()
		for _, k in { "Return", "KeypadEnter", "ButtonA" } do
			t.expect(PaidPlay.testKey(k)).toBe("confirm")
		end
		for _, k in { "Backspace", "ButtonB" } do
			t.expect(PaidPlay.testKey(k)).toBe("cancel")
		end
		for _, k in { "Space", "Escape", "ButtonX", "" } do
			t.expect(PaidPlay.testKey(k)).toBe(nil)
		end
	end)
end)
