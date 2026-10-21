--!strict
-- c0120 AC11: every path a check.sh names exists, from its project's home, so no check passes because the path it
-- guards moved away (`git diff --quiet -- src/server` is green on a path that is not there). It covers the check.sh of
-- every unfinished item (backlog and active, every project root), read from its home (pickman/, z-nile/); finished
-- items' files are finished.spec.luau's (the user's 2026-10-21 decision rewrites them). A literal path is
-- a word of a command (comments aside) with no `$`, that starts with a top-level folder of the repository or a home
-- (src/, tests/, scripts/, z-nile/, pickman/, tracker/, .tracker/, .github/, .claude/) or is a root file of a home
-- (default.project.json, lobby.project.json, zn), or follows `lune run` (then with .luau). A glob matches at least one
-- file. Two kinds of path are exempt: one under a Touched modules entry of the item (or of a member, for a raft),
-- which its own work will create, and the check.sh files of the rafts the user restamps for a re-prep after c0120
-- (R0030 with c0083, R0039 with c0075), by their exact content, so a re-prep that rewrites them is checked again.
local fs = require("@lune/fs")
local projects = require("@znile/engine/projects")
local serde = require("@lune/serde")
local process = require("@lune/process")
local t = require("@tests/lib/t")

-- the checkout's top, with a slash: these specs run from z-nile/ (c0120), and the scan reads the checkout from there
local TOP = (string.gsub(process.exec("git", { "rev-parse", "--show-toplevel" }).stdout, "%s+$", "")) .. "/"

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
				if not string.find(w, "$", 1, true) and string.sub(w, 1, 1) ~= "/" and string.sub(w, 1, 1) ~= "-" then
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
	local lua = "^" .. string.gsub(string.gsub(pat :: string, "[%.%-%+%?%[%]%^%$%(%)%%]", "%%%0"), "%*", ".*") .. "$"
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
		if path == o or string.sub(path, 1, #o + 1) == o .. "/" or string.sub(o, 1, #path + 1) == path .. "/" then
			return true
		end
	end
	return false
end

-- every unfinished item folder under every current root of the checkout at `base` ("" or "<dir>/"): { dir, id, raft },
-- with `dir` relative to that checkout
type Item = { dir: string, id: string, raft: string }
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
type Scan = { bad: { string }, checked: number, found: number, byHome: { [string]: number } }
local function scan(base: string): Scan
	local reg = projects.load(if base == "" then "." else string.sub(base, 1, -2), true)
	local all = items(base)
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
			if not RESTAMPED[blob(text)] then
				out.found += 1
				local home = projects.homeOf(reg, file)
				local own = touched(`{base}{i.dir}/{i.id}.md`)
				local members: { string } = byRaft[i.id] or {}
				for _, o in members do
					table.insert(own, o)
				end
				for _, p in literals(text) do
					if not present(base, home, p) and not under(p, own) then
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

-- a checkout with one item per home (review 001 F3: the scan's reach is proved here, never by counting live items)
local FX = ".cache/c0120-check-paths/"
local REGISTRY = 'retired = ["tracker"]\n\n[[project]]\nname = "pickman"\nroot = "pickman/.tracker"\n\n'
	.. '[[project]]\nname = "z-nile"\nroot = "z-nile/.tracker"\n'
local function put(rel: string, text: string)
	fs.writeDir(string.match(FX .. rel, "^(.*)/[^/]+$") :: string)
	fs.writeFile(FX .. rel, text)
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

	it("in a fixture, each check.sh is read from its home, and a vanished path is reported", function()
		if fs.isDir(FX) then
			fs.removeDir(FX)
		end
		put("z-nile/projects.toml", REGISTRY)
		put("pickman/src/server/Main.server.luau", "--!strict\nreturn nil\n")
		put("pickman/tests/acceptance/f0031/a.spec.luau", "--!strict\nreturn nil\n")
		put("z-nile/tests/tooling/x.spec.luau", "--!strict\nreturn nil\n")
		put("z-nile/tests/run.luau", "--!strict\nreturn nil\n")
		-- pickman's: a path that exists only from pickman/, a glob, its own work, and one that vanished
		put(
			"pickman/.tracker/issues/f0001/f0001.md",
			"---\nid: f0001\nraft: R0001\n---\n### Touched modules\n- `src/shared/Logic/New`\n\n## Next\n"
		)
		put(
			"pickman/.tracker/issues/f0001/check.sh",
			"git diff --quiet -- src/server\nls tests/acceptance/f0031/*.spec.luau\ntest -f src/shared/Logic/New/init.luau\ntest -f src/gone.luau\n"
		)
		-- its raft names a member's own work too
		put("pickman/.tracker/rafts/R0001/R0001.md", "---\nid: R0001\n---\n")
		put("pickman/.tracker/rafts/R0001/check.sh", "test -d src/shared/Logic/New\n")
		-- z-nile's, from z-nile/
		put("z-nile/.tracker/issues/c0002/c0002.md", "---\nid: c0002\n---\n")
		put(
			"z-nile/.tracker/issues/c0002/check.sh",
			"lune run tests/run -- tests/tooling/x.spec.luau\ntest -f src/server\n"
		)
		local s = scan(FX)
		t.expect(s.bad).toEqual({
			"pickman/.tracker/issues/f0001/check.sh: src/gone.luau (from pickman)",
			"z-nile/.tracker/issues/c0002/check.sh: src/server (from z-nile)",
		})
		t.expect(s.checked).toBe(3)
		t.expect(s.byHome).toEqual({ pickman = 2, ["z-nile"] = 1 })
		t.expect(present(FX, ".", "src/server")).toBe(false)
		t.expect(present(FX, "pickman", "tests/acceptance/f0031/*.nope")).toBe(false)
		t.expect(under("tests/unit", { "tests/unit/Touch" })).toBe(true)
		t.expect(under("src/shared/Logic/Touchy", { "src/shared/Logic/Touch" })).toBe(false)
		fs.removeDir(FX)
	end)

	it("every unfinished item's check.sh, in every project root, names only paths that exist from its home", function()
		local s = scan(TOP)
		t.expect(table.concat(s.bad, "\n")).toBe("")
		-- every check.sh found was read (no floor on how many there are: the backlog shrinks)
		t.expect(s.checked).toBe(s.found)
	end)

	it("the restamped check.sh files are exempt only as they are now", function()
		for _, i in items(TOP) do
			local file = `{TOP}{i.dir}/check.sh`
			if fs.isFile(file) and RESTAMPED[blob(fs.readFile(file))] then
				t.expect(RESTAMPED[blob(fs.readFile(file))]).toBe(i.id)
			end
		end
		-- by content: a check.sh one byte apart is not exempt
		for id, _ in RESTAMPED do
			t.expect(RESTAMPED[blob(id .. "\n")]).toBe(nil)
		end
	end)
end)
