--!strict
-- f0186 AC5: the game over shows how many paid revives the run used. Flow.revivesLine is "REVIVES n" (Lobby's words,
-- "REVIVES 0" for none) at the game over and nothing in any other phase; Flow's overlay itself is unchanged, so the
-- results line stays the score and the level. The game client's RevivesView draws the line, under FlowView's lines,
-- from each frame's play: it runs from its real source on a stub engine here, and the client's Main boots it and
-- shows it every frame.
local Flow = require("@logic/Flow")
local Game = require("@logic/Game")
local Lobby = require("@logic/Lobby")
local Session = require("@logic/Session")
local luau = require("@lune/luau")
local place = require("@tests/lib/place")
local t = require("@tests/lib/t")

local gamePlace = place.load()

local function sourceAt(path: { string }): string
	local node: any = gamePlace
	for _, part in path do
		node = node and node:FindFirstChild(part)
	end
	assert(node, `no {table.concat(path, ".")}`)
	return node.Source
end

local function frame(phase: string, revives: number?): Session.PlayFrame
	return {
		phase = phase :: any,
		level = 4,
		score = 900,
		lives = 0,
		timer = 0,
		frightened = 0,
		revives = revives,
	}
end

-- a stub instance: plain fields, children in order
local function instance(class: string): any
	local self: any = { ClassName = class, children = {} }
	return setmetatable(self, {
		__newindex = function(tbl: any, key: string, value: any)
			if key == "Parent" and value ~= nil then
				table.insert(value.children, tbl)
			end
			rawset(tbl, key, value)
		end,
	})
end

local function find(root: any, name: string, class: string): any
	for _, c in root.children do
		if c.Name == name and c.ClassName == class then
			return c
		end
		local deeper = find(c, name, class)
		if deeper then
			return deeper
		end
	end
	return nil
end

local function revivesView(): (any, any)
	local playerGui = instance("PlayerGui")
	local env: { [string]: any } = {
		game = {
			GetService = function(_: any, name: string): any
				assert(name == "Players", name)
				return {
					LocalPlayer = {
						WaitForChild = function(_: any, _n: string): any
							return playerGui
						end,
					},
				}
			end,
		},
		Enum = { Font = { Arcade = "Arcade" } },
		Instance = { new = instance },
		UDim2 = {
			fromScale = function(x: number, y: number): any
				return { x = x, y = y }
			end,
		},
		Color3 = {
			fromRGB = function(r: number, g: number, b: number): any
				return { r = r, g = g, b = b }
			end,
		},
		require = function(spec: string): any
			local name = string.match(spec, "^@game/ReplicatedStorage/Shared/Logic/([%w_]+)$")
			return (require :: any)("@logic/" .. assert(name, spec))
		end,
	}
	local src = sourceAt({ "StarterPlayer", "StarterPlayerScripts", "Client", "RevivesView" })
	local view = luau.load(src, { environment = env, debugName = "RevivesView" })() :: any
	view.start()
	return view, playerGui
end

return t.spec("f0186 the game over shows the revives", function(it)
	it(
		"the revives line: REVIVES n at the game over, REVIVES 0 for none, nothing in any other phase",
		function()
			t.expect(Flow.revivesLine(frame("gameover", 2))).toBe("REVIVES 2")
			t.expect(Flow.revivesLine(frame("gameover", 1))).toBe(Lobby.revivesText(1))
			t.expect(Flow.revivesLine(frame("gameover", nil))).toBe("REVIVES 0")
			for _, phase in { "ready", "playing", "dying", "levelclear", "offer" } do
				t.expect(Flow.revivesLine(frame(phase, 2))).toBe(nil)
			end
		end
	)

	it("the game over's overlay is unchanged: the results line stays the score and the level", function()
		local bought = Flow.overlay(frame("gameover", 3), Game.CLASSIC_CONFIG)
		t.expect(bought.detail).toBe("SCORE 900   LEVEL 4")
		t.expect(bought).toEqual(Flow.overlay(frame("gameover", nil), Game.CLASSIC_CONFIG))
	end)

	it("RevivesView draws the line at the game over and hides it in every other phase", function()
		local view, gui = revivesView()
		local label = find(gui, "Revives", "TextLabel")
		t.expect(label ~= nil).toBe(true)
		t.expect(label.Visible).toBe(false) -- nothing before the first frame
		view.show(frame("gameover", 2))
		t.expect(label.Text).toBe("REVIVES 2")
		t.expect(label.Visible).toBe(true)
		view.show(frame("ready", 2))
		t.expect(label.Visible).toBe(false)
		view.show(frame("gameover", nil))
		t.expect(label.Text).toBe("REVIVES 0")
		t.expect(label.Visible).toBe(true)
		-- under FlowView's lines (its prompt ends at 0.63 of the screen's height), inside the screen
		t.expect(label.Position.y >= 0.63).toBe(true)
		-- above Flow's fade: FlowView's ScreenGui (with its full-screen black Fade) is DisplayOrder 0 and unchanged, so a
		-- tie would leave the line's place to the engine's order of equal guis (HudView's 1 is the precedent)
		local screen = find(gui, "Revives", "ScreenGui")
		t.expect(screen ~= nil).toBe(true)
		t.expect(type(screen.DisplayOrder) == "number" and screen.DisplayOrder > 0).toBe(true)
		t.expect(label.Position.y + label.Size.y <= 1).toBe(true)
	end)

	it("the client's Main boots RevivesView and shows it every frame with the frame's play", function()
		local main = sourceAt({ "StarterPlayer", "StarterPlayerScripts", "Client", "Main" })
		main = string.gsub(main, "%-%-[^\n]*", "")
		t.expect(string.find(main, "RevivesView%.start%(%)") ~= nil).toBe(true)
		local handler = string.find(main, "OnClientEvent:Connect", 1, true)
		local shown = string.find(main, "RevivesView%.show%(%s*frame%.play%s*%)")
		t.expect(handler ~= nil and shown ~= nil and (shown :: number) > (handler :: number)).toBe(true)
	end)
end)
