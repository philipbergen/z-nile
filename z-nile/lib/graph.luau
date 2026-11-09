--!strict
-- Static require graph for the repo. Used by z-nile/affected.luau and tests/meta.
-- Resolves string requires the same way Luau does: "./" and "../" relative to the
-- requiring file (for init.luau: relative to its directory's parent), "@self/",
-- and aliases from .luaurc. Non-string requires are reported as "dynamic". Paths are relative to the current
-- folder; one above it keeps its leading "../" (a project's home reaching the root's files, c0120).

local fs = require("@lune/fs")
local process = require("@lune/process")
local serde = require("@lune/serde")

export type Graph = {
	files: { string },
	deps: { [string]: { string } }, -- file -> resolved repo-relative files it requires
	unresolved: { { file: string, spec: string } },
	dynamic: { string }, -- files containing require() with a non-literal argument
}

export type Unreadable = {
	instance: string, -- the node's "/"-joined instance path ("" for the tree node)
	what: string,
	dollar: boolean?,
}

export type GameRoot = {
	instance: string, -- "/"-joined instance names from the DataModel, e.g. "ReplicatedStorage/Shared"
	path: string, -- the node's normalized "$path", e.g. "src/shared"
}

local graph = {}

-- Specs that require this library load the Rojo-built place, so they implicitly depend on every file the place is
-- built from: the home's project files and every folder or file they map with a "$path", a folder of another home
-- included (c0185: `../arcade/src/shared`). See graph.placeInputs and affectedSpecs.
-- A project's home has its own (c0120): `<home>/tests/lib/place.luau` stands for that home's place inputs. Since c0185 it
-- is a one-line re-export of the shared harness's z-nile/tests/lib/place.luau, so the closure of a place spec names its home.
graph.PLACE_LIB = "tests/lib/place.luau"

-- Captures the spec of a string-literal require. Apply to stripComments output only.
graph.REQUIRE_PATTERN = "require%(%s*[\"']([^\"']+)[\"']"

local function exists(path: string): boolean
	return fs.isFile(path)
end

function graph.listLuau(dir: string, out: { string }?): { string }
	local acc = out or {}
	if not fs.isDir(dir) then
		return acc
	end
	for _, name in fs.readDir(dir) do
		local path = `{dir}/{name}`
		if fs.isDir(path) then
			graph.listLuau(path, acc)
		elseif string.match(name, "%.luau$") then
			table.insert(acc, path)
		end
	end
	table.sort(acc)
	return acc
end

local function normalize(path: string): string
	local parts: { string } = {}
	for part in string.gmatch(path, "[^/]+") do
		if part == ".." then
			-- a ".." that climbs above the current folder is kept (c0120)
			if #parts == 0 or parts[#parts] == ".." then
				table.insert(parts, "..")
			else
				table.remove(parts)
			end
		elseif part ~= "." then
			table.insert(parts, part)
		end
	end
	return table.concat(parts, "/")
end

local function dirname(path: string): string
	return string.match(path, "^(.*)/[^/]*$") or "."
end

local function isInit(path: string): boolean
	return string.match(path, "/init%.luau$") ~= nil or path == "init.luau"
end

-- The current folder, absolute, without a trailing "/".
local function cwd(): string
	local c = string.gsub(process.cwd, "/+$", "")
	return if c == "" then "/" else c
end

-- An absolute path without "." or ".." segments.
local function absNormalize(path: string): string
	local parts: { string } = {}
	for part in string.gmatch(path, "[^/]+") do
		if part == ".." then
			table.remove(parts)
		elseif part ~= "." then
			table.insert(parts, part)
		end
	end
	return "/" .. table.concat(parts, "/")
end

-- An absolute path relative to the current folder ("../" when it is above it).
local function relative(abs: string): string
	local a = string.split(string.sub(cwd(), 2), "/")
	local b = string.split(string.sub(abs, 2), "/")
	if cwd() == "/" then
		a = {}
	end
	local i = 1
	while i <= #a and i <= #b and a[i] == b[i] do
		i += 1
	end
	local parts: { string } = {}
	for _ = i, #a do
		table.insert(parts, "..")
	end
	for j = i, #b do
		if b[j] ~= "" then
			table.insert(parts, b[j])
		end
	end
	return if #parts == 0 then "." else table.concat(parts, "/")
end

local aliasCache: { [string]: { [string]: string } } = {}
-- The aliases a file in `dir` (relative to the current folder; default ".") sees, as Lune and luau-lsp resolve them
-- (c0120 U2): every .luaurc from the filesystem root down to `dir`, an alias in a nearer one replacing the same alias
-- in a farther one. Each target is relative to its own .luaurc's folder; it is returned relative to the current
-- folder (it may start with "../"). Keys are lowercase.
function graph.aliases(dir: string?): { [string]: string }
	local start = absNormalize(`{cwd()}/{dir or "."}`)
	local hit = aliasCache[start]
	if hit then
		return hit
	end
	local folders: { string } = {}
	local at = start
	while true do
		table.insert(folders, 1, at)
		if at == "/" then
			break
		end
		at = string.match(at, "^(.*)/[^/]+$") or "/"
		if at == "" then
			at = "/"
		end
	end
	local map: { [string]: string } = {}
	for _, folder in folders do
		local file = if folder == "/" then "/.luaurc" else `{folder}/.luaurc`
		if fs.isFile(file) then
			local cfg = serde.decode("json", fs.readFile(file))
			for k, v in cfg.aliases or {} do
				if type(v) == "string" and string.sub(v, 1, 1) ~= "~" then
					local target = if string.sub(v, 1, 1) == "/" then v else `{folder}/{v}`
					map[string.lower(k)] = normalize(relative(absNormalize(target)))
				end
			end
		end
	end
	aliasCache[start] = map
	return map
end

local gameRootsCache: { GameRoot }? = nil

local RESERVED: { [any]: boolean } = {
	["$className"] = true,
	["$id"] = true,
	["$ignoreUnknownInstances"] = true,
	["$path"] = true,
	["$properties"] = true,
	["$attributes"] = true,
}

local function article(value: any): string
	return `a {type(value)}`
end

-- What a "$path" that is neither a string nor {"optional": <string>} is, for the home rule's report (c0246).
local function describe(value: any): string
	if type(value) == "table" then
		local optional = (value :: any).optional
		if optional ~= nil then
			return `an optional that is {article(optional)}`
		end
		return if (value :: any)[1] ~= nil then "an array" else "a table without an optional string"
	end
	return article(value)
end

-- Every "$path" of a Rojo project and the instance path of the node that maps it, in both of Rojo's forms (a string, or the
-- `optional` string of a table), at any depth, the tree node itself included (instance ""). The one walker of a project's
-- mappings (c0185): gameRoots, placeInputs and the home rule all read them through here.
local function walkMappings(node: any, prefix: { string }, out: { GameRoot }, bad: { Unreadable }?)
	local path = node["$path"]
	if type(path) == "table" and type((path :: any).optional) == "string" then
		path = (path :: any).optional
	end
	if bad and path ~= nil and type(path) ~= "string" then
		table.insert(bad, { instance = table.concat(prefix, "/"), what = describe(path) })
	end
	if type(path) == "string" then
		-- an absolute path stays absolute (Rojo accepts one; it names nothing of a home)
		table.insert(out, {
			instance = table.concat(prefix, "/"),
			path = if string.sub(path, 1, 1) == "/" then path else normalize(path),
		})
	end
	for key, child in node do
		if type(child) == "table" and string.sub(tostring(key), 1, 1) == "$" and not RESERVED[key] then
			if bad then
				local inst = table.clone(prefix)
				table.insert(inst, tostring(key))
				table.insert(bad, {
					instance = table.concat(inst, "/"),
					what = "a node Rojo builds although its key starts with $",
					dollar = true,
				})
			end
		elseif string.sub(tostring(key), 1, 1) ~= "$" and type(child) == "table" then
			local inst = table.clone(prefix)
			table.insert(inst, key)
			walkMappings(child, inst, out, bad)
		end
	end
