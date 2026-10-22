--!strict
-- c0115, Implementation step 5c: rewrites the skill paths in every finished item's check.sh for the skills' move (the
-- user's decision for c0114 and c0120, 2026-10-21: finished check.sh files are rewritten when a move breaks their
-- paths). A literal `<up>.claude/skills/<old>` (then `/` or the word's end), where `<up>` climbs from the item's home
-- exactly to the repository root (`../` from `z-nile/` or `pickman/`, nothing from the root), becomes the path from
-- the home to the skill's real folder (skills.RENAMED_PATH, the one map): `../.claude/skills/tracker/` from `z-nile/`
-- becomes `skills/zz-rules/`, `../.claude/skills/testing/` from `pickman/` becomes `../z-nile/skills/zz-test/`.
-- A variable-built folder (`"../.claude/skills/$s/SKILL.md"`) is carried by its loop (decided with the user,
-- 2026-10-21, G12: "Rename loop words; delete R0025's"): a `for <v> in <words>; do` line whose words are all old skill
-- names, in a file that names `.claude/skills/$<v>/` or `.claude/skills/${<v>}/`, gets each word renamed (`for s in
-- tracker review; do` becomes `for s in zz-rules zz-review; do`), so the path reads through the skill's new link.
-- A third rule (decided with the user, G13: "Carry c0058, delete five"): a variable assigned exactly `<up>.claude/skills`
-- and read as `$<v>/<old>/` gets the new link's name (`$s/review/` becomes `$s/zz-review/`). Nothing else changes. The
-- criteria no rule carries are deleted, in a commit of its own after the rewrite's (DELETED, like c0120's G17): R0025's
-- RC2 (AGENTS.md now names real paths) and G13's five, which read text c0115 changes on purpose. Run from the repository root, after the renames are committed:
--   lune run z-nile/.tracker/issues/c0115/experiments/rewrite-finished             -- the rewrite (its own commit)
--   lune run z-nile/.tracker/issues/c0115/experiments/rewrite-finished -- --delete  -- the deletion (the next commit)
--   lune run z-nile/.tracker/issues/c0115/experiments/rewrite-finished -- --check   -- AC14: writes nothing
-- Each prints what it changed and a count, and changes nothing when run again. --check exits 1 unless every finished
-- check.sh is exactly its text before c0115's move (the parent of the commit that removed MARK), rewritten by the two
-- rules, with DELETED's statements removed and nothing else: so a path left old, an extra line deleted or a listed
-- criterion kept is red. A file that wasn't finished before the move only has to need no rewrite. No history (a
-- shallow clone, or the move not made) is red.
local fs = require("@lune/fs")
local process = require("@lune/process")
local projects = require("@znile/engine/projects")
local rewrites = require("@tests/acceptance/c0120/rewrites") -- its `relative`, the one path arithmetic
local skills = require("@znile/engine/skills")

local checkOnly = table.find(process.args, "--check") ~= nil
local deleteMode = table.find(process.args, "--delete") ~= nil

