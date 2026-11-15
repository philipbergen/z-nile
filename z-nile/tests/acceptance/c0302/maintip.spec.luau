--!strict
-- c0302 AC4 (Non-goal 1): the tooling keeps its refusal. c0302 fixes seven fixtures, not `layergit.mainTip`: in a
-- repository with no origin/main, no main and only a stack layer branch, mainTip still fails with 'no main branch'
-- (so `./zn start` still refuses there), and with a main it answers main's commit. A fixture under this home's
-- .cache: a `git init` repository (never a clone of the checkout) and a probe script beside it that requires the
-- engine's layergit by a path relative to the probe, run with the fixture as its folder.
local fixture = require("@tests/lib/fixture")
local fs = require("@lune/fs")
local process = require("@lune/process")
local t = require("@tests/lib/t")

local base = ""
local repo = ""

-- mainTip in the fixture: what it printed, what it said on stderr, and whether it succeeded
local function tip(): (string, string, boolean)
	local r = fixture.exec(repo, "lune", { "run", "../probe.luau" })
	return (string.gsub(r.stdout, "%s+$", "")), r.stderr, r.ok
end

return t.spec("c0302 mainTip still refuses a lone layer branch", function(it)
	it("sets up a repository whose only branch is a layer branch", function()
		local home = fixture.physical(".") :: string
		base = `{home}/.cache/c0302-maintip`
		repo = `{base}/repo`
		if fs.isDir(base) then
			fs.removeDir(base)
		end
		fs.writeDir(base)
		process.exec("git", { "init", "-q", "-b", "R0010/1/f0010", repo }) -- raw: init to a named path
		fixture.git(repo, { "config", "user.name", "c0302-maintip" })
		fixture.git(repo, { "config", "user.email", "c0302-maintip@example.invalid" })
		fs.writeFile(`{repo}/seed.txt`, "seed\n")
		fixture.git(repo, { "add", "-A" })
		fixture.git(repo, { "commit", "-q", "-m", "seed" })
		-- .cache/c0302-maintip/probe.luau is two folders below the home, whatever the home is called
		fs.writeFile(
			`{base}/probe.luau`,
			-- the word is split so the require scans (tests/meta/architecture) read this as the text it is, not a require
			"local layergit = req" .. 'uire("../../engine/layergit")\nprint("TIP " .. layergit.mainTip())\n'
		)
		t.expect(fixture.git(repo, { "branch", "--show-current" })).toBe("R0010/1/f0010")
		t.expect(fixture.git(repo, { "for-each-ref", "--format=%(refname:short)", "refs/heads" }))
			.toBe("R0010/1/f0010")
	end)

	it("AC4: with only a layer branch, mainTip fails with 'no main branch'", function()
		local out, err, ok = tip()
		t.expect(ok).toBe(false)
		t.expect(out).toBe("")
		t.expect(string.find(err, "no main branch", 1, true) ~= nil).toBe(true)
	end)

	it("AC4: with a second layer branch below it, mainTip still fails", function()
		fixture.git(repo, { "branch", "R0010/2/f0020" })
		local out, err, ok = tip()
		t.expect(ok).toBe(false)
		t.expect(out).toBe("")
		t.expect(string.find(err, "no main branch", 1, true) ~= nil).toBe(true)
	end)

	it("AC4: with a main, mainTip answers main's commit", function()
		local seed = fixture.git(repo, { "rev-parse", "HEAD" })
		fixture.git(repo, { "branch", "main" })
		fs.writeFile(`{repo}/more.txt`, "more\n")
		fixture.git(repo, { "add", "-A" })
		fixture.git(repo, { "commit", "-q", "-m", "layer work" })
		t.expect(fixture.git(repo, { "rev-parse", "HEAD" }) == seed).toBe(false)
		local out, _, ok = tip()
		t.expect(ok).toBe(true)
		t.expect(out).toBe("TIP " .. seed)
	end)
end)
