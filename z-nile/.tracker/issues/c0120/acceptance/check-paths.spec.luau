--!strict
-- c0120 AC11: every path a check.sh names exists, from its project's home, so no check passes because the path it
-- guards moved away (`git diff --quiet -- src/server` is green on a path that is not there). It covers the check.sh of
-- every unfinished item (backlog and active, every project root): a finished one is never run again. A literal path is
-- a word of a command (comments aside) with no `$`, that starts with a top-level folder of the repository or a home
-- (src/, tests/, scripts/, z-nile/, pickman/, tracker/, .tracker/, .github/, .claude/) or is a root file of a home
-- (default.project.json, lobby.project.json, zn), or follows `lune run` (then with .luau). A glob matches at least one
-- file. Two kinds of path are exempt: one under a Touched modules entry of the item (or of a member, for a raft),
-- which its own work will create, and the check.sh files of the rafts the user restamps for a re-prep after c0120
-- (R0030 with c0083, R0039 with c0075), by their exact content, so a re-prep that rewrites them is checked again.
local fs = require("@lune/fs")
local projects = require("@znile/engine/projects")
local serde = require("@lune/serde")
local t = require("@tests/lib/t")

-- git blob ids of the check.sh files restamped for a re-prep after c0120 (the user's decision), as they are now
local RESTAMPED: { [string]: string } = {
	["3bdafdae668ab8d19cfb26c4e7c0b15290a61bfe"] = "R0030",
	["f9d4fd1f0b1322341c3290961d568d67be9ad21a"] = "c0083",
	["11a38337b7880b1c72dc980c675f4c5a2fd61db7"] = "R0039",
	["6b7764378eb11104e765724ed40cfb1af4833749"] = "c0075",
}
local PREFIXES =
	{ "src/", "tests/", "scripts/", "z-nile/", "pickman/", "tracker/", ".tracker/", ".github/", ".claude/" }
local FILES = { ["default.project.json"] = true, ["lobby.project.json"] = true, zn = true }

local function blob(text: string): string
	return serde.hash("sha1", `blob {#text}\0{text}`)
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
			for w in string.gmatch(line, "[^%s\"'();|&<>`]+") do
				table.insert(words, (string.gsub(w, "[\\,]+$", "")))
			end
			local dir = "" -- a `cd <dir>` earlier on the line: the words after it are relative to <dir>
			for i, w in words do
				local path: string? = nil
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
					elseif FILES[w] then
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

-- does `path` (relative to the home `home`) exist? A glob needs one match in its folder.
local function present(home: string, path: string): boolean
	local full = if home == "." then path else `{home}/{path}`
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

-- every unfinished item folder under every current root: { dir, id, kind, raft }
type Item = { dir: string, id: string, kind: string, raft: string }
local function items(): { Item }
	local out: { Item } = {}
	for _, r in projects.roots(projects.load()) do
		for _, kind in { "issues", "rafts" } do
			for _, state in { "", "active/" } do
				local base = `{r}/{kind}/{state}`
				if fs.isDir(base) then
					for _, id in fs.readDir(base) do
						if string.match(id, "^[fdcR]%d%d%d%d$") then
							local doc = `{base}{id}/{id}.md`
							local raft = if fs.isFile(doc)
								then string.match(fs.readFile(doc), "\nraft:%s*(R%d%d%d%d)") or ""
								else ""
							table.insert(out, { dir = base .. id, id = id, kind = kind, raft = raft })
						end
					end
				end
			end
		end
	end
	return out
end

return t.spec("c0120 every path a live check.sh names exists from its home", function(it)
	it("finds the literal paths of a check.sh, and nothing else", function()
		local text = table.concat({
			"#!/usr/bin/env bash",
			"# tests/not/a/path in a comment",
			'source "$(git -C "$HERE" rev-parse --show-toplevel)/z-nile/lib/ac.sh"',
			'check "AC1: x" lune run tests/run -- "$A/x.spec.luau" tests/meta/architecture.spec.luau',
			'git diff --quiet "$(git merge-base origin/main HEAD)" -- src/server default.project.json src/lobby \\',
			"check \"AC5: tests/label/words are prose\" bash -c 'cd pickman && lune run tests/run -- tests/meta/x.spec.luau'",
			"  || echo moved # src/ignored",
			"check \"AC2: y\" bash -c 'test -f src/shared/Logic/Touch/init.luau'",
			'check "AC3: z" scripts/tracker.sh members R0010; check "AC4" ./zn audit',
			"ls tests/acceptance/f0031/*.spec.luau origin/main pickman",
		}, "\n")
		t.expect(literals(text)).toEqual({
			"tests/run.luau",
			"tests/meta/architecture.spec.luau",
			"src/server",
			"default.project.json",
			"src/lobby",
			"pickman/tests/run.luau",
			"pickman/tests/meta/x.spec.luau",
			"src/shared/Logic/Touch/init.luau",
			"scripts/tracker.sh",
			"tests/acceptance/f0031/*.spec.luau",
		})
	end)

	it("a path resolves from its home; a glob needs a match; own work is exempt", function()
		t.expect(present("pickman", "src/server")).toBe(true)
		t.expect(present("pickman", "tests/run.luau")).toBe(true)
		t.expect(present(".", "src/server")).toBe(false)
		t.expect(present("pickman", "tests/acceptance/f0031/*.spec.luau")).toBe(true)
		t.expect(present("pickman", "tests/acceptance/f0031/*.nope")).toBe(false)
		t.expect(under("src/shared/Logic/Touch/init.luau", { "src/shared/Logic/Touch" })).toBe(true)
		t.expect(under("tests/unit", { "tests/unit/Touch" })).toBe(true)
		t.expect(under("src/server", { "src/shared/Logic/Touch" })).toBe(false)
		t.expect(under("src/shared/Logic/Touchy", { "src/shared/Logic/Touch" })).toBe(false)
	end)

	it(
		"every unfinished item's check.sh, in every project root, names only paths that exist from its home",
		function()
			local reg = projects.load()
			local all = items()
			local byRaft: { [string]: { string } } = {}
			for _, i in all do
				if i.raft ~= "" then
					byRaft[i.raft] = byRaft[i.raft] or {}
					for _, o in touched(`{i.dir}/{i.id}.md`) do
						table.insert(byRaft[i.raft], o)
					end
				end
			end
			local bad: { string } = {}
			local checked, homes = 0, { pickman = 0, root = 0 }
			for _, i in all do
				local file = `{i.dir}/check.sh`
				if fs.isFile(file) then
					local text = fs.readFile(file)
					if not RESTAMPED[blob(text)] then
						checked += 1
						local home = projects.homeOf(reg, file)
						homes[if home == "." then "root" else "pickman"] += 1
						local own = touched(`{i.dir}/{i.id}.md`)
						local members: { string } = byRaft[i.id] or {}
						for _, o in members do
							table.insert(own, o)
						end
						for _, p in literals(text) do
							if not present(home, p) and not under(p, own) then
								table.insert(bad, `{file}: {p} (from {home})`)
							end
						end
					end
				end
			end
			t.expect(table.concat(bad, "\n")).toBe("")
			-- not vacuous: pickman's live check.sh files (R0012, R0035, R0041 and their members, ...) were read from pickman/
			t.expect(homes.pickman >= 10).toBe(true)
			t.expect(homes.root >= 5).toBe(true)
			t.expect(checked).toBe(homes.pickman + homes.root)
		end
	)

	it("the restamped check.sh files are exempt only as they are now", function()
		local found = 0
		for _, i in items() do
			local file = `{i.dir}/check.sh`
			if fs.isFile(file) and RESTAMPED[blob(fs.readFile(file))] then
				found += 1
				t.expect(RESTAMPED[blob(fs.readFile(file))]).toBe(i.id)
			end
		end
		-- while those rafts wait for their re-prep all four are here; once a re-prep rewrites one, it is checked
		t.expect(found <= 4).toBe(true)
		t.expect(RESTAMPED[blob(fs.readFile(`{(items())[1].dir}/check.sh`) .. "\n")]).toBe(nil)
	end)
end)
