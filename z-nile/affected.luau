--!strict
-- Which specs does a change affect?
--   lune run z-nile/affected                    -- changes vs origin/main (or main) + working tree
--   lune run z-nile/affected -- --base <ref>    -- changes vs <ref>
--   lune run z-nile/affected -- <file> ...      -- explicit changed files
--   ... --project <name>                         -- that project's specs only, relative to its home (c0120)
-- Prints one spec path per line (repo-relative; home-relative with --project), or the single line "ALL" when a full
-- run is required. Prints nothing if no spec is affected.

local changes = require("./lib/changed")
local graph = require("./lib/graph")
local process = require("@lune/process")
local projects = require("./engine/projects")
local stdio = require("@lune/stdio")

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
local HOME_FULL = {
	"tests/lib/",
	"tests/run%.luau$",
	"tests/meta/",
	"scripts/",
	"%.luaurc$",
	"default%.project%.json$",
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

type Home = { name: string, prefix: string }

local function homes(reg: projects.Registry): { Home }
	local out: { Home } = {}
	for _, p in reg.projects do
		table.insert(out, { name = p.name, prefix = if p.home == "." then "" else p.home .. "/" })
	end
	return out
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

local function affected(changed: { string }, reg: projects.Registry, only: string?): { string } | "ALL"
	local list = homes(reg)
	local exempt: { string } = {}
	for _, r in projects.roots(reg) do
		table.insert(exempt, "^" .. escape(r) .. "/")
	end
	local full: { [string]: boolean } = {}
	for _, f in changed do
		local skip = false
		for _, pat in exempt do
			if string.match(f, pat) then
				skip = true
			end
		end
		if not skip then
			for _, pat in SHARED_FULL do
				if string.match(f, pat) then
					return "ALL"
				end
			end
			local h = homeOf(list, f)
			if h and h.prefix ~= "" then
				for _, pat in HOME_FULL do
					if string.match(f, "^" .. escape(h.prefix) .. pat) then
						full[h.name] = true
					end
				end
				if h.name == TOOLING and not string.match(f, "^z%-nile/tests/") then
					full[h.name] = true
				end
			end
			for _, pat in OLD_ROOTS do
				if string.match(f, pat) and not projects.rootOf(f, projects.roots(reg)) then
					full[TOOLING] = true
				end
			end
		end
	end
	if only then
		if full[only] then
			return "ALL"
		end
	else
		for _ in full do
			return "ALL"
		end
	end
	local roots: { string } = {}
	for _, h in list do
		table.insert(roots, h.prefix .. "src")
		table.insert(roots, h.prefix .. "tests")
	end
	local specs = graph.affectedSpecs(graph.build(roots), changed, function(f)
		return string.match(f, "%.spec%.luau$") ~= nil
	end)
	if not only then
		return specs
	end
	local out: { string } = {}
	for _, s in specs do
		local h = homeOf(list, s)
		if h and h.name == only then
			table.insert(out, string.sub(s, #h.prefix + 1))
		end
	end
	return out
end

local base: string? = nil
local only: string? = nil
local explicit: { string } = {}
local i = 1
while i <= #process.args do
	local a = process.args[i]
	if a == "--base" then
		base = process.args[i + 1]
		i += 1
	elseif a == "--project" then
		only = process.args[i + 1]
		i += 1
	elseif a ~= "--" then
		table.insert(explicit, a)
	end
	i += 1
end

local reg = projects.load()
if only and not projects.named(reg, only) then
	stdio.ewrite(`affected: no project {only} in {projects.FILE}\n`)
	process.exit(2)
end
local result = affected(if #explicit > 0 then explicit else changes.files(base), reg, only)
if result == "ALL" then
	print("ALL")
else
	for _, s in result :: { string } do
		print(s)
	end
end
