--!strict
-- The project roots of this checkout's z-nile/projects.toml, for the shell parts of the gate (c0114, design review 001
-- F5): the gate scripts take every root from here, so a new root (c0120's pickman/.tracker) needs no edit to them.
--   lune run z-nile/roots                  -- every current root, one per line
--   lune run z-nile/roots -- --luau-dirs   -- the format and lint stages' folders, space-separated
-- A registry that does not parse is an error (exit 1): the gate never guesses its folders.
local process = require("@lune/process")
local projects = require("./engine/projects")
local stdio = require("@lune/stdio")

local ok, reg = pcall(projects.load, ".")
if not ok then
	stdio.ewrite(`z-nile/roots: {reg}\n`)
	process.exit(1)
end
local roots = projects.roots(reg :: projects.Registry)
if table.find(process.args, "--luau-dirs") then
	-- stylua skips hidden folders unless they are named, so every root is named itself (E9)
	local dirs = { "src", "tests", "scripts", "z-nile" }
	for _, r in roots do
		if not table.find(dirs, r) then
			table.insert(dirs, r)
		end
	end
	print(table.concat(dirs, " "))
else
	for _, r in roots do
		print(r)
	end
end
