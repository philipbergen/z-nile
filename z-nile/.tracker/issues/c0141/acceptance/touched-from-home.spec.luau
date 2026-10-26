--!strict
-- c0141: check-paths' Touched exemption compares the repository-relative form of the path a check.sh names (its
-- project home plus the path, `.` and `..` folded) with what each Touched entry names, read ONE way chosen from the
-- document's own text (design review 002 F1, never the disk): when any of a document's Touched entries starts with a
-- registered project's home, every entry of that document is read from the checkout's top; otherwise every entry is
-- read from the item's home, a root path being written `../X`. A path that climbs above the checkout is never exempt. The scanner lives in c0120's promoted folder (F3) and c0120's spec takes its scan from it (F2).
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

	it("reads a document's Touched entries by the document's convention, never the disk's", function()
		local homes = { "pickman", "z-nile", "game2" }
		-- any entry starting with a registered home: the whole document is read from the top
		t.expect(checkpaths.owned("z-nile", { "z-nile/skills" }, homes)).toEqual({ "z-nile/skills" })
		t.expect(checkpaths.owned("z-nile", { ".models.toml", "z-nile/x" }, homes))
			.toEqual({ ".models.toml", "z-nile/x" })
		t.expect(checkpaths.owned("z-nile", { "AGENTS.md", "game2/x" }, homes)).toEqual({ "AGENTS.md", "game2/x" })
		-- the home entry first, and in the middle: any entry decides, never the last or the first (design review 003 F1)
		t.expect(checkpaths.owned("z-nile", { "z-nile/x", ".models.toml" }, homes))
			.toEqual({ "z-nile/x", ".models.toml" })
		t.expect(checkpaths.owned("z-nile", { "AGENTS.md", "z-nile/x", "scripts/y" }, homes))
			.toEqual({ "AGENTS.md", "z-nile/x", "scripts/y" })
		-- none does: the whole document is read from the home, `..` reaching the top
		t.expect(checkpaths.owned("pickman", { "src/New", "../AGENTS.md" }, homes))
			.toEqual({ "pickman/src/New", "AGENTS.md" })
		t.expect(checkpaths.owned("pickman", { ".github/workflows/new.yml" }, homes))
			.toEqual({ "pickman/.github/workflows/new.yml" })
		-- a name not in `homes` is not taken as a home
		t.expect(checkpaths.owned("z-nile", { "game3/x" }, homes)).toEqual({ "z-nile/game3/x" })
		-- climbing above the checkout names nothing
		t.expect(checkpaths.owned("pickman", { "../../x" }, homes)).toEqual({})
	end)

	it("the verdict doesn't change when the item's own work creates the path (design review 002's probe)", function()
		local fx = ".cache/c0141-probe/"
		if fs.isDir(fx) then
			fs.removeDir(fx)
		end
		local function at(rel: string, text: string)
			fs.writeDir(string.match(fx .. rel, "^(.*)/[^/]+$") :: string)
			fs.writeFile(fx .. rel, text)
		end
		at("z-nile/projects.toml", REGISTRY)
		at(".github/workflows/ci.yml", "x\n")
		at("AGENTS.md", "x\n")
		at("z-nile/.tracker/issues/.gitkeep", "")
		local doc = "---\nid: %s\n---\n### Touched modules\n- `.github/workflows/new.yml`\n\n## Next\n"
		at("pickman/.tracker/issues/f0001/f0001.md", string.format(doc, "f0001"))
		at("pickman/.tracker/issues/f0001/check.sh", "test -f .github/workflows/new.yml\n")
		at("pickman/.tracker/issues/f0002/f0002.md", string.format(doc, "f0002"))
		at("pickman/.tracker/issues/f0002/check.sh", "cd .. && test -f .github/workflows/new.yml\n")
		local function verdict(): { string }
			return checkpaths.scan(fx, function(_text: string): boolean
				return false
			end).bad
		end
		local want = { "pickman/.tracker/issues/f0002/check.sh: ../.github/workflows/new.yml (from pickman)" }
		t.expect(verdict()).toEqual(want) -- before pickman/.github exists
		at("pickman/.github/workflows/new.yml", "x\n")
		t.expect(verdict()).toEqual(want) -- after: the same
		fs.removeDir(fx)
	end)

	it("in a fixture, a path the item creates is exempt from any home and through a cd; others are reported", function()
		if fs.isDir(FX) then
			fs.removeDir(FX)
		end
		put("z-nile/projects.toml", REGISTRY)
		put("pickman/.tracker/issues/.gitkeep", "")
		put("pickman/src/.gitkeep", "")
		put("z-nile/skills/.gitkeep", "")
		put("game2/.tracker/issues/.gitkeep", "")
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
		-- design review 003 F2: a document naming a third registered project is read from the top only when `scan` takes
		-- its homes from the registry, so its root `scripts/new` is exempt (a hand list of two reads it from the home and
		-- reports it). `game2/…` itself isn't a word check-paths reads as a path (c0120's prefixes), so the root entry
		-- carries the case.
		item("z-nile/.tracker", "c0008", { "game2/x", "scripts/new" }, "cd .. && test -f scripts/new\n")
		local s = checkpaths.scan(FX, function(_text: string): boolean
			return false
		end)
		t.expect(s.bad).toEqual({
			"pickman/.tracker/issues/f0007/check.sh: ../src/New (from pickman)",
			"z-nile/.tracker/issues/c0002/check.sh: ../pickman/other (from z-nile)",
			"z-nile/.tracker/issues/c0004/check.sh: ../../tests/x (from z-nile)",
			"z-nile/.tracker/issues/c0006/check.sh: z-nile/skills/new (from z-nile)",
		})
		t.expect(s.checked).toBe(8)
		fs.removeDir(FX)
	end)
end)
