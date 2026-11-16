--!strict
-- f0395 AC1: the test purchase screen's lines strike the price of a play. PaidPlay.testLines(title, "play", prices)
-- prints the price line as rich text, the struck price marked for strike-through: "<s>{struck}</s> {price} {sale}"
-- ("<s>5 R$</s> 1 R$ SALE" with the shipped Prices). A revive's price line is its own library value, Prices.revive
-- ("1 R$"), with nothing struck (a guess pending the user, f0186's G3). Every text testLines puts in a line is shown
-- as it is: "&", "<" and ">" become entities, so the only markup is the play's one <s> tag. The first and last lines
-- are f0201's. Prices is one frozen table: the badge's three words and the revive's price.
local PaidPlay = require("@logic/PaidPlay")
local Prices = require("@shared/Prices")
local t = require("@tests/lib/t")

-- words no shipped table holds, so a line built from anything but the table it is given fails
local OTHER: PaidPlay.Prices = { struck = "9 X", price = "2 X", sale = "DEAL", revive = "3 Y" }

local function count(text: string, needle: string): number
	local n, at = 0, 1
	while true do
		local i = string.find(text, needle, at, true)
		if i == nil then
			return n
		end
		n += 1
		at = i + #needle
	end
end

return t.spec("f0395 the test screen strikes the price", function(it)
	it("a play's price line strikes the badge's struck price, then the price and the sale", function()
		for _, title in { "PICKMAN", "SNAKE", "INVADERS", "ASTEROIDS" } do
			t.expect(PaidPlay.testLines(title, "play", Prices)).toEqual({
				`{title}: 1 GAME`,
				"<s>5 R$</s> 1 R$ SALE",
				"TEST PURCHASE: NOTHING IS CHARGED",
			})
		end
	end)

	it("a play's price line is built from the prices it is given", function()
		t.expect(PaidPlay.testLines("SNAKE", "play", OTHER)[2]).toBe("<s>9 X</s> 2 X DEAL")
	end)

	it("a revive's price line is the revive's own price, with nothing struck", function()
		for _, title in { "PICKMAN", "SNAKE", "INVADERS", "ASTEROIDS" } do
			local lines = PaidPlay.testLines(title, "revive", Prices)
			t.expect(lines).toEqual({
				`{title}: REVIVE: 3 NEW LIVES`,
				"1 R$",
				"TEST PURCHASE: NOTHING IS CHARGED",
			})
			for _, line in lines do
				t.expect((string.find(line, "<s>", 1, true))).toBe(nil)
			end
		end
		t.expect(PaidPlay.testLines("SNAKE", "revive", OTHER)).toEqual({
			"SNAKE: REVIVE: 3 NEW LIVES",
			"3 Y",
			"TEST PURCHASE: NOTHING IS CHARGED",
		})
	end)

	it(
		"every text in a line shows as it is: &, < and > become entities, the play's <s> is the only markup",
		function()
			local odd: PaidPlay.Prices = { struck = "<5 & 6>", price = "&1", sale = "S>", revive = "<r&>" }
			t.expect(PaidPlay.testLines("A<B>&C", "play", odd)).toEqual({
				"A&lt;B&gt;&amp;C: 1 GAME",
				"<s>&lt;5 &amp; 6&gt;</s> &amp;1 S&gt;",
				"TEST PURCHASE: NOTHING IS CHARGED",
			})
			t.expect(PaidPlay.testLines("A<B>&C", "revive", odd)).toEqual({
				"A&lt;B&gt;&amp;C: REVIVE: 3 NEW LIVES",
				"&lt;r&amp;&gt;",
				"TEST PURCHASE: NOTHING IS CHARGED",
			})
			-- an entity already in a text is shown as typed, not read as an entity
			t.expect(PaidPlay.testLines("&lt;", "revive", OTHER)[1]).toBe("&amp;lt;: REVIVE: 3 NEW LIVES")
			-- with the shipped words the play's lines hold exactly one tag pair and no entity
			local lines = PaidPlay.testLines("PICKMAN", "play", Prices)
			local all = table.concat(lines, "\n")
			t.expect(count(all, "<")).toBe(2)
			t.expect(count(all, "<s>")).toBe(1)
			t.expect(count(all, "</s>")).toBe(1)
			t.expect(count(all, "&")).toBe(0)
		end
	)

	it("Prices is one frozen table: 5 R$ struck, 1 R$, SALE, and the revive's 1 R$, the charge", function()
		t.expect(Prices).toEqual({ struck = "5 R$", price = "1 R$", sale = "SALE", revive = "1 R$" })
		t.expect(Prices.revive).toBe(`{PaidPlay.PRICE} R$`)
		t.expect(Prices.price).toBe(`{PaidPlay.PRICE} R$`)
		t.expect(table.isfrozen(Prices)).toBe(true)
	end)
end)