-- The finished criteria no rewrite carries, deleted (G12): file -> the ids of its `check "<id>: …"` statements.
local DELETED: { [string]: { string } } = {
	["z-nile/.tracker/rafts/done/R0025/check.sh"] = { "RC2" },
	-- G13 (decided with the user: "Carry c0058, delete five"): they read text c0115 changes on purpose
	["pickman/.tracker/issues/done/c0010/check.sh"] = { "AC7" }, -- game phrases moved to pickman-test
	["z-nile/.tracker/issues/done/c0045/check.sh"] = { "AC6" }, -- the prompt template's hard rule 1
	["z-nile/.tracker/issues/done/c0067/check.sh"] = { "AC11" }, -- the c0047 override's text
	["z-nile/.tracker/issues/done/c0068/check.sh"] = { "AC7" }, -- `name: stop-raft`
	["z-nile/.tracker/issues/done/c0069/check.sh"] = { "AC5" }, -- `name: launch-raft`
}
-- A file the move takes away: its parent is the tree before c0115's move.
local MARK = ".claude/skills/testing/SKILL.md"
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
	text = table.concat(lines, "\n")
	-- rule 3 (G13): a variable assigned exactly `<up>.claude/skills` (c0058's `local s=../.claude/skills`) and read as
	-- `$<v>/<old>/` or `${<v>}/<old>/`: the old name becomes the new link's name, so the path reads through it
	local vars: { string } = {}
	for v, after in
		string.gmatch(
			text,
			"([%a_][%w_]*)=" .. string.gsub(`{up}.claude/skills`, "%p", "%%%0") .. "([^%w_/%-]?)"
		)
	do
		if after ~= "/" then
			table.insert(vars, v)
		end
	end
	for _, v in vars do
		for old, real in skills.RENAMED_PATH do
			local link = string.match(real, "[^/]+$") :: string
			for _, form in { `${v}/{old}/`, `${"{"}{v}{"}"}/{old}/` } do
				local new =
					string.gsub(form, "/" .. string.gsub(old, "%p", "%%%0") .. "/$", "/" .. link .. "/")
				local count
				text, count =
					string.gsub(text, string.gsub(form, "%p", "%%%0"), (string.gsub(new, "%%", "%%%%")))
				n += count
			end
		end
	end
	return text, n
end

-- `text` without the `check "<id>: …"` statement of each id: the statement runs to the line where its single quotes
-- balance and it doesn't end in `\` (RC2's `bash -c '…'` spans five lines). Nil and why unless each id is exactly one
-- statement.
local function deleteCriteria(text: string, ids: { string }): (string?, string?)
	local lines = string.split(text, "\n")
	for _, id in ids do
		local found = 0
		local kept: { string } = {}
		local i = 1
		while i <= #lines do
			if string.sub(lines[i], 1, #id + 8) == `check "{id}:` then
				found += 1
				local quotes = select(2, string.gsub(lines[i], "'", ""))
				while (quotes % 2 == 1 or string.sub(lines[i], -1) == "\\") and i < #lines do
					i += 1
					quotes += select(2, string.gsub(lines[i], "'", ""))
				end
			else
				table.insert(kept, lines[i])
			end
			i += 1
		end
		if found ~= 1 then
			return nil, `{id}: {found} check statements`
		end
		lines = kept
	end
	return table.concat(lines, "\n"), nil
end

local function git(args: { string }): (boolean, string)
	local r = process.exec("git", args, { cwd = top })
	return r.ok, (string.gsub(r.stdout, "%s+$", ""))
end
-- the tree before c0115's move, or nil and why
local function premove(): (string?, string?)
	if fs.isFile(`{top}/{MARK}`) then
		return nil, `{MARK} is still in the tree: the move hasn't happened`
	end
	local okM, moved = git({ "log", "-1", "--format=%H", "--", MARK })
	if not okM or moved == "" then
		return nil, `no commit removed {MARK}: the history is shallow or the move hasn't happened`
	end
	local okP, parent = git({ "rev-parse", "--verify", "-q", moved .. "^" })
	if not okP or parent == "" then
		return nil, `the move {moved} has no parent in this history`
	end
	return parent, nil
end

if deleteMode then
	local files: { string } = {}
	for file in DELETED do
		table.insert(files, file)
	end
	table.sort(files)
	local changed = 0
	for _, file in files do
		local text = fs.readFile(`{top}/{file}`)
		local new = deleteCriteria(text, DELETED[file])
		if new and new ~= text then
			fs.writeFile(`{top}/{file}`, new)
			changed += 1
			print(`{file}: {table.concat(DELETED[file], ", ")} deleted`)
		end
	end
	print(`delete: {changed} of {#files} files changed`)
	process.exit(0)
end

local pre: string? = nil
if checkOnly then
	local why
	pre, why = premove()
	if not pre then
		print(`rewrite-finished: {why}: nothing checked`)
		process.exit(1)
	end
end
local wrong = 0
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
					local home = projects.homeOf(reg, file)
					local new, n = rewrite(text, home)
					if checkOnly then
						-- exactly the pre-move text, rewritten, with DELETED's statements gone
						local okB, before = git({ "show", `{pre}:{file}` })
						if okB then
							local want: string? = rewrite(before .. "\n", home)
							local why: string? = nil
							if DELETED[file] then
								want, why = deleteCriteria(want :: string, DELETED[file])
							end
							if want ~= text then
								wrong += 1
								print(
									`{file}: not its pre-move text rewritten{if DELETED[file]
										then " less " .. table.concat(DELETED[file], ", ")
										else ""}{if why then " (" .. why .. ")" else ""}`
								)
							end
						end
					end
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
if checkOnly and (changed > 0 or wrong > 0) then
	process.exit(1)
end
