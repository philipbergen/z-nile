--!strict
-- `tracker.sh worktree` and stale remote-tracking refs (review 001 F1): the repo deletes branches on
-- merge, so a clone keeps `origin/<name>` refs for branches that no longer exist. A fetch without
-- --prune made `worktree <name>` resume such a dead branch instead of cutting a fresh one.
local clone = require("@tests/lib/clone")
local fixture = require("@tests/lib/fixture")
local fs = require("@lune/fs")
local process = require("@lune/process")
local t = require("@tests/lib/t")

type Result = { ok: boolean, code: number, stdout: string, stderr: string }

local function trim(s: string): string
	return (string.gsub(string.gsub(s, "^%s+", ""), "%s+$", ""))
end

-- Fixture repos are throwaway: no background gc/maintenance that could race a re-created fixture. The
-- runner's guard (scripts/lib/fence.sh) turns both off for every git a spec runs; a spec must not set
-- git config through the environment, which would replace the guard's (testing skill).
local NO_GC: { [string]: string } = {}

local root = trim(process.exec("git", { "rev-parse", "--show-toplevel" }).stdout)
local base = `{root}/.cache/wt-fetch`
local seed = `{base}/seed`
local origin = `{base}/origin.git`
local main = `{base}/main`

local function run(cwd: string, cmd: string, args: { string }): Result
	return fixture.exec(cwd, cmd, args, { env = NO_GC })
end

local function must(r: Result, what: string): string
	if not r.ok then
		error(`{what} failed ({r.code}): {r.stderr}{r.stdout}`, 2)
	end
	return trim(r.stdout)
end

local function git(cwd: string, args: { string }): string
	return must(run(cwd, "git", args), "git " .. table.concat(args, " "))
end

local function tr(cwd: string, args: { string }): Result
	return run(cwd, "bash", { "scripts/tracker.sh", table.unpack(args) })
end

local function identity(cwd: string)
	git(cwd, { "config", "user.name", "t" })
	git(cwd, { "config", "user.email", "t@example.invalid" })
end

-- Push a branch with one commit to origin, from `main`, and return the commit.
local function pushBranch(name: string, message: string): string
	git(main, { "switch", "-q", "-c", name, "origin/main" })
	git(main, { "commit", "-q", "--allow-empty", "-m", message })
	git(main, { "push", "-q", "-u", "origin", name })
	local tip = git(main, { "rev-parse", "HEAD" })
	git(main, { "switch", "-q", "main" })
	return tip
end

return t.spec("worktree and stale remote refs", function(it)
	it("sets up a clone whose origin is a local bare repository", function()
		if fs.isDir(base) then
			fs.removeDir(base)
		end
		fs.writeDir(base)
		clone.isolated(root, seed)
		identity(seed)
		git(seed, { "checkout", "-q", "-B", "main" })
		git(seed, { "remote", "remove", "origin" })
		-- overlay the working tree's tooling so uncommitted changes are what gets tested
		local listed = process.exec(
			"git",
			{ "ls-files", "-co", "--exclude-standard", "scripts", ".gitignore" },
			{ cwd = root }
		)
		for path in string.gmatch(listed.stdout, "[^\n]+") do
			if fs.isFile(`{root}/{path}`) then
				local parent = string.match(path, "^(.*)/[^/]+$")
				if parent then
					fs.writeDir(`{seed}/{parent}`)
				end
				fs.writeFile(`{seed}/{path}`, fs.readFile(`{root}/{path}`))
			end
		end
		git(seed, { "add", "-A" })
		git(seed, { "commit", "-q", "--allow-empty", "-m", "fixture" })
		must(process.exec("git", { "clone", "-q", "--bare", seed, origin }), "bare origin")
		must(process.exec("git", { "clone", "-q", origin, main }), "clone main")
		identity(main)
		t.expect(git(main, { "branch", "--show-current" })).toBe("main")
	end)

	it("a branch deleted on origin is not resumed: the worktree starts from origin/main", function()
		pushBranch("prep-x", "old prep")
		git(main, { "branch", "-D", "prep-x" })
		-- the branch is deleted on origin behind main's back, so main keeps a stale origin/prep-x
		git(origin, { "branch", "-D", "prep-x" })
		t.expect(run(main, "git", { "rev-parse", "--verify", "--quiet", "refs/remotes/origin/prep-x" }).ok)
			.toBe(true)
		local path = must(tr(main, { "worktree", "prep-x" }), "worktree prep-x")
		t.expect(git(path, { "rev-parse", "HEAD" })).toBe(git(main, { "rev-parse", "origin/main" }))
		t.expect(run(path, "git", { "rev-parse", "--abbrev-ref", "@{u}" }).ok).toBe(false)
	end)

	it("a live origin-only branch still resumes", function()
		local tip = pushBranch("resume-y", "work on another host")
		git(main, { "branch", "-D", "resume-y" })
		local path = must(tr(main, { "worktree", "resume-y" }), "worktree resume-y")
		t.expect(git(path, { "branch", "--show-current" })).toBe("resume-y")
		t.expect(git(path, { "rev-parse", "HEAD" })).toBe(tip)
	end)

	it("a local branch whose upstream is gone resumes with a warning", function()
		pushBranch("prep-z", "merged long ago")
		git(origin, { "branch", "-D", "prep-z" })
		local r = tr(main, { "worktree", "prep-z" })
		t.expect(r.ok).toBe(true)
		t.expect(string.find(r.stderr, "upstream of prep-z is gone", 1, true) ~= nil).toBe(true)
		t.expect(git(trim(r.stdout), { "branch", "--show-current" })).toBe("prep-z")
	end)
end)
