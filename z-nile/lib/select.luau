--!strict
-- The selection rules (c0165): which paths force a full run, and which specs a set of changed paths reaches.
-- Moved out of affected.luau unchanged (c0185's rules included); affected.luau is a thin wrapper over `affected`.
-- Pure: the caller builds the context (the graph of every home, the inputs files) and reads the changed paths.

local graph = require("./graph")
local projects = require("../engine/projects")

local sel = {}

export type Home = { name: string, prefix: string } -- prefix "pickman/", "z-nile/"
export type Rules = { homes: { Home }, roots: { string } } -- roots: every project root ("pickman/.tracker", ...)
export type Inputs = { [string]: { string } } -- repo-relative spec -> extra inputs
export type Context = {
	rules: Rules,
	graph: graph.Graph,
	inputs: Inputs,
	places: { [string]: { string } }, -- home prefix -> its place inputs (graph.placeInputs, read by context.luau)
}

-- Changes to these paths can affect every spec of every project, so they force a full run: the shared runner
-- (z-nile/tests/run.luau) and harness (z-nile/tests/lib/), z-nile's libraries (the fence, the graph, the shell helpers),
-- ./zn, the root's scripts/ (c0114's shims, which belong to no project) and the root configs (c0120). Every project
-- root holds tracker documents, which select nothing.
local SHARED_FULL = {
	"^z%-nile/tests/lib/",
	"^z%-nile/tests/run%.luau$",
	"^z%-nile/lib/",
	"^zn$",
	"^scripts/",
	"^%.luaurc$",
	"^rokit%.toml$",
	"^selene%.toml$",
	"^stylua%.toml$",
}
-- Within a project's home (prefix "" for the root's, "pickman/" for pickman's): these force that project's full run.
-- Every Rojo project file counts (c0185): a place may map folders of another home, and a project file decides how a
-- file's `@game` requires resolve; a change to any of them reruns the project.
local HOME_FULL = {
	"tests/lib/",
	"tests/run%.luau$",
	"tests/meta/",
	"scripts/",
	"%.luaurc$",
	"[^/]*%.project%.json$",
}
-- The rest of z-nile/ (the engine, the gate, the templates) forces z-nile's full run: its specs are the tooling's.
local TOOLING = "z-nile"
-- The old places c0120 emptied (the root's tests/, pickman's src/ and project files, the retired tracker/): anything
-- there again forces z-nile's full run, whose old-roots spec then fails.
local OLD_ROOTS =
	{ "^tests/", "^tracker/", "^src/", "^src$", "^default%.project%.json$", "^lobby%.project%.json$" }

local function escape(s: string): string
	return (string.gsub(s, "[%^%$%(%)%%%.%[%]%*%+%-%?]", "%%%0"))
end

function sel.rules(reg: projects.Registry): Rules
	local list: { Home } = {}
	for _, p in reg.projects do
		table.insert(list, { name = p.name, prefix = if p.home == "." then "" else p.home .. "/" })
	end
	return { homes = list, roots = projects.roots(reg) }
end

