--!strict
-- c0178 AC6: trackerfix.worktrees makes named worktrees of a fixture's main checkout the way `./zn worktree <name>` does
-- (a branch off origin/main with no upstream, under main's .worktree/), the first through tracker.sh and the rest as
-- copies of its tree under their own git metadata, so twenty worktrees are one checkout and one tracker.sh run, not
-- twenty. Fixture under .cache/c0178-wt.
local fixture = require("@tests/lib/fixture")
local fs = require("@lune/fs")
local process = require("@lune/process")
local t = require("@tests/lib/t")
local trackerfix = require("@tests/lib/trackerfix")

local HOME = fixture.physical(".") :: string
local BASE = `{HOME}/.cache/c0178-wt-calls`
local REQ = "require" -- built by concatenation: a literal require in a string would join the graph

local function out(cmd: string, args: { string }): string
	local r = process.exec(cmd, args)
	if not r.ok then
		error(`{cmd} {table.concat(args, " ")} failed: {r.stderr}`, 2)
	end
	return (string.gsub(r.stdout, "%s+$", ""))
end

local f: trackerfix.Fixture
local made: { string } = {}
local byZn = ""

local function branchOf(wt: string): string
	return fixture.git(wt, { "rev-parse", "--abbrev-ref", "HEAD" })
end

return t.spec("c0178 trackerfix.worktrees", function(it)
	it("makes the worktrees, in order, under main's .worktree", function()
		f = trackerfix.new("c0178-wt")
		made = trackerfix.worktrees(f, { "raft-a", "raft-b", "prep-c" })
		byZn = trackerfix.trOk(f, f.main, { "worktree", "raft-z" })
		t.expect(#made).toBe(3)
		for i, name in { "raft-a", "raft-b", "prep-c" } do
			t.expect(made[i]).toBe(`{f.main}/.worktree/{name}`)
			t.expect(fs.isDir(made[i])).toBe(true)
		end
		t.expect(byZn).toBe(`{f.main}/.worktree/raft-z`)
	end)

	it(
		"each is what `./zn worktree` makes: its own branch at origin/main, no upstream, clean, registered with git",
		function()
			local tip = fixture.git(f.main, { "rev-parse", "origin/main" })
			local listed = fixture.git(f.main, { "worktree", "list", "--porcelain" }) .. "\n" -- git output, trimmed
			for _, wt in { made[1], made[2], made[3], byZn } do
				local branch = branchOf(wt)
				t.expect(string.match(branch, "^[a-z][a-z0-9%-]*$") ~= nil).toBe(true)
				t.expect(fixture.git(wt, { "rev-parse", "HEAD" })).toBe(tip)
				t.expect(fixture.git(wt, { "status", "--porcelain" })).toBe("")
				t.expect(fixture.exec(wt, "git", { "config", "--get", `branch.{branch}.merge` }).ok)
					.toBe(false) -- no upstream
				t.expect(string.find(listed, `worktree {wt}\n`, 1, true) ~= nil).toBe(true)
				t.expect(string.find(listed, `branch refs/heads/{branch}\n`, 1, true) ~= nil).toBe(true)
				t.expect(fixture.git(wt, { "rev-parse", "--show-toplevel" })).toBe(wt)
			end
			t.expect(branchOf(made[1])).toBe("raft-a")
			t.expect(branchOf(made[3])).toBe("prep-c")
		end
	)

	it(
		"the copies hold the same files as the one zn made, executable bits included, and git sees them tracked",
		function()
			t.expect(out("diff", { "-r", "-x", ".git", made[2], byZn })).toBe("")
			t.expect(out("diff", { "-r", "-x", ".git", made[3], byZn })).toBe("")
			local function executables(wt: string): string
				local r = process.exec(
					"find",
					{ ".", "-type", "f", "-perm", "-u+x", "-not", "-path", "./.git/*" },
					{ cwd = wt }
				)
				return r.stdout
			end
			t.expect(executables(made[3])).toBe(executables(byZn))
			t.expect(fixture.git(made[3], { "ls-files" })).toBe(fixture.git(byZn, { "ls-files" }))
		end
	)

	it("a copy is its own checkout: a file changed in one is not changed in another", function()
		fs.writeFile(`{made[2]}/zn`, "#!/bin/sh\n# changed in raft-b only\n")
		t.expect(fixture.git(made[2], { "status", "--porcelain" })).toBe("M zn")
		t.expect(fixture.git(made[3], { "status", "--porcelain" })).toBe("")
		t.expect(fixture.git(made[1], { "status", "--porcelain" })).toBe("")
		fixture.git(made[2], { "checkout", "-q", "--", "zn" })
	end)

	it("tracker.sh runs in a copy like in any worktree", function()
		local r = trackerfix.tr(f, made[3], { "status" })
		t.expect(r.ok).toBe(true)
	end)

	it(
		"judges every name before it makes anything: bad shapes, existing branches, existing folders, repeats",
		function()
			fixture.git(f.main, { "branch", "taken-local" })
			fixture.git(f.other, { "push", "-q", "origin", "HEAD:refs/heads/taken-remote" }) -- another terminal pushed it; main has not fetched
			local before = fixture.git(f.main, { "worktree", "list" })
			local cases: { { names: { string }, needle: string } } = {
				{ names = { "raft-fresh-a", "R0010" }, needle = "R0010" },
				{ names = { "raft-fresh-a", "Bad" }, needle = "Bad" },
				{ names = { "raft-fresh-a", "has_underscore" }, needle = "has_underscore" },
				{ names = { "taken-local", "raft-fresh-a" }, needle = "taken-local" }, -- the FIRST name is judged too
				{ names = { "raft-fresh-a", "taken-remote" }, needle = "taken-remote" },
				{ names = { "raft-fresh-a", "raft-a" }, needle = "raft-a" }, -- a worktree made earlier in this spec
				{ names = { "raft-fresh-a", "raft-fresh-b", "raft-fresh-a" }, needle = "listed twice" },
			}
			for _, case in cases do
				local ok, err = pcall(trackerfix.worktrees, f, case.names)
				t.expect(ok).toBe(false)
				t.expect(string.find(tostring(err), case.needle, 1, true) ~= nil).toBe(true)
				-- nothing was made: not even the fresh first name that came before the refused one
				t.expect(fixture.git(f.main, { "worktree", "list" })).toBe(before)
				t.expect(fs.isDir(`{f.main}/.worktree/raft-fresh-a`)).toBe(false)
			end
			t.expect(#trackerfix.worktrees(f, { "raft-fresh-a" })).toBe(1) -- and a fresh name is made
		end
	)

	it("twenty worktrees are one tracker.sh run", function()
		local dir = BASE
		if fs.isDir(dir) then
			fs.removeDir(dir)
		end
		fs.writeDir(`{dir}/bin`)
		for _, cmd in { "bash" } do
			local real = out("which", { cmd })
			fs.writeFile(
				`{dir}/bin/{cmd}`,
				`#!/bin/sh\necho "{cmd} $1 $2" >> "$SHIM_LOG"\nexec {real} "$@"\n`
			)
			out("chmod", { "+x", `{dir}/bin/{cmd}` })
		end
		local names = {}
		for i = 1, 20 do
			table.insert(names, `twenty-{string.char(96 + i)}`)
		end
		fs.writeFile(
			`{dir}/child.luau`,
			table.concat({
				"--!strict",
				`local trackerfix = {REQ}("@tests/lib/trackerfix")`,
				`local f = trackerfix.new("c0178-wt-twenty")`,
				'local made = trackerfix.worktrees(f, { "' .. table.concat(names, '", "') .. '" })',
				"assert(#made == 20)",
				"",
			}, "\n")
		)
		local r = process.exec("lune", { "run", `{dir}/child.luau` }, {
			cwd = HOME,
			env = { PATH = `{dir}/bin:{process.env.PATH or ""}`, SHIM_LOG = `{dir}/log` },
		})
		t.expect(r.ok).toBe(true)
		local runs = 0
		for line in string.gmatch(fs.readFile(`{dir}/log`), "[^\n]+") do
			if string.find(line, "scripts/tracker.sh", 1, true) then
				runs += 1
			end
		end
		t.expect(runs).toBe(1)
	end)
end)
