--!strict
-- Lobby boards: rules the acceptance spec does not pin.
local Lobby = require("@logic/Lobby")
local t = require("@tests/lib/t")

return t.spec("Lobby board extras", function(it)
	it("a highlighted rank that is not on the panel marks nothing", function()
		local panel = Lobby.boardPanel({ { rank = 1, name = "A", score = 5, level = 1 } }, "all")
		t.expect(Lobby.lines(panel, 4)).toBe("1 A 5 1")
		t.expect(Lobby.lines(panel, nil)).toBe("1 A 5 1")
	end)

	it("two rows that share a rank are both marked", function()
		local panel = Lobby.boardPanel({
			{ rank = 1, name = "A", score = 5, level = 1 },
			{ rank = 1, name = "B", score = 5, level = 1 },
		}, "week")
		t.expect(Lobby.lines(panel, 1)).toBe("> 1 A 5 1\n> 1 B 5 1")
	end)

	it("the retry wait doubles from READ_GAP and ends after MAX_RETRIES", function()
		t.expect(Lobby.retryAfter(1)).toBe(Lobby.READ_GAP)
		t.expect(Lobby.retryAfter(Lobby.MAX_RETRIES)).toBe(Lobby.READ_GAP * 2 ^ (Lobby.MAX_RETRIES - 1))
		t.expect(Lobby.retryAfter(Lobby.MAX_RETRIES + 1)).toBe(nil)
		t.expect(Lobby.retryAfter(-1)).toBe(nil)
	end)
end)
