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

local REGISTRY = 'retired = ["tracker"]\n\n[[project]]\nname = "pickman"\nroot = "pickman/.tracker"\n\n'
	.. '[[project]]\nname = "z-nile"\nroot = "z-nile/.tracker"\n'
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
local MARK = "tracker/rafts/done/R0001/check.sh"
local function branchOff(name: string, from: string, file: string)
	fixture.git(f.main, { "checkout", "-q", "-b", name, from })
	fs.writeFile(`{f.main}/{file}`, `--!strict\nreturn "{name}"\n`)
	fixture.git(f.main, { "add", "-A" })
	fixture.git(f.main, { "commit", "-qm", name })
	fixture.git(f.main, { "checkout", "-q", "main" })
end
-- c0120's prep on origin: one commit main doesn't have
local function pushPrep()
	branchOff("prep-c0120", "main", "NOTES-c0120.md")
	fixture.git(f.main, { "push", "-q", "origin", "prep-c0120" })
	fixture.git(f.main, { "fetch", "-q", "origin" })
end
local function dropPrep()
	fixture.git(f.main, { "branch", "-q", "-D", "prep-c0120" })
	fixture.git(f.main, { "push", "-q", "origin", "--delete", "prep-c0120" })
	fixture.git(f.main, { "fetch", "-q", "--prune", "origin" })
end

