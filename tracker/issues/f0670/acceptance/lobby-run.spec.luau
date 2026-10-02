--!strict
-- f0670: the lobby as a player lives it, driven the way the server adapter drives it: a press, the engine's
-- answer, the cool-down, a second try, the teleport that takes the player away.
local Lobby = require("@logic/Lobby")
local Travel = require("@logic/Travel")
local t = require("@tests/lib/t")

-- what the server adapter does with a press: ask Travel, and show the player what Lobby says for the status
local function press(tr: Travel.Travel, id: string, now: number): (Travel.Answer, Lobby.Button)
	local answer: Travel.Answer = Travel.request(tr, id, now)
	return answer, Lobby.button(Travel.status(tr, id, now), true)
end

return t.spec("f0670 lobby run", function(it)
	it("press, a failed teleport, the wait, press again, and the player is taken away", function()
		local tr = Travel.new()
		-- 1: the first press starts a teleport
		local answer, button = press(tr, "p1", 0)
		t.expect(answer).toBe("go")
		t.expect(button.text).toBe("STARTING...")
		t.expect(button.enabled).toBe(false)
		-- 2: pressing again while it is under way starts nothing
		answer, button = press(tr, "p1", 1)
		t.expect(answer).toBe("busy")
		t.expect(button.text).toBe("STARTING...")
		-- 3: the engine says it failed: the button waits, with a message
		Travel.failed(tr, "p1", 2)
		answer, button = press(tr, "p1", 3)
		t.expect(answer).toBe("cooling")
		t.expect(button.enabled).toBe(false)
		t.expect(button.message ~= nil).toBe(true)
		-- 4: after the cool-down the button is live again and a press goes
		t.expect(Lobby.button(Travel.status(tr, "p1", 5), true))
			.toEqual({ text = "START GAME", enabled = true })
		answer, button = press(tr, "p1", 5)
		t.expect(answer).toBe("go")
		-- 5: the teleport succeeds: the player is gone and nothing is kept
		Travel.left(tr, "p1")
		t.expect((next(tr.entries))).toBe(nil)
	end)

	it("a teleport nobody answers frees the player after the timeout and the cool-down", function()
		local tr = Travel.new()
		press(tr, "p1", 0)
		Travel.answered(tr, "p1", 1) -- the engine call returned; nothing came of it
		local _, button = press(tr, "p1", 15)
		t.expect(button.text).toBe("STARTING...")
		_, button = press(tr, "p1", 16)
		t.expect(button.message ~= nil).toBe(true)
		local answer = press(tr, "p1", 19)
		t.expect(answer).toBe("go")
	end)

	it("two players do not get in each other's way", function()
		local tr = Travel.new()
		t.expect((press(tr, "p1", 0))).toBe("go")
		t.expect((press(tr, "p2", 0.5))).toBe("go")
		Travel.failed(tr, "p1", 1)
		t.expect(Lobby.button(Travel.status(tr, "p2", 2), true).text).toBe("STARTING...")
		t.expect(Lobby.button(Travel.status(tr, "p1", 2), true).enabled).toBe(false)
	end)

	it("a lobby with no destination never starts anything: the button is unavailable", function()
		local destination = Travel.destination(0)
		t.expect(destination).toBe(nil)
		t.expect(Lobby.button("idle", destination ~= nil).enabled).toBe(false)
	end)
end)
