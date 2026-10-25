--!strict
-- c0115 (E4): rewrites lesson ids from the old skill folders to the new ones, in every harvest.md under every
-- project root (backlog, active/ and done/) and in every lesson file's body. Run from the repository root, after
-- the skill folders have moved:
--   lune run "$(./zn find c0115)/experiments/rename-lesson-ids" [-- --dry-run | --check]
-- (--check: write nothing, and exit 1 if anything is left to rename: c0115's AC14)
-- The rules are lessons.renameLedger for a harvest.md and skills.oldLessonIds for prose, the ones AC4 and AC5 check
-- with. In a harvest.md the id list of each entry lessons.parseHarvest reads takes the id rule (every old id renamed in
-- place); every other part of a ledger is prose (a note's text, a one-off's reason, and the lines parseHarvest skips or
-- refuses), where a token is renamed only where `<new>/<slug>.md` exists. A lesson body is prose too, and its old skill
-- names are renamed by skills.oldNames (AC4's rule). Only a parsed id with no lesson at the new place is reported
-- (exit 1). Prints each changed file with its count. Idempotent: a second run changes nothing.
local fs = require("@lune/fs")
local lessons = require("@znile/engine/lessons")
local process = require("@lune/process")
local skills = require("@znile/engine/skills")

local checkOnly = table.find(process.args, "--check") ~= nil
local dry = checkOnly or table.find(process.args, "--dry-run") ~= nil
-- Every path is anchored at the repository root (design review 007 F1): the script may be run from any home.
local function topLevel(): string
	local r = process.exec("git", { "rev-parse", "--show-toplevel" })
	if not r.ok then
		error(`not in a git checkout: {r.stderr}`)
	end
	return (string.gsub(r.stdout, "%s+$", ""))
end
local TOP = topLevel()
local function rel(p: string): string
	return if string.sub(p, 1, #TOP + 1) == TOP .. "/" then string.sub(p, #TOP + 2) else p
end
local existing = skills.lessonIndex(TOP)
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
	local r = process.exec("lune", { "run", "z-nile/roots" }, { cwd = TOP })
	if not r.ok then
		print(`lune run z-nile/roots failed: {r.stderr}`)
		process.exit(1) -- fail closed: no roots, nothing checked
	end
	local out = {}
	for line in string.gmatch(r.stdout, "[^\n]+") do
		table.insert(out, `{TOP}/{line}`)
	end
	if #out == 0 then
		print("lune run z-nile/roots printed no root: nothing to check")
		process.exit(1)
	end
	table.insert(out, `{TOP}/tracker`) -- the retired root, for any ledger left there
	return out
end

local total = 0
local function fix(path: string, ledger: boolean)
	local text = fs.readFile(path)
	local out, n, unknown
	if ledger then
		-- a ledger: each entry's parsed id list takes the id rule; every other part of a ledger is prose
		out, n, unknown = lessons.renameLedger(text, existing)
	else
		out, n = skills.renameLessonIds(text, existing)
		unknown = {}
		-- a lesson body is live text: its old skill names go too (skills.oldNames, AC4's rule); a ledger is history
		local named, m = skills.renameOldNames(out)
		out, n = named, n + m
	end
	for _, id in unknown do
		missing[id] = true
	end
	if n > 0 then
		total += n
		print(`{n} {rel(path)}`)
		if not dry then
			fs.writeFile(path, out)
		end
	end
end

-- The items c0115's branch is stacked on, whose design and sequestered files are their own work in flight, so pass 3
-- leaves them alone (their harvest.md is a ledger like any other, so pass 1 renames it). Emptied at the rebase onto
-- landed c0120 (c0115.md §11 (p)): c0120 is done, and its folder is renamed like every other.
local STACKED_ON: { [string]: boolean } = {}

for _, root in roots() do
	walk(root, function(p)
		if string.match(p, "/harvest%.md$") then
			fix(p, true)
		end
	end)
end
for _, folder in { `{TOP}/z-nile/skills`, `{TOP}/pickman/skills` } do
	walk(folder, function(p)
		if string.match(p, "/lessons/[^/]+%.md$") then
			fix(p, false)
		end
	end)
end
-- Pass 3 (the user's decision on G4, 2026-10-21): live backlog designs. In every unfinished item but c0115 itself, an
-- issue document is rewritten from its `## Design` heading on (its captured title, Problem, Non-goals and Solution stay
-- as captured) and a raft document after its frontmatter, by the name and prose-id rules. Its check.sh and acceptance/
-- files are rewritten only when they name an old skill path (`.claude/skills/<old>`): those are
-- sequestered, and the user's decision covers them; each is printed with "(sequestered)". Reviews, refutes and
-- harvest.md are history (harvest.md is pass 1's), and experiments/ are prep evidence; neither is touched.
local SELF = "c0115"
local function renameProse(text: string): (string, number)
	local a, n = skills.renameLessonIds(text, existing)
	local b, m = skills.renameOldNames(a)
	return b, n + m
end
local function namesOldPath(text: string): boolean
	for old in skills.RENAMED_PATH do
		-- a path built from a variable (`{SKILLS}/ticket-prep/SKILL.md`) names the old folder too
		if string.find(text, `/{old}/SKILL.md`, 1, true) then
			return true
		end
		local from = 1
		while true do
			local i, j = string.find(text, `.claude/skills/{old}`, from, true)
			if not i then
				break
			end
			local after = string.sub(text, (j :: number) + 1, (j :: number) + 1)
			if not string.match(after, "[%w_%-]") then
				return true
			end
			from = (j :: number) + 1
		end
	end
	return false
end
local function write(path: string, out: string, n: number, tag: string)
	if n > 0 then
		total += n
		print(`{n} {rel(path)}{tag}`)
		if not dry then
			fs.writeFile(path, out)
		end
	end
end
for _, root in roots() do
	for _, kind in { "issues", "rafts" } do
		for _, state in { "", "/active" } do
			local parent = `{root}/{kind}{state}`
			if fs.isDir(parent) then
				local ids = fs.readDir(parent)
				table.sort(ids)
				for _, id in ids do
					local dir = `{parent}/{id}`
					if
						id == SELF
						or STACKED_ON[id]
						or not string.match(id, "^[cdfR]%d%d%d%d$")
						or not fs.isDir(dir)
					then
						continue
					end
					local doc = `{dir}/{id}.md`
					if fs.isFile(doc) then
						local text = fs.readFile(doc)
						local cut = if string.sub(id, 1, 1) == "R"
							then (select(2, string.find(text, "^%-%-%-\n.-\n%-%-%-\n")) or 0) + 1
							else string.find(text, "\n## Design\n", 1, true)
						if cut then
							local tail, n = renameProse(string.sub(text, cut :: number))
							write(doc, string.sub(text, 1, (cut :: number) - 1) .. tail, n, "")
						end
					end
					walk(dir, function(p)
						local inItem = string.sub(p, #dir + 2)
						local sequestered = inItem == "check.sh" or string.sub(inItem, 1, 11) == "acceptance/"
						if sequestered then
							local text = fs.readFile(p)
							if namesOldPath(text) then
								local out, n = renameProse(text)
								write(p, out, n, " (sequestered)")
							end
						end
					end)
				end
			end
		end
	end
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
if checkOnly and total > 0 then
	print("the rename is not finished: run the script without --check")
	process.exit(1)
end
