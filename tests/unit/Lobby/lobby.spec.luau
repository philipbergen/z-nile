--!strict
-- Lobby: rules the acceptance spec does not pin.
local Lobby = require("@logic/Lobby")
local t = require("@tests/lib/t")

return t.spec("Lobby extras", function(it)
	it("rows that share a rank are all shown", function()
		local p = Lobby.panel({
			{ rank = 2, name = "c", score = 10, level = 1 },
			{ rank = 1, name = "a", score = 30, level = 1 },
			{ rank = 1, name = "b", score = 30, level = 1 },
		})
		t.expect(#p.rows).toBe(3)
		t.expect(p.rows[1].rank).toBe(1)
		t.expect(p.rows[2].rank).toBe(1)
		t.expect(p.rows[3].name).toBe("c")
	end)
end)
