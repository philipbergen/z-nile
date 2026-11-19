--!strict
-- f0186 AC6: wherever pickman shows the price of a play, it shows "5 R$" struck through, on sale for "1 R$" (the
-- charge stays 1 R$: the Developer Product's price). The words are the arcade library's Prices (c0202: Lobby keeps no
-- copy), and Lobby.salePrice(Prices) is them as rich text ("<s>5 R$</s> 1 R$ SALE"). The lobby's line under START
-- GAME (f0145's Lobby.payLine) uses it where it showed "1 ROBUX A GAME"; its free, held and closed lines are as they
-- were. The continue's own price line (Flow.OFFER.price) is as it was (a guess pending the user: the capture names the
-- price of a play). The lobby's pay line is drawn as rich text (PayView). The test purchase screen is the library's
-- since c0202 (f0201's specs pin it, f0395's and c0202's its struck price).
local Flow = require("@logic/Flow")
local Lobby = require("@logic/Lobby")
local Prices = require("@arcade/Prices") -- c0202: the price words are the library's
local place = require("@tests/lib/place")
local t = require("@tests/lib/t")

local NOW = 1792108800
local SALE = "<s>5 R$</s> 1 R$ SALE"

local lobbyPlace = place.load("lobby.project.json")

local function sourceAt(root: any, path: { string }): string
	local node: any = root
	for _, part in path do
		node = node and node:FindFirstChild(part)
	end
	assert(node, `no {table.concat(path, ".")}`)
	return node.Source
end

return t.spec("f0186 the price of a play shows on sale", function(it)
	it("the price of a play: 5 R$ struck through, on sale for 1 R$", function()
		-- the library's words for a play (f0395 may add a revive's own value beside them)
		t.expect({ struck = Prices.struck, price = Prices.price, sale = Prices.sale }).toEqual({
			struck = "5 R$",
			price = "1 R$",
			sale = "SALE",
		})
		t.expect(Lobby.salePrice(Prices)).toBe(SALE)
	end)

	it("the lobby's line shows that price wherever it showed the price of a play", function()
		t.expect(
			Lobby.payLine(
				{ free = false, nextFree = NOW + 41 * 60 + 5, plays = 0, continues = 0 },
				"live",
				NOW,
				Prices
			)
		).toBe(`A GAME: {SALE}, NEXT FREE GAME IN 42 MIN`)
		t.expect(Lobby.payLine({ free = false, plays = 0, continues = 0 }, "live", NOW, Prices))
			.toBe(`A GAME: {SALE}`)
		t.expect(Lobby.payLine({ free = false, plays = 0, continues = 0 }, "test", NOW, Prices))
			.toBe(`A GAME: {SALE} (TEST: NOTHING IS CHARGED)`)
		t.expect(Lobby.payLine({ free = false, plays = 0, continues = 0 }, nil, NOW, Prices))
			.toBe(`A GAME: {SALE} (TEST: NOTHING IS CHARGED)`)
	end)

	it("the lobby's free, held and closed lines are as they were", function()
		t.expect(Lobby.payLine(nil, "live", NOW, Prices)).toBe(nil)
		t.expect(Lobby.payLine({ free = true, plays = 2, continues = 0 }, "live", NOW, Prices))
			.toBe("FREE GAME")
		t.expect(Lobby.payLine({ free = false, plays = 1, continues = 0 }, "live", NOW, Prices))
			.toBe("1 GAME YOU BOUGHT")
		t.expect(
			Lobby.payLine(
				{ free = false, nextFree = NOW + 60, plays = 0, continues = 0 },
				"closed",
				NOW,
				Prices
			)
		).toBe("STORE UNAVAILABLE, NEXT FREE GAME IN 1 MIN")
		t.expect(Lobby.payLine({ free = true, plays = 0, continues = 0 }, "test", NOW, Prices))
			.toBe("FREE GAME (TEST: NOTHING IS CHARGED)")
	end)

	it("the continue's price is not a play's: no struck price under the offer's buttons", function()
		t.expect((string.find(Flow.OFFER.price, Prices.struck, 1, true))).toBe(nil)
		t.expect((string.find(Flow.OFFER.price, "<s>", 1, true))).toBe(nil)
		t.expect(Flow.offerPrice({ mode = "live", held = 0 })).toBe(Flow.OFFER.price)
	end)

	it("the lobby draws its pay line as rich text", function()
		local pay = sourceAt(lobbyPlace, { "StarterPlayer", "StarterPlayerScripts", "Lobby", "PayView" })
		pay = string.gsub(pay, "%-%-[^\n]*", "")
		t.expect(string.find(pay, "RichText%s*=%s*true") ~= nil).toBe(true)
	end)
end)
