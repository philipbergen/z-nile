--!strict
-- c0178 slice 1 (AC1): trackerfix.new makes its fixture from this run's packed template by one whole-tree clone
-- (clonefileat on APFS, a copy elsewhere), rewrites and checks the files that name the template's path before any push, and the
-- fixture is the one a build makes. The run's templates are never written: a case that must damage a template builds a private
-- one through trackerfix.TOOLING (design review 005 F1), whose tooling is made with engine.copy (F2).
-- Sequestered: it targets z-nile/tests/lib/trackerfix.luau and fxclone.luau as the Design states them (Seams).
local engine = require("@tests/lib/engine")
local fixture = require("@tests/lib/fixture")
local fs = require("@lune/fs")
local fxclone = require("@tests/lib/fxclone")
local process = require("@lune/process")
local t = require("@tests/lib/t")
local trackerfix = require("@tests/lib/trackerfix")

local NAME = "c0178-template"
local ROOT = fixture.physical(".") :: string
local BASE = `{ROOT}/.cache/{NAME}`
local TEMPLATES = `{ROOT}/.cache/fixture-templates`

local function git(dir: string, args: { string }): string
	return fixture.git(dir, args)
end

-- every regular file under `dir` whose bytes hold `needle`, relative to `dir`, sorted
local function naming(dir: string, needle: string): { string }
	local r = process.exec("grep", { "-rlF", "--", needle, dir })
	local out: { string } = {}
	for line in string.gmatch(r.stdout, "[^\n]+") do
		table.insert(out, string.sub(line, #dir + 2))
	end
	table.sort(out)
	return out
end

local function sorted(list: { string }): string
	local copy = table.clone(list)
	table.sort(copy)
	return table.concat(copy, "\n")
end

local function fresh(dir: string)
	if fs.isDir(dir) then
		fs.removeDir(dir)
	end
	fs.writeDir(dir)
end

-- runs `body` with trackerfix.TOOLING at a private copy of the tooling (engine.copy: no .cache, .tracker or tests), so the
-- templates it builds are its own; restores the run's tooling whatever happens
local function withPrivateTooling(dir: string, body: (tooling: string) -> ...any)
	fresh(dir)
	engine.copy(fixture.physical(trackerfix.TOOLING) :: string, dir)
	t.expect(fs.isFile(`{dir}/zn`)).toBe(true)
	t.expect(fs.isDir(`{dir}/z-nile/tests`)).toBe(false)
	t.expect(fs.isDir(`{dir}/z-nile/.cache`)).toBe(false)
	local was = trackerfix.TOOLING
	trackerfix.TOOLING = dir
	trackerfix.forget()
	local ok, err = pcall(body, dir)
	trackerfix.TOOLING = was
	trackerfix.forget()
	if not ok then
		error(err, 0)
	end
end

local SEED = {
	["pickman/.tracker/issues/c0001/c0001.md"] = trackerfix.stub("c0001", "seeded", "new"),
	["z-nile/extra.txt"] = "an extra file\n",
}

return t.spec("c0178 fixtures from a per-run template", function(it)
	it(
		"a cloned fixture holds what a built one holds: tree, one seed commit by the fixture, remotes, identities",
		function()
			local built = trackerfix.build(`{NAME}-built`, SEED)
			local cloned = trackerfix.new(`{NAME}-cloned`, SEED)
			t.expect(git(cloned.main, { "rev-parse", "HEAD^{tree}" }))
				.toBe(git(built.main, { "rev-parse", "HEAD^{tree}" }))
			t.expect(git(cloned.main, { "rev-list", "--count", "HEAD" })).toBe("1")
			t.expect(git(cloned.main, { "log", "-1", "--format=%ae %ce %s" }))
				.toBe(`{NAME}-cloned@example.invalid {NAME}-cloned@example.invalid seed`)
			t.expect(git(cloned.main, { "config", "remote.origin.url" })).toBe(cloned.origin)
			t.expect(git(cloned.other, { "config", "remote.origin.url" })).toBe(cloned.origin)
			for _, dir in { cloned.main, cloned.other } do
				t.expect(git(dir, { "config", "user.email" })).toBe(`{NAME}-cloned@example.invalid`)
				t.expect(git(dir, { "status", "--porcelain" })).toBe("")
			end
			t.expect(git(cloned.origin, { "rev-parse", "main" }))
				.toBe(git(cloned.main, { "rev-parse", "HEAD" }))
			t.expect(git(cloned.other, { "rev-parse", "HEAD" }))
				.toBe(git(cloned.main, { "rev-parse", "HEAD" }))
			t.expect(fs.readFile(`{cloned.other}/z-nile/extra.txt`)).toBe("an extra file\n")
			t.expect(process.exec("test", { "-x", `{cloned.main}/zn` }).ok).toBe(true)
			-- the same top-level entries as a build, but no seed (and no stamp)
			local want: { string } = {}
			for _, name in fs.readDir(built.base) do
				if name ~= "seed" then
					table.insert(want, name)
				end
			end
			t.expect(sorted(fs.readDir(cloned.base))).toBe(sorted(want))
		end
	)

	it("no file of a cloned fixture names the template or the templates' folder", function()
		local f = trackerfix.new(NAME, SEED)
		t.expect(#naming(f.base, trackerfix.template(false))).toBe(0)
		t.expect(#naming(f.base, TEMPLATES)).toBe(0)
	end)

	it(
		"the rewrite list is exactly the files of a fresh template that name the template's own path",
		function()
			local tpl = trackerfix.template(false)
			t.expect(table.concat(naming(tpl, tpl), "\n")).toBe(sorted(trackerfix.REWRITE))
			t.expect(#naming(tpl, `{tpl}.build`)).toBe(0)
		end
	)

	it("a template whose rewrite list is short by one file refuses at build", function()
		withPrivateTooling(`{BASE}-short-tooling`, function()
			local was = trackerfix.REWRITE
			local short = table.clone(was)
			table.remove(short, table.find(short, "origin.git/config"))
			trackerfix.REWRITE = short
			local ok, err = pcall(trackerfix.template, false)
			trackerfix.REWRITE = was
			t.expect(ok).toBe(false)
			t.expect(string.find(tostring(err), "origin.git/config", 1, true) ~= nil).toBe(true)
		end)
	end)

	it("a rewrite that misses a file refuses before any push, and leaves no fixture", function()
		local tpl = trackerfix.template(false)
		local tip = git(`{tpl}/origin.git`, { "rev-parse", "main" })
		for _, skip in { "other/.git/logs/HEAD", "main/.git/config" } do
			trackerfix.SKIP_REWRITE = skip
			local ok, err = pcall(trackerfix.new, `{NAME}-skip`, SEED)
			trackerfix.SKIP_REWRITE = nil
			t.expect(ok).toBe(false)
			t.expect(string.find(tostring(err), tpl, 1, true) ~= nil).toBe(true)
			t.expect(fs.isDir(`{BASE}-skip`)).toBe(false)
			t.expect(git(`{tpl}/origin.git`, { "rev-parse", "main" })).toBe(tip)
		end
	end)

	it("a rewrite to a wrong path refuses before any push, by the remote check alone", function()
		-- added after job 2's mutant run (design review 005 F22: a survivor gets a case): the read of the nine files passes here,
		-- since nothing names the template any more, and only the comparison of the remotes with the fixture's origin refuses
		local tpl = trackerfix.template(false)
		local tip = git(`{tpl}/origin.git`, { "rev-parse", "main" })
		trackerfix.REWRITE_TO = `{BASE}-elsewhere`
		local ok, err = pcall(trackerfix.new, `{NAME}-wrong`, SEED)
		trackerfix.REWRITE_TO = nil
		t.expect(ok).toBe(false)
		t.expect(string.find(tostring(err), "remote origin", 1, true) ~= nil).toBe(true)
		t.expect(fs.isDir(`{BASE}-wrong`)).toBe(false)
		t.expect(git(`{tpl}/origin.git`, { "rev-parse", "main" })).toBe(tip)
	end)

	it(
		"the fixture's bare origin keeps pushes as packs, and the checkouts' own configuration is untouched",
		function()
			local f = trackerfix.new(NAME, SEED)
			t.expect(git(f.origin, { "config", "receive.unpackLimit" })).toBe("1")
			for _, dir in { f.main, f.other } do
				local r = fixture.exec(dir, "git", { "config", "--local", "--get-regexp", "unpacklimit" })
				t.expect(r.stdout).toBe("")
			end
		end
	)

	it("one template per run and lessons choice, built once and reused", function()
		local before = trackerfix.builds()
		trackerfix.new(`{NAME}-a`, SEED)
		trackerfix.new(`{NAME}-b`, {})
		local lessons = trackerfix.builds()
		trackerfix.new(`{NAME}-c`, SEED, { noLessons = true })
		trackerfix.new(`{NAME}-d`, SEED, { noLessons = true })
		t.expect(lessons - before <= 1).toBe(true)
		t.expect(trackerfix.builds() - lessons <= 1).toBe(true)
		t.expect(trackerfix.template(true) ~= trackerfix.template(false)).toBe(true)
		local f = trackerfix.new(`{NAME}-e`, SEED, { noLessons = true })
		t.expect(fs.isDir(`{f.main}/z-nile/skills/zz-test/lessons`)).toBe(false)
	end)

	it(
		"a template of an earlier run is removed by the first fixture of this run, and nothing outside the grammar is",
		function()
			local stale = `{TEMPLATES}/pickman-run.EARLIER-lessons-000000000000`
			fs.writeDir(`{stale}/main`)
			fs.writeFile(`{stale}/main/marker`, "earlier run\n")
			fs.writeDir(`{TEMPLATES}/c0178-not-a-template`)
			fs.writeFile(`{TEMPLATES}/c0178-not-a-template/marker`, "kept\n")
			trackerfix.forget() -- as a new worker would
			local f = trackerfix.new(NAME, SEED)
			t.expect(fs.isDir(stale)).toBe(false)
			t.expect(fs.isFile(`{TEMPLATES}/c0178-not-a-template/marker`)).toBe(true)
			t.expect(fs.isFile(`{f.main}/marker`)).toBe(false)
			fs.removeDir(`{TEMPLATES}/c0178-not-a-template`)
			local run = string.match(process.env.TMPDIR or "", "([^/]+)/*$") or ""
			if string.match(run, "^pickman%-run%.%w+$") then
				t.expect(string.find(trackerfix.template(false), run, 1, true) ~= nil).toBe(true)
			end
		end
	)

	it("reserved and malformed fixture names are refused", function()
		for _, bad in { "fixture-templates", "Fixture-Templates/x", "a/../b", "", "./x", "x//y" } do
			t.expect(function()
				trackerfix.new(bad, {})
			end).toThrow("reserved or malformed")
		end
		t.expect(fs.isDir(TEMPLATES)).toBe(true)
	end)

	it("a tooling file changed after the template was made gives the next fixture a new template", function()
		withPrivateTooling(`{BASE}-tooling`, function(tooling: string)
			trackerfix.new(NAME, {})
			local first = trackerfix.template(false)
			fs.writeFile(`{tooling}/zn`, fs.readFile(`{tooling}/zn`) .. "\n# changed after the template\n")
			local f = trackerfix.new(NAME, {})
			t.expect(trackerfix.template(false) ~= first).toBe(true)
			t.expect(string.find(fs.readFile(`{f.main}/zn`), "changed after the template", 1, true) ~= nil)
				.toBe(true)
		end)
	end)

	it(
		"a private template written into, or whose file mode changed, refuses the next clone; the run's own stay clean",
		function()
			withPrivateTooling(`{BASE}-poison-tooling`, function(tooling: string)
				local tpl = trackerfix.template(false)
				t.expect(trackerfix.changed(tpl)).toBe(nil)
				trackerfix.new(`{NAME}-poison`, {})
				t.expect(trackerfix.changed(tpl)).toBe(nil) -- a clone does not change its source
				fs.writeFile(`{tpl}/main/zn.c0178`, "changed\n")
				t.expect(function()
					trackerfix.new(`{NAME}-poison`, {})
				end).toThrow("template changed")
				t.expect(fs.isDir(`{BASE}-poison`)).toBe(false)
				-- the ctime half: a mode change keeps the mtime
				fs.writeFile(`{tooling}/scripts/c0178-key`, "a new key\n")
				local second = trackerfix.template(false)
				t.expect(second ~= tpl).toBe(true)
				t.expect(process.exec("chmod", { "a-x", `{second}/main/zn` }).ok).toBe(true)
				t.expect(function()
					trackerfix.new(`{NAME}-poison`, {})
				end).toThrow("template changed")
			end)
			t.expect(trackerfix.changed(trackerfix.template(false))).toBe(nil)
			t.expect(trackerfix.changed(trackerfix.template(true))).toBe(nil)
		end
	)

	it("where a clone is refused the tree is copied, and the copy keeps modes and is independent", function()
		local dir = `{BASE}-copy`
		fresh(dir)
		fs.writeDir(`{dir}/src/a`)
		fs.writeFile(`{dir}/src/a/f`, "one\n")
		fs.writeFile(`{dir}/src/x`, "#!/bin/sh\n")
		t.expect(process.exec("chmod", { "+x", `{dir}/src/x` }).ok).toBe(true)
		local how = fxclone.tree(`{dir}/src`, `{dir}/copied`, { copy = true })
		t.expect(how).toBe("copy")
		t.expect(fs.readFile(`{dir}/copied/a/f`)).toBe("one\n")
		t.expect(process.exec("test", { "-x", `{dir}/copied/x` }).ok).toBe(true)
		fs.writeFile(`{dir}/copied/a/f`, "two\n")
		t.expect(fs.readFile(`{dir}/src/a/f`)).toBe("one\n")
		local plain = fxclone.tree(`{dir}/src`, `{dir}/cloned`)
		t.expect(plain).toBe(if process.os == "macos" then "clone" else "copy")
		if process.os == "macos" then
			local fell, reason = fxclone.tree(`{dir}/src`, `{dir}/fell`, { simulate = "EXDEV" })
			t.expect(fell).toBe("copy")
			t.expect(string.find(reason or "", "EXDEV", 1, true) ~= nil).toBe(true)
			t.expect(fs.readFile(`{dir}/fell/a/f`)).toBe("one\n")
		end
	end)

	it("a clone or copy into a folder that exists is refused and leaves it alone", function()
		local dir = `{BASE}-exists`
		fresh(dir)
		fs.writeFile(`{dir}/keep`, "kept\n")
		local both: { fxclone.Options } = { { copy = true }, {} }
		for _, opts in both do
			t.expect(function()
				fxclone.tree(`{BASE}-copy/src`, dir, opts)
			end).toThrow("exists")
			t.expect(fs.readFile(`{dir}/keep`)).toBe("kept\n")
			t.expect(fs.isDir(`{dir}/a`)).toBe(false)
		end
	end)

	it("a source that is a link is refused", function()
		local link = `{BASE}-copy/link`
		t.expect(process.exec("ln", { "-s", `{BASE}-copy/src`, link }).ok).toBe(true)
		t.expect(function()
			fxclone.tree(link, `{BASE}-copy/from-link`)
		end).toThrow("link")
		t.expect(fs.isDir(`{BASE}-copy/from-link`)).toBe(false)
	end)

	it("a clone that fails for another reason raises naming it and leaves no destination", function()
		if process.os ~= "macos" then
			return -- the seam stands for clonefileat, which only macOS calls
		end
		t.expect(function()
			fxclone.tree(`{BASE}-copy/src`, `{BASE}-copy/nospace`, { simulate = "ENOSPC" })
		end).toThrow("ENOSPC")
		t.expect(fs.isDir(`{BASE}-copy/nospace`)).toBe(false)
	end)
end)
