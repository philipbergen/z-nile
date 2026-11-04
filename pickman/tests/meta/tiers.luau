--!strict
-- The spec tiers' require rules that architecture.spec enforces (pickman-test skill, Spec tiers; c0170): pure, over
-- the require graph as graph.build gives it (files and the files each one's requires resolve to, relative to
-- pickman/; @lune/ builtins are not files and are never listed; a file outside pickman/ keeps a leading ../). It
-- picks the specs it judges itself, every *.spec.luau under tests/helper/ and tests/unit/, so a caller cannot hand
-- it a filtered set (design review 002 F2). Judging resolved files, not spellings, catches a relative or differently
-- cased require of the same file (design review 001 F2).
-- A helper is a tests/lib module, tests/lib/<helper>.luau or tests/lib/<helper>/init.luau (design review 004 F3).
-- What a spec loads is every file it reaches: its own requires, and the requires of any file under tests/ outside
-- tests/lib/ that it reaches (a fixture, a sibling module), followed with a visited set; a src/ file, a tests/lib/
-- file and a file outside pickman/ end a path (design reviews 003 F3 and 004 F1, F2). Then:
-- - a helper spec lives in tests/helper/<helper>/, <helper> a tests/lib helper, and loads that helper (its own
--   require, at least once), tests/lib/t.luau and its own fixtures under tests/fixtures/<helper>/, nothing else;
-- - a unit spec (tests/unit/) loads no tests/lib helper but tests/lib/t.luau, and nothing outside pickman/: a
--   helper's specs go in tests/helper.
-- It fails closed (design review 005 F1): a judged spec that reaches a tests/ file the graph does not list (a
-- miscased path a case-insensitive disk still opens, such as tests/Lib/plain.luau), or that has a dynamic require
-- (graph.build's g.dynamic), breaks the rule, since neither can be judged.
export type Graph = { files: { string }, deps: { [string]: { string } }, dynamic: { string }? }

local tiers = {}

local T = "tests/lib/t.luau"

local function under(path: string, dir: string): boolean
	return string.sub(path, 1, #dir) == dir
end

-- the helper a tests/lib file is, or nil
local function helperOf(path: string): string?
	return string.match(path, "^tests/lib/([^/]+)%.luau$") or string.match(path, "^tests/lib/([^/]+)/")
end

-- every file the spec loads: its own deps, and the deps of every tests/ file outside tests/lib/ it reaches, in
-- first-seen order; src/, tests/lib/ and outside files are listed but not followed
local function reached(g: Graph, file: string): { string }
	local out: { string } = {}
	local seen: { [string]: boolean } = { [file] = true }
	local function walk(f: string)
		local deps: { string } = g.deps[f] or {}
		for _, d in deps do
			if not seen[d] then
				seen[d] = true
				table.insert(out, d)
				if under(d, "tests/") and not under(d, "tests/lib/") then
					walk(d)
				end
			end
		end
	end
	walk(file)
	return out
end

local function helperSpec(g: Graph, file: string, helpers: { [string]: boolean }, out: { string })
	local helper = string.match(file, "^tests/helper/([^/]+)/[^/]+%.spec%.luau$")
	if helper == nil then
		table.insert(out, `{file}: a helper spec lives in tests/helper/<helper>/`)
		return
	end
	if not helpers[helper] then
		table.insert(out, `{file}: tests/lib has no helper named {helper}`)
		return
	end
	local fixtures = `tests/fixtures/{helper}/`
	local found = false
	local direct: { string } = g.deps[file] or {}
	for _, d in direct do
		if helperOf(d) == helper then
			found = true
		end
	end
	for _, d in reached(g, file) do
		local mine = helperOf(d) == helper or d == T or under(d, fixtures)
		if not mine then
			local how = if table.find(direct, d) then "loads" else "reaches, through another test file,"
			table.insert(out, `{file}: {how} {d}; a helper spec may load only its helper, {T} and {fixtures}`)
		end
	end
	if not found then
		table.insert(out, `{file}: does not load its helper tests/lib/{helper}`)
	end
end

-- the failures no rule can judge past: an unlisted tests/ file reached, or a dynamic require in the spec itself
local function unjudgeable(g: Graph, file: string, listed: { [string]: boolean }, out: { string })
	for _, d in reached(g, file) do
		if string.lower(string.sub(d, 1, 6)) == "tests/" and not listed[d] then
			table.insert(
				out,
				`{file}: loads {d}, which is not a file of the tree as listed (check its spelling)`
			)
		end
	end
	if g.dynamic and table.find(g.dynamic, file) then
		table.insert(out, `{file}: has a dynamic require, which the tier rules cannot judge`)
	end
end

local function unitSpec(g: Graph, file: string, out: { string })
	for _, d in reached(g, file) do
		local name = helperOf(d)
		if name and d ~= T then
			table.insert(out, `{file}: loads {d}; a helper's specs go in tests/helper/{name}/`)
		elseif under(d, "../") then
			table.insert(out, `{file}: loads {d}, outside pickman/; a unit spec loads its feature and {T}`)
		end
	end
end

-- Every rule a spec breaks, as "<file>: <why>", in the graph's file order and each spec's load order. helpers holds
-- the tests/lib helper names (file names without .luau, and folders with an init.luau).
function tiers.violations(g: Graph, helpers: { [string]: boolean }): { string }
	local out: { string } = {}
	local listed: { [string]: boolean } = {}
	for _, file in g.files do
		listed[file] = true
	end
	for _, file in g.files do
		if string.match(file, "%.spec%.luau$") then
			if under(file, "tests/helper/") then
				helperSpec(g, file, helpers, out)
				unjudgeable(g, file, listed, out)
			elseif under(file, "tests/unit/") then
				unitSpec(g, file, out)
				unjudgeable(g, file, listed, out)
			end
		end
	end
	return out
end

return tiers
