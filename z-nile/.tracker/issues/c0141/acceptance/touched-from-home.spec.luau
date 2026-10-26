--!strict
-- c0141: check-paths' Touched exemption compares the repository-relative form of the path a check.sh names (its
-- project home plus the path, `.` and `..` folded) with each Touched entry read both ways the trackers write them:
-- repository-relative (`pickman/skills`) and relative to the item's home (`src/shared/Logic/New` in pickman/). A path
-- that climbs above the checkout is never exempt. Fixture under .cache/c0141-touched-home.
local checkpaths = require("@tests/lib/checkpaths")
local fs = require("@lune/fs")
local t = require("@tests/lib/t")

local FX = ".cache/c0141-touched-home/"
local REGISTRY = 'retired = ["tracker"]\n\n[[project]]\nname = "pickman"\nroot = "pickman/.tracker"\n\n'
	.. '[[project]]\nname = "z-nile"\nroot = "z-nile/.tracker"\n'

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

	it("reads each Touched entry both as repository-relative and from the item's home", function()
		local own = checkpaths.owned("pickman", { "src/New", "pickman/skills/" })
		t.expect(table.find(own, "src/New") ~= nil).toBe(true)
		t.expect(table.find(own, "pickman/src/New") ~= nil).toBe(true)
		t.expect(table.find(own, "pickman/skills") ~= nil).toBe(true)
		t.expect(checkpaths.owned(".", { "zn" })).toEqual({ "zn" })
	end)

	it(
		"in a fixture, a path the item creates is exempt from any home and through a cd; others are reported",
		function()
			if fs.isDir(FX) then
				fs.removeDir(FX)
			end
			put("z-nile/projects.toml", REGISTRY)
			put("pickman/.tracker/issues/.gitkeep", "")
			-- c0001: z-nile's, a repository-relative entry named after `cd ..`: exempt
			item("z-nile/.tracker", "c0001", { "pickman/new-thing" }, "cd .. && test -d pickman/new-thing\n")
			-- c0002: the same path with no Touched entry: reported as written, from its home
			item("z-nile/.tracker", "c0002", {}, "cd .. && test -d pickman/other\n")
			-- f0003: pickman's, a home-relative entry named from its home: exempt
			item("pickman/.tracker", "f0003", { "src/New" }, "test -d src/New\n")
			-- c0004: a path that climbs above the checkout is never exempt, whatever its Touched entry says
			item("z-nile/.tracker", "c0004", { "tests/x" }, "cd ../.. && test -f tests/x\n")
			-- c0005: a repository-relative entry, the path named from the home without a cd: exempt
			item(
				"z-nile/.tracker",
				"c0005",
				{ "z-nile/tests/new.spec.luau" },
				"test -f tests/new.spec.luau\n"
			)
			local s = checkpaths.scan(FX, function(_text: string): boolean
				return false
			end)
			t.expect(s.bad).toEqual({
				"z-nile/.tracker/issues/c0002/check.sh: ../pickman/other (from z-nile)",
				"z-nile/.tracker/issues/c0004/check.sh: ../../tests/x (from z-nile)",
			})
			t.expect(s.checked).toBe(5)
			fs.removeDir(FX)
		end
	)
end)