end

-- Every mapping of a decoded project (instance path "/"-joined, "$path" normalized against the project file's folder, so
-- "../arcade/src/shared" stays as written), in tree order. A table without a tree has none.
function graph.mappings(project: any): { GameRoot }
	local out: { GameRoot } = {}
	if type(project) == "table" and type((project :: any).tree) == "table" then
		walkMappings((project :: any).tree, {}, out)
	end
	return out
end

-- Every node of a decoded project whose "$path" mappings() skips: a value that is neither a string nor a table with an
-- `optional` string (c0246), sorted by instance path. Rojo 7.7.1 parses a one-element array of strings as a path too, so
-- this is a report of what the reader cannot see, never a guess at what Rojo would build.
function graph.unreadable(project: any): { Unreadable }
	local bad: { Unreadable } = {}
	if type(project) == "table" and type((project :: any).tree) == "table" then
		walkMappings((project :: any).tree, {}, {}, bad)
	end
	table.sort(bad, function(a, b)
		return a.instance < b.instance
	end)
	return bad
end

-- Whether a "$path" written in a project file stays inside the folder of that file once its "." and ".." segments are
-- applied ("src/../../arcade" does not).
function graph.insideFolder(path: string): boolean
	if string.sub(path, 1, 1) == "/" then
		return false
	end
	local depth = 0
	for seg in string.gmatch(path, "[^/]+") do
		if seg == ".." then
			depth -= 1
			if depth < 0 then
				return false
			end
		elseif seg ~= "." then
			depth += 1
		end
	end
	return true
