--!strict
-- c0115, Implementation step 5c: rewrites the skill paths in every finished item's check.sh for the skills' move (the
-- user's decision for c0114 and c0120, 2026-10-21: finished check.sh files are rewritten when a move breaks their
-- paths). A literal `<up>.claude/skills/<old>` (then `/` or the word's end), where `<up>` climbs from the item's home
-- exactly to the repository root (`../` from `z-nile/` or `pickman/`, nothing from the root), becomes the path from
-- the home to the skill's real folder (skills.RENAMED_PATH, the one map): `../.claude/skills/tracker/` from `z-nile/`
-- becomes `skills/zz-rules/`, `../.claude/skills/testing/` from `pickman/` becomes `../z-nile/skills/zz-test/`.
-- A variable-built folder (`"../.claude/skills/$s/SKILL.md"`) is carried by its loop (Guess (pending user) G12): a
-- `for <v> in <words>; do` line whose words are all old skill names, in a file that names `.claude/skills/$<v>/` or
-- `.claude/skills/${<v>}/`, gets each word renamed (`for s in tracker review; do` becomes `for s in zz-rules
-- zz-review; do`), so the path reads through the skill's new link. Nothing else changes. Run once from the repository
-- root, after the renames are committed:
--   lune run z-nile/.tracker/issues/c0115/experiments/rewrite-finished [-- --check]
-- It prints each file it changed and a count, and changes nothing when run again; --check writes nothing and exits 1
-- if anything is left to rewrite.
local fs = require("@lune/fs")
local process = require("@lune/process")
local projects = require("@znile/engine/projects")
local rewrites = require("@tests/acceptance/c0120/rewrites") -- its `relative`, the one path arithmetic
local skills = require("@znile/engine/skills")

local checkOnly = table.find(process.args, "--check") ~= nil
local top = (string.gsub(process.exec("git", { "rev-parse", "--show-toplevel" }).stdout, "%s+$", ""))
assert(top ~= "", "rewrite-finished: not in a git checkout")
local reg = projects.load(top, true)

local function nameChar(c: string): boolean
	return c ~= "" and string.match(c, "[%w_%-]") ~= nil
end
-- the finished file's text with every literal old skill path that names the root's .claude rewritten for `home`
local function rewrite(text: string, home: string): (string, number)
	local depth = if home == "." then 0 else #string.split(home, "/")
	local up = string.rep("../", depth)
	local n = 0
	for old, real in skills.RENAMED_PATH do
		local needle = `{up}.claude/skills/{old}`
		local from = 1
		while true do
			local a, b = string.find(text, needle, from, true)
			if not a then
				break
			end
			local before = string.sub(text, (a :: number) - 1, (a :: number) - 1)
			local after = string.sub(text, (b :: number) + 1, (b :: number) + 1)
			-- the literal starts the word (after a space, a quote, `=` or the line start) and the old name ends there
			if (before == "" or not string.match(before, "[%w_%./%-]")) and not nameChar(after) then
				local new = if home == "." then real else rewrites.relative(home, real)
				text = string.sub(text, 1, (a :: number) - 1) .. new .. string.sub(text, (b :: number) + 1)
				n += 1
				from = (a :: number) + #new
			else
				from = (b :: number) + 1
			end
		end
	end
	-- the loops that feed a variable-built skill path (G12)
	local lines = string.split(text, "\n")
	for i, line in lines do
		local lead, var, words, tail =
			string.match(line, "^(%s*for%s+)([%a_][%w_]*)(%s+in%s+[^;]-)(;%s*do.*)$")
		if lead and var and words and tail then
			local fed = string.find(text, `.claude/skills/${var}/`, 1, true)
				or string.find(text, `.claude/skills/${"{"}{var}{"}"}/`, 1, true)
			local list = string.split(string.gsub(string.gsub(words, "^%s+in%s+", ""), "%s+$", ""), " ")
			local all = #list > 0
			for _, w in list do
				if not skills.RENAMED[w] then
					all = false
				end
			end
			if fed and all then
				local renamed = {}
				for _, w in list do
					table.insert(renamed, skills.RENAMED[w])
				end
				lines[i] = `{lead}{var} in {table.concat(renamed, " ")}{tail}`
				n += 1
			end
		end
	end
	return table.concat(lines, "\n"), n
end

local changed, read = 0, 0
for _, root in projects.roots(reg) do
	for _, kind in { "issues", "rafts" } do
		local dir = `{top}/{root}/{kind}/done`
		if fs.isDir(dir) then
			local ids = fs.readDir(dir)
			table.sort(ids)
			for _, id in ids do
				local file = `{root}/{kind}/done/{id}/check.sh`
				if string.match(id, "^[fdcR]%d%d%d%d$") and fs.isFile(`{top}/{file}`) then
					read += 1
					local text = fs.readFile(`{top}/{file}`)
					local new, n = rewrite(text, projects.homeOf(reg, file))
					if n > 0 then
						changed += 1
						print(`{n} {file}`)
						if not checkOnly then
							fs.writeFile(`{top}/{file}`, new)
						end
					end
				end
			end
		end
	end
end
print(`{changed} of {read} finished check.sh files {if checkOnly then "would be rewritten" else "rewritten"}`)
if read == 0 then
	print("no finished check.sh was read: nothing checked")
	process.exit(1)
end
if checkOnly and changed > 0 then
	process.exit(1)
end
