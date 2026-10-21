--!strict
-- R0034 code review 001 F1: the real FlowView, run on the fake client, with both things that share the end-of-run
-- screen: R0011's all-time rank line (heard on the Rank remote, which the server makes at run time, so the built
-- place lacks it and this spec adds it) and f0065's prompt for the way back. Each is drawn in its own label, and
-- one never overwrites or hides the other.
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

-- the built place's remotes plus the Rank remote the server's Ranks makes when it starts
local withRank = {
	ReplicatedStorage = {
		Remotes = {
			GetChildren = function(_: any): { any }
				local list: { any } = gamePlace.ReplicatedStorage.Remotes:GetChildren()
				table.insert(list, { Name = "Rank" })
				return list
			end,
		},
	},
}

local function overlay(phase: string, trip: Flow.Trip?): Flow.Overlay
	local p: any = { phase = phase, level = 4, score = 2500, lives = 0, timer = 10, frightened = 0 }
	local frame: Session.PlayFrame = p
	return Flow.overlay(frame, Game.CLASSIC_CONFIG, trip)
end

local IDLE: Flow.Trip = { phase = "idle", configured = true }
local COOLING: Flow.Trip = { phase = "cooling", configured = true }

local function boot(): (fake.Client, any)
	local c = fake.client(withRank)
	local view = c.boot(source())
	return c, view
end

local function screen(c: fake.Client): { [string]: string | false }
	local out: { [string]: string | false } = {}
	for _, name in { "Banner", "Detail", "Rank", "Prompt" } do
		local label = c.find(name)
		out[name] = if label.Visible then label.Text else false
	end
	return out
end

return t.spec("R0034 FlowView draws the rank and the way back together", function(it)
	it(
		"a rank heard during game over shows in its own line, under the results and above the prompt",
		function()
			local c, view = boot()
			view.show(overlay("gameover", IDLE))
			c.receive("Rank", 1, 3)
			t.expect(screen(c)).toEqual({
				Banner = "GAME OVER",
				Detail = "SCORE 2500   LEVEL 4",
				Rank = "ALL-TIME #3",
				Prompt = Flow.PROMPT.idle,
			})
			t.expect(c.find("Continue").Visible).toBe(true)
			t.expect(c.find("Rank").Position.Y.Scale < c.find("Prompt").Position.Y.Scale).toBe(true)
		end
	)

	it("a rank heard before game over waits, then shows with the prompt", function()
		local c, view = boot()
		view.show(overlay("playing"))
		c.receive("Rank", 1, 5)
		t.expect(screen(c)).toEqual({ Banner = false, Detail = false, Rank = false, Prompt = false })
		view.show(overlay("gameover", IDLE))
		t.expect(screen(c).Rank).toBe("ALL-TIME #5")
		t.expect(screen(c).Prompt).toBe(Flow.PROMPT.idle)
	end)

	it("a trip report changes the prompt and the tap, and the rank line stays", function()
		local c, view = boot()
		view.show(overlay("gameover", IDLE))
		c.receive("Rank", 1, 2)
		view.show(overlay("gameover", COOLING))
		t.expect(screen(c).Rank).toBe("ALL-TIME #2")
		t.expect(screen(c).Prompt).toBe(Flow.PROMPT.cooling)
		t.expect(c.find("Continue").Visible).toBe(false)
		view.show(overlay("gameover", { phase = "going", configured = true }))
		t.expect(screen(c).Rank).toBe("ALL-TIME #2")
		t.expect(screen(c).Prompt).toBe(Flow.PROMPT.going)
	end)
end)