end

-- Every node of the Rojo project tree that has a "$path", longest instance path first. `project` is
-- a decoded project table; nil reads ./default.project.json and caches that result per process (an
-- explicit project is never cached and never answered from the cache). No ./default.project.json (the repository
-- root once the game moved into pickman/, c0120) has no roots.
function graph.gameRoots(project: any?): { GameRoot }
	if project == nil and gameRootsCache ~= nil then
		return gameRootsCache
	end
	local decoded = project
		or (
			if fs.isFile("default.project.json")
				then serde.decode("json", fs.readFile("default.project.json"))
				else {}
		)
	local out: { GameRoot } = {}
	for _, m in graph.mappings(decoded) do
		if m.instance ~= "" then
			table.insert(out, m)
		end
	end
	table.sort(out, function(a, b)
		if #a.instance ~= #b.instance then
			return #a.instance > #b.instance
		end
		return a.instance < b.instance
	end)
	if project == nil then
		table.freeze(out)
		gameRootsCache = out
	end
	return out
end

-- The folder whose default.project.json builds the place `file` belongs to (c0120): the nearest one at or above the
-- file's folder, up to the current folder, or "." when there is none.
local function placeDirOf(file: string): string
	local d = dirname(file)
	while d ~= "." and d ~= "" and string.sub(d, 1, 2) ~= ".." do
		if fs.isFile(`{d}/default.project.json`) then
			return d
		end
		d = dirname(d)
	end
	return "."
end

local rootsAt: { [string]: { GameRoot } } = {}
-- graph.gameRoots() for the place built from `<dir>/default.project.json`, its paths relative to the current folder.
local function gameRootsAt(dir: string): { GameRoot }
	if dir == "." then
		return graph.gameRoots()
	end
	local hit = rootsAt[dir]
	if hit then
		return hit
	end
	local out: { GameRoot } = {}
	for _, r in graph.gameRoots(serde.decode("json", fs.readFile(`{dir}/default.project.json`))) do
		table.insert(out, { instance = r.instance, path = normalize(`{dir}/{r.path}`) })
	end
	rootsAt[dir] = out
	return out
end

