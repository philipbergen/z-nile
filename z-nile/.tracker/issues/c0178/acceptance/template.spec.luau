--!strict
-- c0178 slice 1 (AC1): trackerfix.new makes its fixture from this run's packed template by one whole-tree clone
-- (clonefileat on APFS, a plain copy elsewhere), rewrites the files that name the template's path, and the fixture is the
-- one a build makes: same tree, one seed commit authored by the fixture, same remotes, same identities. The template is
-- never handed to a spec, a write into it is refused at the next clone, and a template of another run is never used.
-- Sequestered: it targets z-nile/tests/lib/trackerfix.luau and fxclone.luau as the Design states them.
local fixture = require("@tests/lib/fixture")
local fs = require("@lune/fs")
local fxclone = require("@tests/lib/fxclone")
local process = require("@lune/process")
local t = require("@tests/lib/t")
local trackerfix = require("@tests/lib/trackerfix")

local NAME = "c0178-template"
local ROOT = fixture.physical(".") :: string
local BASE = `{ROOT}/.cache/{NAME}`

local function trim(s: string): string
	return (string.gsub(string.gsub(s, "^%s+", ""), "%s+$", ""))
end

local function git(dir: string, args: { string }): string
	return fixture.git(dir, args)
end

-- every regular file under `dir` whose bytes hold `needle`, relative to `dir`, sorted
local function naming(dir: string, needle: string): { string }
	local r = process.exec("/usr/bin/grep", { "-rlF", "--", needle, dir })
	local out: { string } = {}
	for line in string.gmatch(r.stdout, "[^\n]+") do
		table.insert(out, string.sub(line, #dir + 2))
	end
	table.sort(out)
	return out
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
		end
	)

	it("no file of a cloned fixture names the template or a template build folder", function()
		local f = trackerfix.new(NAME, SEED)
		local tpl = trackerfix.template(false)
		t.expect(#naming(f.base, tpl)).toBe(0)
		t.expect(#naming(f.base, "fixture-templates")).toBe(0)
	end)

	it(
		"the rewrite list is exactly the files of a fresh template that name the template's own path",
		function()
			local tpl = trackerfix.template(false)
			local want = table.clone(trackerfix.REWRITE)
			table.sort(want)
			t.expect(table.concat(naming(tpl, tpl), "\n")).toBe(table.concat(want, "\n"))
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
		"a template made for an earlier run is never used, and the first fixture of this run removes it",
		function()
			local parent = `{ROOT}/.cache/fixture-templates`
			local stale = `{parent}/pickman-run.EARLIER-lessons`
			fs.writeDir(`{stale}/main`)
			fs.writeFile(`{stale}/main/marker`, "earlier run\n")
			trackerfix.forget() -- the seam: this process forgets the template it resolved, as a new worker would
			local f = trackerfix.new(NAME, SEED)
			t.expect(fs.isDir(stale)).toBe(false)
			t.expect(fs.isFile(`{f.main}/marker`)).toBe(false)
			local run = string.match(process.env.TMPDIR or "", "([^/]+)/*$") or ""
			t.expect(string.find(trackerfix.template(false), run, 1, true) ~= nil).toBe(true)
		end
	)

	it("a tooling file changed after the template was made gives the next fixture a new template", function()
		local tooling = `{BASE}-tooling`
		if fs.isDir(tooling) then
			fs.removeDir(tooling)
		end
		fs.writeDir(tooling)
		process.exec("cp", { "-R", `{fixture.physical(trackerfix.TOOLING)}/zn`, `{tooling}/zn` })
		process.exec("cp", { "-R", `{fixture.physical(trackerfix.TOOLING)}/scripts`, `{tooling}/scripts` })
		process.exec("cp", { "-R", `{fixture.physical(trackerfix.TOOLING)}/z-nile`, `{tooling}/z-nile` })
		local was = trackerfix.TOOLING
		trackerfix.TOOLING = tooling
		local ok, err = pcall(function()
			trackerfix.forget()
			trackerfix.new(NAME, {})
			local first = trackerfix.template(false)
			fs.writeFile(`{tooling}/zn`, fs.readFile(`{tooling}/zn`) .. "\n# changed after the template\n")
			local f = trackerfix.new(NAME, {})
			t.expect(trackerfix.template(false) ~= first).toBe(true)
			t.expect(string.find(fs.readFile(`{f.main}/zn`), "changed after the template", 1, true) ~= nil)
				.toBe(true)
		end)
		trackerfix.TOOLING = was
		trackerfix.forget()
		if not ok then
			error(err, 0)
		end
	end)

	it("where a clone is refused the tree is copied, and the copy is the same and independent", function()
		local src = `{BASE}-copy/src`
		if fs.isDir(`{BASE}-copy`) then
			fs.removeDir(`{BASE}-copy`)
		end
		fs.writeDir(`{src}/a`)
		fs.writeFile(`{src}/a/f`, "one\n")
		fs.writeFile(`{src}/x`, "#!/bin/sh\n")
		process.exec("chmod", { "+x", `{src}/x` })
		t.expect(fxclone.tree(src, `{BASE}-copy/copied`, { copy = true })).toBe("copy")
		t.expect(fs.readFile(`{BASE}-copy/copied/a/f`)).toBe("one\n")
		t.expect(trim(process.exec("stat", { "-f", "%Lp", `{BASE}-copy/copied/x` }).stdout)).toBe("755")
		fs.writeFile(`{BASE}-copy/copied/a/f`, "two\n")
		t.expect(fs.readFile(`{src}/a/f`)).toBe("one\n")
		local how = fxclone.tree(src, `{BASE}-copy/cloned`)
		t.expect(how == (if process.os == "macos" then "clone" else "copy")).toBe(true)
	end)

	it("a clone into a folder that exists is refused and leaves it alone", function()
		local dir = `{BASE}-exists`
		fs.writeDir(dir)
		fs.writeFile(`{dir}/keep`, "kept\n")
		t.expect(function()
			fxclone.tree(`{BASE}-copy/src`, dir)
		end).toThrow("exists")
		t.expect(fs.readFile(`{dir}/keep`)).toBe("kept\n")
	end)

	it(
		"the fixture's bare origin keeps pushes as packs, and the checkouts' own configuration is untouched",
		function()
			local f = trackerfix.new(NAME, SEED)
			t.expect(git(f.origin, { "config", "receive.unpackLimit" })).toBe("1")
			for _, dir in { f.main, f.other } do
				local r = fixture.exec(dir, "git", { "config", "--local", "--get-regexp", "unpacklimit" })
				t.expect(trim(r.stdout)).toBe("")
			end
		end
	)

	it(
		"a fixture's push never reaches the template, and a template that changed refuses the next clone",
		function()
			local tpl = trackerfix.template(false)
			local tip = git(`{tpl}/origin.git`, { "rev-parse", "main" })
			local f = trackerfix.new(NAME, SEED)
			fs.writeFile(`{f.main}/pushed.txt`, "x\n")
			git(f.main, { "add", "pushed.txt" })
			git(f.main, { "commit", "-qm", "a fixture's own commit" })
			git(f.main, { "push", "-q", "origin", "HEAD:main" })
			t.expect(git(`{tpl}/origin.git`, { "rev-parse", "main" })).toBe(tip)
			t.expect(fs.isFile(`{tpl}/main/pushed.txt`)).toBe(false)
			-- a spec that writes into the template on purpose (this case runs last: the run's template stays refused): the next
			-- clone names the changed path and refuses
			fs.writeFile(`{tpl}/main/zn.c0178`, "changed\n")
			t.expect(function()
				trackerfix.new(NAME, SEED)
			end).toThrow("template changed")
		end
	)
end)
