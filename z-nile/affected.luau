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
local sel = require("./lib/select")
local stdio = require("@lune/stdio")

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
local rules = sel.rules(reg)
local files = if #explicit > 0 then explicit else changes.files(base)
local result: { string } | "ALL" = "ALL"
if not sel.forcedAll(rules, files, only) then
	-- the graph is read only when no forcing path decided the answer
	result = sel.affected(
		{ rules = rules, graph = graph.build(sel.graphRoots(rules)), inputs = {}, places = {} },
		files,
		only
	)
end
if result == "ALL" then
	print("ALL")
else
	for _, s in result :: { string } do
		print(s)
	end
end
