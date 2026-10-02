--!strict
-- f0670: the lobby adapters stay thin and safe. Their real source is run against a fake engine
-- (@tests/lib/fakeengine) and the real Logic: the server relays a player's request, the clock and the engine's
-- answer to Travel and never trusts the client; the client draws Lobby's models and sends one request.
local fake = require("@tests/lib/fakeengine")
local place = require("@tests/lib/place")
local t = require("@tests/lib/t")

local lobby = place.load("lobby.project.json")

local function sourceOf(path: { string }): string
	local node: any = lobby
	for _, name in path do
		node = node and node:FindFirstChild(name)
	end
	return node.Source
end

local SERVER = { "ServerScriptService", "Lobby", "Starts" }
local CLIENT = { "StarterPlayer", "StarterPlayerScripts", "Lobby", "LobbyView" }

-- the source without comments, so a mention in a comment proves nothing
local function code(path: { string }): string
	local src = string.gsub(sourceOf(path), "%-%-[^\n]*", "")
	return src
end

local P1 = fake.player(1)
local P2 = fake.player(2)

-- a booted lobby server with two players already in it (their status is not announced until it changes).
-- `destination` is the value of the GamePlaceId attribute the publisher would set (nil: as checked in, 0)
local function server(destination: any): fake.Server
	local attributes: { [string]: any } = {}
	if destination ~= nil then
		attributes.GamePlaceId = destination
	end
	local s = fake.server(lobby, attributes)
	P1.Parent, P2.Parent = nil, nil
	s.here(P1)
	s.here(P2)
	s.boot(sourceOf(SERVER))
	return s
end

local function pairsOf(list: { { any } }): string
	local out: { string } = {}
	for _, args in list do
		table.insert(out, `{tostring(args[1])}/{tostring(args[2])}`)
	end
	return table.concat(out, " ")
end

