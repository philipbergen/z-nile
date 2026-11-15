--!strict
-- f0201 AC2: the configuration every place shares. A title is live only for exactly "live" with both its product ids
-- (whole positive numbers); "live" with one missing or bad is closed; anything else is test. An id two products share
-- belongs to neither. Each mode has its store (test mode its own). The shipped catalog has the four titles with their
-- stores and attributes, Pickman keeping f0145's; the badge text is one config table ("5 R$" struck, "1 R$", "SALE")
-- that says the charge; the test screen prints the title, the product, the badge and that nothing is charged, and
-- takes Return, KeypadEnter or ButtonA to buy and Backspace or ButtonB to cancel.
local PaidPlay = require("@logic/PaidPlay")
local luau = require("@lune/luau")
local place = require("@tests/lib/place")
local t = require("@tests/lib/t")

local built = place.load()
local function source(service: string, name: string): string
	local node = (built :: any):GetService(service):FindFirstChild("Arcade"):FindFirstChild(name)
	assert(node, `no {service}.Arcade.{name}`)
	return node.Source
end
-- the server-only catalog, run as Roblox would (it requires nothing)
local Catalog = luau.load(source("ServerStorage", "Catalog"), { debugName = "Catalog" })()
local Prices = require("@shared/Prices")

local A: PaidPlay.Entry = {
	name = "alpha",
	title = "ALPHA",
	store = "AlphaStore",
	testStore = "AlphaTest",
	play = "AlphaPlay",
	revive = "AlphaRevive",
}
local B: PaidPlay.Entry = {
	name = "beta",
	title = "BETA",
	store = "BetaStore",
	testStore = "BetaTest",
	play = "BetaPlay",
	revive = "BetaRevive",
}

local function reader(values: { [string]: any }): (string) -> any
	return function(name: string): any
		return values[name]
	end
end