return t.spec("c0120 busy lists what holds the paths a move needs", function(it)
	it("sets up a fixture on pickman's layout with nothing in flight", function()
		local seed: { [string]: string } = {
			["z-nile/projects.toml"] = REGISTRY,
			["src/a.luau"] = "--!strict\nreturn 1\n",
			["tests/a.spec.luau"] = "--!strict\nreturn 1\n",
			-- the old layout's mark (AC18's MARK): origin/main doesn't hold the move yet, so c0120's freeze is on
			[MARK] = "#!/usr/bin/env bash\n",
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

	-- decided with the user, 2026-10-23: "Re-prep R0044 after; exempt the stack": a branch stacked on c0120's own prep
	-- (its history holds a commit of origin/prep-c0120 that main doesn't), or one of the listed stacked preps by name, is
	-- no freeze; any other branch is, whatever its name claims
	it(
		"a branch stacked on c0120's prep, or one the user approved by name, is ignored; an unrelated or similarly named one is listed",
		function()
			pushPrep()
			branchOff("stacked-work", "origin/prep-c0120", "src/stacked.luau")
			branchOff("unrelated-work", "main", "src/unrelated.luau")
			branchOff("prep-c0120-stacked", "main", "src/claims.luau")
			branchOff("prep-c0115", "main", "src/listed.luau")
			-- the branches the user approved by exact name (decided with the user, 2026-10-23: "Named exemptions you
			-- approve"); a similar name blocks
			branchOff("proto-c0117", "main", "src/approved.luau")
			branchOff("proto-c0117-copy", "main", "src/similar.luau")
			-- only a remote-tracking ref loses its `origin/`: a local branch named origin/proto-c0117 is not
			-- proto-c0117 (code review 011 F5)
			branchOff("origin/proto-c0117", "main", "src/local-origin.luau")
			local r = busy(f.main, OLD)
			t.expect(has(r.stdout, "stacked-work")).toBe(false)
			t.expect(has(r.stdout, "branch prep-c0120 ")).toBe(false)
			t.expect(has(r.stdout, "branch origin/prep-c0120 ")).toBe(false)
			t.expect(has(r.stdout, "prep-c0115")).toBe(false)
			t.expect(has(r.stdout, "branch unrelated-work changes")).toBe(true)
			t.expect(has(r.stdout, "branch prep-c0120-stacked changes")).toBe(true)
			t.expect(has(r.stdout, "branch proto-c0117 ")).toBe(false)
			t.expect(has(r.stdout, "branch proto-c0117-copy changes")).toBe(true)
			t.expect(has(r.stdout, "branch origin/proto-c0117 changes")).toBe(true)
			-- each ignored ref is named on stderr, uncounted (code review 011 F1)
			t.expect(has(r.stderr, "ignored for c0120's freeze: stacked-work (stacked on its prep)"))
				.toBe(true)
			t.expect(has(r.stderr, "ignored for c0120's freeze: prep-c0115 (stacked on its prep)")).toBe(true)
			t.expect(has(r.stderr, "ignored for c0120's freeze: proto-c0117 (approved by name)")).toBe(true)
			t.expect(has(r.stderr, "unrelated-work")).toBe(false)
			t.expect(r.code).toBe(1)
			fixture.git(f.main, {
				"branch",
				"-q",
				"-D",
				"prep-c0120",
				"stacked-work",
				"unrelated-work",
				"prep-c0120-stacked",
				"prep-c0115",
				"proto-c0117",
				"proto-c0117-copy",
				"origin/proto-c0117",
			})
			fixture.git(f.main, { "push", "-q", "origin", "--delete", "prep-c0120" })
			fixture.git(f.main, { "fetch", "-q", "--prune", "origin" })
			t.expect(busy(f.main, OLD).stdout).toBe("")
		end
	)

	-- code review 011 F1: the exemption is the freeze's alone (paths given, origin/main without the move). With no
	-- paths busy lists what `./zn compact` refuses on; once the move lands a branch with one of these names blocks
	it("the exemption is off without paths, and once origin/main holds the move", function()
		pushPrep()
		branchOff("stacked-work", "origin/prep-c0120", "pickman/.tracker/issues/active/stacked.md")
		branchOff("proto-c0117", "main", "pickman/.tracker/issues/active/approved.md")
		local frozen = busy(f.main, { "pickman/.tracker" })
		t.expect(frozen.stdout).toBe("")
		t.expect(frozen.code).toBe(0)
		t.expect(has(frozen.stderr, "ignored for c0120's freeze: proto-c0117 (approved by name)")).toBe(true)
		local all = busy(f.main, {})
		t.expect(all.code).toBe(1)
		t.expect(has(all.stdout, "branch stacked-work changes")).toBe(true)
		t.expect(has(all.stdout, "branch proto-c0117 changes")).toBe(true)
		t.expect(has(all.stderr, "ignored")).toBe(false)
		-- the move lands: origin/main loses the old layout's mark
		fixture.git(f.other, { "pull", "-q", "origin", "main" })
		fixture.git(f.other, { "rm", "-q", MARK })
		fixture.git(f.other, { "commit", "-qm", "the move" })
		fixture.git(f.other, { "push", "-q", "origin", "HEAD:main" })
		fixture.git(f.main, { "pull", "-q", "origin", "main" })
		local landed = busy(f.main, { "pickman/.tracker" })
		t.expect(landed.code).toBe(1)
		t.expect(has(landed.stdout, "branch stacked-work changes")).toBe(true)
		t.expect(has(landed.stdout, "branch proto-c0117 changes")).toBe(true)
		t.expect(has(landed.stderr, "ignored")).toBe(false)
		-- the mark back, for the cases after this one
		trackerfix.elsewhere(f, { [MARK] = "#!/usr/bin/env bash\n" }, "the mark back")
		fixture.git(f.main, { "pull", "-q", "origin", "main" })
		fixture.git(f.main, { "branch", "-q", "-D", "stacked-work", "proto-c0117" })
		dropPrep()
		t.expect(busy(f.main, OLD).stdout).toBe("")
	end)

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

	-- code review 011 F2: a worktree on a branch the freeze ignores is ignored with it (Guess 20, "Named exemptions you
	-- approve"); one on a look-alike name, or a detached one, is listed
	it("a worktree on an ignored branch is ignored; one on a similar name, or detached, is listed", function()
		local trees: { [string]: string } = {}
		for _, spec in
			{ { "approved", "proto-c0117" }, { "similar", "proto-c0117-copy" }, { "detached", "" } }
		do
			local dir = `{f.base}/wt-{spec[1]}`
			if spec[2] == "" then
				fixture.git(f.main, { "worktree", "add", "-q", "--detach", dir, "main" })
			else
				fixture.git(f.main, { "worktree", "add", "-q", "-b", spec[2], dir, "main" })
			end
			fs.writeFile(`{dir}/src/a.luau`, `--!strict\nreturn "{spec[1]}"\n`)
			trees[spec[1]] = fixture.physical(dir) :: string
		end
		local r = busy(f.main, OLD)
		t.expect(r.code).toBe(1)
		t.expect(has(r.stdout, `worktree {trees.approved} has`)).toBe(false)
		t.expect(
			has(
				r.stderr,
				`ignored for c0120's freeze: worktree {trees.approved} on proto-c0117 (approved by name)`
			)
		).toBe(true)
		t.expect(has(r.stdout, `worktree {trees.similar} has uncommitted changes`)).toBe(true)
		t.expect(has(r.stdout, `worktree {trees.detached} has uncommitted changes`)).toBe(true)
		for _, name in { "approved", "similar", "detached" } do
			fixture.git(f.main, { "worktree", "remove", "--force", `{f.base}/wt-{name}` })
		end
		fixture.git(f.main, { "branch", "-q", "-D", "proto-c0117", "proto-c0117-copy" })
		t.expect(busy(f.main, OLD).stdout).toBe("")
	end)
end)
