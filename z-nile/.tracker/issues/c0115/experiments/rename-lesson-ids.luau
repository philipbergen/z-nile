--!strict
-- c0115 (E4): rewrites lesson ids from the old skill folders to the new ones, in every harvest.md under every
-- project root (backlog, active/ and done/) and in every lesson file's body. Run from the repository root, after
-- the skill folders have moved:
--   lune run "$(./zn find c0115)/experiments/rename-lesson-ids" [-- --dry-run]
-- The rule is skills.oldLessonIds, the one AC4 and AC5 check with: an `<old>/<slug>` token is renamed only where
-- `<new>/<slug>.md` exists, and a lesson body's old skill names are renamed by skills.oldNames (AC4's rule). In a
-- harvest.md every such token is an id, so one with no lesson at the new place is
-- reported (exit 1); in a lesson body a token may be a path (tracker/next), so it is only left alone. Prints each
-- changed file with its count. Idempotent: a second run changes nothing.
local fs = require("@lune/fs")
local process = require("@lune/process")
local skills = require("@znile/engine/skills")

local dry = table.find(process.args, "--dry-run") ~= nil
local existing = skills.lessonIndex(".")
local missing: { [string]: boolean } = {}

local function walk(dir: string, visit: (string) -> ())
	if not fs.isDir(dir) then
		return
	end
	local names = fs.readDir(dir)
	table.sort(names)
	for _, name in names do
		local p = `{dir}/{name}`
		if fs.isDir(p) then
			walk(p, visit)
		else
			visit(p)
		end
	end
end

local function roots(): { string }
	local r = process.exec("lune", { "run", "z-nile/roots" })
	if not r.ok then
		error(`lune run z-nile/roots failed: {r.stderr}`)
	end
	local out = {}
	for line in string.gmatch(r.stdout, "[^\n]+") do
		table.insert(out, line)
	end
	table.insert(out, "tracker") -- the retired root, for any ledger left there
	return out
end

local total = 0
local function fix(path: string, ledger: boolean)
	local out, n, unknown = skills.renameLessonIds(fs.readFile(path), existing, ledger)
	if not ledger then
		-- a lesson body is live text: its old skill names go too (skills.oldNames, AC4's rule); a ledger is history
		local named, m = skills.renameOldNames(out)
		out, n = named, n + m
	end
	for _, id in unknown do
		missing[id] = true
	end
	if n > 0 then
		total += n
		print(`{n} {path}`)
		if not dry then
			fs.writeFile(path, out)
		end
	end
end

for _, root in roots() do
	walk(root, function(p)
		if string.match(p, "/harvest%.md$") then
			fix(p, true)
		end
	end)
end
for _, folder in { "z-nile/skills", "pickman/skills" } do
	walk(folder, function(p)
		if string.match(p, "/lessons/[^/]+%.md$") then
			fix(p, false)
		end
	end)
end
print(`{total} ids rewritten{if dry then " (dry run: nothing written)" else ""}`)
local gaps = {}
for id in missing do
	table.insert(gaps, id)
end
table.sort(gaps)
if #gaps > 0 then
	print("old ids with no lesson at the new place:\n" .. table.concat(gaps, "\n"))
	process.exit(1)
end