-- "@game/<seg>/<seg>..." to a repo-relative .luau file, or nil. `roots` nil means
-- graph.gameRoots(), looked up through the module table at call time.
function graph.resolveGame(spec: string, roots: { GameRoot }?): string?
	if string.sub(spec, 1, 6) ~= "@game/" then
		return nil
	end
	local segs = string.split(string.sub(spec, 7), "/")
	for _, seg in segs do
		if seg == "" or seg == "." or seg == ".." then
			return nil
		end
	end
	if segs[#segs] == "init" then
		return nil -- Roblox names the instance after the directory, never "init"
	end
	for _, root in roots or graph.gameRoots() do
		local rootSegs = string.split(root.instance, "/")
		local match = #rootSegs <= #segs
		if match then
			for i, seg in rootSegs do
				if segs[i] ~= seg then
					match = false
					break
				end
			end
		end
		if match then
			-- the longest mapped node owns its subtree: no fallback to a shorter root
			local base = root.path
			for i = #rootSegs + 1, #segs do
				base ..= "/" .. segs[i]
			end
			if string.match(base, "%.server$") or string.match(base, "%.client$") then
				return nil
			end
			if exists(base .. ".luau") then
				return base .. ".luau"
			elseif exists(base .. "/init.luau") then
				return base .. "/init.luau"
			end
			return nil
		end
	end
	return nil
end

-- true for "./…", "../…", "@self/<x>" and "@game/ReplicatedStorage/<x>", and, for a file of a server root
-- (`fromServer`, c0185), "@game/ServerStorage/<x>": the only specs src may use. ServerStorage never replicates, so a
-- client or shared file requiring it fails at runtime; ServerScriptService and StarterPlayer stay refused everywhere.
function graph.srcAliasAllowed(spec: string, fromServer: boolean?): boolean
	return string.sub(spec, 1, 2) == "./"
		or string.sub(spec, 1, 3) == "../"
		or string.sub(spec, 1, 6) == "@self/"
		or string.sub(spec, 1, 24) == "@game/ReplicatedStorage/"
		or (fromServer == true and string.sub(spec, 1, 20) == "@game/ServerStorage/")
end

-- The one lister of a folder's Rojo projects (c0185): every `*.project.json` directly in `dir`, in name order, decoded. A file
-- that is not a Rojo project (JSON with a tree) is an error naming it: neither the selector nor the server-file rule can be
-- judged without it. A missing folder holds none.
local function projectsIn(dir: string): { { name: string, project: any } }
	local names: { string } = {}
	if fs.isDir(dir) then
		for _, name in fs.readDir(dir) do
			if string.match(name, "%.project%.json$") and fs.isFile(`{dir}/{name}`) then
				table.insert(names, name)
			end
		end
	end
	table.sort(names)
	local out: { { name: string, project: any } } = {}
	for _, name in names do
		local ok, project = pcall(serde.decode, "json" :: "json", fs.readFile(`{dir}/{name}`))
		if not ok or type(project) ~= "table" or type((project :: any).tree) ~= "table" then
			error(
				`graph: {dir}/{name} is not a Rojo project (JSON with a tree): its mappings can't be told`,
				0
			)
		end
		table.insert(out, { name = name, project = project })
	end
	return out
end

-- The mappings (graph.gameRoots) of every project of the current folder, one list per place.
local function currentPlaces(): { { GameRoot } }
	local out: { { GameRoot } } = {}
	for _, entry in projectsIn(".") do
		table.insert(out, graph.gameRoots(entry.project))
	end
	return out
end

-- Whether `file` (relative to the current folder) is a server file (c0185): at least one place maps it, and every place that
-- maps it does so under ServerScriptService or ServerStorage, the longest mapped path owning it within each place. A folder
-- one place keeps on the server and another replicates (a ServerStorage require would fail there) is no server file.
-- `places` injects the places' mappings, one list each (default: every project file of the current folder).
function graph.serverFile(file: string, places: { { GameRoot } }?): boolean
	local owners, servers = 0, 0
	for _, roots in places or currentPlaces() do
		local best: GameRoot? = nil
		for _, root in roots do
			if file == root.path or string.sub(file, 1, #root.path + 1) == root.path .. "/" then
				if best == nil or #root.path > #(best :: GameRoot).path then
					best = root
				end
			end
		end
		if best ~= nil then
			owners += 1
			local inst = (best :: GameRoot).instance
			if
				inst == "ServerScriptService"
				or inst == "ServerStorage"
				or string.sub(inst, 1, 20) == "ServerScriptService/"
				or string.sub(inst, 1, 14) == "ServerStorage/"
			then
				servers += 1
			end
		end
	end
	return owners > 0 and servers == owners
end

-- Resolve a require string from `from` (repo-relative file) to a repo-relative file, or nil.
-- `game` optionally injects the @game roots (default: graph.gameRoots()).
function graph.resolve(from: string, spec: string, game: { GameRoot }?): string?
	local base: string
	if string.sub(spec, 1, 6) == "@lune/" then
		return nil
	elseif string.sub(spec, 1, 6) == "@game/" then
		return graph.resolveGame(spec, game or gameRootsAt(placeDirOf(from)))
	elseif string.sub(spec, 1, 6) == "@self/" or spec == "@self" then
		local selfDir = if isInit(from) then dirname(from) else string.gsub(from, "%.luau$", "")
		base = selfDir .. string.sub(spec, 6)
	elseif string.sub(spec, 1, 1) == "@" then
		local alias, rest = string.match(spec, "^@([^/]+)(.*)$")
		local target = alias and graph.aliases(dirname(from))[string.lower(alias)]
		if not target then
			return nil
		end
		base = target .. (rest or "")
	else
		local dir = dirname(from)
		if isInit(from) then
			dir = dirname(dir)
		end
		base = `{dir}/{spec}`
	end
	base = normalize(base)
	if exists(base .. ".luau") then
		return base .. ".luau"
	elseif exists(base .. "/init.luau") then
		return base .. "/init.luau"
	end
	return nil
end

-- Remove Luau comments so require-like text in comments is never scanned. A small lexer: string
-- literals ('', "", ``, [[ ]] / [=[ ]=]) are copied verbatim, so `--` or `--[[` inside a string
-- never starts a comment; `---[[ ... --]]` toggles are line comments, as in Luau.
function graph.stripComments(src: string): string
	local out: { string } = {}
	local i, n = 1, #src
	local function longClose(at: number): (number?, number?)
		-- at points to "[" of a long bracket opener; returns (closeEnd, openerEnd) or nil
		local eq = string.match(src, "^%[(=*)%[", at)
		if not eq then
			return nil, nil
		end
		local openEnd = at + #eq + 1
		local _, closeEnd = string.find(src, "]" .. eq .. "]", openEnd + 1, true)
		return closeEnd or n, openEnd
	end
	while i <= n do
		local c = string.sub(src, i, i)
		if c == "-" and string.sub(src, i + 1, i + 1) == "-" then
			local closeEnd = longClose(i + 2)
			if closeEnd then
				i = closeEnd + 1
			else
				local nl = string.find(src, "\n", i, true)
				i = nl or n + 1
			end
		elseif c == '"' or c == "'" or c == "`" then
			local j = i + 1
			while j <= n do
				local d = string.sub(src, j, j)
				if d == "\\" then
					j += 2
				elseif d == c or (d == "\n" and c ~= "`") then
					break
				else
					j += 1
				end
			end
			table.insert(out, string.sub(src, i, j))
			i = j + 1
		elseif c == "[" then
			local closeEnd = longClose(i)
			if closeEnd then
				table.insert(out, string.sub(src, i, closeEnd))
				i = closeEnd + 1
			else
				table.insert(out, c)
				i += 1
			end
		else
			table.insert(out, c)
			i += 1
		end
	end
	return table.concat(out)
end

-- `game` optionally injects the @game roots, passed to graph.resolve.
function graph.build(roots: { string }, game: { GameRoot }?): Graph
	local g: Graph = { files = {}, deps = {}, unresolved = {}, dynamic = {} }
	for _, root in roots do
		graph.listLuau(root, g.files)
	end
	for _, file in g.files do
		local src = graph.stripComments(fs.readFile(file))
		local deps: { string } = {}
		for spec in string.gmatch(src, graph.REQUIRE_PATTERN) do
			-- skip @lune builtins and interpolation lookalikes such as `require("{x}")` in strings
			if string.sub(spec, 1, 6) ~= "@lune/" and not string.find(spec, "{", 1, true) then
				local target = graph.resolve(file, spec, game)
				if target then
					table.insert(deps, target)
				else
					table.insert(g.unresolved, { file = file, spec = spec })
				end
			end
		end
		for arg in string.gmatch(src, "require%s*%(%s*([^%)\"'%s][^%)]*)%)") do
			if arg ~= "" then
				table.insert(g.dynamic, file)
				break
			end
		end
		g.deps[file] = deps
	end
	return g
end

-- Every string-literal require in `dir` (recursive, comments ignored) that srcAliasAllowed rejects for its file
-- (c0185: a file of a server root may use "@game/ServerStorage/"). `places` optionally injects the places' mappings (graph.serverFile).
function graph.srcAliasViolations(dir: string, places: { { GameRoot } }?): { { file: string, spec: string } }
	local out: { { file: string, spec: string } } = {}
	places = places or currentPlaces()
	for _, file in graph.listLuau(dir) do
		local server = graph.serverFile(file, places)
		for spec in string.gmatch(graph.stripComments(fs.readFile(file)), graph.REQUIRE_PATTERN) do
			if not graph.srcAliasAllowed(spec, server) then
				table.insert(out, { file = file, spec = spec })
			end
		end
	end
	return out
end

-- All files reachable from `file` through requires (including itself).
function graph.closure(g: Graph, file: string): { [string]: boolean }
	local seen: { [string]: boolean } = {}
	local stack = { file }
	while #stack > 0 do
		local f = table.remove(stack) :: string
		if not seen[f] then
			seen[f] = true
			local deps: { string } = g.deps[f] or {}
			for _, d in deps do
				table.insert(stack, d)
			end
		end
	end
	return seen
end

-- What the place built for a project home depends on (c0185), as repo-relative files and folders: each
-- `*.project.json` in the home, and every "$path" any of them maps resolved against the home, so `../arcade/src/shared`
-- from `snake/` is `arcade/src/shared`. `home` is "" for the current folder or "<dir>/". A home with no project file
-- gets the legacy answer (its src/ and the two project files c0120 named), the conservative one. A project file
-- that is not JSON with a tree is an error naming it (projectsIn): the selection can't be made without it, and the build refuses it too.
function graph.placeInputs(home: string): { string }
	local dir = if home == "" then "." else string.sub(home, 1, -2)
	local found = projectsIn(dir)
	if #found == 0 then
		return { home .. "src", home .. "default.project.json", home .. "lobby.project.json" }
	end
	local out: { string } = {}
	for _, entry in found do
		table.insert(out, normalize(home .. entry.name))
		for _, m in graph.mappings(entry.project) do
			table.insert(out, if string.sub(m.path, 1, 1) == "/" then m.path else normalize(home .. m.path))
		end
	end
	return out
end

local function underAny(f: string, list: { string }): boolean
	for _, p in list do
		if f == p or string.sub(f, 1, #p + 1) == p .. "/" then
			return true
		end
	end
	return false
end

-- Spec files (per `isSpec`) whose require closure contains any changed file (or a file under a
-- changed directory prefix). A closure containing a place library (PLACE_LIB, the root's or a home's) also counts as
-- containing that home's place inputs (graph.placeInputs, or `inputsOf` when given), because the place is built from them.
function graph.affectedSpecs(
	g: Graph,
	changed: { string },
	isSpec: (string) -> boolean,
	inputsOf: ((string) -> { string })?
): { string }
	local inputs = inputsOf or graph.placeInputs
	local changedSet: { [string]: boolean } = {}
	for _, f in changed do
		changedSet[f] = true
	end
	-- every place library in the graph: the root's and each project home's (`<home>/tests/lib/place.luau`, c0120)
	for _, file in g.files do
		if file == graph.PLACE_LIB or string.sub(file, -(#graph.PLACE_LIB + 1)) == "/" .. graph.PLACE_LIB then
			local home = string.sub(file, 1, #file - #graph.PLACE_LIB)
			local list = inputs(home)
			for _, f in changed do
				if underAny(f, list) then
					changedSet[file] = true
				end
			end
		end
	end
	-- a graph that lists no place library (a fixture's) still marks the root's, as before
	if not changedSet[graph.PLACE_LIB] then
		local list = inputs("")
		for _, f in changed do
			if underAny(f, list) then
				changedSet[graph.PLACE_LIB] = true
			end
		end
	end
	local specs: { string } = {}
	for _, file in g.files do
		if isSpec(file) then
			for dep in graph.closure(g, file) do
				local hit = changedSet[dep]
				if not hit then
					for _, c in changed do
						if string.sub(dep, 1, #c + 1) == c .. "/" then
							hit = true
							break
						end
					end
				end
				if hit then
					table.insert(specs, file)
					break
				end
			end
		end
	end
	table.sort(specs)
	return specs
end

return graph
