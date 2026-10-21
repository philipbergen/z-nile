--!strict
-- c0120 AC9: `./zn busy [<path>...]` lists what holds paths, read-only: every raft active on origin/main (the current
-- branch's own raft aside), every branch, local or on origin, that changes them since it left origin/main
-- (compaction's busy-branch check, compact.busyRefs, now taking paths), and every other worktree with uncommitted
-- changes under them. It exits 1 when anything does, 0 and silent when nothing does. Without paths it guards what
-- compaction guards: every project root and promoted-spec folder. c0120 is readied only when
-- `./zn busy tracker src tests` prints nothing. Fixture under .cache/c0120-busy (tests/lib/trackerfix).
local fixture = require("@tests/lib/fixture")
local fs = require("@lune/fs")
local t = require("@tests/lib/t")
local trackerfix = require("@tests/lib/trackerfix")

local REGISTRY = 'retired = ["tracker"]\n\n[[project]]\nname = "pickman"\nroot = "pickman/.tracker"\nhome = "pickman"\n\n'
	.. '[[project]]\nname = "z-nile"\nroot = "z-nile/.tracker"\nhome = "."\n'
local f: trackerfix.Fixture
local wt = ""

local function busy(cwd: string, args: { string }): fixture.Result
	local argv = { "busy" }
	for _, a in args do
		table.insert(argv, a)
	end
	return trackerfix.tr(f, cwd, argv)
end
local function has(text: string, needle: string): boolean
	return string.find(text, needle, 1, true) ~= nil
end
local OLD = { "tracker", "src", "tests" }

return t.spec("c0120 busy lists what holds the paths a move needs", function(it)
	it("sets up a fixture on pickman's layout with nothing in flight", function()
		local seed: { [string]: string } = {
			["z-nile/projects.toml"] = REGISTRY,
			["src/a.luau"] = "--!strict\nreturn 1\n",
			["tests/a.spec.luau"] = "--!strict\nreturn 1\n",
		}
		for _, state in { "issues/active", "issues/done", "rafts/active", "rafts/done" } do
			seed[`pickman/.tracker/{state}/.gitkeep`] = ""
		end
		f = trackerfix.new("c0120-busy", seed)
	end)

	it("nothing in flight: silent, and exit 0", function()
		local r = busy(f.main, OLD)
		t.expect(r.code).toBe(0)
		t.expect(r.stdout).toBe("")
	end)

	it("a raft active on origin/main is listed, but not from its own branch", function()
		trackerfix.elsewhere(f, {
			["pickman/.tracker/rafts/active/R0010/R0010.md"] = trackerfix.stub(
				"R0010",
				"demo",
				"active-a-b-c"
			),
		}, "tracker: start R0010")
		fixture.git(f.main, { "pull", "-q", "origin", "main" })
		local r = busy(f.main, OLD)
		t.expect(r.code).toBe(1)
		t.expect(has(r.stdout, "raft R0010 is active")).toBe(true)
		fixture.git(f.main, { "checkout", "-q", "-b", "R0010-demo" })
		local own = busy(f.main, OLD)
		fixture.git(f.main, { "checkout", "-q", "main" })
		fixture.git(f.main, { "branch", "-q", "-D", "R0010-demo" })
		t.expect(has(own.stdout, "raft R0010")).toBe(false)
	end)

	it(
		"a branch that changes one of the paths is listed, local or on origin; one that doesn't is not",
		function()
			fixture.git(f.other, { "rm", "-q", "-r", "pickman/.tracker/rafts/active/R0010" })
			fixture.git(f.other, { "commit", "-qm", "tracker: done R0010" })
			fixture.git(f.other, { "push", "-q", "origin", "HEAD:main" })
			fixture.git(f.main, { "pull", "-q", "origin", "main" })
			t.expect(busy(f.main, OLD).stdout).toBe("")
			-- a branch changing src/, pushed; a branch changing only docs, local
			fixture.git(f.main, { "checkout", "-q", "-b", "game-work" })
			fs.writeFile(`{f.main}/src/a.luau`, "--!strict\nreturn 2\n")
			fixture.git(f.main, { "commit", "-qam", "game work" })
			fixture.git(f.main, { "push", "-q", "origin", "game-work" })
			fixture.git(f.main, { "checkout", "-q", "main" })
			fixture.git(f.main, { "checkout", "-q", "-b", "docs-work" })
			fs.writeFile(`{f.main}/NOTES.md`, "notes\n")
			fixture.git(f.main, { "add", "NOTES.md" })
			fixture.git(f.main, { "commit", "-qm", "docs" })
			fixture.git(f.main, { "checkout", "-q", "main" })
			fixture.git(f.main, { "fetch", "-q", "origin" })
			local r = busy(f.main, OLD)
			t.expect(r.code).toBe(1)
			t.expect(has(r.stdout, "branch game-work changes")).toBe(true)
			t.expect(has(r.stdout, "branch origin/game-work changes")).toBe(true)
			t.expect(has(r.stdout, "docs-work")).toBe(false)
			-- by default it guards what compaction guards: the project roots and promoted specs, not src/
			t.expect(has(busy(f.main, {}).stdout, "game-work")).toBe(false)
			fixture.git(f.main, { "branch", "-q", "-D", "game-work", "docs-work" })
			fixture.git(f.main, { "push", "-q", "origin", "--delete", "game-work" })
			fixture.git(f.main, { "fetch", "-q", "--prune", "origin" })
			t.expect(busy(f.main, OLD).stdout).toBe("")
		end
	)

	it("another worktree with uncommitted changes under one of the paths is listed", function()
		wt = `{f.base}/wt`
		fixture.git(f.main, { "worktree", "add", "-q", "-b", "wt-work", wt, "main" })
		fs.writeFile(`{wt}/tests/b.spec.luau`, "--!strict\nreturn 2\n") -- untracked counts too
		local r = busy(f.main, OLD)
		t.expect(r.code).toBe(1)
		t.expect(has(r.stdout, "has uncommitted changes")).toBe(true)
		t.expect(has(r.stdout, fixture.physical(wt) :: string)).toBe(true)
		-- read without git's optional locks: the other worktree's index is not rewritten
		fs.removeFile(`{wt}/tests/b.spec.luau`)
		t.expect(busy(f.main, OLD).stdout).toBe("")
		fixture.git(f.main, { "worktree", "remove", "--force", wt })
		fixture.git(f.main, { "branch", "-q", "-D", "wt-work" })
	end)
end)
