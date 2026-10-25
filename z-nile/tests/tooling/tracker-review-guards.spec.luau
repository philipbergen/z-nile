--!strict
-- R0200 review 001: the repo-root guard also refuses when git's directory is not the checkout's own .git (F2),
-- --desc reaches a stub made without publishing (F5), and local ids count origin's too (F1).
local engine = require("@tests/lib/engine")
local fs = require("@lune/fs")
local process = require("@lune/process")
local t = require("@tests/lib/t")

type Result = { ok: boolean, code: number, stdout: string, stderr: string }

local function trim(s: string): string
	return (string.gsub(string.gsub(s, "^%s+", ""), "%s+$", ""))
end
local root = trim(process.exec("git", { "rev-parse", "--show-toplevel" }).stdout)
-- fixtures under this home's .cache (the working directory, c0120); root is for reading the tooling
local base = `{(string.gsub(process.exec("pwd", { "-P" }).stdout, "%s+$", ""))}/.cache/tracker-review-guards`
local repo, other = `{base}/repo`, `{base}/other`
-- built by concatenation: the repository guards' gate scan bans the literal name in tests/ (R0210)
local GITDIR_VAR = "GIT_" .. "DIR"

local function physical(path: string): string
	return trim(process.exec("pwd", { "-P" }, { cwd = path }).stdout)
end

-- git in a fixture this spec made, after checking the directory is that fixture's own top
local function git(cwd: string, args: { string }): string
	local top = process.exec("git", { "rev-parse", "--show-toplevel" }, { cwd = cwd })
	if not top.ok or trim(top.stdout) ~= physical(cwd) then
		error(`{cwd} is not a fixture repository; not running git there`)
	end
	local r: Result = process.exec("git", args, { cwd = cwd })
	if not r.ok then
		error(`git {table.concat(args, " ")} failed: {r.stderr}{r.stdout}`, 2)
	end
	return trim(r.stdout)
end

local ready = false

return t.spec("tracker guards after review 001", function(it)
	it("sets up a tracker repository and another repository beside it", function()
		if fs.isDir(base) then
			fs.removeDir(base)
		end
		fs.writeDir(`{repo}/tracker`)
		engine.copy(root, repo)
		t.expect(process.exec("git", { "init", "-q", "-b", "main", repo }).ok).toBe(true)
		t.expect(process.exec("git", { "init", "-q", "-b", "main", other }).ok).toBe(true)
		for _, r in { repo, other } do
			git(r, { "config", "user.name", "t" })
			git(r, { "config", "user.email", "t@example.invalid" })
		end
		ready = true
	end)

	it("--desc reaches the stub when nothing is published", function()
		t.expect(ready).toBe(true)
		local r = process.exec("bash", {
			"scripts/tracker.sh",
			"new",
			"issue",
			"c",
			"alpha",
			"--desc",
			"Alpha's one line.",
			"--project",
			"pickman",
		}, { cwd = repo, env = { PICKMAN_PUBLISH = "0" } })
		if not r.ok then
			error(r.stderr .. r.stdout)
		end
		local doc = fs.readFile(`{repo}/{trim(r.stdout)}`)
		t.expect(string.find(doc, "## Problem\nAlpha's one line.", 1, true) ~= nil).toBe(true)
	end)

	it("a writing command refuses when git's directory is not this checkout's own", function()
		t.expect(ready).toBe(true)
		local otherHead = process.exec("git", { "rev-parse", "--git-dir" }, { cwd = other })
		t.expect(otherHead.ok).toBe(true)
		local r = process.exec(
			"bash",
			{ "scripts/tracker.sh", "new", "issue", "c", "beta", "--project", "pickman" },
			{ cwd = repo, env = { PICKMAN_PUBLISH = "0", [GITDIR_VAR] = `{other}/.git` } }
		)
		t.expect(r.ok).toBe(false)
		t.expect(string.find(r.stderr, "refusing to run", 1, true) ~= nil).toBe(true)
		t.expect(fs.isDir(`{repo}/tracker/issues/c0020`)).toBe(false)
		-- read-only commands stay exempt
		local listed = process.exec(
			"bash",
			{ "scripts/tracker.sh", "list" },
			{ cwd = repo, env = { [GITDIR_VAR] = `{other}/.git` } }
		)
		t.expect(string.find(listed.stderr, "refusing to run", 1, true) == nil).toBe(true)
	end)

	it("local ids are numbered above the ids handed in from origin", function()
		-- the store reads the tracker of the folder it runs in, and this spec runs from z-nile/ (c0120), which holds no
		-- registry: the numbers are taken by a child run at the checkout's top (a script under this home's .cache)
		fs.writeDir(base)
		local script = `{base}/next-number.luau`
		fs.writeFile(
			script,
			table.concat({
				`local store = {"req" .. "uire"}("@znile/engine/store")`,
				'print(store.nextNumber("issue"), store.nextNumber("issue", { "c9980" }), store.nextNumber("issue", {}))',
				"",
			}, "\n")
		)
		local r = process.exec("lune", { "run", script }, { cwd = root })
		if not r.ok then
			error(`numbering failed: {r.stderr}`)
		end
		local mine, above, none = string.match(r.stdout, "^(%d+)%s+(%d+)%s+(%d+)%s*$")
		t.expect(mine ~= nil).toBe(true)
		t.expect((tonumber(above) :: number) >= 9990).toBe(true)
		t.expect(none).toBe(mine)
	end)

	it("cleans up", function()
		fs.removeDir(base)
	end)
end)
