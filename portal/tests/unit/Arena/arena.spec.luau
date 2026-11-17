--!strict
local Arena = require("@logic/Arena")
local t = require("@tests/lib/t")

return t.spec("Arena", function(it)
	it("with no arena open, the first player opens one", function()
		t.expect(Arena.join(nil, "x", 100)).toEqual({ id = "x", count = 1, opened = 100 })
	end)
end)