return t.spec("f0201 paid-play configuration", function(it)
	it(
		"the mode is live only for exactly 'live' with both ids; 'live' with an id missing is closed; else test",
		function()
			t.expect(PaidPlay.mode("live", { play = 1, revive = 2 })).toBe("live")
			t.expect(PaidPlay.mode("live", { play = 1 })).toBe("closed")
			t.expect(PaidPlay.mode("live", {})).toBe("closed")
			t.expect(PaidPlay.mode("Live", { play = 1, revive = 2 })).toBe("test")
			t.expect(PaidPlay.mode(nil, { play = 1, revive = 2 })).toBe("test")
			t.expect(PaidPlay.mode(true, { play = 1, revive = 2 })).toBe("test")
		end
	)

	it(
		"each mode has its own store: test credits never reach a live record; closed keeps the live one",
		function()
			t.expect(PaidPlay.store(A, "live")).toBe("AlphaStore")
			t.expect(PaidPlay.store(A, "closed")).toBe("AlphaStore")
			t.expect(PaidPlay.store(A, "test")).toBe("AlphaTest")
		end
	)

	it(
		"configure reads each title's ids: whole positive numbers only, per title, and maps them to title and kind",
		function()
			local c = PaidPlay.configure(
				{ A, B },
				"live",
				reader({
					AlphaPlay = 11,
					AlphaRevive = 12,
					BetaPlay = "21",
					BetaRevive = 22.5,
				})
			)
			t.expect(c.titles.alpha.mode).toBe("live")
			t.expect(c.titles.alpha.ids).toEqual({ play = 11, revive = 12 })
			t.expect(c.titles.beta.mode).toBe("closed")
			t.expect(c.titles.beta.ids).toEqual({})
			t.expect(c.products[11]).toEqual({ name = "alpha", kind = "play" })
			t.expect(c.products[12]).toEqual({ name = "alpha", kind = "revive" })
			t.expect(c.products[21]).toBe(nil)
			t.expect(c.titles.alpha.entry).toBe(A)
		end
	)

	it("an id two products share belongs to neither, and its titles are closed", function()
		local c = PaidPlay.configure(
			{ A, B },
			"live",
			reader({
				AlphaPlay = 11,
				AlphaRevive = 12,
				BetaPlay = 12,
				BetaRevive = 22,
			})
		)
		t.expect(c.products[12]).toBe(nil)
		t.expect(c.products[11]).toEqual({ name = "alpha", kind = "play" })
		t.expect(c.products[22]).toEqual({ name = "beta", kind = "revive" })
		t.expect(c.titles.alpha.mode).toBe("closed")
		t.expect(c.titles.beta.mode).toBe("closed")
	end)

	it("a known product maps in every mode, so a receipt that was charged is always recognised", function()
		local c = PaidPlay.configure({ A }, nil, reader({ AlphaPlay = 11, AlphaRevive = 12 }))
		t.expect(c.titles.alpha.mode).toBe("test")
		t.expect(c.products[11]).toEqual({ name = "alpha", kind = "play" })
		local closed = PaidPlay.configure({ A }, "live", reader({ AlphaPlay = 11 }))
		t.expect(closed.titles.alpha.mode).toBe("closed")
		t.expect(closed.products[11]).toEqual({ name = "alpha", kind = "play" })
	end)

	it("a catalog name is lowercase letters and appears once", function()
		t.expect(function()
			PaidPlay.configure({ A, A }, nil, reader({}))
		end).toThrow("twice")
		local bad = table.clone(A)
		bad.name = "al/pha"
		t.expect(function()
			PaidPlay.configure({ bad }, nil, reader({}))
		end).toThrow("lowercase")
	end)

	it(
		"the shipped catalog: four titles, their stores and attributes; Pickman keeps f0145's names",
		function()
			local byName: { [string]: any } = {}
			for _, e in Catalog do
				byName[e.name] = e
			end
			t.expect(#Catalog).toBe(4)
			t.expect(byName.pickman).toEqual({
				name = "pickman",
				title = "PICKMAN",
				store = "PaidPlay",
				testStore = "PaidPlayTest",
				play = "PlayProductId",
				revive = "ContinueProductId",
			})
			for _, n in { "snake", "invaders", "asteroids" } do
				local cap = string.upper(string.sub(n, 1, 1)) .. string.sub(n, 2)
				t.expect(byName[n]).toEqual({
					name = n,
					title = string.upper(n),
					store = `{cap}PaidPlay`,
					testStore = `{cap}PaidPlayTest`,
					play = `{cap}PlayProductId`,
					revive = `{cap}ReviveProductId`,
				})
			end
			-- every store and attribute name is distinct, so no two titles share a record or an id
			local seen: { [string]: boolean } = {}
			for _, e in Catalog do
				for _, v in { e.store, e.testStore, e.play, e.revive } do
					t.expect(seen[v]).toBe(nil)
					seen[v] = true
				end
			end
			PaidPlay.configure(Catalog, nil, reader({}))
		end
	)

	it(
		"the badge text is one config table: 5 R$ struck through, on sale for 1 R$, which is the charge",
		function()
			t.expect(Prices).toEqual({ struck = "5 R$", price = "1 R$", sale = "SALE" })
			t.expect(Prices.price).toBe(`{PaidPlay.PRICE} R$`)
			t.expect(table.isfrozen(Prices)).toBe(true)
		end
	)

	it("the test screen's lines: the title and product, the badge, and that nothing is charged", function()
		t.expect(PaidPlay.testLines("SNAKE", "play", Prices)).toEqual({
			"SNAKE: 1 GAME",
			"5 R$ 1 R$ SALE",
			"TEST PURCHASE: NOTHING IS CHARGED",
		})
		t.expect(PaidPlay.testLines("PICKMAN", "revive", Prices)[1]).toBe("PICKMAN: REVIVE: 3 NEW LIVES")
	end)

	it(
		"the test screen's keys: Return, KeypadEnter, ButtonA buy; Backspace, ButtonB cancel; nothing else",
		function()
			for _, k in { "Return", "KeypadEnter", "ButtonA" } do
				t.expect(PaidPlay.testKey(k)).toBe("confirm")
			end
			for _, k in { "Backspace", "ButtonB" } do
				t.expect(PaidPlay.testKey(k)).toBe("cancel")
			end
			for _, k in { "Space", "Escape", "ButtonX", "E" } do
				t.expect(PaidPlay.testKey(k)).toBe(nil)
			end
		end
	)
end)