return t.spec("f0670 lobby adapters", function(it)
	it(
		"five presses while a teleport is under way reach the engine once, with the destination and the player",
		function()
			local s = server(123456)
			for _ = 1, 5 do
				s.press(P1)
			end
			t.expect(#s.engine.calls).toBe(1)
			t.expect(s.engine.calls[1].destination).toBe(123456)
			t.expect(s.engine.calls[1].players).toEqual({ P1 })
			t.expect(s.engine.calls[1].players[1]).toBe(P1)
			t.expect(pairsOf(s.statuses(P1))).toBe("going/true")
		end
	)

	it("with no destination (no attribute, 0, text that is not an id) nothing reaches the engine", function()
		local none: { any } = { 0, "abc", -5, 1.5 }
		for _, destination in none do
			local s = server(destination)
			s.press(P1)
			s.press(P1)
			t.expect(#s.engine.calls).toBe(0)
			t.expect(pairsOf(s.statuses(P1))).toBe("idle/false")
		end
		local s = server(nil)
		s.press(P1)
		t.expect(#s.engine.calls).toBe(0)
		t.expect(pairsOf(s.statuses(P1))).toBe("idle/false")
	end)

	it("a destination given as digits is accepted", function()
		local s = server("987654321")
		s.press(P1)
		t.expect(s.engine.calls[1].destination).toBe(987654321)
	end)

	it("what the client sends with the request is ignored", function()
		local s = server(777)
		s.press(P1, "elsewhere", 999999, { destination = 5 })
		t.expect(#s.engine.calls).toBe(1)
		t.expect(s.engine.calls[1].destination).toBe(777)
		t.expect(s.engine.calls[1].players[1]).toBe(P1)
	end)

	it("a failed call tells the player, and the cool-down ends on screen by itself, once", function()
		local s = server(777)
		s.engine.mode = "error"
		s.press(P1)
		t.expect(pairsOf(s.statuses(P1))).toBe("going/true cooling/true")
		s.engine.mode = "ok"
		s.press(P1) -- still cooling: nothing reaches the engine
		t.expect(#s.engine.calls).toBe(1)
		s.tick(1)
		s.tick(1)
		t.expect(pairsOf(s.statuses(P1))).toBe("going/true cooling/true")
		s.tick(1) -- 3 s after the failure: the cool-down is over, and the player is told within the second
		t.expect(pairsOf(s.statuses(P1))).toBe("going/true cooling/true idle/true")
		s.tick(1)
		s.tick(1)
		t.expect(pairsOf(s.statuses(P1))).toBe("going/true cooling/true idle/true")
		s.press(P1)
		t.expect(#s.engine.calls).toBe(2)
	end)

	it("an init failure from the engine is a failure too", function()
		local s = server(777)
		s.press(P1)
		s.initFailed(P1)
		t.expect(pairsOf(s.statuses(P1))).toBe("going/true cooling/true")
		s.tick(4)
		s.press(P1)
		t.expect(#s.engine.calls).toBe(2)
	end)

	it("an init failure for a player who is not going changes nothing on screen", function()
		local s = server(777)
		s.initFailed(P1) -- nobody asked: the player just hears that the lobby is idle
		t.expect(pairsOf(s.statuses(P1))).toBe("idle/true")
		s.press(P1)
		s.tick(20) -- timed out and cooling
		s.tick(1)
		s.initFailed(P1) -- a late report: already cooling, nothing to add
		t.expect(pairsOf(s.statuses(P1))).toBe("idle/true going/true cooling/true")
	end)

	it("a teleport nobody answers frees the player after 15 s and the cool-down", function()
		local s = server(777)
		s.press(P1) -- the call returns, the player stays: nothing happens
		s.tick(14)
		s.press(P1)
		t.expect(#s.engine.calls).toBe(1)
		t.expect(pairsOf(s.statuses(P1))).toBe("going/true")
		s.tick(2)
		t.expect(pairsOf(s.statuses(P1))).toBe("going/true cooling/true")
		s.tick(3)
		t.expect(pairsOf(s.statuses(P1))).toBe("going/true cooling/true idle/true")
	end)

	it(
		"an engine call that has not returned keeps the player waiting: no second call while it is in the engine",
		function()
			local s = server(777)
			s.engine.mode = "hold"
			s.press(P1)
			t.expect(#s.engine.calls).toBe(1)
			for _ = 1, 5 do
				s.tick(10) -- 50 s: well past 15 s
				s.press(P1)
			end
			t.expect(#s.engine.calls).toBe(1)
			t.expect(pairsOf(s.statuses(P1))).toBe("going/true")
			-- the call fails at last: that cools the player down (it is still the one request)
			s.release(1, true)
			t.expect(pairsOf(s.statuses(P1))).toBe("going/true cooling/true")
		end
	)

	it("a call that never returns is given up on after the 60 s cap", function()
		local s = server(777)
		s.engine.mode = "hold"
		s.press(P1)
		s.tick(61)
		t.expect(pairsOf(s.statuses(P1))).toBe("going/true cooling/true")
		s.tick(4)
		s.press(P1)
		t.expect(#s.engine.calls).toBe(2)
	end)

	it(
		"a call abandoned after the cap reports nothing to the newer request: no third call while the second is in the engine",
		function()
			local s = server(777)
			s.engine.mode = "hold"
			s.press(P1) -- call A, held
			s.tick(61) -- A is given up on at 60 s
			s.tick(4)
			s.press(P1) -- call B, held; its own cap is at 125
			t.expect(#s.engine.calls).toBe(2)
			s.release(1, true) -- A fails very late: it was not B
			s.tick(4)
			s.press(P1)
			t.expect(#s.engine.calls).toBe(2) -- B is still going: no third call
		end
	)

	it("an abandoned call that returns at last does not shorten the newer request's wait", function()
		local s = server(777)
		s.engine.mode = "hold"
		s.press(P1) -- call A, held
		s.tick(61) -- A is given up on at 60 s
		s.tick(4) -- the cool-down is over
		s.press(P1) -- call B at t = 65, held, with its own cap at 125
		s.tick(5)
		s.release(1, false) -- A returns at t = 70 with no error: it was not B
		s.tick(19)
		s.press(P1) -- t = 89: B is still in the engine
		t.expect(#s.engine.calls).toBe(2)
		s.tick(40) -- t = 129: B's own cap has passed
		t.expect(pairsOf(s.statuses(P1))).toBe("going/true cooling/true idle/true going/true cooling/true")
	end)

	it("a player who leaves is forgotten, players are separate", function()
		local s = server(777)
		s.press(P1)
		s.press(P2)
		t.expect(#s.engine.calls).toBe(2)
		s.leave(P1)
		s.press(P1) -- the same user comes back at once
		t.expect(#s.engine.calls).toBe(3)
		t.expect(pairsOf(s.statuses(P2))).toBe("going/true")
	end)

	it("a player already in the lobby when the server starts hears the state within a second", function()
		local s = server(777)
		s.tick(1)
		t.expect(pairsOf(s.statuses(P1))).toBe("idle/true")
		t.expect(pairsOf(s.statuses(P2))).toBe("idle/true")
		local unset = server(nil)
		unset.tick(1)
		t.expect(pairsOf(unset.statuses(P1))).toBe("idle/false")
	end)

	it("a joining player is told the lobby's state once", function()
		local s = fake.server(lobby, {})
		P1.Parent = nil
		s.boot(sourceOf(SERVER))
		s.join(P1)
		s.tick(1)
		s.tick(1)
		t.expect(pairsOf(s.statuses(P1))).toBe("idle/false")
	end)

	it("the client draws the panel's empty state and a live button at the start", function()
		local c = fake.client(lobby)
		c.boot(sourceOf(CLIENT))
		t.expect(c.find("Title").Text).toBe("HISCORES")
		t.expect(c.find("Rows").Text).toBe("No scores yet")
		t.expect(c.find("Start").Text).toBe("START GAME")
		t.expect(c.find("Start").Active).toBe(true)
		t.expect(c.find("Message").Text).toBe("")
	end)

	it("the client redraws the button for every status the server sends", function()
		local c = fake.client(lobby)
		c.boot(sourceOf(CLIENT))
		c.status("going", true)
		t.expect(c.find("Start").Text).toBe("STARTING...")
		t.expect(c.find("Start").Active).toBe(false)
		c.status("cooling", true)
		t.expect(c.find("Start").Active).toBe(false)
		t.expect(c.find("Message").Text).toBe("Could not start. Try again in a moment.")
		c.status("idle", true)
		t.expect(c.find("Start").Text).toBe("START GAME")
		t.expect(c.find("Start").Active).toBe(true)
		t.expect(c.find("Message").Text).toBe("")
		c.status("idle", false)
		t.expect(c.find("Start").Text).toBe("UNAVAILABLE")
		t.expect(c.find("Start").Active).toBe(false)
		t.expect(c.find("Message").Text).toBe("Starting is not set up yet.")
	end)

	it("pressing the button sends the start request with no arguments, once per press", function()
		local c = fake.client(lobby)
		c.boot(sourceOf(CLIENT))
		c.activate()
		c.activate()
		t.expect(#c.fired).toBe(2)
		t.expect(#c.fired[1]).toBe(0)
		t.expect(#c.fired[2]).toBe(0)
	end)

	it("the start button is at least 44 px tall", function()
		local c = fake.client(lobby)
		c.boot(sourceOf(CLIENT))
		t.expect(c.find("Start").Size.Y.Offset >= 44).toBe(true)
	end)

	it(
		"a teleport that returns after a long wait still gets its 15 s: the answer is reported with the time it came",
		function()
			local s = server(777)
			s.engine.mode = "hold"
			s.press(P1)
			s.tick(20)
			s.release(1, false) -- the call returns at t = 20, with no error
			s.tick(14)
			s.press(P1)
			t.expect(#s.engine.calls).toBe(1)
			t.expect(pairsOf(s.statuses(P1))).toBe("going/true")
			s.tick(2)
			t.expect(pairsOf(s.statuses(P1))).toBe("going/true cooling/true")
		end
	)

	it(
		"a report that arrives after the player left sends nothing, and a player who comes back hears the state again",
		function()
			local s = server(777)
			s.engine.mode = "hold"
			s.press(P1)
			s.leave(P1)
			s.release(1, true) -- the call fails after the player closed the app
			s.initFailed(P1)
			t.expect(pairsOf(s.statuses(P1))).toBe("going/true")
			s.engine.mode = "ok"
			s.join(P1) -- the same player, back: told the state again, whatever was shown before
			s.tick(5)
			t.expect(pairsOf(s.statuses(P1))).toBe("going/true idle/true")
		end
	)

	it(
		"a player who leaves and comes back is told the state again, even if it is the same as before",
		function()
			local s = fake.server(lobby, {})
			local p = fake.player(9)
			s.boot(sourceOf(SERVER))
			s.join(p)
			s.leave(p)
			s.join(p)
			t.expect(pairsOf(s.statuses(p))).toBe("idle/false idle/false")
		end
	)

	it("the destination is read from the attribute the built lobby carries, under its name", function()
		-- the fake refuses an attribute the built place does not carry: a wrong name in the project or the adapter shows here
		local ok = pcall(fake.server, lobby, { PlaceId = 777 })
		t.expect(ok).toBe(false)
		local s = server(777)
		s.press(P1)
		t.expect(s.engine.calls[1].destination).toBe(777)
	end)

	it(
		"the adapters reach the instances the built lobby has: its remotes by their names, however they are looked up",
		function()
			-- booting finds StartGame and Status in ReplicatedStorage.Remotes of the built place, or fails naming the path
			server(777)
			local c = fake.client(lobby)
			c.boot(sourceOf(CLIENT))
		end
	)

	it(
		"the lobby's screen is on the player's PlayerGui: a black backdrop over the whole screen holds the title, the panel and the button",
		function()
			local c = fake.client(lobby)
			c.boot(sourceOf(CLIENT))
			local backdrop = c.find("Backdrop")
			t.expect(backdrop ~= nil).toBe(true)
			t.expect(backdrop.BackgroundColor3).toEqual({ R = 0, G = 0, B = 0 })
			t.expect(backdrop.Size.X.Scale).toBe(1)
			t.expect(backdrop.Size.Y.Scale).toBe(1)
			for _, name in { "Title", "Rows", "Message", "Start" } do
				local item = c.find(name)
				t.expect(item ~= nil).toBe(true)
				t.expect(item.Parent == backdrop).toBe(true)
			end
			local gui = c.find("Lobby")
			t.expect(gui.Parent.ClassName).toBe("PlayerGui")
			-- and it can be seen: over the whole screen including the top bar, enabled, nothing hidden or see-through
			t.expect(gui.IgnoreGuiInset).toBe(true)
			t.expect(gui.Enabled ~= false).toBe(true)
			t.expect((backdrop.BackgroundTransparency or 0) == 0).toBe(true)
			for _, name in { "Backdrop", "Title", "Rows", "Message", "Start" } do
				t.expect(c.find(name).Visible ~= false).toBe(true)
			end
			local at = c.find("Start").Position
			t.expect(at.X.Scale >= 0 and at.X.Scale <= 1).toBe(true)
			t.expect(at.Y.Scale >= 0 and at.Y.Scale < 1).toBe(true)
		end
	)

	it("the client decides nothing and leaves the mouse free: no teleport, no clock, no lock", function()
		local src = code(CLIENT)
		t.expect((string.find(src, "TeleportService", 1, true))).toBe(nil)
		t.expect((string.find(src, "os.clock", 1, true))).toBe(nil)
		t.expect((string.find(src, "Travel.request", 1, true))).toBe(nil)
		t.expect((string.find(src, "LockCenter", 1, true))).toBe(nil)
		t.expect((string.find(src, "MouseBehavior", 1, true))).toBe(nil)
	end)

	it("no place id is written into the server's code", function()
		t.expect((string.find(code(SERVER), "%d%d%d%d%d"))).toBe(nil)
	end)
end)
