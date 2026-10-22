--!strict
-- c0440: `worktree-prune` flags worktrees outside .worktree/ and leaves them (`tracker.sh launch` is gone, c0069).
-- Fixture under .cache/launch-e2e: a seed clone of the repo (no origin, `main` forced, the working
-- tree's tooling overlaid, tracker emptied) with raft R0010, a done raft R0020 and issues f0010,
-- f0020; then a bare origin and a clone `main/`.
local clone = require("@tests/lib/clone")
local engine = require("@tests/lib/engine")
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
-- c0120 override: fixtures live under the home's .cache (the jail refuses the checkout top's)
local here = fixture.physical(".") or "."
local base = `{here}/.cache/launch-e2e`
local seed = `{base}/seed`
local origin = `{base}/origin.git`
local main = `{base}/main`
local strays = { `{base}/outside`, `{main}/.claude/worktrees/x`, `{main}/.worktree-old/y` }

local function run(
	cwd: string,
	cmd: string,
	args: { string },
	env: { [string]: string }?,
	stdin: string?
): Result
	local merged = table.clone(NO_GC)
	if env then
		for k, v in env do
			merged[k] = v
		end
	end
	return fixture.exec(cwd, cmd, args, { env = merged, stdin = stdin })
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

local function tr(cwd: string, args: { string }, env: { [string]: string }?, stdin: string?): Result
	return run(cwd, "bash", { "scripts/tracker.sh", table.unpack(args) }, env, stdin)
end

local function has(text: string, needle: string): boolean
	return string.find(text, needle, 1, true) ~= nil
end

return t.spec("launch", function(it)
	it("sets up a fixture with an origin and a clone", function()
		if fs.isDir(base) then
			fs.removeDir(base)
		end
		fs.writeDir(base)
		clone.isolated(root, seed)
		git(seed, { "config", "user.name", "e2e" })
		git(seed, { "config", "user.email", "e2e@example.invalid" })
		git(seed, { "checkout", "-q", "-B", "main" })
		git(seed, { "remote", "remove", "origin" })
		local listed = process.exec("git", {
			"ls-files",
			"-co",
			"--exclude-standard",
			"zn",
			"scripts",
			"z-nile",
			":(exclude)z-nile/.tracker",
			":(exclude)z-nile/next",
			":(exclude)z-nile/compaction.txt",
			".gitignore",
		}, { cwd = root })
		for path in string.gmatch(listed.stdout, "[^\n]+") do
			if fs.isFile(`{root}/{path}`) then
				local parent = string.match(path, "^(.*)/[^/]+$")
				if parent then
					fs.writeDir(`{seed}/{parent}`)
				end
				fs.writeFile(`{seed}/{path}`, fs.readFile(`{root}/{path}`))
			end
		end
		-- c0114 override: every project root is emptied, and the counter moved to z-nile/next
		engine.empty(seed)
		must(tr(seed, { "new", "issue", "f", "alpha", "--project", "pickman" }), "new f0010")
		must(tr(seed, { "new", "issue", "f", "beta", "--project", "pickman" }), "new f0020")
		must(tr(seed, { "new", "raft", "feature", "demo", "f0010", "--project", "pickman" }), "raft demo")
		must(tr(seed, { "new", "raft", "feature", "old", "f0020", "--project", "pickman" }), "raft old")
		-- R0020 is finished
		git(seed, { "add", "-A" })
		git(seed, { "commit", "-qm", "fixture" })
		-- c0120 override: pickman's items live under pickman/.tracker (the fixtures' layout)
		fs.writeDir(`{seed}/pickman/.tracker/rafts/done`)
		fs.writeDir(`{seed}/pickman/.tracker/issues/done`)
		git(seed, { "mv", "pickman/.tracker/rafts/R0020", "pickman/.tracker/rafts/done/R0020" })
		git(seed, { "mv", "pickman/.tracker/issues/f0020", "pickman/.tracker/issues/done/f0020" })
		git(seed, { "commit", "-qm", "R0020 is done" })
		must(process.exec("git", { "clone", "-q", "--bare", seed, origin }), "bare origin")
		must(process.exec("git", { "clone", "-q", origin, main }), "clone main")
		git(main, { "config", "user.name", "e2e" })
		git(main, { "config", "user.email", "e2e@example.invalid" })
	end)

	it("worktree-prune warns about a worktree outside .worktree/ and leaves it", function()
		-- three strays: a sibling directory, the harness's .claude/worktrees/ and .worktree-old/, both inside the repo
		for i, path in strays do
			git(main, { "worktree", "add", "-q", "-b", `stray{i}`, path, "origin/main" })
		end
		local r = tr(main, { "worktree-prune" })
		t.expect(r.ok).toBe(true)
		for _, path in strays do
			t.expect(has(r.stderr, `warning: {path} is outside .worktree/`)).toBe(true)
			t.expect(fs.isDir(path)).toBe(true) -- left alone
		end
		-- worktrees inside .worktree/ and the main checkout are not flagged
		local _, warnings = string.gsub(r.stderr, "warning:", "")
		t.expect(warnings).toBe(#strays)
		t.expect(has(r.stderr, `warning: {main}/.worktree/`)).toBe(false)
	end)
end)
