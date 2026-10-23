--!strict
-- Which specs does a change affect?
--   lune run z-nile/affected                    -- changes vs origin/main (or main) + working tree
--   lune run z-nile/affected -- --base <ref>    -- changes vs <ref>
--   lune run z-nile/affected -- <file> ...      -- explicit changed files
-- Prints one spec path per line, or the single line "ALL" when a full run is required.
-- Prints nothing if no spec is affected.

local changes = require("./lib/changed")
local graph = require("./lib/graph")
local process = require("@lune/process")
local projects = require("./engine/projects")

-- Changes to these paths can affect every spec, so they force a full run. z-nile/ is the engine and the gate (c0114);
-- its .tracker/ holds tracker documents, which select nothing, like tracker/.
local FULL_RUN_PATTERNS = {
	"^tests/lib/",
	"^tests/run%.luau$",
	"^tests/meta/",
	"^scripts/",
	"^z%-nile/",
	"^zn$",
	"^%.luaurc$",
	"^rokit%.toml$",
	"^default%.project%.json$",
	"^selene%.toml$",
	"^stylua%.toml$",
}

-- every project root of the registry: a tracker document selects nothing, wherever its root is (design review 001 F5)
local NOT_FULL: { string } = {}
do
	local ok, reg = pcall(projects.load, ".")
	if not ok then
		error(`affected: {reg}`, 0)
	end
	for _, r in projects.roots(reg :: projects.Registry) do
		table.insert(NOT_FULL, "^" .. (string.gsub(r, "%p", "%%%0")) .. "/")
	end
end

local function affected(changed: { string }): { string } | "ALL"
	for _, f in changed do
		local exempt = false
		for _, pat in NOT_FULL do
			if string.match(f, pat) then
				exempt = true
			end
		end
		for _, pat in FULL_RUN_PATTERNS do
			if not exempt and string.match(f, pat) then
				return "ALL"
			end
		end
	end
	return graph.affectedSpecs(graph.build({ "src", "tests" }), changed, function(f)
		return string.match(f, "%.spec%.luau$") ~= nil
	end)
end

local base: string? = nil
local explicit: { string } = {}
local i = 1
while i <= #process.args do
	local a = process.args[i]
	if a == "--base" then
		base = process.args[i + 1]
		i += 1
	elseif a ~= "--" then
		table.insert(explicit, a)
	end
	i += 1
end

local result = affected(if #explicit > 0 then explicit else changes.files(base))
if result == "ALL" then
	print("ALL")
else
	for _, s in result :: { string } do
		print(s)
	end
end
