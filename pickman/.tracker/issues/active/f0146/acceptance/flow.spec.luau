--!strict
-- f0146 AC3: the gamepad's continue on the game-over overlay, FlowView's real source on the fake client. FlowView binds
-- Pad.CONTINUE: a press asks (one ToLobby request) while the overlay asks, and sends nothing otherwise (in play the
-- same button jumps, through Controls, which passes it on). Flow.CONTINUE_KEYS stays Return and KeypadEnter.
local Flow = require("@logic/Flow")
local Game = require("@logic/Game")
local Pad = require("@logic/Pad")
local Session = require("@logic/Session")
local fake = require("@tests/lib/fakeengine")
local place = require("@tests/lib/place")
local t = require("@tests/lib/t")

local gamePlace = place.load()

local function source(): string
	local node: any = gamePlace
	for _, name in { "StarterPlayer", "StarterPlayerScripts", "Client", "FlowView" } do
		node = node and node:FindFirstChild(name)
	end
	assert(node, "no Client.FlowView in the game place")
	return node.Source
end

local function overlay(phase: string, trip: Flow.Trip?): Flow.Overlay
	local p: any = { phase = phase, level = 2, score = 300, lives = 0, timer = 10, frightened = 0 }
	local play: Session.PlayFrame = p
	return Flow.overlay(play, Game.CLASSIC_CONFIG, trip)
end

local function asked(c: fake.Client): number
	local n = 0
	for _, f in c.firedOn do
		if f.remote == "ToLobby" then
			n += 1
		end
	end
	return n
end

return t.spec("f0146 the pad's continue on the overlay", function(it)
	it("on the fake client, the pad's continue asks while the overlay asks, and not otherwise", function()
		local c = fake.client(gamePlace)
		local view = c.boot(source())
		view.show(overlay("playing"))
		c.key(Pad.CONTINUE)
		t.expect(asked(c)).toBe(0)
		view.show(overlay("gameover", { phase = "cooling", configured = true }))
		c.key(Pad.CONTINUE)
		t.expect(asked(c)).toBe(0)
		view.show(overlay("gameover", { phase = "idle", configured = true }))
		c.key(Pad.CONTINUE)
		t.expect(asked(c)).toBe(1)
		c.key(Pad.CONTINUE, "End")
		t.expect(asked(c)).toBe(1)
		t.expect(Flow.CONTINUE_KEYS).toEqual({ "Return", "KeypadEnter" })
	end)
end)
