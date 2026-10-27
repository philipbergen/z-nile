--!strict
-- c0160: c0120's check-paths scan (c0141's module, z-nile/tests/acceptance/c0120/checkpaths.luau) reads a third
-- project's check.sh files the way it reads pickman's and z-nile's. A word starting with any registered project's home
-- (`<home>/…`) is a literal path, the homes taken from the registry of the checkout being scanned, never a hand list.
-- The third project, `tern`, exists only in this fixture, under .cache/c0160-third.
local checkpaths = require("@znile/tests/acceptance/c0120/checkpaths")
local fs = require("@lune/fs")
local process = require("@lune/process")
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
		"a third project's check.sh, backlog and active, is read from its own home: a missing path or glob is listed",
		function()
			if fs.isDir(FX) then
				fs.removeDir(FX)
			end
			put("z-nile/projects.toml", REGISTRY)
			fs.writeDir(FX .. "pickman/.tracker/issues")
			put("tern/src/here.luau", "--!strict\nreturn nil\n")
			put("tern/.tracker/issues/c0001/c0001.md", "---\nid: c0001\n---\n")
			put("tern/.tracker/issues/c0001/check.sh", "test -f src/here.luau\ntest -f src/gone.luau\n")
			-- an active item too, with a glob that matches and one that doesn't (the capture's outcomes)
			put("tern/.tracker/issues/active/c0004/c0004.md", "---\nid: c0004\n---\n")
			put("tern/.tracker/issues/active/c0004/check.sh", "ls src/*.luau\nls src/*.nope\n")
			local s = scanFixture()
			t.expect(s.bad).toEqual({
				"tern/.tracker/issues/active/c0004/check.sh: src/*.nope (from tern)",
				"tern/.tracker/issues/c0001/check.sh: src/gone.luau (from tern)",
			})
			t.expect(s.checked).toBe(2)
			t.expect(s.byHome).toEqual({ tern = 2 })
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
				"tern/.tracker/issues/active/c0004/check.sh: src/*.nope (from tern)",
				"tern/.tracker/issues/c0001/check.sh: src/gone.luau (from tern)",
				"z-nile/.tracker/issues/c0002/check.sh: ../tern/src/missing.luau (from z-nile)",
			})
			t.expect(s.byHome).toEqual({ tern = 2, ["z-nile"] = 1 })
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
		-- the reader finds the tern word, so the exemption (not a missed word) is what keeps it off the list (review 001 F3)
		local homes = { "pickman", "z-nile", "tern" }
		local words = checkpaths.literals(fs.readFile(FX .. "tern/.tracker/issues/c0003/check.sh"), homes)
		t.expect(table.find(words, "../tern/src/new/init.luau") ~= nil).toBe(true)
		local s = scanFixture()
		for _, line in s.bad do
			t.expect((string.find(line, "c0003", 1, true))).toBe(nil)
		end
		t.expect(s.byHome).toEqual({ tern = 3, ["z-nile"] = 1 })
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

	it("the default homes are the registry's of the checkout a reader runs in, never a fixed list", function()
		-- review 001 F1: a child Lune in another checkout (a git repository under .cache/c0160-default whose registry has
		-- tern and z-nile, not pickman) reads tern/ and z-nile/ paths and not pickman/ ones, through both readers
		local DX = ".cache/c0160-default/"
		if fs.isDir(DX) then
			fs.removeDir(DX)
		end
		fs.writeDir(DX .. "checkout/z-nile")
		fs.writeFile(
			DX .. "checkout/z-nile/projects.toml",
			'[[project]]\nname = "z-nile"\nroot = "z-nile/.tracker"\n\n[[project]]\nname = "tern"\nroot = "tern/.tracker"\n'
		)
		t.expect(process.exec("git", { "init", "-q", DX .. "checkout" }).ok).toBe(true)
		local R = "req" .. "uire" -- keeps literal require text out of this file (the require scanner)
		fs.writeDir(DX .. "probe")
		fs.writeFile(
			DX .. "probe/probe.luau",
			table.concat({
				`local checkpaths = {R}("../../../tests/acceptance/c0120/checkpaths")`,
				`local rewrites = {R}("../../../tests/acceptance/c0120/rewrites")`,
				'local text = "test -f pickman/a.luau z-nile/b.luau tern/c.luau"',
				"local out = {}",
				"for _, w in checkpaths.literals(text) do",
				'\ttable.insert(out, "cp:" .. w)',
				"end",
				"for _, l in rewrites.literals(text) do",
				'\ttable.insert(out, "rw:" .. l.path)',
				"end",
				'print(table.concat(out, ","))',
				"",
			}, "\n")
		)
		local here = (string.gsub(process.exec("pwd", { "-P" }).stdout, "%s+$", ""))
		local r = process.exec(
			"lune",
			{ "run", `{here}/{DX}probe/probe.luau` },
			{ cwd = `{here}/{DX}checkout` }
		)
		if not r.ok then
			print(r.stdout .. r.stderr)
		end
		t.expect(r.ok).toBe(true)
		t.expect((string.gsub(r.stdout, "%s+$", "")))
			.toBe("cp:z-nile/b.luau,cp:tern/c.luau,rw:z-nile/b.luau,rw:tern/c.luau")
		fs.removeDir(DX)
	end)
end)
