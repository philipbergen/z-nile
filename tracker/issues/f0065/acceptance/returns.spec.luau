--!strict
-- f0065 AC3: the game place's Returns adapter sends a player back to the lobby only once the run is over, with
-- f0061's Travel rules. Its real source runs against the fake engine (@tests/lib/fakeengine) over the BUILT game
-- place, with the real Travel; whether a run is over comes from the `isOver` it is started with.
local fake = require("@tests/lib/fakeengine")
local place = require("@tests/lib/place")
local t = require("@tests/lib/t")

local gamePlace = place.load()

local function sourceOf(path: { string }): string
	local node: any = gamePlace
	for _, name in path do
		node = node and node:FindFirstChild(name)
	end
	assert(node, `no {table.concat(path, ".")} in the game place`)
	return node.Source
end

local SERVER = { "ServerScriptService", "Server", "Returns" }

local P1 = fake.player(1)
local P2 = fake.player(2)

type World = { s: fake.Server, over: { [any]: boolean } }

-- a booted Returns with two players already in the game place, neither run over yet. `lobby` is the value of
-- the LobbyPlaceId attribute the publisher would set (nil: as checked in, 0)
local function world(lobby: any): World
	local attributes: { [string]: any } = {}
	if lobby ~= nil then
		attributes.LobbyPlaceId = lobby
	end
	local s = fake.server(gamePlace, attributes)
	P1.Parent, P2.Parent = nil, nil
	s.here(P1)
	s.here(P2)
	local over: { [any]: boolean } = {}
	s.boot(sourceOf(SERVER), function(player: any): boolean
		return over[player] == true
	end)
	return { s = s, over = over }
end

local function ask(w: World, player: any, ...: any)
	w.s.fire("ToLobby", player, ...)
end

local function pairsOf(list: { { any } }): string
	local out: { string } = {}
	for _, args in list do
		table.insert(out, `{tostring(args[1])}/{tostring(args[2])}`)
	end
	return table.concat(out, " ")
end

