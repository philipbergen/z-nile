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
local process = require("@lune/process")
local serde = require("@lune/serde")
local t = require("@tests/lib/t")

-- the checkout's top, with a slash: these specs run from z-nile/ (c0120), and the scan reads the checkout from there
local TOP = (string.gsub(process.exec("git", { "rev-parse", "--show-toplevel" }).stdout, "%s+$", "")) .. "/"

-- git blob ids of the check.sh files restamped for a re-prep after c0120 (the user's decision), as they are now
local RESTAMPED: { [string]: string } = {
	["3bdafdae668ab8d19cfb26c4e7c0b15290a61bfe"] = "R0030",
	["2ed112435a2d5bf9e9670158939bc83cbc7c45aa"] = "c0083", -- c0115 override: its old skill paths renamed (the user's G4)
	["11a38337b7880b1c72dc980c675f4c5a2fd61db7"] = "R0039",
	["6b7764378eb11104e765724ed40cfb1af4833749"] = "c0075",
	-- decided with the user, 2026-10-23: "Re-prep R0044 after; exempt the stack": R0044 (prepared on main for the old
	-- layout) is re-prepped after c0120, restamped `preparing` on main
	["f989acf181d949b6ca4e8a189f0034d2475ab321"] = "R0044",
	["3145713efb3b956619a8db297ea3fc8157db6a28"] = "d0124",
}
local function blob(text: string): string
	return serde.hash("sha1", `blob {#text}\0{text}`)
end

local checkpaths = require("./checkpaths")
local literals, present, under, items =
	checkpaths.literals, checkpaths.present, checkpaths.under, checkpaths.items
local function scanFrom(base: string): checkpaths.Scan
	return checkpaths.scan(base, function(text: string): boolean
		return RESTAMPED[blob(text)] ~= nil
	end)
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
		local s = scanFrom(FX)
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

	it(
		"every unfinished item's check.sh, in every project root, names only paths that exist from its home",
		function()
			local s = scanFrom(TOP)
			t.expect(table.concat(s.bad, "\n")).toBe("")
			-- every check.sh found was read (no floor on how many there are: the backlog shrinks)
			t.expect(s.checked).toBe(s.found)
		end
	)

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
