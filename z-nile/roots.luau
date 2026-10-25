--!strict
-- The project registry for the shell parts of the gate and the checks (c0114, design review 001 F5; c0120): the gate
-- scripts, ac.sh and the stop hook take every root and home from here, so a new project needs no edit to them.
--   lune run z-nile/roots                             -- every current root, one per line
--   lune run z-nile/roots -- --projects               -- name, home and root per project, tab-separated (c0120)
--   lune run z-nile/roots -- --luau-dirs [<name>...]  -- the format and lint stages' folders, space-separated: each
--                                                       named project's (every project's without a name)
-- A registry that does not parse is an error (exit 1): the gate never guesses its folders.
local fs = require("@lune/fs")
local process = require("@lune/process")
local projects = require("./engine/projects")
local stdio = require("@lune/stdio")

local ok, reg = pcall(projects.load, ".")
if not ok then
	stdio.ewrite(`z-nile/roots: {reg}\n`)
	process.exit(1)
end
local registry = reg :: projects.Registry
local roots = projects.roots(registry)
local args = table.clone(process.args)
if args[1] == "--" then
	table.remove(args, 1)
end

if args[1] == "--projects" then
	for _, p in registry.projects do
		print(`{p.name}\t{p.home}\t{p.root}`)
	end
elseif args[1] == "--luau-dirs" then
	-- A project's folders (c0120): a game's home's src/, tests/ and scripts/; the tooling's (a home with no src/,
	-- z-nile/) whole home, its engine and libraries with its tests; for z-nile also the root's scripts/, c0114's shims,
	-- which belong to no project; and the project's root: stylua skips hidden folders unless they are named, so every
	-- root is named itself (E9). A folder counts only where it exists.
	local wanted: { [string]: boolean } = {}
	for i = 2, #args do
		if not projects.named(registry, args[i]) then
			stdio.ewrite(`z-nile/roots: no project {args[i]} in {projects.FILE}\n`)
			process.exit(2)
		end
		wanted[args[i]] = true
	end
	local dirs: { string } = {}
	local function add(d: string)
		if fs.isDir(d) and not table.find(dirs, d) then
			table.insert(dirs, d)
		end
	end
	for _, p in registry.projects do
		if #args < 2 or wanted[p.name] then
			local prefix = if p.home == "." then "" else p.home .. "/"
			if p.home == "." or fs.isDir(prefix .. "src") then
				for _, d in { "src", "tests", "scripts" } do
					add(prefix .. d)
				end
			else
				add(p.home)
			end
			if p.home == "." then
				add(p.name)
			end
			if p.name == "z-nile" then
				add("scripts")
			end
			if not table.find(dirs, p.root) then
				table.insert(dirs, p.root)
			end
		end
	end
	print(table.concat(dirs, " "))
else
	for _, r in roots do
		print(r)
	end
end
