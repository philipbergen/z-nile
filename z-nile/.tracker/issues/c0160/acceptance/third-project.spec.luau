--!strict
-- c0160: c0120's check-paths scan (c0141's module, z-nile/tests/acceptance/c0120/checkpaths.luau) reads a third
-- project's check.sh files the way it reads pickman's and z-nile's. A word starting with any registered project's home
-- (`<home>/…`) is a literal path, the homes taken from the registry of the checkout being scanned, never a hand list.
-- The third project, `tern`, exists only in this fixture, under .cache/c0160-third.
local checkpaths = require("@znile/tests/acceptance/c0120/checkpaths")
local fs = require("@lune/fs")
local rewrites = require("@znile/tests/acceptance/c0120/rewrites")
local t = require("@tests/lib/t")

local FX = ".cache/c0160-third/"
local REGISTRY = 'retired = ["tracker"]\n\n[[project]]\nname = "pickman"\nroot = "pickman/.tracker"\n\n'
	.. '[[project]]\nname = "z-nile"\nroot = "z-nile/.tracker"\n\n'
	.. '[[project]]\nname = "tern"\nroot = "tern/.tracker"\n'
local function put(rel: string, text: string)
	fs.writeDir(string.match(FX .. rel, "^(.*)/[^/]+$") :: string)
	fs.writeFile(FX .. rel, text)
end
local function scanFixture(): checkpaths.Scan
	return checkpaths.scan(FX, function(_text: string): boolean
		return false
	end)
end

return t.spec("c0160 the check-paths scan reads a third project like the first two", function(it)
	it(
		"a third project's check.sh is read from its own home: a missing path is listed, a present one not",
		function()
			if fs.isDir(FX) then
				fs.removeDir(FX)
			end
			put("z-nile/projects.toml", REGISTRY)
			fs.writeDir(FX .. "pickman/.tracker/issues")
			put("tern/src/here.luau", "--!strict\nreturn nil\n")
			put("tern/.tracker/issues/c0001/c0001.md", "---\nid: c0001\n---\n")
			put("tern/.tracker/issues/c0001/check.sh", "test -f src/here.luau\ntest -f src/gone.luau\n")
			local s = scanFixture()
			t.expect(s.bad).toEqual({ "tern/.tracker/issues/c0001/check.sh: src/gone.luau (from tern)" })
			t.expect(s.checked).toBe(1)
			t.expect(s.byHome).toEqual({ tern = 1 })
		end
	)

	it(
		"a path through the third project's home, named from another home, is a literal path and is checked",
		function()
			-- z-nile's check names tern's files from the top (after `cd ..`): one there, one gone
			put("z-nile/.tracker/issues/c0002/c0002.md", "---\nid: c0002\n---\n")
			put(
				"z-nile/.tracker/issues/c0002/check.sh",
				"cd .. && test -f tern/src/here.luau && test -f tern/src/missing.luau\n"
			)
			local s = scanFixture()
			t.expect(s.bad).toEqual({
				"tern/.tracker/issues/c0001/check.sh: src/gone.luau (from tern)",
				"z-nile/.tracker/issues/c0002/check.sh: ../tern/src/missing.luau (from z-nile)",
			})
			t.expect(s.byHome).toEqual({ tern = 1, ["z-nile"] = 1 })
			-- the homes are the scanned checkout's: a word under a folder that is no registered home is no path
			t.expect(checkpaths.literals("test -f tern/a.luau ternary/b.luau", { "tern" }))
				.toEqual({ "tern/a.luau" })
			t.expect(checkpaths.literals("test -f tern/a.luau", { "pickman", "z-nile" })).toEqual({})
		end
	)

	it("a third project's own work, named in its Touched modules, is exempt as the others' is", function()
		put(
			"tern/.tracker/issues/c0003/c0003.md",
			"---\nid: c0003\n---\n### Touched modules\n- `tern/src/new`\n\n## Next\n"
		)
		put(
			"tern/.tracker/issues/c0003/check.sh",
			"test -d src/new\ncd .. && test -f tern/src/new/init.luau\n"
		)
		local s = scanFixture()
		for _, line in s.bad do
			t.expect((string.find(line, "c0003", 1, true))).toBe(nil)
		end
		t.expect(s.byHome).toEqual({ tern = 2, ["z-nile"] = 1 })
		fs.removeDir(FX)
	end)

	it(
		"called without homes, the literal reader takes the homes of the checkout it runs in, from its registry",
		function()
			-- this checkout registers pickman and z-nile: both are read, an unregistered folder is not
			t.expect(checkpaths.literals("test -f pickman/a.luau z-nile/b.luau tern/c.luau")).toEqual({
				"pickman/a.luau",
				"z-nile/b.luau",
			})
		end
	)

	it(
		"c0120's finished-file reader takes the homes the same way: given, or the checkout's registry",
		function()
			local function words(text: string, homes: { string }?): { string }
				local out = {}
				for _, l in rewrites.literals(text, homes) do
					table.insert(out, l.path)
				end
				return out
			end
			t.expect(words("test -f tern/a.luau ternary/b.luau", { "tern" })).toEqual({ "tern/a.luau" })
			t.expect(words("test -f tern/a.luau", { "pickman", "z-nile" })).toEqual({})
			t.expect(words("test -f pickman/a.luau z-nile/b.luau tern/c.luau"))
				.toEqual({ "pickman/a.luau", "z-nile/b.luau" })
		end
	)
end)
