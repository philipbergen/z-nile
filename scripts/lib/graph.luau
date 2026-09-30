--!strict
-- Static require graph for the repo. Used by scripts/affected.luau and tests/meta.
-- Resolves string requires the same way Luau does: "./" and "../" relative to the
-- requiring file (for init.luau: relative to its directory's parent), "@self/",
-- and aliases from .luaurc. Non-string requires are reported as "dynamic".

local fs = require("@lune/fs")
local serde = require("@lune/serde")

export type Graph = {
	files: { string },
	deps: { [string]: { string } }, -- file -> resolved repo-relative files it requires
	unresolved: { { file: string, spec: string } },
	dynamic: { string }, -- files containing require() with a non-literal argument
}

export type GameRoot = {
	instance: string, -- "/"-joined instance names from the DataModel, e.g. "ReplicatedStorage/Shared"
	path: string, -- the node's normalized "$path", e.g. "src/shared"
}

local graph = {}

-- Specs that require this library load the Rojo-built place, so they implicitly depend on every
-- file under src/ and on default.project.json (see affectedSpecs).
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
			table.remove(parts)
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

local aliases: { [string]: string }? = nil
function graph.aliases(): { [string]: string }
	if aliases == nil then
		local cfg = serde.decode("json", fs.readFile(".luaurc"))
		local map: { [string]: string } = {}
		for k, v in cfg.aliases or {} do
			map[string.lower(k)] = normalize(v)
		end
		aliases = map
	end
	return aliases :: { [string]: string }
end

local gameRootsCache: { GameRoot }? = nil

local function collectRoots(node: any, prefix: { string }, out: { GameRoot })
	for key, child in node do
		if string.sub(key, 1, 1) ~= "$" and type(child) == "table" then
			local inst = table.clone(prefix)
			table.insert(inst, key)
			local path = child["$path"]
			if type(path) == "string" then
				table.insert(out, { instance = table.concat(inst, "/"), path = normalize(path) })
			end
			collectRoots(child, inst, out)
		end
	end
end

-- Every node of the Rojo project tree that has a "$path", longest instance path first. `project` is
-- a decoded project table; nil reads ./default.project.json and caches that result per process (an
-- explicit project is never cached and never answered from the cache).
function graph.gameRoots(project: any?): { GameRoot }
	if project == nil and gameRootsCache ~= nil then
		return gameRootsCache
	end
	local decoded = project or serde.decode("json", fs.readFile("default.project.json"))
	local out: { GameRoot } = {}
	collectRoots(decoded.tree or {}, {}, out)
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

-- true for "./…", "../…", "@self/<x>" and "@game/ReplicatedStorage/<x>": the only specs src may use.
function graph.srcAliasAllowed(spec: string): boolean
	return string.sub(spec, 1, 2) == "./"
		or string.sub(spec, 1, 3) == "../"
		or string.sub(spec, 1, 6) == "@self/"
		or string.sub(spec, 1, 24) == "@game/ReplicatedStorage/"
end

-- Resolve a require string from `from` (repo-relative file) to a repo-relative file, or nil.
-- `game` optionally injects the @game roots (default: graph.gameRoots()).
function graph.resolve(from: string, spec: string, game: { GameRoot }?): string?
	local base: string
	if string.sub(spec, 1, 6) == "@lune/" then
		return nil
	elseif string.sub(spec, 1, 6) == "@game/" then
		return graph.resolveGame(spec, game)
	elseif string.sub(spec, 1, 6) == "@self/" or spec == "@self" then
		local selfDir = if isInit(from) then dirname(from) else string.gsub(from, "%.luau$", "")
		base = selfDir .. string.sub(spec, 6)
	elseif string.sub(spec, 1, 1) == "@" then
		local alias, rest = string.match(spec, "^@([^/]+)(.*)$")
		local target = alias and graph.aliases()[string.lower(alias)]
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

-- Every string-literal require in `dir` (recursive, comments ignored) that srcAliasAllowed rejects.
function graph.srcAliasViolations(dir: string): { { file: string, spec: string } }
	local out: { { file: string, spec: string } } = {}
	for _, file in graph.listLuau(dir) do
		for spec in string.gmatch(graph.stripComments(fs.readFile(file)), graph.REQUIRE_PATTERN) do
			if not graph.srcAliasAllowed(spec) then
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

-- Spec files (per `isSpec`) whose require closure contains any changed file (or a file under a
-- changed directory prefix). A closure containing PLACE_LIB also counts as containing every file
-- under src/ and default.project.json, because the place is built from them.
function graph.affectedSpecs(g: Graph, changed: { string }, isSpec: (string) -> boolean): { string }
	local changedSet: { [string]: boolean } = {}
	local placeChanged = false
	for _, f in changed do
		changedSet[f] = true
		if f == "src" or string.sub(f, 1, 4) == "src/" or f == "default.project.json" then
			placeChanged = true
		end
	end
	if placeChanged then
		changedSet[graph.PLACE_LIB] = true
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
