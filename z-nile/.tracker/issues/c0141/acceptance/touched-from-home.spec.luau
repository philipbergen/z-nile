--!strict
-- c0141: check-paths' Touched exemption compares the repository-relative form of the path a check.sh names (its
-- project home plus the path, `.` and `..` folded) with what each Touched entry names, read ONE way chosen from the
-- entry's own text (design review 001 F1): an entry starting with a registered project's home is repository-relative;
-- otherwise the item's home wins when the entry's first segment exists there, a root-level file or folder that exists
-- at the top is repository-relative, and anything else is read from the home. A path that climbs above the checkout
-- is never exempt. The scanner lives in c0120's promoted folder (F3) and c0120's spec takes its scan from it (F2).
-- Fixture under .cache/c0141-touched-home.
local checkpaths = require("@tests/acceptance/c0120/checkpaths")
local fs = require("@lune/fs")
local t = require("@tests/lib/t")

local FX = ".cache/c0141-touched-home/"
local REGISTRY = 'retired = ["tracker"]\n\n[[project]]\nname = "pickman"\nroot = "pickman/.tracker"\n\n'
	.. '[[project]]\nname = "z-nile"\nroot = "z-nile/.tracker"\n\n'
	.. '[[project]]\nname = "game2"\nroot = "game2/.tracker"\n'

local function put(rel: string, text: string)
	fs.writeDir(string.match(FX .. rel, "^(.*)/[^/]+$") :: string)
	fs.writeFile(FX .. rel, text)
end
local function item(root: string, id: string, touchedPaths: { string }, check: string)
	local lines = { `---\nid: {id}\n---\n### Touched modules` }
	for _, p in touchedPaths do
		table.insert(lines, `- \`{p}\``)
	end
	put(`{root}/issues/{id}/{id}.md`, table.concat(lines, "\n") .. "\n\n## Next\n")
	put(`{root}/issues/{id}/check.sh`, check)
end

return t.spec("c0141 a check.sh path is compared with Touched modules from the checkout's top", function(it)
	it("folds a home-relative path to the checkout's top, and refuses one that climbs above it", function()
		t.expect(checkpaths.repoPath("z-nile", "../pickman/skills")).toBe("pickman/skills")
		t.expect(checkpaths.repoPath("z-nile", "z-nile/skills")).toBe("z-nile/z-nile/skills")
		t.expect(checkpaths.repoPath(".", "AGENTS.md")).toBe("AGENTS.md")
		t.expect(checkpaths.repoPath("pickman", "./a/../b")).toBe("pickman/b")
		t.expect(checkpaths.repoPath("pickman", "src/*.luau")).toBe("pickman/src/*.luau")
		t.expect(checkpaths.repoPath("z-nile", "../../outside/x")).toBe(nil)
		t.expect(checkpaths.repoPath(".", "../x")).toBe(nil)
	end)

	it("reads each Touched entry one way, chosen from its own text", function()
		local base = ".cache/c0141-owned/"
		if fs.isDir(base) then
			fs.removeDir(base)
		end
		fs.writeDir(base .. "pickman/src")
		fs.writeDir(base .. ".github")
		fs.writeFile(base .. "AGENTS.md", "x\n")
		fs.writeDir(base .. "scripts")
		fs.writeDir(base .. "pickman/scripts")
		local homes = { "pickman", "z-nile", "game2" }
		-- a registered home's prefix: repository-relative only
		t.expect(checkpaths.owned(base, "z-nile", { "z-nile/skills" }, homes)).toEqual({ "z-nile/skills" })
		t.expect(checkpaths.owned(base, "z-nile", { "game2/x" }, homes)).toEqual({ "game2/x" })
		-- the first segment exists in the home: read from the home only
		t.expect(checkpaths.owned(base, "pickman", { "src/New" }, homes)).toEqual({ "pickman/src/New" })
		-- the first segment exists both in the home and at the top (`scripts/`): the home wins
		t.expect(checkpaths.owned(base, "pickman", { "scripts/x" }, homes)).toEqual({ "pickman/scripts/x" })
		-- a root-level file or folder that exists at the top (and not in the home): repository-relative
		t.expect(checkpaths.owned(base, "z-nile", { "AGENTS.md", ".github/workflows" }, homes))
			.toEqual({ "AGENTS.md", ".github/workflows" })
		-- neither: read from the home (a new folder the item creates)
		t.expect(checkpaths.owned(base, "pickman", { "assets/New" }, homes)).toEqual({ "pickman/assets/New" })
		-- a name not in `homes` is not taken as a home
		t.expect(checkpaths.owned(base, "z-nile", { "game3/x" }, homes)).toEqual({ "z-nile/game3/x" })
		fs.removeDir(base)
	end)

	it("in a fixture, a path the item creates is exempt from any home and through a cd; others are reported", function()
		if fs.isDir(FX) then
			fs.removeDir(FX)
		end
		put("z-nile/projects.toml", REGISTRY)
		put("pickman/.tracker/issues/.gitkeep", "")
		put("pickman/src/.gitkeep", "")
		put("z-nile/skills/.gitkeep", "")
		-- c0001: z-nile's, a repository-relative entry named after `cd ..`: exempt
		item("z-nile/.tracker", "c0001", { "pickman/new-thing" }, "cd .. && test -d pickman/new-thing\n")
		-- c0002: the same path with no Touched entry: reported as written, from its home
		item("z-nile/.tracker", "c0002", {}, "cd .. && test -d pickman/other\n")
		-- f0003: pickman's, a home-relative entry named from its home: exempt
		item("pickman/.tracker", "f0003", { "src/New" }, "test -d src/New\n")
		-- c0004: a path that climbs above the checkout is never exempt, whatever its Touched entry says
		item("z-nile/.tracker", "c0004", { "tests/x" }, "cd ../.. && test -f tests/x\n")
		-- c0005: a repository-relative entry, the path named from the home without a cd: exempt
		item("z-nile/.tracker", "c0005", { "z-nile/tests/new.spec.luau" }, "test -f tests/new.spec.luau\n")
		-- design review 001 F1 (a): a repository-relative entry, the check names it from the home (tests z-nile/z-nile/…)
		item("z-nile/.tracker", "c0006", { "z-nile/skills" }, "test -d z-nile/skills/new\n")
		-- design review 001 F1 (b): a home-relative entry, the check climbs to the top (tests the root's src/New)
		item("pickman/.tracker", "f0007", { "src/New" }, "cd .. && test -d src/New\n")
		local s = checkpaths.scan(FX, function(_text: string): boolean
			return false
		end)
		t.expect(s.bad).toEqual({
			"pickman/.tracker/issues/f0007/check.sh: ../src/New (from pickman)",
			"z-nile/.tracker/issues/c0002/check.sh: ../pickman/other (from z-nile)",
			"z-nile/.tracker/issues/c0004/check.sh: ../../tests/x (from z-nile)",
			"z-nile/.tracker/issues/c0006/check.sh: z-nile/skills/new (from z-nile)",
		})
		t.expect(s.checked).toBe(7)
		fs.removeDir(FX)
	end)
end)
