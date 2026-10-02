--!strict
-- f0670: what the lobby screen shows: the hiscore panel (empty until the boards exist) and the start button.
local Lobby = require("@logic/Lobby")
local t = require("@tests/lib/t")

local function rows(n: number): { Lobby.Row }
	local out: { Lobby.Row } = {}
	for i = 1, n do
		table.insert(out, { rank = i, name = `p{i}`, score = 500 + (i * 7) % 13, level = 1 })
	end
	return out
end

return t.spec("f0670 Lobby", function(it)
	it("the constants", function()
		t.expect(Lobby.TITLE).toBe("HISCORES")
		t.expect(Lobby.EMPTY).toBe("No scores yet")
		t.expect(Lobby.MAX_ROWS).toBe(10)
		t.expect(Lobby.BUTTON_MIN_PX).toBe(44)
	end)

	it("with no rows the panel is the empty state", function()
		local none: { Lobby.Panel } = { Lobby.panel(nil), Lobby.panel({}) }
		t.expect(#none).toBe(2)
		for _, p in none do
			t.expect(p.title).toBe("HISCORES")
			t.expect(p.rows).toEqual({})
			t.expect(p.empty).toBe("No scores yet")
		end
	end)

	it("with rows the panel shows them in rank order and no empty message", function()
		local given: { Lobby.Row } = {
			{ rank = 3, name = "c", score = 20, level = 1 },
			{ rank = 1, name = "a", score = 10, level = 3 },
			{ rank = 2, name = "b", score = 30, level = 2 },
		}
		local p = Lobby.panel(given)
		t.expect(p.empty).toBe(nil)
		t.expect(#p.rows).toBe(3)
		t.expect(p.rows[1].name).toBe("a")
		t.expect(p.rows[2].name).toBe("b")
		t.expect(p.rows[3].name).toBe("c")
	end)

	it("the panel shows at most 10 rows, the best ranks, whatever order they come in", function()
		local given = rows(12)
		local reversed: { Lobby.Row } = {}
		for i = #given, 1, -1 do
			table.insert(reversed, given[i])
		end
		local p = Lobby.panel(reversed)
		t.expect(#p.rows).toBe(10)
		for i = 1, 10 do
			t.expect(p.rows[i].rank).toBe(i)
		end
	end)

	it("the panel leaves the caller's rows alone", function()
		local given = rows(2)
		local p = Lobby.panel(given)
		p.rows[1].score = -1
		t.expect(given[1].score).toBe(507)
		t.expect(given[1] ~= p.rows[1]).toBe(true)
	end)

	it("the start button is live when a destination is set and nothing is under way", function()
		t.expect(Lobby.button("idle", true)).toEqual({ text = "START GAME", enabled = true })
	end)

	it("while a teleport is under way the button says so and is not live", function()
		t.expect(Lobby.button("going", true)).toEqual({ text = "STARTING...", enabled = false })
	end)

	it("after a failure the button is not live and says to try again", function()
		local b = Lobby.button("cooling", true)
		t.expect(b.text).toBe("START GAME")
		t.expect(b.enabled).toBe(false)
		t.expect(b.message).toBe("Could not start. Try again in a moment.")
	end)

	it("with no destination the button is unavailable whatever the status", function()
		for _, status: any in { "idle", "going", "cooling" } do
			local b = Lobby.button(status, false)
			t.expect(b.text).toBe("UNAVAILABLE")
			t.expect(b.enabled).toBe(false)
			t.expect(b.message).toBe("Starting is not set up yet.")
		end
	end)
end)
