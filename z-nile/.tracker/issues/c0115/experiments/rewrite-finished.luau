--!strict
-- c0115, Implementation step 5c: rewrites the skill paths in every finished item's check.sh for the skills' move (the
-- user's decision for c0114 and c0120, 2026-10-21: finished check.sh files are rewritten when a move breaks their
-- paths). `<up>` is the climb from the item's home to the repository root (`../` from `z-nile/` or `pickman/`). Five
-- rules, nothing else:
-- 1. A literal `<up>.claude/skills/<old>` (then `/` or the word's end) becomes the path from the home to the skill's
--    real folder (skills.RENAMED_PATH, the one map): `../.claude/skills/tracker/` from `z-nile/` becomes
--    `skills/zz-rules/`, `../.claude/skills/testing/` from `pickman/` becomes `../z-nile/skills/zz-test/`.
-- 1b. A bare `<up>.claude/skills` operand (a word of its own: not after `=` or `/`, and then a space, a quote, `)`,
--    `;` or the line's end) becomes the real skills folders from the home (`skills ../pickman/skills` from `z-nile/`):
--    `grep -r` doesn't follow the links, so an absence scan over the links would pass vacuously (design review 010 F3).
-- 2. (decided with the user, 2026-10-21, G12: "Rename loop words; delete R0025's") a `for <v> in <words>; do` line
--    whose words are all old skill names, in a file that names `.claude/skills/$<v>/` or `.claude/skills/${<v>}/`, gets
--    each word renamed (`for s in tracker review; do` becomes `for s in zz-rules zz-review; do`).
-- 3. (decided with the user, G13: "Carry c0058, delete five"; widened by design review 010 F2) a variable assigned a
--    value that ends in `.claude/skills` (c0058's `local s=../.claude/skills`, c0040's
--    `R="$(git … --show-toplevel)/.claude/skills"`) and read as `$<v>/<old>/` or `${<v>}/<old>/` gets the new link's
--    name (`$s/review/` becomes `$s/zz-review/`).
-- 1c. (G13, design review 011 F3) such a variable used bare (`grep -rnF … "$S"`, c0084) becomes every real skills
--    folder, unquoted, as in rule 1b.
-- The criteria no rule carries are deleted, in a commit of their own (DELETED, like c0120's G17): R0025's RC2 (G12) and
-- G13's five, which read text c0115 changes on purpose. Run from the repository root:
--   lune run z-nile/.tracker/issues/c0115/experiments/rewrite-finished             -- the rewrite (its own commit)
--   lune run z-nile/.tracker/issues/c0115/experiments/rewrite-finished -- --delete  -- the deletion (its own commit)
--   lune run z-nile/.tracker/issues/c0115/experiments/rewrite-finished -- --check   -- AC14: writes nothing
-- Rerun the rewrite (then --check) after every merge of origin/main, as its own commit: an item that finished on main
-- meanwhile arrives with old paths. Each mode prints what it changed and a count, and changes nothing when run again.
-- --check is three-way (design review 010 F1, the same as c0120's AC18) against the trusted base (trusted-base.luau,
-- design review 011 F1: `git merge-base HEAD <main's tip from git ls-remote origin>`, never the local
-- refs/remotes/origin/main): every finished check.sh at the base must be exactly its base text rewritten by the five
-- rules, with DELETED's statements removed (an id with no statement at the base stays absent), and nothing else; a
-- file that isn't at the base, and every file when the range is empty (the branch landed), only has to need no
-- rewrite; a non-empty range that compares no file with its base (a main from before the layout) is red. From the
-- base's side too (011 F2): every finished check.sh at the base, under the base's own roots, must still be at HEAD at
-- the same path. Independently of the rules, no finished check.sh may still name `.claude/skills/<old>` or
-- `/<old>/SKILL.md`, or run a recursive grep over the links (011 F3). No trusted base is red.
local fs = require("@lune/fs")
local process = require("@lune/process")
local projects = require("@znile/engine/projects")
local rewrites = require("@tests/acceptance/c0120/rewrites") -- its `relative`, the one path arithmetic
local skills = require("@znile/engine/skills")
local trustedBase = require("./trusted-base")

local checkOnly = table.find(process.args, "--check") ~= nil
local deleteMode = table.find(process.args, "--delete") ~= nil

-- The finished criteria no rewrite carries, deleted: file -> the ids of its `check "<id>: …"` statements.
local DELETED: { [string]: { string } } = {
	["z-nile/.tracker/rafts/done/R0025/check.sh"] = { "RC2" }, -- G12: AGENTS.md now names real paths
	-- G13 (decided with the user: "Carry c0058, delete five"): they read text c0115 changes on purpose
	["pickman/.tracker/issues/done/c0010/check.sh"] = { "AC7" }, -- game phrases moved to pickman-test
	["z-nile/.tracker/issues/done/c0045/check.sh"] = { "AC6" }, -- the prompt template's hard rule 1
	["z-nile/.tracker/issues/done/c0067/check.sh"] = { "AC11" }, -- the c0047 override's text
	["z-nile/.tracker/issues/done/c0068/check.sh"] = { "AC7" }, -- `name: stop-raft`
	["z-nile/.tracker/issues/done/c0069/check.sh"] = { "AC5" }, -- `name: launch-raft`
}
local top = (string.gsub(process.exec("git", { "rev-parse", "--show-toplevel" }).stdout, "%s+$", ""))
assert(top ~= "", "rewrite-finished: not in a git checkout")
local reg = projects.load(top, true)

local function esc(s: string): string
	return (string.gsub(s, "%p", "%%%0"))
end
local function nameChar(c: string): boolean
	return c ~= "" and string.match(c, "[%w_%-]") ~= nil
end
-- the old skill names, longest first, so `ready-raft` never matches inside a longer name
local OLD: { string } = {}
for old in skills.RENAMED_PATH do
	table.insert(OLD, old)
end
table.sort(OLD, function(a: string, b: string): boolean
	return #a > #b or (#a == #b and a < b)
end)

-- every real skills folder seen from `home`, z-nile's first (`skills ../pickman/skills` from `z-nile/`)
local function realFolders(home: string): string
	local folders: { string } = {}
	for _, f in skills.folders(reg) do
		table.insert(folders, if home == "." then f.path else rewrites.relative(home, f.path))
	end
	return table.concat(folders, " ")
end
-- the variables whose assigned value ends in `.claude/skills` (the nearest `<v>=` starting a word before it, on its
-- line): rule 3's and rule 1c's, and the recursive-grep scan's
local function skillVars(text: string): { [string]: boolean }
	local vars: { [string]: boolean } = {}
	for _, line in string.split(text, "\n") do
		local from = 1
		while true do
			local a, b = string.find(line, ".claude/skills", from, true)
			if not a then
				break
			end
			local after = string.sub(line, (b :: number) + 1, (b :: number) + 1)
			if after == "" or string.match(after, "[%s\"']") then
				local prefix = string.sub(line, 1, (a :: number) - 1)
				local last: string? = nil
				for v in string.gmatch(" " .. prefix, "%s([%a_][%w_]*)=") do
					last = v
				end
				if last then
					vars[last] = true
				end
			end
			from = (b :: number) + 1
		end
	end
	return vars
end
-- the bare uses of `$v` (`"$v"`, `$v`, `"${v}"`, `${v}`) as a word of its own: (start, end) pairs, quotes included
local function bareUses(line: string, v: string): { { number } }
	local out: { { number } } = {}
	for _, form in { `"${v}"`, `"${"{"}{v}{"}"}"`, `${"{"}{v}{"}"}`, `${v}` } do
		local from = 1
		while true do
			local a, b = string.find(line, form, from, true)
			if not a then
				break
			end
			local before = string.sub(line, (a :: number) - 1, (a :: number) - 1)
			local after = string.sub(line, (b :: number) + 1, (b :: number) + 1)
			local opens = before == "" or string.match(before, "[%s%(]") ~= nil
			local closes = after == "" or string.match(after, "[%s%);]") ~= nil
			local taken = false
			for _, u in out do
				if (a :: number) >= u[1] and (a :: number) <= u[2] then
					taken = true
				end
			end
			if opens and closes and not taken then
				table.insert(out, { a :: number, b :: number })
			end
			from = (b :: number) + 1
		end
	end
	table.sort(out, function(x: { number }, y: { number }): boolean
		return x[1] > y[1]
	end)
	return out
end

-- `text` (a finished check.sh in `home`) rewritten by the five rules, and how many places changed
local function rewrite(text: string, home: string): (string, number)
	local depth = if home == "." then 0 else #string.split(home, "/")
	local up = string.rep("../", depth)
	local n = 0
	-- rule 1
	for _, old in OLD do
		local real = skills.RENAMED_PATH[old]
		local needle = `{up}.claude/skills/{old}`
		local from = 1
		while true do
			local a, b = string.find(text, needle, from, true)
			if not a then
				break
			end
			local before = string.sub(text, (a :: number) - 1, (a :: number) - 1)
			local after = string.sub(text, (b :: number) + 1, (b :: number) + 1)
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
	-- rule 1b: a bare operand becomes every real skills folder, z-nile's first
	do
		local new = realFolders(home)
		local needle = `{up}.claude/skills`
		local from = 1
		while true do
			local a, b = string.find(text, needle, from, true)
			if not a then
				break
			end
			local before = string.sub(text, (a :: number) - 1, (a :: number) - 1)
			local after = string.sub(text, (b :: number) + 1, (b :: number) + 1)
			local opens = before == "" or string.match(before, "[%s\"'%(]") ~= nil
			local closes = after == "" or string.match(after, "[%s\"'%);]") ~= nil
			if opens and closes then
				text = string.sub(text, 1, (a :: number) - 1) .. new .. string.sub(text, (b :: number) + 1)
				n += 1
				from = (a :: number) + #new
			else
				from = (b :: number) + 1
			end
		end
	end
	-- rule 2: the loops that feed a variable-built skill path
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
	-- rule 3: a variable whose assigned value ends in `.claude/skills`, read as `$<v>/<old>/`
	local vars = skillVars(text)
	for v in vars do
		for _, old in OLD do
			local link = string.match(skills.RENAMED_PATH[old], "[^/]+$") :: string
			for _, form in { `${v}/{old}/`, `${"{"}{v}{"}"}/{old}/` } do
				local new = string.sub(form, 1, #form - #old - 1) .. link .. "/"
				local count
				text, count = string.gsub(text, esc(form), (string.gsub(new, "%%", "%%%%")))
				n += count
			end
		end
	end
	-- rule 1c (design review 011 F3): such a variable used bare (`grep -rnF … "$S"`) becomes every real skills folder,
	-- unquoted (two words), as rule 1b does for a literal operand
	if next(vars) then
		local folders = realFolders(home)
		local out: { string } = {}
		for _, line in string.split(text, "\n") do
			-- never the assignment itself (`S=../.claude/skills`): only uses
			for v in vars do
				for _, u in bareUses(line, v) do
					line = string.sub(line, 1, u[1] - 1) .. folders .. string.sub(line, u[2] + 1)
					n += 1
				end
			end
			table.insert(out, line)
		end
		text = table.concat(out, "\n")
	end
	return text, n
end

-- every recursive grep (`grep -…r…`, which doesn't follow links) still reading the link folder, independently of
-- the rules: a bare `.claude/skills` operand, or a bare use of a variable assigned it (design review 011 F3)
local function linkScans(text: string): { string }
	local out: { string } = {}
	local vars = skillVars(text)
	local n = 0
	for _, line in string.split(text, "\n") do
		n += 1
		local recursive = false
		for flags in string.gmatch(line, "grep%s+(%-[%w]+)") do
			if string.find(flags, "r", 1, true) then
				recursive = true
			end
		end
		if recursive then
			local bare = false
			local from = 1
			while true do
				local a, b = string.find(line, ".claude/skills", from, true)
				if not a then
					break
				end
				-- bare: then an optional `/` and a non-name character (`../.claude/skills/`, `…/skills/*`): grep -r
				-- follows no link, not even one named on the command line (design review 012 F2)
				local rest = string.sub(line, (b :: number) + 1)
				if string.match(rest, "^/?[^%w_%-%.]") or string.match(rest, "^/?$") then
					bare = true
				end
				from = (b :: number) + 1
			end
			for v in vars do
				if #bareUses(line, v) > 0 then
					bare = true
				end
			end
			if bare then
				table.insert(out, `line {n}`)
			end
		end
	end
	return out
end

-- every old skill path a finished check.sh still names, independently of the rules: `.claude/skills/<old>` (then a
-- non-name character or the end) or `/<old>/SKILL.md`
local function oldPaths(text: string): { string }
	local out: { string } = {}
	for _, old in OLD do
		for _, form in
			{
				{ "%.claude/skills/" .. esc(old) .. "%f[^%w_%-]", `.claude/skills/{old}` },
				{ "/" .. esc(old) .. "/SKILL%.md", `/{old}/SKILL.md` },
			}
		do
			if string.find(text, form[1]) then
				table.insert(out, form[2])
			end
		end
	end
	return out
end

-- `text` without the `check "<id>: …"` statement of each id: the statement runs to the line where its single quotes
-- balance and it doesn't end in `\`. Nil and why unless each id is exactly one statement; `absentOk` lets an id with
-- no statement stay absent.
local function deleteCriteria(text: string, ids: { string }, absentOk: boolean?): (string?, string?)
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
		if found > 1 or (found == 0 and not absentOk) then
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

if deleteMode then
	local files: { string } = {}
	for file in DELETED do
		table.insert(files, file)
	end
	table.sort(files)
	local changed = 0
	for _, file in files do
		local text = fs.readFile(`{top}/{file}`)
		local new = deleteCriteria(text, DELETED[file], true)
		if new and new ~= text then
			fs.writeFile(`{top}/{file}`, new)
			changed += 1
			print(`{file}: {table.concat(DELETED[file], ", ")} deleted`)
		end
	end
	print(`delete: {changed} of {#files} files changed`)
	process.exit(0)
end

-- --check's base: the merge-base with origin/main, or nil when the range is empty (the branch landed)
local base: string? = nil
if checkOnly then
	-- the one trusted base (design review 011 F1): main's tip from the remote, never refs/remotes/origin/main
	local b = trustedBase.get(top)
	if not b.ok then
		print(`rewrite-finished: {b.why}: nothing checked`)
		process.exit(1)
	end
	print(`rewrite-finished: main's tip read from {b.url}`)
	if not b.empty then
		base = b.base
	else
		print("rewrite-finished: no commits since origin's main: checking only that nothing needs a rewrite")
	end
end

local wrong = 0
local compared = 0 -- finished files judged against their base text: zero with a base is red (no vacuous pass)
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
						for _, p in oldPaths(text) do
							wrong += 1
							print(`{file}: still names {p}`)
						end
						for _, at in linkScans(text) do
							wrong += 1
							print(`{file}: {at}: a recursive grep still reads the .claude/skills links`)
						end
						local okB, before = false, ""
						if base then
							okB, before = git({ "show", `{base}:{file}` })
						end
						if okB then
							compared += 1
							local want: string? = rewrite(before .. "\n", home)
							local why: string? = nil
							if DELETED[file] then
								want, why = deleteCriteria(want :: string, DELETED[file], true)
							end
							if want ~= text then
								wrong += 1
								print(
									`{file}: not its base text rewritten{if DELETED[file]
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
-- the base's side (design review 011 F2): every finished check.sh at the base, under the base's own roots, must still
-- be at HEAD at the same path; a deleted, renamed or moved finished file drops its criteria
if checkOnly and base then
	local okT, regText = git({ "show", `{base}:z-nile/projects.toml` })
	local baseReg = if okT then projects.parse(regText) else nil
	if not baseReg then
		print(`rewrite-finished: no readable z-nile/projects.toml at the base {base}: nothing compared`)
		process.exit(1)
	end
	local okL, listing = git({ "ls-tree", "-r", "--name-only", base :: string })
	assert(okL, "git ls-tree of the base failed")
	local roots: { [string]: boolean } = {}
	for _, r in projects.allRoots(baseReg :: projects.Registry) do
		roots[r] = true
	end
	local atBase = 0
	for path in string.gmatch(listing, "[^\n]+") do
		local root = string.match(path, "^(.-)/[a-z]+/done/[fdcR]%d%d%d%d/check%.sh$")
		local kind = string.match(path, "/([a-z]+)/done/[fdcR]%d%d%d%d/check%.sh$")
		if root and roots[root] and (kind == "issues" or kind == "rafts") then
			atBase += 1
			if not fs.isFile(`{top}/{path}`) then
				wrong += 1
				print(`{path}: at the base, gone at HEAD`)
			end
		end
	end
	print(`{atBase} finished check.sh files at the base, each still at HEAD or named above`)
end
print(`{changed} of {read} finished check.sh files {if checkOnly then "would be rewritten" else "rewritten"}`)
if read == 0 then
	print("no finished check.sh was read: nothing checked")
	process.exit(1)
end
if checkOnly and base and compared == 0 then
	print(
		`no finished check.sh is at the base {base}: nothing compared (does origin/main predate the layout?)`
	)
	process.exit(1)
end
if checkOnly and base then
	print(`{compared} finished check.sh files compared with their base text`)
end
if checkOnly and (changed > 0 or wrong > 0) then
	process.exit(1)
end
