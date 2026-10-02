--!strict
-- f0180 AC3: the client draws the HUD with a thin HudView adapter: Main hands it each frame's play record,
-- and it shows Hud.model of it, laid out by Hud.layout for the current viewport. It sends nothing.
local place = require("@tests/lib/place")
local t = require("@tests/lib/t")

local game = place.load()

local function find(path: { string }): any
	local node = game
	for _, name in path do
		node = node and node:FindFirstChild(name)
	end
	return node
end

local function client(name: string): any
	return find({ "StarterPlayer", "StarterPlayerScripts", "Client", name })
end

-- a script's source without comments, so a mention in a comment proves nothing
local function source(node: any): string
	local src = string.gsub(node.Source, "%-%-[^\n]*", "")
	return src
end

local function resolved(from: any): { any }
	local out = {}
	for _, spec in place.requireSpecs(from.Source) do
		local target = place.resolveRequire(from, spec)
		if target == nil then
			error(`{from:GetFullName()}: require of "{spec}" does not resolve in the place`)
		end
		table.insert(out, target)
	end
	return out
end

local function includes(list: { any }, target: any): boolean
	return table.find(list, target) ~= nil
end

local function logic(name: string): any
	return find({ "ReplicatedStorage", "Shared", "Logic", name })
end
return t.spec("f0180 client HUD adapter", function(it)
	it("the client Main requires the HudView module", function()
		local view = client("HudView")
		t.expect(view and view.ClassName).toBe("ModuleScript")
		t.expect(includes(resolved(client("Main")), view)).toBe(true)
	end)

	it("HudView uses the Hud feature: Hud.model for the content, Hud.layout for the sizes", function()
		t.expect(includes(resolved(client("HudView")), logic("Hud"))).toBe(true)
		local src = source(client("HudView"))
		t.expect(string.find(src, "Hud.model(", 1, true) ~= nil).toBe(true)
		t.expect(string.find(src, "Hud.layout(", 1, true) ~= nil).toBe(true)
	end)

	it("HudView lays out again when the viewport changes size", function()
		t.expect(string.find(source(client("HudView")), "ViewportSize", 1, true) ~= nil).toBe(true)
	end)

	it("Main passes each frame's play record to HudView.show", function()
		local src = source(client("Main"))
		t.expect(string.find(src, "HudView%.show%(%s*[%w_]+%.play%s*%)") ~= nil).toBe(true)
	end)

	it("HudView sends nothing to the server", function()
		local src = source(client("HudView"))
		t.expect((string.find(src, "FireServer", 1, true))).toBe(nil)
		t.expect((string.find(src, "Remotes", 1, true))).toBe(nil)
	end)
end)
