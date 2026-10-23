--!strict
-- c0062: one part of c0510's commands spec, split so that `tests/run` runs the parts concurrently.
-- This part: `sync`, and a directory that lost its .git.
-- Driven through `scripts/tracker.sh` in a worktree, exactly as a terminal would. Cases share this part's fixture
-- and run in order.
local engine = require("@tests/lib/engine")
local fixture = require("@tests/lib/fixture")
local fs = require("@lune/fs")
local process = require("@lune/process")
local t = require("@tests/lib/t")
local trackerfix = require("@tests/lib/trackerfix")

local git = fixture.git
local f: trackerfix.Fixture = { base = "", origin = "", main = "", other = "" }
local base, origin, main = "", "", ""

local function trOk(cwd: string, args: { string }): string
	return trackerfix.trOk(f, cwd, args)
end
local function has(text: string?, needle: string): boolean
	return text ~= nil and string.find(text, needle, 1, true) ~= nil
end
-- another terminal pushes a commit straight to origin's main
local function elsewhere(files: { [string]: string }, message: string)
	trackerfix.elsewhere(f, files, message)
end
local stub = trackerfix.stub

local cap = "" -- the capture worktree

-- a commit identity for the repositories of the "lost .git" case
local function identity(dir: string)
	git(dir, { "config", "user.name", "c0053-commands-sync" })
	git(dir, { "config", "user.email", "c0053-commands-sync@example.invalid" })
end
-- git at `cwd` (not a repository yet) making the repository at the path `args` names
local function create(cwd: string, args: { string })
	local r = process.exec("git", args, { cwd = cwd })
	if not r.ok then
		error(`git {table.concat(args, " ")} failed ({r.code}): {r.stderr}{r.stdout}`, 2)
	end
end

return t.spec("tracker commands publish state to origin/main (sync)", function(it)
	it("sets up the sync fixture", function()
		f = trackerfix.new("c0053-commands-sync", nil)
		base, origin, main = f.base, f.origin, f.main
		cap = trOk(main, { "worktree", "cap-a" })
		t.expect(git(cap, { "branch", "--show-current" })).toBe("cap-a")
	end)

	it("sync brings a worktree and the main checkout up to date", function()
		elsewhere({ ["tracker/issues/f0400/f0400.md"] = stub("f0400", "remote-c", "new") }, "other f0400")
		trOk(cap, { "sync" })
		t.expect(fs.isFile(`{cap}/tracker/issues/f0400/f0400.md`)).toBe(true)
		trOk(main, { "sync" })
		t.expect(git(main, { "rev-parse", "HEAD" })).toBe(git(origin, { "rev-parse", "main" }))
	end)

	it(
		"a tracker command in a directory that lost its .git refuses instead of using the enclosing repository",
		function()
			-- the incident: a fixture's .git vanished and git walked up to the real repository, with its origin
			local outer = `{base}/outer`
			if fs.isDir(outer) then
				fs.removeDir(outer)
			end
			fs.writeDir(`{outer}/seed`)
			create(outer, { "init", "-q", "-b", "main", `{outer}/seed` })
			identity(`{outer}/seed`)
			fs.writeFile(`{outer}/seed/readme`, "x")
			git(`{outer}/seed`, { "add", "-A" })
			git(`{outer}/seed`, { "commit", "-q", "-m", "seed" })
			create(outer, { "clone", "-q", "--bare", `{outer}/seed`, `{outer}/origin.git` })
			create(outer, { "clone", "-q", `{outer}/origin.git`, `{outer}/repo` })
			identity(`{outer}/repo`)
			-- a directory with a copy of the tracker but no .git, inside the outer repository
			git(`{outer}/repo`, { "worktree", "add", "-q", "-b", "w", `{outer}/wt` })
			local lost = `{outer}/wt/lost`
			fs.writeDir(`{lost}/tracker`)
			local root = fixture.physical(".") :: string
			engine.copy(root, lost) -- c0114 override: ./zn, scripts/ and z-nile/ (the engine, the gate, the templates)
			local before = git(`{outer}/origin.git`, { "rev-parse", "main" })
			-- Exception to the fixture rule: `lost` has no repository of its own, which is the point of this case, and
			-- fixture.exec refuses such a directory. So tracker.sh runs here through process.exec. It sits inside the
			-- part's own fixture folder, and the runner's guards still fence git; nothing is written outside it.
			local function trLost(args: { string }, env: { [string]: string }?): fixture.Result
				local argv = { "scripts/tracker.sh" }
				for _, arg in args do
					table.insert(argv, arg)
				end
				return process.exec("bash", argv, { cwd = lost, env = env })
			end
			-- every command that is not read-only is refused, not just the ones that publish
			local writing = {
				{ "new", "issue", "c", "x", "--project", "pickman" },
				{ "new", "raft", "chore", "r", "c0010", "--single", "--project", "pickman" },
				{ "renumber", "c0010", "c0011" },
				{ "migrate" },
				{ "start", "R0010" },
				{ "focus", "c0010" },
				{ "commit", "-m", "x" },
				{ "done", "R0010" },
				{ "check", "c0010" },
				{ "status" },
				{ "sync" },
				{ "worktree", "zz" },
				{ "worktree-prune" },
				{ "prompt", "c0010", "--stdout" },
			}
			for _, args in writing do
				local r = trLost(args)
				t.expect(r.ok).toBe(false)
				t.expect(has(r.stderr, "repository root")).toBe(true)
			end
			-- the read-only commands are exempt (other specs run them in sandboxes without a .git)
			for _, args in
				{
					{ "list" },
					{ "find", "c0010" },
					{ "members", "R0010" },
					{ "metrics" },
					{ "board", "--out", `{lost}/board.html`, "-O" }, -- -O (c0550): never start a browser
					{ "workstreams", "R0010" },
					{ "promote-check", "R0010" },
					{ "stamp", "new" },
				}
			do
				t.expect(has(trLost(args).stderr, "repository root")).toBe(false)
			end
			-- turning publishing off does not switch the guard off
			local offline = trLost(
				{ "new", "issue", "c", "y", "--project", "pickman" },
				{ PICKMAN_PUBLISH = "0" }
			)
			t.expect(offline.ok).toBe(false)
			t.expect(has(offline.stderr, "repository root")).toBe(true)
			t.expect(has(git(`{outer}/repo`, { "worktree", "list" }), "zz")).toBe(false)
			t.expect(git(`{outer}/origin.git`, { "rev-parse", "main" })).toBe(before)
			t.expect(fs.isDir(`{lost}/tracker/issues`)).toBe(false)
		end
	)
end)