return t.spec("f0065 the way back to the lobby", function(it)
	it("a request while the run is not over does nothing", function()
		local w = world(4242)
		for _ = 1, 3 do
			ask(w, P1)
		end
		t.expect(#w.s.engine.calls).toBe(0)
		t.expect(pairsOf(w.s.reports("LobbyStatus", P1))).toBe("")
	end)

	it(
		"once the run is over, five requests reach the engine once, with the lobby's id and the player",
		function()
			local w = world(4242)
			w.over[P1] = true
			for _ = 1, 5 do
				ask(w, P1)
			end
			t.expect(#w.s.engine.calls).toBe(1)
			t.expect(w.s.engine.calls[1].destination).toBe(4242)
			t.expect(w.s.engine.calls[1].players).toEqual({ P1 })
			t.expect(w.s.engine.calls[1].players[1]).toBe(P1)
			t.expect(pairsOf(w.s.reports("LobbyStatus", P1))).toBe("going/true")
		end
	)

	it("whether the run is over is asked at the time of each request", function()
		local w = world(4242)
		ask(w, P1)
		t.expect(#w.s.engine.calls).toBe(0)
		w.over[P1] = true
		ask(w, P1)
		t.expect(#w.s.engine.calls).toBe(1)
	end)

	it("only the sender goes, and only its own run counts", function()
		local w = world(4242)
		w.over[P2] = true
		ask(w, P1)
		t.expect(#w.s.engine.calls).toBe(0)
		ask(w, P2)
		t.expect(#w.s.engine.calls).toBe(1)
		t.expect(w.s.engine.calls[1].players).toEqual({ P2 })
	end)

	it("what the client sends with the request is ignored", function()
		local w = world(4242)
		w.over[P1] = true
		ask(w, P1, 999, P2, "lobby")
		t.expect(#w.s.engine.calls).toBe(1)
		t.expect(w.s.engine.calls[1].destination).toBe(4242)
		t.expect(w.s.engine.calls[1].players).toEqual({ P1 })
	end)

	it("with no lobby set up (no attribute, 0, text that is not an id) nothing reaches the engine", function()
		local none: { any } = { 0, "abc", -5, 1.5 }
		for _, lobby in none do
			local w = world(lobby)
			w.over[P1] = true
			ask(w, P1)
			ask(w, P1)
			t.expect(#w.s.engine.calls).toBe(0)
			t.expect(pairsOf(w.s.reports("LobbyStatus", P1))).toBe("idle/false")
		end
		local w = world(nil)
		w.over[P1] = true
		ask(w, P1)
		t.expect(#w.s.engine.calls).toBe(0)
		t.expect(pairsOf(w.s.reports("LobbyStatus", P1))).toBe("idle/false")
	end)

	it("every report goes on LobbyStatus and nothing on any other remote, through a whole trip", function()
		local w = world(4242)
		w.over[P1] = true
		w.s.engine.mode = "error"
		ask(w, P1)
		w.s.tick(3.5)
		w.s.engine.mode = "ok"
		ask(w, P1)
		w.s.initFailed(P1)
		w.s.tick(16)
		t.expect(#w.s.reports("LobbyStatus", P1) >= 4).toBe(true)
		for _, f in w.s.sent do
			t.expect(f.remote).toBe("LobbyStatus")
		end
	end)

	it("a lobby id given as digits is accepted", function()
		local w = world("4242")
		w.over[P1] = true
		ask(w, P1)
		t.expect(#w.s.engine.calls).toBe(1)
		t.expect(w.s.engine.calls[1].destination).toBe(4242)
	end)

	it("a failed call tells the player, cools down for 3 s, and then the player may try again", function()
		local w = world(4242)
		w.over[P1] = true
		w.s.engine.mode = "error"
		ask(w, P1)
		t.expect(#w.s.engine.calls).toBe(1)
		t.expect(pairsOf(w.s.reports("LobbyStatus", P1))).toBe("going/true cooling/true")
		ask(w, P1)
		t.expect(#w.s.engine.calls).toBe(1)
		w.s.tick(2)
		ask(w, P1)
		t.expect(#w.s.engine.calls).toBe(1)
		w.s.tick(1.5)
		t.expect(pairsOf(w.s.reports("LobbyStatus", P1))).toBe("going/true cooling/true idle/true")
		w.s.engine.mode = "ok"
		ask(w, P1)
		t.expect(#w.s.engine.calls).toBe(2)
	end)

	it("an init failure from the engine is a failure too", function()
		local w = world(4242)
		w.over[P1] = true
		ask(w, P1)
		w.s.initFailed(P1)
		t.expect(pairsOf(w.s.reports("LobbyStatus", P1))).toBe("going/true cooling/true")
	end)

	it("a trip nobody answers frees the player after 15 s", function()
		local w = world(4242)
		w.over[P1] = true
		ask(w, P1)
		w.s.tick(14)
		t.expect(pairsOf(w.s.reports("LobbyStatus", P1))).toBe("going/true")
		w.s.tick(1.5)
		t.expect(pairsOf(w.s.reports("LobbyStatus", P1))).toBe("going/true cooling/true")
	end)

	it("a joining player is told the trip's state once", function()
		local w = world(4242)
		local p3 = fake.player(3)
		w.s.join(p3)
		t.expect(pairsOf(w.s.reports("LobbyStatus", p3))).toBe("idle/true")
		w.s.tick(1)
		w.s.tick(1)
		t.expect(pairsOf(w.s.reports("LobbyStatus", p3))).toBe("idle/true")
	end)

	it("a player who leaves is forgotten and told nothing more; players are separate", function()
		local w = world(4242)
		w.over[P1], w.over[P2] = true, true
		w.s.engine.mode = "hold"
		ask(w, P1)
		ask(w, P2)
		t.expect(#w.s.engine.calls).toBe(2)
		w.s.leave(P1)
		local heard = #w.s.reports("LobbyStatus", P1)
		w.s.release(1, true)
		w.s.tick(20)
		t.expect(#w.s.reports("LobbyStatus", P1)).toBe(heard)
		t.expect(pairsOf(w.s.reports("LobbyStatus", P2))).toBe("going/true")
	end)

	it("a player who leaves while a trip is under way and comes back may ask again at once", function()
		local w = world(4242)
		w.over[P1] = true
		w.s.engine.mode = "hold"
		ask(w, P1)
		t.expect(#w.s.engine.calls).toBe(1)
		w.s.leave(P1)
		w.s.join(P1)
		ask(w, P1)
		t.expect(#w.s.engine.calls).toBe(2)
	end)

	it(
		"a call abandoned after the cap reports nothing to the newer request: no third call while the second runs",
		function()
			local w = world(4242)
			w.over[P1] = true
			w.s.engine.mode = "hold"
			ask(w, P1) -- call A, held
			w.s.tick(61) -- A is given up on at 60 s
			w.s.tick(4)
			ask(w, P1) -- call B, held; its own cap is at 125
			t.expect(#w.s.engine.calls).toBe(2)
			w.s.release(1, true) -- A fails very late: it was not B
			w.s.tick(4)
			ask(w, P1)
			t.expect(#w.s.engine.calls).toBe(2) -- B is still going: no third call
		end
	)

	it("an abandoned call that returns at last does not shorten the newer request's wait", function()
		local w = world(4242)
		w.over[P1] = true
		w.s.engine.mode = "hold"
		ask(w, P1) -- call A, held
		w.s.tick(61) -- A is given up on at 60 s
		w.s.tick(4) -- the cool-down is over
		ask(w, P1) -- call B at t = 65, held, with its own cap at 125
		w.s.tick(5)
		w.s.release(1, false) -- A returns at t = 70 with no error: it was not B
		w.s.tick(19)
		ask(w, P1) -- t = 89: B is still in the engine
		t.expect(#w.s.engine.calls).toBe(2)
		w.s.tick(40) -- t = 129: B's own cap has passed
		t.expect(pairsOf(w.s.reports("LobbyStatus", P1)))
			.toBe("going/true cooling/true idle/true going/true cooling/true")
	end)

	it(
		"a player who leaves and comes back is told the state again, even if it is the same as before",
		function()
			local w = world(4242)
			local p3 = fake.player(3)
			w.s.join(p3)
			w.s.leave(p3)
			w.s.join(p3)
			t.expect(pairsOf(w.s.reports("LobbyStatus", p3))).toBe("idle/true idle/true")
		end
	)

	it("the lobby's id is read from the attribute the built game place carries, 0 as checked in", function()
		local attribute = gamePlace:GetService("ServerScriptService"):GetAttribute("LobbyPlaceId")
		t.expect(attribute).toBe(0)
		local w = world(nil)
		w.over[P1] = true
		ask(w, P1)
		t.expect(#w.s.engine.calls).toBe(0)
	end)

	it("no place id is written into the server's code", function()
		local code = string.gsub(sourceOf(SERVER), "%-%-[^\n]*", "")
		t.expect((string.find(code, "%d%d%d%d"))).toBe(nil)
		t.expect(string.find(code, '"LobbyPlaceId"', 1, true) ~= nil).toBe(true)
	end)
end)
