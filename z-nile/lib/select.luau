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
	places: { [string]: { string } }, -- home prefix -> its place inputs (empty until c0165 step 2 reads them)
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

-- The specs a set of changed paths reaches, or "ALL" when a full run is required. `only` limits the answer to one
-- project's specs, relative to its home.
function sel.affected(ctx: Context, changed: { string }, only: string?): { string } | "ALL"
	if sel.forcedAll(ctx.rules, changed, only) then
		return "ALL"
	end
	local specs = graph.affectedSpecs(ctx.graph, changed, isSpec)
	if not only then
		return specs
	end
	local out: { string } = {}
	for _, s in specs do
		local h = homeOf(ctx.rules.homes, s)
		if h and h.name == only then
			table.insert(out, string.sub(s, #h.prefix + 1))
		end
	end
	return out
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

return sel
