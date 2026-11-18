--!strict
-- R0120 code review 001 F1: the real RevivesView (f0186), run from the built game place on a stub engine, draws its
-- line exactly as f0186's Design §4 says: a ScreenGui "Revives" (ResetOnSpawn false, IgnoreGuiInset true,
-- DisplayOrder 1) in the player's PlayerGui, holding one TextLabel "Revives" in the Arcade font, yellow, TextScaled,
-- at (0.2, 0.64) and of size (0.6, 0.05), with no background, empty and hidden until a frame shows it.
local luau = require("@lune/luau")
local place = require("@tests/lib/place")
local t = require("@tests/lib/t")

local gamePlace = place.load()

local function source(): string
	local node: any = gamePlace
	for _, name in { "StarterPlayer", "StarterPlayerScripts", "Client", "RevivesView" } do
		node = node and node:FindFirstChild(name)
	end
	assert(node, "no Client.RevivesView in the game place")
	return node.Source
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

local function started(): any
	local playerGui = instance("PlayerGui")
	local env: { [string]: any } = {
		game = {
			GetService = function(_: any, name: string): any
				assert(name == "Players", name)
				return {
					LocalPlayer = {
						WaitForChild = function(_: any, child: string): any
							assert(child == "PlayerGui", child)
							return playerGui
						end,
					},
				}
			end,
		},
		Enum = { Font = { Arcade = "Arcade", Legacy = "Legacy" } },
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
	local view = luau.load(source(), { environment = env, debugName = "RevivesView" })() :: any
	view.start()
	return playerGui
end

return t.spec("RevivesView's look (f0186 §4)", function(it)
	it("its ScreenGui is Revives, kept across respawns, drawn over the inset, above Flow's fade", function()
		local playerGui = started()
		t.expect(#playerGui.children).toBe(1)
		local gui = playerGui.children[1]
		t.expect(gui.ClassName).toBe("ScreenGui")
		t.expect(gui.Name).toBe("Revives")
		t.expect(gui.ResetOnSpawn).toBe(false)
		t.expect(gui.IgnoreGuiInset).toBe(true)
		t.expect(gui.DisplayOrder).toBe(1)
	end)

	it(
		"its one label is Arcade, yellow, scaled, at (0.2, 0.64) of size (0.6, 0.05), empty and hidden",
		function()
			local gui = started().children[1]
			t.expect(#gui.children).toBe(1)
			local label = gui.children[1]
			t.expect(label.ClassName).toBe("TextLabel")
			t.expect(label.Name).toBe("Revives")
			t.expect(label.Font).toBe("Arcade")
			t.expect(label.TextColor3).toEqual({ r = 255, g = 255, b = 0 })
			t.expect(label.TextScaled).toBe(true)
			t.expect(label.BackgroundTransparency).toBe(1)
			t.expect(label.Position).toEqual({ x = 0.2, y = 0.64 })
			t.expect(label.Size).toEqual({ x = 0.6, y = 0.05 })
			t.expect(label.Text).toBe("")
			t.expect(label.Visible).toBe(false)
		end
	)
end)
