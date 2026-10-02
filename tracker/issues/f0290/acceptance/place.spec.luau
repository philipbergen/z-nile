--!strict
-- f0290 AC4: the client draws pellets with a thin PelletView adapter: Main hands it each frame's pellets,
-- and it decodes them with Pellets and places and pulses them with View. It decides nothing and sends nothing.
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

return t.spec("f0290 client pellet adapter", function(it)
	it("the client Main requires the PelletView module", function()
		local view = client("PelletView")
		t.expect(view and view.ClassName).toBe("ModuleScript")
		t.expect(includes(resolved(client("Main")), view)).toBe(true)
	end)

	it("PelletView uses the Pellets and View features", function()
		local deps = resolved(client("PelletView"))
		t.expect(includes(deps, logic("Pellets"))).toBe(true)
		t.expect(includes(deps, logic("View"))).toBe(true)
	end)

	it(
		"PelletView decodes with Pellets.decode, lists slots with Pellets.slots, and places and pulses with View",
		function()
			local src = source(client("PelletView"))
			for _, call in { "Pellets.decode(", "Pellets.slots(", "View.pellet(", "View.pulse(" } do
				t.expect(string.find(src, call, 1, true) ~= nil).toBe(true)
			end
		end
	)

	it("Main passes each frame's pellets field to PelletView.show", function()
		local src = source(client("Main"))
		t.expect(string.find(src, "PelletView%.show%(%s*[%w_]+%s*,%s*[%w_]+%.pellets%s*%)") ~= nil).toBe(true)
	end)

	it("PelletView sends nothing to the server", function()
		local src = source(client("PelletView"))
		t.expect((string.find(src, "FireServer", 1, true))).toBe(nil)
		t.expect((string.find(src, "Remotes", 1, true))).toBe(nil)
	end)
end)
