--!strict
-- The Rojo-built place, loaded headlessly with @lune/roblox, for tests/place specs.
-- graph.luau resolves requires on the filesystem (what Lune does); resolveRequire resolves them
-- on the instance tree (what Roblox does). Specs that require this file are selected by
-- scripts/affected for every src/ or default.project.json change (graph.PLACE_LIB).
local fs = require("@lune/fs")
local graph = require("@scripts/lib/graph")
local process = require("@lune/process")
local roblox = require("@lune/roblox")

export type Instance = any -- @lune/roblox Instance

local OUT = ".cache/place-test.rbxl"
local SCRIPT_ROOTS = {
	{ "ReplicatedStorage", "Shared" },
	{ "ServerScriptService", "Server" },
	{ "StarterPlayer", "StarterPlayerScripts", "Client" },
}

local place = {}

local cached: Instance? = nil

-- Builds default.project.json once per process and returns the deserialized DataModel.
function place.load(): Instance
	if cached == nil then
		fs.writeDir(".cache")
		local r = process.exec("rojo", { "build", "default.project.json", "-o", OUT })
		if not r.ok then
			error(`rojo build failed ({r.code}): {r.stderr}{r.stdout}`)
		end
		cached = roblox.deserializePlace(fs.readFile(OUT))
	end
	return cached
end

-- Every LuaSourceContainer under the three script roots, in GetFullName order.
function place.scripts(game: Instance): { Instance }
	local out: { Instance } = {}
	for _, path in SCRIPT_ROOTS do
		local node = game
		for _, name in path do
			node = node and node:FindFirstChild(name)
		end
		if node then
			for _, d in node:GetDescendants() do
				if d:IsA("LuaSourceContainer") then
					table.insert(out, d)
				end
			end
		end
	end
	table.sort(out, function(a, b)
		return a:GetFullName() < b:GetFullName()
	end)
	return out
end

-- Resolve a string require the way Roblox does, from `from` (a LuaSourceContainer). "@self"
-- starts at `from`, "./" at its Parent, "../" at its Parent's Parent (each extra "../" one more
-- level up). Returns the ModuleScript, or nil if a segment is missing, the target is not a
-- ModuleScript, or the spec is an alias (aliases are not valid in src/).
function place.resolveRequire(from: Instance, spec: string): Instance?
	local node: Instance? = nil
	local rest: string
	if spec == "@self" or string.sub(spec, 1, 6) == "@self/" then
		node, rest = from, string.sub(spec, 7)
	elseif string.sub(spec, 1, 2) == "./" then
		node, rest = from.Parent, string.sub(spec, 3)
	elseif string.sub(spec, 1, 3) == "../" then
		node, rest = from.Parent and from.Parent.Parent, string.sub(spec, 4)
	else
		return nil
	end
	for segment in string.gmatch(rest, "[^/]+") do
		if node == nil then
			return nil
		elseif segment == ".." then
			node = node.Parent
		elseif segment ~= "." then
			node = node:FindFirstChild(segment)
		end
	end
	if node ~= nil and node.ClassName == "ModuleScript" then
		return node
	end
	return nil
end

-- String-literal require specs in `source`, ignoring comments (same pattern as graph.luau).
function place.requireSpecs(source: string): { string }
	local out: { string } = {}
	for spec in string.gmatch(graph.stripComments(source), graph.REQUIRE_PATTERN) do
		table.insert(out, spec)
	end
	return out
end

return place
