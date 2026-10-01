--!strict
-- Which specs does a change affect?
--   lune run scripts/affected                    -- changes vs origin/main (or main) + working tree
--   lune run scripts/affected -- --base <ref>    -- changes vs <ref>
--   lune run scripts/affected -- <file> ...      -- explicit changed files
-- Prints one spec path per line, or the single line "ALL" when a full run is required.
-- Prints nothing if no spec is affected.

local changes = require("./lib/changed")
local graph = require("./lib/graph")
local process = require("@lune/process")

-- Changes to these paths can affect every spec, so they force a full run.
local FULL_RUN_PATTERNS = {
	"^tests/lib/",
	"^tests/run%.luau$",
	"^tests/meta/",
	"^scripts/",
	"^%.luaurc$",
	"^rokit%.toml$",
	"^default%.project%.json$",
	"^selene%.toml$",
	"^stylua%.toml$",
}

local function affected(changed: { string }): { string } | "ALL"
	for _, f in changed do
		for _, pat in FULL_RUN_PATTERNS do
			if string.match(f, pat) then
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
