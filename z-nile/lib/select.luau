--!strict
-- Which paths force a static stage, and which specs a set of changed paths reaches.
-- Spec selection is the watch map (z-nile/lib/watch.luau): a change runs a spec only when it touches that spec,
-- its watch file, or a path the watch file names. Nothing falls back to every spec. `forces` and `staticProjects`
-- are unchanged: they decide static stages, not which specs run.
-- Pure: the caller builds the context (the watch files) and reads the changed paths.

local graph = require("./graph")
local projects = require("../engine/projects")
local watch = require("./watch")

local sel = {}

export type Home = { name: string, prefix: string } -- prefix "pickman/", "z-nile/"
export type Rules = { homes: { Home }, roots: { string } } -- roots: every project root ("pickman/.tracker", ...)
export type Inputs = { [string]: { string } } -- repo-relative spec -> extra inputs
export type Context = {
	rules: Rules,
	graph: graph.Graph,
	inputs: Inputs,
	places: { [string]: { string } }, -- home prefix -> its place inputs (kept for callers; selection does not read it)
	watches: { [string]: { string } }?, -- repo-relative spec -> the paths in its watch file
	current: { string }?, -- the current raft's acceptance specs, when the change includes a source file
}

-- Changes to these root paths can affect every spec of every project, so they force a full run: ./zn, the root's
-- scripts/ (c0114's shims, which belong to no project) and the root configs (c0120). Tooling paths force z-nile alone.
-- Every project root holds tracker documents, which select nothing.
local SHARED_FULL = {
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
		if
			h.name == TOOLING
			and not string.match(path, "^z%-nile/tests/")
			and not string.match(path, "^z%-nile/skills/")
			and not string.match(path, "^z%-nile/.*%.md$")
		then
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

-- Whether the changed paths force a full static run (of every project, or of `only`). Spec selection does not use this.
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

-- The projects whose static stages a change set can affect: "ALL" when a path forces every project, otherwise the
-- projects whose home holds a changed path (a tracker document lives in its project's home, so it names that project).
-- An empty change set names none. Order is sorted.
function sel.staticProjects(rules: Rules, changed: { string }): { string } | "ALL"
	local names: { [string]: boolean } = {}
	local order: { string } = {}
	local function add(name: string)
		if not names[name] then
			names[name] = true
			table.insert(order, name)
		end
	end
	for _, path in changed do
		if sel.forces(rules, path) == "all" then
			return "ALL"
		end
		local h = homeOf(rules.homes, path)
		if h and h.prefix ~= "" then
			add(h.name)
		end
		local forced = sel.forces(rules, path)
		if type(forced) == "string" then
			add(forced)
		end
	end
	table.sort(order)
	return order
end

-- the project a repo-relative path belongs to (nil: the root's, which belongs to none)
local function projectOf(rules: Rules, path: string): string?
	local h = homeOf(rules.homes, path)
	return if h and h.prefix ~= "" then h.name else nil
end

local function isRefEntry(e: string): boolean
	return string.sub(e, 1, 4) == "ref:"
end

-- Whether a change to `path` can change spec S's result: the spec itself, its watch file, or a path that file names.
function sel.isInput(ctx: Context, spec: string, path: string): boolean
	if path == spec or path == watch.fileFor(spec) then
		return true
	end
	local list = if ctx.watches then ctx.watches[spec] else nil
	if list then
		for _, w in list do
			if w == path then
				return true
			end
		end
	end
	return false
end

-- The specs a set of changed paths reaches. `only` limits the answer to one project's specs, relative to its home.
-- Never "ALL": a change that no watch file names selects nothing.
function sel.affected(ctx: Context, changed: { string }, only: string?): { string } | "ALL"
	local bindings: { watch.Binding } = {}
	local watches: { [string]: { string } } = ctx.watches or {}
	for spec, paths in watches do
		table.insert(bindings, { spec = spec, watch = watch.fileFor(spec), paths = paths })
	end
	local picked = watch.select(bindings, changed, ctx.current)
	local out: { string } = {}
	for _, spec in picked do
		local h = homeOf(ctx.rules.homes, spec)
		if only == nil or (h and h.name == only) then
			table.insert(out, if only and h then string.sub(spec, #h.prefix + 1) else spec)
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
