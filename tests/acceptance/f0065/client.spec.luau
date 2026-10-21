--!strict
-- f0065 AC4: the real FlowView, run on the fake engine's client over the BUILT game place with the real Flow. It
-- keeps the server's latest LobbyStatus for Flow.overlay, shows the full-screen tap target only while a tap asks,
-- and sends ToLobby with no arguments, once per tap, click or continue key, only then.
local Flow = require("@logic/Flow")
local Game = require("@logic/Game")
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

local function play(phase: string): Session.PlayFrame
	local p: any = { phase = phase, level = 2, score = 300, lives = 0, timer = 10, frightened = 0 }
	return p
end

local function overlay(phase: string, trip: Flow.Trip?): Flow.Overlay
	return Flow.overlay(play(phase), Game.CLASSIC_CONFIG, trip)
end

local function boot(): (fake.Client, any)
	local c = fake.client(gamePlace)
	local view = c.boot(source())
	return c, view
end

-- how many requests the client sent on ToLobby, and that each had no arguments
local function asked(c: fake.Client): number
	local n = 0
	for _, f in c.firedOn do
		t.expect(f.remote).toBe("ToLobby")
		t.expect(#f.args).toBe(0)
		n += 1
	end
	return n
end

return t.spec("f0065 FlowView on the fake client", function(it)
	it("has no report before the server sends one, then keeps the latest LobbyStatus", function()
		local c, view = boot()
		t.expect(view.trip()).toBe(nil)
		c.receive("LobbyStatus", "cooling", true)
		t.expect(view.trip()).toEqual({ phase = "cooling", configured = true })
		c.receive("LobbyStatus", "idle", false)
		t.expect(view.trip()).toEqual({ phase = "idle", configured = false })
		c.receive("LobbyStatus", "going", true)
		t.expect(view.trip()).toEqual({ phase = "going", configured = true })
	end)

	it("hears reports only on LobbyStatus", function()
		local c, view = boot()
		c.receive("ToLobby", "cooling", true)
		c.receive("Snapshot", "cooling", true)
		t.expect(view.trip()).toBe(nil)
	end)

	it("shows the tap target only while a tap asks, and a tap then sends one request", function()
		local c, view = boot()
		for _, phase in { "ready", "playing", "dying", "levelclear" } do
			view.show(overlay(phase, { phase = "idle", configured = true }))
			t.expect(c.find("Continue").Visible).toBe(false)
		end
		view.show(overlay("gameover", { phase = "going", configured = true }))
		t.expect(c.find("Continue").Visible).toBe(false)
		view.show(overlay("gameover", { phase = "idle", configured = false }))
		t.expect(c.find("Continue").Visible).toBe(false)
		t.expect(asked(c)).toBe(0)
		view.show(overlay("gameover", { phase = "idle", configured = true }))
		local target = c.find("Continue")
		t.expect(target.Visible).toBe(true)
		t.expect(target.Size).toEqual({ X = { Scale = 1, Offset = 0 }, Y = { Scale = 1, Offset = 0 } })
		c.click("Continue")
		t.expect(asked(c)).toBe(1)
	end)

	it("a tap that is not live sends nothing, even if the button is hit", function()
		local c, view = boot()
		view.show(overlay("gameover", { phase = "cooling", configured = true }))
		c.find("Continue").Activated:fire()
		t.expect(asked(c)).toBe(0)
	end)

	it("Return and KeypadEnter send one request each at game over, other keys and key-up nothing", function()
		local c, view = boot()
		view.show(overlay("playing"))
		c.key("Return")
		t.expect(asked(c)).toBe(0)
		view.show(overlay("gameover", { phase = "idle", configured = true }))
		for _, result in c.key("Return") do
			t.expect(result).toBe("ContextActionResult.Pass")
		end
		t.expect(asked(c)).toBe(1)
		c.key("KeypadEnter")
		t.expect(asked(c)).toBe(2)
		c.key("Return", "End")
		c.key("Space")
		t.expect(asked(c)).toBe(2)
	end)

	it(
		"binds the continue keys without an on-screen touch button: a tap anywhere is the touch way",
		function()
			local c = boot()
			t.expect(#c.bindings >= 1).toBe(true)
			for _, b in c.bindings do
				t.expect(b.touch).toBe(false)
			end
		end
	)

	it("draws the results and the prompt the overlay gives", function()
		local c, view = boot()
		view.show(overlay("gameover", { phase = "cooling", configured = true }))
		t.expect(c.find("Banner").Text).toBe("GAME OVER")
		t.expect(c.find("Detail").Text).toBe("SCORE 300   LEVEL 2")
		t.expect(c.find("Prompt").Text).toBe(Flow.PROMPT.cooling)
		t.expect(c.find("Prompt").Visible).toBe(true)
		view.show(overlay("playing"))
		t.expect(c.find("Prompt").Visible).toBe(false)
	end)
end)
