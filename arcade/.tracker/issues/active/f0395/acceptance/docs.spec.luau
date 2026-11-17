--!strict
-- f0395 AC3: the library's binding design says what changed. arcade/.tracker/architecture.md's PaidPlay and Receipts
-- section (f0201's) names a revive's price in the Prices bullet, and says in the TestPurchase bullet that the screen's
-- lines are rich text, a play's price line striking the badge's struck price. Each sentence sits in its own bullet.
local fs = require("@lune/fs")
local t = require("@tests/lib/t")

-- the bullet of the section's list that starts with `start`, up to the next bullet or heading
local function bullet(doc: string, start: string): string?
	local at = string.find(doc, "\n- " .. start, 1, true)
	if at == nil then
		return nil
	end
	local rest = string.sub(doc, at + 1)
	local stop = string.find(rest, "\n[-#]", 2)
	return if stop then string.sub(rest, 1, stop - 1) else rest
end

return t.spec("f0395 the architecture says the test screen strikes the price", function(it)
	it("the Prices bullet names a revive's price, nothing struck", function()
		local doc = fs.readFile(".tracker/architecture.md")
		local b = bullet(doc, "`src/shared/Prices.luau`:")
		t.expect(b ~= nil).toBe(true)
		t.expect(
			string.find(b :: string, 'a revive\'s price ("1 R$", nothing struck; f0395)', 1, true) ~= nil
		)
			.toBe(true)
	end)

	it("the TestPurchase bullet says its lines are rich text, a play's price line struck", function()
		local doc = fs.readFile(".tracker/architecture.md")
		local b = bullet(doc, "`src/shared/TestPurchase.luau`:")
		t.expect(b ~= nil).toBe(true)
		local sentence =
			"Its lines are rich text: a play's price line strikes the badge's struck price (f0395)."
		t.expect(string.find(b :: string, sentence, 1, true) ~= nil).toBe(true)
	end)
end)
