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

local OUT_PREFIX = ".cache/place-test"
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
		-- per-process file, so concurrent test processes never read each other's partial builds
		local out = `{OUT_PREFIX}-{os.time()}-{math.random(1, 1e9)}.rbxl`
		local r = process.exec("rojo", { "build", "default.project.json", "-o", out })
		if not r.ok then
			error(`rojo build failed ({r.code}): {r.stderr}{r.stdout}`)
		end
		local ok, loaded = pcall(roblox.deserializePlace, fs.readFile(out))
		fs.removeFile(out)
		if not ok then
			error(`could not load {out}: {loaded}`)
		end
		cached = loaded
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

-- Resolve a string require the way Roblox does, from `from` (a LuaSourceContainer). "@self/"
-- starts at `from`, "./" at its Parent, "../" at its Parent's Parent (each extra leading "../"
-- one more level up), and "@game/" at the root of `from`'s instance tree (the DataModel in the
-- built place; ".." is not allowed after it). Returns the ModuleScript, or nil if a segment is missing, the target is
-- not a ModuleScript, the spec is any other alias (aliases are not valid in src/), or the path is
-- malformed: empty, with empty or "." segments, or ".." anywhere but the leading "../" run.
function place.resolveRequire(from: Instance, spec: string): Instance?
	local node: Instance?
	local rest: string
	local leadingUp = false
	if string.sub(spec, 1, 6) == "@game/" then
		node = from
		while node.Parent ~= nil do
			node = node.Parent
		end
		rest = string.sub(spec, 7)
	elseif string.sub(spec, 1, 6) == "@self/" then
		node, rest = from, string.sub(spec, 7)
	elseif string.sub(spec, 1, 2) == "./" then
		node, rest = from.Parent, string.sub(spec, 3)
	elseif string.sub(spec, 1, 3) == "../" then
		node, rest, leadingUp = from.Parent and from.Parent.Parent, string.sub(spec, 4), true
	else
		return nil
	end
	if rest == "" then
		return nil
	end
	for _, segment in string.split(rest, "/") do
		if node == nil or segment == "" or segment == "." then
			return nil
		elseif segment == ".." then
			if not leadingUp then
				return nil
			end
			node = node.Parent
		else
			leadingUp = false
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
