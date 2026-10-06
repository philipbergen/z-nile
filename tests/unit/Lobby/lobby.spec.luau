--!strict
-- Lobby: cases beyond the acceptance spec.
local Lobby = require("@logic/Lobby")
local t = require("@tests/lib/t")

return t.spec("Lobby extras", function(it)
	it("does not alias the caller's rows", function()
		local rows: { Lobby.Row } = { { rank = 1, name = "a", score = 10, level = 1 } }
		local panel = Lobby.panel(rows)
		panel.rows[1].score = 99
		t.expect(rows[1].score).toBe(10)
	end)
end)
