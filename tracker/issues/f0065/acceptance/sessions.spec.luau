--!strict
-- f0065 AC3: the game place's real Sessions and Returns, run together on the fake engine over the BUILT game place
-- with the real Logic, the way the server's Main starts them. Sessions.isOver says whether a player's own run is
-- over (asked of Logic), and Returns, started with it, sends that player to the lobby only then. A spy on
-- Session.join hands the spec the session Sessions made, so it can end the run with Session.kill.
local Session = require("@logic/Session")
local fake = require("@tests/lib/fakeengine")
local place = require("@tests/lib/place")
local t = require("@tests/lib/t")

local gamePlace = place.load()

local function sourceOf(name: string): string
	local node = gamePlace:FindFirstChild("ServerScriptService")
	node = node and node:FindFirstChild("Server")
	node = node and node:FindFirstChild(name)
	assert(node, `no Server.{name} in the game place`)
	return (node :: any).Source
end

type World = { s: fake.Server, sessions: any, made: { [string]: Session.Session } }

-- the server as Main boots it: Sessions, then Returns with Sessions.isOver
local function world(): World
	local made: { [string]: Session.Session } = {}
	local spy = setmetatable({
		join = function(s: Session.Session, id: string)
			Session.join(s, id)
			made[id] = s
		end,
	}, { __index = Session })
	local s = fake.server(gamePlace, { LobbyPlaceId = 4242 }, { Session = spy })
	local sessions = s.boot(sourceOf("Sessions"))
	s.boot(sourceOf("Returns"), sessions.isOver)
	return { s = s, sessions = sessions, made = made }
end

local function phaseOf(w: World, player: any): string
	return Session.frame(w.made[tostring(player.UserId)], tostring(player.UserId)).play.phase
end

-- the server's clock runs; whenever the player is in play, a ghost (the spec) takes a life
local function endRun(w: World, player: any)
	local id = tostring(player.UserId)
	for _ = 1, 3000 do
		if Session.isOver(w.made[id], id) then
			return
		end
		if phaseOf(w, player) == "playing" then
			Session.kill(w.made[id], id)
		end
		w.s.tick(0.2)
	end
	error("the run never ended")
end

return t.spec("f0065 Sessions and Returns together", function(it)
	it(
		"Sessions.isOver is false with no session, false in play, and true once the player's own run is over",
		function()
			local w = world()
			local p1, p2 = fake.player(1), fake.player(2)
			w.s.join(p1)
			w.s.join(p2)
			t.expect(w.sessions.isOver(p1)).toBe(false)
			w.s.fire("Ready", p1)
			w.s.fire("Ready", p2)
			t.expect(w.made["1"] ~= nil).toBe(true)
			w.s.tick(0.2)
			t.expect(w.sessions.isOver(p1)).toBe(false)
			endRun(w, p1)
			t.expect(w.sessions.isOver(p1)).toBe(true)
			t.expect(w.sessions.isOver(p2)).toBe(false)
			t.expect(w.sessions.isOver(fake.player(3))).toBe(false)
		end
	)

	it(
		"a request in play goes nowhere; once the run is over one request reaches the engine for that player",
		function()
			local w = world()
			local p1 = fake.player(1)
			w.s.join(p1)
			w.s.fire("Ready", p1)
			w.s.tick(0.2)
			w.s.fire("ToLobby", p1)
			t.expect(#w.s.engine.calls).toBe(0)
			endRun(w, p1)
			w.s.fire("ToLobby", p1)
			w.s.fire("ToLobby", p1)
			t.expect(#w.s.engine.calls).toBe(1)
			t.expect(w.s.engine.calls[1].destination).toBe(4242)
			t.expect(w.s.engine.calls[1].players).toEqual({ p1 })
		end
	)

	it("a player who leaves has no run any more", function()
		local w = world()
		local p1 = fake.player(1)
		w.s.join(p1)
		w.s.fire("Ready", p1)
		endRun(w, p1)
		w.s.leave(p1)
		t.expect(w.sessions.isOver(p1)).toBe(false)
	end)
end)
