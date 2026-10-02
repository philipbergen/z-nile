--!strict
-- f0300 AC3: the client presents the flow with a thin FlowView adapter: Main computes Flow.overlay of each
-- frame with the server's rules and hands its parts to FlowView, MazeView (the flash) and Camera (the cursor).
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
return t.spec("f0300 client flow adapter", function(it)
	it("the client Main requires the FlowView module", function()
		local view = client("FlowView")
		t.expect(view and view.ClassName).toBe("ModuleScript")
		t.expect(includes(resolved(client("Main")), view)).toBe(true)
	end)

	it("Main computes Flow.overlay with the server's rules, Session.GAME_CONFIG", function()
		t.expect(includes(resolved(client("Main")), logic("Flow"))).toBe(true)
		local src = source(client("Main"))
		t.expect(string.find(src, "Flow%.overlay%(%s*[%w_]+%.play%s*,") ~= nil).toBe(true)
		t.expect(string.find(src, "Session.GAME_CONFIG", 1, true) ~= nil).toBe(true)
	end)

	it("Main hands the overlay to FlowView.show, MazeView.flash and Camera.setCursor", function()
		local src = source(client("Main"))
		t.expect(string.find(src, "FlowView%.show%(") ~= nil).toBe(true)
		t.expect(string.find(src, "MazeView%.flash%([^)]*%.flash%s*%)") ~= nil).toBe(true)
		t.expect(string.find(src, "Camera%.setCursor%(%s*[%w_]+%.playAgain%s*%)") ~= nil).toBe(true)
	end)

	it("MazeView can light its walls and Camera can free the mouse", function()
		t.expect(string.find(source(client("MazeView")), "function MazeView.flash(", 1, true) ~= nil)
			.toBe(true)
		local camera = source(client("Camera"))
		t.expect(string.find(camera, "function Camera.setCursor(", 1, true) ~= nil).toBe(true)
		t.expect(string.find(camera, "MouseBehavior.Default", 1, true) ~= nil).toBe(true)
	end)

	it("Camera no longer locks the mouse unconditionally: the lock depends on the cursor", function()
		local camera = source(client("Camera"))
		t.expect((string.find(camera, "MouseBehavior%s*=%s*Enum%.MouseBehavior%.LockCenter"))).toBe(nil)
		t.expect((string.find(camera, "MouseIconEnabled%s*=%s*false"))).toBe(nil)
	end)

	it("the cursor flag frees the mouse and shows the icon, never the other way round", function()
		local camera = source(client("Camera"))
		local flag = string.match(
			camera,
			"MouseBehavior%s*=%s*if%s+([%w_]+)%s+then%s+Enum%.MouseBehavior%.Default%s+else%s+Enum%.MouseBehavior%.LockCenter"
		)
		t.expect(flag ~= nil).toBe(true)
		t.expect(string.find(camera, "MouseIconEnabled%s*=%s*" .. (flag :: string) .. "%f[^%w_]") ~= nil)
			.toBe(true)
		t.expect((string.find(camera, "MouseIconEnabled%s*=%s*not%f[^%w_]"))).toBe(nil)
	end)

	it("Main starts every adapter before it signals Ready, so no frame meets an unbuilt view", function()
		local src = source(client("Main"))
		local ready = string.find(src, "ready:FireServer(", 1, true)
		t.expect(ready ~= nil).toBe(true)
		for _, start in { "PelletView.start(", "HudView.start(", "FlowView.start(", "Camera.start(" } do
			local at = string.find(src, start, 1, true)
			t.expect(at ~= nil and at < (ready :: number)).toBe(true)
		end
	end)

	it("FlowView fires the PlayAgain remote, on Flow's keys", function()
		t.expect(includes(resolved(client("FlowView")), logic("Flow"))).toBe(true)
		local src = source(client("FlowView"))
		t.expect(string.find(src, '"PlayAgain"', 1, true) ~= nil).toBe(true)
		t.expect(string.find(src, ":FireServer(", 1, true) ~= nil).toBe(true)
		t.expect(string.find(src, "Flow.PLAY_AGAIN_KEYS", 1, true) ~= nil).toBe(true)
	end)

	it("FlowView sends the request with no arguments: the server knows who asked", function()
		for call in string.gmatch(source(client("FlowView")), ":FireServer%b()") do
			t.expect(call).toBe(":FireServer()")
		end
	end)
end)
