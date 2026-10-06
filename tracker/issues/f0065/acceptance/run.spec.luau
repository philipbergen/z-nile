--!strict
-- f0065 AC5 (and R0034 RC1): a run's end as the player lives it. A real Session plays to game over; the real
-- Returns adapter, on the fake engine over the built game place, asks that Session whether the run is over; the
-- client's overlay is Flow.overlay of each frame with the last LobbyStatus the server sent. A request in play does
-- nothing; at game over the results and the prompt show, a tap goes, a failure says try again, and after the
-- cool-down a second tap goes.
local Flow = require("@logic/Flow")
local Game = require("@logic/Game")
local Maze = require("@logic/Maze")
local Session = require("@logic/Session")
local fake = require("@tests/lib/fakeengine")
local place = require("@tests/lib/place")
local t = require("@tests/lib/t")

local gamePlace = place.load()
local SMALL = Maze.parse({ "######", "#o..P#", "######" }, "small")
local PAUSES: Game.Config =
	{ lives = 3, extraLifeScore = 10000, readyTicks = 3, dyingTicks = 4, levelClearTicks = 12, tickRate = 30 }
local RULES: Session.Config = {
	movement = { speed = 30, turnBufferTicks = 24 },
	maxIntentsPerTick = 4,
	play = PAUSES,
	eatSlowdown = true,
}

local function returnsSource(): string
	local node: any = gamePlace
	for _, name in { "ServerScriptService", "Server", "Returns" } do
		node = node and node:FindFirstChild(name)
	end
	assert(node, "no Returns in the game place")
	return node.Source
end

type Client = { session: Session.Session, server: fake.Server, player: any }

-- the overlay the client draws now: this frame, and the server's latest LobbyStatus to this player
local function overlay(c: Client): Flow.Overlay
	local reports = c.server.reports("LobbyStatus", c.player)
	local last = reports[#reports]
	local trip: Flow.Trip? = if last then { phase = last[1], configured = last[2] } else nil
	return Flow.overlay(Session.frame(c.session, tostring(c.player.UserId)).play, PAUSES, trip)
end

-- the client taps: it asks only when the overlay says a tap asks (FlowView's rule)
local function tap(c: Client)
	if overlay(c).tap then
		c.server.fire("ToLobby", c.player)
	end
end

local function boot(lobby: any): Client
	local player = fake.player(7)
	local id = tostring(player.UserId)
	local s = Session.new(SMALL, 3, RULES)
	Session.join(s, id)
	local server = fake.server(gamePlace, { LobbyPlaceId = lobby })
	server.join(player)
	server.boot(returnsSource(), function(p: any): boolean
		return Session.isOver(s, tostring(p.UserId))
	end)
	return { session = s, server = server, player = player }
end

local function untilPhase(c: Client, phase: string)
	for _ = 1, 400 do
		if Session.frame(c.session, tostring(c.player.UserId)).play.phase == phase then
			return
		end
		Session.step(c.session)
	end
	error(`never reached {phase}`)
end

local function gameOver(c: Client)
	local id = tostring(c.player.UserId)
	for _ = 1, 3 do
		untilPhase(c, "playing")
		Session.kill(c.session, id)
	end
	untilPhase(c, "gameover")
end

return t.spec("f0065 from game over back to the lobby", function(it)
	it("results, a tap, a failed trip, the wait, a second tap and the trip", function()
		local c = boot(5555)
		untilPhase(c, "playing")
		-- a request in play does nothing, even sent by hand
		c.server.fire("ToLobby", c.player)
		t.expect(#c.server.engine.calls).toBe(0)
		t.expect(overlay(c).prompt).toBe(nil)

		gameOver(c)
		local results = overlay(c)
		t.expect(results.banner).toBe("GAME OVER")
		t.expect(results.detail).toBe("SCORE 0   LEVEL 1")
		t.expect(results.prompt).toBe(Flow.PROMPT.idle)
		t.expect(results.tap).toBe(true)
		t.expect(results.cursor).toBe(true)

		-- the results wait for the tap
		for _ = 1, 60 do
			Session.step(c.session)
		end
		c.server.tick(5)
		t.expect(#c.server.engine.calls).toBe(0)
		t.expect(overlay(c).banner).toBe("GAME OVER")

		-- a tap goes; the engine refuses; the player is told to try again and a tap does nothing for 3 s
		c.server.engine.mode = "error"
		tap(c)
		t.expect(#c.server.engine.calls).toBe(1)
		t.expect(c.server.engine.calls[1].destination).toBe(5555)
		local failed = overlay(c)
		t.expect(failed.banner).toBe("GAME OVER")
		t.expect(failed.prompt).toBe(Flow.PROMPT.cooling)
		t.expect(failed.tap).toBe(false)
		tap(c)
		c.server.fire("ToLobby", c.player)
		t.expect(#c.server.engine.calls).toBe(1)

		-- after the cool-down the prompt is back and a second tap goes
		c.server.tick(3.5)
		t.expect(overlay(c).prompt).toBe(Flow.PROMPT.idle)
		c.server.engine.mode = "hold"
		tap(c)
		t.expect(#c.server.engine.calls).toBe(2)
		local going = overlay(c)
		t.expect(going.prompt).toBe(Flow.PROMPT.going)
		t.expect(going.tap).toBe(false)
		t.expect(going.detail).toBe("SCORE 0   LEVEL 1")
		t.expect(c.server.engine.calls[2].players).toEqual({ c.player })
	end)

	it("with no lobby set up the results say so and nothing reaches the engine", function()
		local c = boot(0)
		gameOver(c)
		-- before any report the client offers the way back; the server's answer corrects it
		c.server.fire("ToLobby", c.player)
		t.expect(#c.server.engine.calls).toBe(0)
		local o = overlay(c)
		t.expect(o.prompt).toBe(Flow.PROMPT.unset)
		t.expect(o.tap).toBe(false)
		t.expect(o.banner).toBe("GAME OVER")
	end)
end)