-- the home a repo-relative path lies in: the longest prefix (a path under no project's home has the root's "", which
-- belongs to no project since c0120)
local function homeOf(list: { Home }, path: string): Home?
	local best: Home? = nil
	for _, h in list do
		if
			string.sub(path, 1, #h.prefix) == h.prefix and (best == nil or #h.prefix > #(best :: Home).prefix)
		then
			best = h
		end
	end
	return best
end

-- Whether a path forces a full run: "all" (every project's), a project's name (that project's), or nil. A path
-- under a project root holds tracker documents, which select nothing.
function sel.forces(rules: Rules, path: string): ("all" | string)?
	for _, r in rules.roots do
		if string.match(path, "^" .. escape(r) .. "/") then
			return nil
		end
	end
	for _, pat in SHARED_FULL do
		if string.match(path, pat) then
			return "all"
		end
	end
	local h = homeOf(rules.homes, path)
	if h and h.prefix ~= "" then
		for _, pat in HOME_FULL do
			if string.match(path, "^" .. escape(h.prefix) .. pat) then
				return h.name
			end
		end
		if h.name == TOOLING and not string.match(path, "^z%-nile/tests/") then
			return h.name
		end
	end
	for _, pat in OLD_ROOTS do
		if string.match(path, pat) and not projects.rootOf(path, rules.roots) then
			return TOOLING
		end
	end
	return nil
end

local function isSpec(f: string): boolean
	return string.match(f, "%.spec%.luau$") ~= nil
end

-- Whether the changed paths force a full run (of every project, or of `only`): the answer needs no graph.
function sel.forcedAll(rules: Rules, changed: { string }, only: string?): boolean
	local full: { [string]: boolean } = {}
	for _, f in changed do
		local forced = sel.forces(rules, f)
		if forced == "all" then
			return true
		elseif forced then
			full[forced] = true
		end
	end
	if only then
		return full[only] == true
	end
	for _ in full do
		return true
	end
	return false
end

local PLACE_LIB = "tests/lib/place.luau"

local function underAny(f: string, list: { string }): boolean
	for _, p in list do
		if f == p or string.sub(f, 1, #p + 1) == p .. "/" then
			return true
		end
	end
	return false
end

-- the project a repo-relative path belongs to (nil: the root's, which belongs to none)
local function projectOf(rules: Rules, path: string): string?
	local h = homeOf(rules.homes, path)
	return if h and h.prefix ~= "" then h.name else nil
end

-- one closure per (graph, file): a context is read many times
local closures: { [any]: { [string]: { [string]: boolean } } } = setmetatable({}, { __mode = "k" }) :: any
local function closureOf(g: graph.Graph, file: string): { [string]: boolean }
	local perGraph = closures[g]
	if perGraph == nil then
		perGraph = {}
		closures[g] = perGraph
	end
	local c = perGraph[file]
	if c == nil then
		c = graph.closure(g, file)
		perGraph[file] = c
	end
	return c
end

local function isRefEntry(e: string): boolean
	return string.sub(e, 1, 4) == "ref:"
end

local function underRoot(rules: Rules, path: string): string?
	for _, r in rules.roots do
		if path == r or string.sub(path, 1, #r + 1) == r .. "/" then
			return r
		end
	end
	return nil
end

-- Whether a change to `path` can change spec S's result: the one predicate of selection and of fingerprints.
function sel.isInput(ctx: Context, spec: string, path: string): boolean
	local entries: { string } = ctx.inputs[spec] or {}
	for _, e in entries do
		if e == "*" then
			return true
		end
	end
	local rules = ctx.rules
	-- a tracker document is an input only through an entry that itself names a path under the same root
	local root = underRoot(rules, path)
	if root then
		if string.match(path, "[^/]*$") == "spend.md" then
			return false
		end
		for _, e in entries do
			if e ~= "*" and not isRefEntry(e) and string.sub(e, 1, #root + 1) == root .. "/" then
				if e == path or (string.sub(e, -1) == "/" and string.sub(path, 1, #e) == e) then
					return true
				end
			end
		end
		return false
	end
	local project = projectOf(rules, spec)
	local forced = sel.forces(rules, path)
	if forced == "all" or (forced ~= nil and forced == project) then
		return true
	end
	local closure = closureOf(ctx.graph, spec)
	if closure[path] then
		return true
	end
	for dep in closure do
		if string.sub(dep, 1, #path + 1) == path .. "/" then
			return true
		end
	end
	local h = homeOf(rules.homes, spec)
	if
		h
		and closure[h.prefix .. PLACE_LIB]
		and underAny(path, ctx.places[h.prefix] or ({} :: { string }))
	then
		return true
	end
	for _, e in entries do
		if e ~= "*" and not isRefEntry(e) then
			if e == path or (string.sub(e, -1) == "/" and string.sub(path, 1, #e) == e) then
				return true
			end
		end
	end
	if h and #entries > 0 and path == h.prefix .. "tests/inputs.tsv" then
		return true
	end
	return false
end

-- The specs a set of changed paths reaches, or "ALL" when a full run is required. `only` limits the answer to one
-- project's specs, relative to its home. A spec with a `ref:` entry of the project asked for (every project's without
-- `only`) is always selected: selection is stateless and can't see a ref move, so its fingerprint decides.
function sel.affected(ctx: Context, changed: { string }, only: string?): { string } | "ALL"
	if sel.forcedAll(ctx.rules, changed, only) then
		return "ALL"
	end
	local out: { string } = {}
	for _, file in ctx.graph.files do
		if isSpec(file) then
			local h = homeOf(ctx.rules.homes, file)
			if only == nil or (h and h.name == only) then
				local hit = false
				for _, e in (ctx.inputs[file] :: { string }?) or ({} :: { string }) do
					if isRefEntry(e) then
						hit = true
					end
				end
				if not hit then
					for _, p in changed do
						if sel.isInput(ctx, file, p) then
							hit = true
							break
						end
					end
				end
				if hit then
					table.insert(out, if only and h then string.sub(file, #h.prefix + 1) else file)
				end
			end
		end
	end
	table.sort(out)
	return out
end

-- The project a change set is confined to (c0239, the stop hook's scope), or "ALL". A project's name only when (1) the
-- selection is not "ALL", (2) it holds a spec, (3) every selected spec lies in that one project's home, and (4) every
-- changed path lies under that project's home (its tracker root is inside it). Anything else is "ALL": a gate scoped
-- to a project is never narrower than the unscoped one.
function sel.scope(ctx: Context, changed: { string }): string
	local picked = sel.affected(ctx, changed)
	if picked == "ALL" or #(picked :: { string }) == 0 then
		return "ALL"
	end
	local name: string? = nil
	for _, spec in picked :: { string } do
		local p = projectOf(ctx.rules, spec)
		if p == nil or (name ~= nil and p ~= name) then
			return "ALL"
		end
		name = p
	end
	for _, path in changed do
		if projectOf(ctx.rules, path) ~= name then
			return "ALL"
		end
	end
	return name :: string
end

-- the root list graph.build is given for a set of rules: each home's src and tests
function sel.graphRoots(rules: Rules): { string }
	local roots: { string } = {}
	for _, h in rules.homes do
		table.insert(roots, h.prefix .. "src")
		table.insert(roots, h.prefix .. "tests")
	end
	return roots
end

-- A full ref name `git check-ref-format` accepts (the component rules), under refs/.
local function refOk(ref: string): boolean
	if string.sub(ref, 1, 5) ~= "refs/" or #ref <= 5 then
		return false
	end
	if
		string.find(ref, "[%c%s~%^:%?%*%[\\]")
		or string.find(ref, "..", 1, true)
		or string.find(ref, "@{", 1, true)
	then
		return false
	end
	if string.sub(ref, -1) == "/" or string.sub(ref, -1) == "." or string.find(ref, "//", 1, true) then
		return false
	end
	for comp in string.gmatch(ref, "[^/]+") do
		if string.sub(comp, 1, 1) == "." or string.sub(comp, -5) == ".lock" then
			return false
		end
	end
	return ref ~= "@"
end

-- The declarations of one home's tests/inputs.tsv: `#` comments and blank lines are skipped; every other line is
-- `<home-relative spec path>\t<input>`: a repo-relative file, a folder ending `/`, `*`, or `ref:<full ref>`. Any
-- malformed line refuses the whole file with "line N: <reason>" (N counted from 1).
function sel.parseInputs(text: string, homePrefix: string, roots: { string }?): (Inputs?, string?)
	local out: Inputs = {}
	local n = 0
	for line in string.gmatch(text .. "\n", "([^\n]*)\n") do
		n += 1
		if line ~= "" and string.sub(line, 1, 1) ~= "#" then
			local fields = string.split(line, "\t")
			if #fields ~= 2 then
				return nil, `line {n}: expected <spec><TAB><input>`
			end
			local spec, input = fields[1] :: string, fields[2] :: string
			if string.sub(spec, -10) ~= ".spec.luau" then
				return nil, `line {n}: {spec} is not a .spec.luau path`
			end
			if input == "" then
				return nil, `line {n}: empty input`
			end
			if isRefEntry(input) then
				if not refOk(string.sub(input, 5)) then
					return nil, `line {n}: {input} is not a full ref name`
				end
			elseif input ~= "*" then
				if string.sub(input, 1, 1) == "/" then
					return nil, `line {n}: {input} is absolute`
				end
				for comp in string.gmatch(input, "[^/]+") do
					if comp == ".." then
						return nil, `line {n}: {input} contains ..`
					end
				end
				local bare = if string.sub(input, -1) == "/" then string.sub(input, 1, -2) else input
				for _, r in (roots :: { string }?) or ({} :: { string }) do
					if bare == r then
						return nil, `line {n}: {input} is a project root`
					end
				end
				if string.sub(bare, -8) == ".tracker" then
					return nil, `line {n}: {input} is a project root`
				end
				if string.match(bare, "[^/]*$") == "spend.md" then
					return nil, `line {n}: {input} is a spend.md`
				end
			end
			local key = homePrefix .. spec
			local list = out[key]
			if list == nil then
				list = {}
				out[key] = list
			end
			table.insert(list, input)
		end
	end
	return out, nil
end

return sel
