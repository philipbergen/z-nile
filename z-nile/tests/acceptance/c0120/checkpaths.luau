--!strict
-- The literal paths a check.sh names, and the scan of every unfinished item's check.sh (c0120 AC11's rule, moved here
-- from its spec by c0141 so it can be tested on its own). A path is read from the item's project home; one under the
-- item's own Touched modules (or a raft member's), which its work will create, is exempt. c0141: the exemption
-- compares the path's repository-relative form (home plus the path, `.` and `..` folded) with what each Touched entry
-- names, read one way chosen from the entry's own text (`owned`). A path that climbs above the checkout is never exempt.
-- It lives in c0120's promoted folder (c0141 design review 001 F3), so it stays under "never edit promoted specs".
local fs = require("@lune/fs")
local projects = require("@znile/engine/projects")

local checkpaths = {}

export type Item = { dir: string, id: string, raft: string }
export type Scan = { bad: { string }, checked: number, found: number, byHome: { [string]: number } }

-- `path` as written in a check.sh read from the home `home` ("." for the checkout's top), as a path from the
-- checkout's top with `.` and `..` folded; nil when it climbs above the top
function checkpaths.repoPath(home: string, path: string): string?
	local parts: { string } = {}
	local full = if home == "." or home == "" then path else `{home}/{path}`
	for seg in string.gmatch(full, "[^/]+") do
		if seg == ".." then
			if #parts == 0 then
				return nil
			end
			table.remove(parts)
		elseif seg ~= "." then
			table.insert(parts, seg)
		end
	end
	return table.concat(parts, "/")
end

-- the repository-relative path each Touched entry of an item in `home` names (c0141 design review 001 F1: one reading
-- per entry, chosen from its own text, never both): an entry whose first segment is a registered project's home
-- (`homes`, from the registry) is repository-relative; otherwise, when its first segment exists in the item's home
-- (in the checkout at `base`) or doesn't exist at the checkout's top either, it is read from the home; otherwise (a
-- root-level file or folder: `zn`, `AGENTS.md`, `.github`) it is repository-relative. An entry that climbs above the
-- checkout is dropped. A home holding a folder named after another home (`z-nile/pickman/…`) would read wrong; none
-- does today.
function checkpaths.owned(base: string, home: string, entries: { string }, homes: { string }): { string }
	local out: { string } = {}
	for _, e in entries do
		local first = string.match((string.gsub(e, "^%./", "")), "^([^/]+)") or e
		local reading: string?
		if table.find(homes, first) then
			reading = checkpaths.repoPath(".", e)
		else
			local homed = home ~= "." and home ~= ""
			local inHome = homed and (fs.isDir(`{base}{home}/{first}`) or fs.isFile(`{base}{home}/{first}`))
			local atTop = fs.isDir(base .. first) or fs.isFile(base .. first)
			reading = if inHome or not atTop
				then checkpaths.repoPath(home, e)
				else checkpaths.repoPath(".", e)
		end
		if reading then
			table.insert(out, reading)
		end
	end
	return out
end

local PREFIXES =
	{ "src/", "tests/", "scripts/", "z-nile/", "pickman/", "tracker/", ".tracker/", ".github/", ".claude/" }
-- A file named alone (no folder) is a path only outside double quotes: in quotes it is a message, a case's name or
-- a grep pattern (c0099's), found by running the finished checks by hand
local FILES = {
	["default.project.json"] = true,
	["lobby.project.json"] = true,
	zn = true,
	-- the repository root's own files (found by running the finished checks by hand)
	["AGENTS.md"] = true,
	["CLAUDE.md"] = true,
	["SETUP.md"] = true,
	["rokit.toml"] = true,
	["selene.toml"] = true,
	["stylua.toml"] = true,
	[".luaurc"] = true,
	[".gitignore"] = true,
}
-- A file named alone is a path only outside quotes and not right after one (c0053's `merging='zn sync…'` is a
-- pattern, c0042's `for s in "./zn board"` a list of patterns), or as the command of a command substitution, quoted
-- or not (`"$(./zn find f0014)/check.sh"`)
local function substituted(line: string, first: number): boolean
	return first > 2 and string.sub(line, first - 2, first - 1) == "$("
end
-- a top-level folder a move takes, named alone: a path only as a folder `find` searches (in prose it is a word)
local FOLDERS = { tracker = true, src = true, tests = true }

-- The words of a grep's pattern (a pattern names text, not a file: c0046's `grep -qF "./zn worktree" …`): after
-- `grep` or `rg` and its options, the first other word, or each `-e`'s; a quoted pattern runs to its closing quote.
-- `line` is the scanned line, `raw[k]` the k-th word as written and `starts[k]` its first byte.
local function patternWords(line: string, raw: { string }, starts: { number }): { [number]: boolean }
	local marked: { [number]: boolean } = {}
	local function mark(k: number)
		local s = starts[k]
		local q = if s > 1 then string.sub(line, s - 1, s - 1) else ""
		if q == '"' or q == "'" then
			local close = string.find(line, q, s, true) or (#line + 1)
			for j = k, #raw do
				if starts[j] < close then
					marked[j] = true
				end
			end
		else
			marked[k] = true
		end
	end
	for k, w in raw do
		if w == "grep" or w == "rg" or w == "egrep" then
			local j, named = k + 1, false
			while raw[j] and string.sub(raw[j], 1, 1) == "-" and raw[j] ~= "--" do
				if raw[j] == "-e" or raw[j] == "--regexp" then
					if raw[j + 1] then
						mark(j + 1)
						named = true
					end
					j += 2
				else
					j += 1
				end
			end
			if raw[j] == "--" then
				j += 1
			end
			if not named and raw[j] then
				mark(j)
			end
		end
	end
	return marked
end

-- the literal paths of a check.sh, in order (a path may repeat)
local function literals(text: string): { string }
	local out: { string } = {}
	for line in string.gmatch(text .. "\n", "([^\n]*)\n") do
		if not string.match(line, "^%s*#") then
			line = string.gsub(line, "%s#%s.*$", "")
			-- a check's label is prose, not a command
			line = string.gsub(line, '^(%s*check%s+)"[^"]*"', "%1")
			local words: { string } = {}
			local quoted: { boolean } = {}
			local starts: { number } = {}
			local at = 1
			while true do
				local s, e = string.find(line, "[^%s\"'();|&<>`]+", at)
				if not s then
					break
				end
				at = (e :: number) + 1
				local _, quotes = string.gsub(string.sub(line, 1, s - 1), '"', "")
				table.insert(quoted, quotes % 2 == 1)
				table.insert(starts, s)
				local w = string.sub(line, s, e :: number)
				local word = string.gsub(w, "[\\,]+$", "")
				-- a shell assignment's value is the word (`f=.claude/skills/testing/SKILL.md`)
				local name = string.match(word, "^[%a_][%w_]*=")
				if name and #word > #name then
					word = string.sub(word, #name + 1)
				end
				-- a word that goes on with a variable: its literal folder is the path
				local dollar = string.find(word, "$", 1, true)
				if dollar and dollar > 1 then
					local folder = string.match(string.sub(word, 1, dollar - 1), "^(.*)/[^/]*$")
					if folder and folder ~= "" then
						word = folder .. "/"
					end
				end
				table.insert(words, word)
			end
			local pattern = patternWords(line, words, starts)
			local dir = "" -- a `cd <dir>` earlier on the line: the words after it are relative to <dir>
			local finding = false -- the words after `find`, before its first option, are the folders it searches
			for i, w in words do
				local path: string? = nil
				if pattern[i] then
					continue
				end
				if w == "find" then
					finding = true
					continue
				elseif string.sub(w, 1, 1) == "-" then
					finding = false
				end
				if words[i - 1] == "cd" and not string.find(w, "$", 1, true) then
					dir = w .. "/"
					continue
				end
				if
					not string.find(w, "$", 1, true)
					and string.sub(w, 1, 1) ~= "/"
					and string.sub(w, 1, 1) ~= "-"
				then
					if words[i - 2] == "lune" and words[i - 1] == "run" and string.find(w, "/", 1, true) then
						path = if string.match(w, "%.luau$") then w else w .. ".luau"
					elseif
						(
							FILES[w]
							and (
								substituted(line, starts[i])
								or not (
									quoted[i]
									or string.find(string.sub(line, starts[i] - 1, starts[i] - 1), "[\"']")
								)
							)
						) or (finding and FOLDERS[w])
					then
						path = w
					else
						for _, p in PREFIXES do
							if string.sub(w, 1, #p) == p and #w > #p then
								path = w
							end
						end
					end
				end
				if path then
					table.insert(out, dir .. path)
				end
			end
		end
	end
	return out
end

-- does `path` (relative to the home `home`, in the checkout at `base`) exist? A glob needs one match in its folder.
local function present(base: string, home: string, path: string): boolean
	local full = base .. (if home == "." then path else `{home}/{path}`)
	if not string.find(full, "*", 1, true) then
		return fs.isFile(full) or fs.isDir(full)
	end
	local dir, pat = string.match(full, "^(.*)/([^/]*)$")
	if not dir or string.find(dir, "*", 1, true) or not fs.isDir(dir) then
		return false
	end
	local lua = "^"
		.. string.gsub(string.gsub(pat :: string, "[%.%-%+%?%[%]%^%$%(%)%%]", "%%%0"), "%*", ".*")
		.. "$"
	for _, name in fs.readDir(dir) do
		if string.match(name, lua) then
			return true
		end
	end
	return false
end

-- the Touched modules entries of an item document
local function touched(doc: string): { string }
	local out: { string } = {}
	local text = if fs.isFile(doc) then fs.readFile(doc) else ""
	local section = string.match(text, "\n### Touched modules\n(.-)\n#") or ""
	for path in string.gmatch(section, "\n?%- `([^`]+)`") do
		table.insert(out, (string.gsub(path, "/+$", "")))
	end
	return out
end
local function under(path: string, own: { string }): boolean
	for _, o in own do
		if
			path == o
			or string.sub(path, 1, #o + 1) == o .. "/"
			or string.sub(o, 1, #path + 1) == path .. "/"
		then
			return true
		end
	end
	return false
end

-- every unfinished item folder under every current root of the checkout at `base` ("" or "<dir>/"): { dir, id, raft },
-- with `dir` relative to that checkout
local function items(base: string): { Item }
	local out: { Item } = {}
	local reg = projects.load(if base == "" then "." else string.sub(base, 1, -2), true)
	for _, r in projects.roots(reg) do
		for _, kind in { "issues", "rafts" } do
			for _, state in { "", "active/" } do
				local rel = `{r}/{kind}/{state}`
				if fs.isDir(base .. rel) then
					for _, id in fs.readDir(base .. rel) do
						if string.match(id, "^[fdcR]%d%d%d%d$") then
							local doc = `{base}{rel}{id}/{id}.md`
							local raft = if fs.isFile(doc)
								then string.match(fs.readFile(doc), "\nraft:%s*(R%d%d%d%d)") or ""
								else ""
							table.insert(out, { dir = rel .. id, id = id, raft = raft })
						end
					end
				end
			end
		end
	end
	return out
end

-- The scan, over the checkout at `base`: every path an unfinished check.sh names that is missing from its home and not
-- its own work; how many check.sh files it read, and how many it found (the restamped aside); and, per home, how many.
local function scan(base: string, skip: (text: string) -> boolean): Scan
	local reg = projects.load(if base == "" then "." else string.sub(base, 1, -2), true)
	local all = items(base)
	local homes: { string } = {}
	for _, r in projects.roots(reg) do
		local folder = projects.folderOf(r)
		if folder then
			table.insert(homes, folder)
		end
	end
	local byRaft: { [string]: { string } } = {}
	for _, i in all do
		if i.raft ~= "" then
			byRaft[i.raft] = byRaft[i.raft] or {}
			for _, o in touched(`{base}{i.dir}/{i.id}.md`) do
				table.insert(byRaft[i.raft], o)
			end
		end
	end
	local out: Scan = { bad = {}, checked = 0, found = 0, byHome = {} }
	for _, i in all do
		local file = `{i.dir}/check.sh`
		if fs.isFile(base .. file) then
			local text = fs.readFile(base .. file)
			if not skip(text) then
				out.found += 1
				local home = projects.homeOf(reg, file)
				local entries = touched(`{base}{i.dir}/{i.id}.md`)
				local members: { string } = byRaft[i.id] or {}
				for _, o in members do
					table.insert(entries, o)
				end
				local own = checkpaths.owned(base, home, entries, homes)
				for _, p in literals(text) do
					local at = checkpaths.repoPath(home, p)
					if not present(base, home, p) and not (at and under(at, own)) then
						table.insert(out.bad, `{file}: {p} (from {home})`)
					end
				end
				out.checked += 1
				out.byHome[home] = (out.byHome[home] or 0) + 1
			end
		end
	end
	table.sort(out.bad)
	return out
end

checkpaths.literals = literals
checkpaths.present = present
checkpaths.touched = touched
checkpaths.under = under
checkpaths.items = items
checkpaths.scan = scan

return checkpaths
