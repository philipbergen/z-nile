--!strict
-- Travel: cases beyond the acceptance spec.
local Travel = require("@logic/Travel")
local t = require("@tests/lib/t")

return t.spec("Travel extras", function(it)
	it("forgets a player who leaves", function()
		local tr = Travel.new()
		Travel.request(tr, "a", 0)
		Travel.left(tr, "a")
		t.expect(Travel.status(tr, "a", 1)).toBe("idle")
	end)

	it("treats players separately", function()
		local tr = Travel.new()
		t.expect((Travel.request(tr, "a", 0))).toBe("go")
		t.expect((Travel.request(tr, "b", 0))).toBe("go")
	end)
end)
