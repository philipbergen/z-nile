--!strict
-- c0129 AC2: removing the adapter's play-again hook keeps the Logic it called. Hiscores.onAgain stays exported
-- (f0025's run.spec pins its behaviour), and an accepted play again is still the next run.
local Hiscores = require("@logic/Hiscores")
local t = require("@tests/lib/t")

return t.spec("c0129 Hiscores.onAgain stays", function(it)
	it("AC2: Hiscores.onAgain stays: an accepted play again is the next run", function()
		t.expect(type(Hiscores.onAgain)).toBe("function")
		local next = Hiscores.onAgain(Hiscores.newRun(), true)
		t.expect(next.run).toBe(2)
	end)
end)
