--!strict
-- The Rojo-built place, loaded headlessly with @lune/roblox, for the place tier of every project home (c0185: it was
-- pickman's; each home re-exports it as tests/lib/place.luau, so a spec's closure names its home). It runs from the
-- home: the project files and .cache are the home's. graph.luau resolves requires on the filesystem (what Lune does);
-- resolveRequire resolves them on the instance tree (what Roblox does). Specs that require a home's re-export are
-- selected for every change to that home's place inputs (graph.placeInputs, graph.PLACE_LIB).
local fs = require("@lune/fs")
local graph = require("../../lib/graph")
local process = require("@lune/process")
local roblox = require("@lune/roblox")
local serde = require("@lune/serde")

export type Instance = any -- @lune/roblox Instance

local OUT_PREFIX = ".cache/place-test"

local place = {}

local cached: { [string]: Instance } = {}
-- the script roots of each loaded place: the instance paths of the project file's own "$path" nodes
local rootsOf: { [Instance]: { string } } = setmetatable({}, { __mode = "k" }) :: any

-- Builds a Rojo project (default: default.project.json, the game place) once per process and returns the
-- deserialized DataModel. place.load("lobby.project.json") is the lobby place. The script roots place.scripts lists are
-- read from the project file: every node it maps from inside its own folder.
function place.load(project: string?): Instance
	local file = project or "default.project.json"
	local loaded = cached[file]
	if loaded == nil then
		local decoded: any = serde.decode("json" :: "json", fs.readFile(file))
		fs.writeDir(".cache")
		-- per-process file, so concurrent test processes never read each other's partial builds
		local out = `{OUT_PREFIX}-{os.time()}-{math.random(1, 1e9)}.rbxl`
		local r = process.exec("rojo", { "build", file, "-o", out })
		if not r.ok then
			error(`rojo build failed ({r.code}): {r.stderr}{r.stdout}`)
		end
		local ok, result = pcall(roblox.deserializePlace, fs.readFile(out))
		fs.removeFile(out)
		if not ok then
			error(`could not load {out}: {result}`)
		end
		local roots: { string } = {}
		for _, root in graph.gameRoots(decoded) do
			if graph.insideFolder(root.path) then
				table.insert(roots, root.instance)
			end
		end
		rootsOf[result] = roots
		cached[file] = result
		loaded = result
	end
	return loaded
end

-- Every LuaSourceContainer under the script roots of the loaded place (the nodes its project file maps from its own
-- folder), in GetFullName order.
function place.scripts(game: Instance): { Instance }
	local roots = rootsOf[game]
	if roots == nil then
		error(
			"place.scripts: the place was not loaded by place.load, so its project file's script roots are unknown",
			0
		)
	end
	local out: { Instance } = {}
	local seen: { [Instance]: boolean } = {}
	for _, path in roots do
		local node = game
		for _, name in string.split(path, "/") do
			node = node and node:FindFirstChild(name)
		end
		if node then
			local found: { Instance } = node:GetDescendants()
			table.insert(found, node)
			for _, d in found do
				if d:IsA("LuaSourceContainer") and not seen[d] then
					seen[d] = true
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
