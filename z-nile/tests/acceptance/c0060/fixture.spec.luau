--!strict
-- c0660: `@tests/lib/fixture` runs git and tracker.sh only in a fixture repository: one under a .cache folder that
-- is the top of its own worktree (or a bare repository's own git directory). Anything else is refused before the
-- command runs.
local fixture = require("@tests/lib/fixture")
local fs = require("@lune/fs")
local process = require("@lune/process")
local t = require("@tests/lib/t")

type Result = { ok: boolean, code: number, stdout: string, stderr: string }

local root = (string.gsub(process.exec("git", { "rev-parse", "--show-toplevel" }).stdout, "%s+$", ""))
-- c0120 override: fixtures live under the spec's home's .cache (the jail refuses the checkout top's)
local base = `{fixture.physical(".") :: string}/.cache/c0660-fixture`
local fx, wt, bare, norepo = `{base}/fx`, `{base}/fx-wt`, `{base}/bare.git`, `{base}/norepo`
local outside = "" -- a repository outside any .cache folder
local foreign = "" -- a repository under some other .cache folder

local function must(r: Result, what: string): string
	if not r.ok then
		error(`{what} failed ({r.code}): {r.stderr}{r.stdout}`, 2)
	end
	return (string.gsub(r.stdout, "%s+$", ""))
end

local function refused(f: () -> ()): string
	local ok: boolean, err: any = pcall(f :: any)
	t.expect(ok).toBe(false)
	return tostring(err)
end

local ready = false
local function setUp()
	if not ready then
		error("setup did not finish: not running this case", 2)
	end
end

return t.spec("c0660 fixture helper", function(it)
	it("sets up a fixture, its worktree, a bare fixture, and folders that aren't fixtures", function()
		if fs.isDir(base) then
			fs.removeDir(base)
		end
		fs.writeDir(base)
		-- creating a fixture names its path explicitly; everything after goes through the helper
		must(process.exec("git", { "init", "-q", "-b", "main", fx }), "git init")
		must(process.exec("git", { "init", "-q", "--bare", bare }), "git init --bare")
		fs.writeDir(`{fx}/sub`)
		fs.writeDir(norepo)
		fixture.git(fx, {
			"-c",
			"user.name=e2e",
			"-c",
			"user.email=e2e@example.invalid",
			"commit",
			"-q",
			"--allow-empty",
			"-m",
			"x",
		})
		fixture.git(fx, { "worktree", "add", "-q", "-b", "w", wt })
		outside = must(process.exec("mktemp", { "-d" }), "mktemp")
		must(process.exec("git", { "init", "-q", outside }), "git init outside")
		foreign = `{outside}/.cache/fx`
		must(process.exec("git", { "init", "-q", foreign }), "git init foreign")
		ready = true
	end)

	it("a fixture repository, a worktree of it and a bare fixture are accepted", function()
		setUp()
		t.expect(fixture.git(fx, { "rev-parse", "--abbrev-ref", "HEAD" })).toBe("main")
		t.expect(fixture.git(wt, { "rev-parse", "--abbrev-ref", "HEAD" })).toBe("w")
		t.expect(fixture.git(bare, { "rev-parse", "--is-bare-repository" })).toBe("true")
	end)

	it("a folder under .cache without its own repository is refused, and nothing runs there", function()
		setUp()
		local err = refused(function()
			fixture.exec(norepo, "sh", { "-c", "touch ran" })
		end)
		t.expect(string.find(err, "not a fixture repository", 1, true) ~= nil).toBe(true)
		t.expect(fs.isFile(`{norepo}/ran`)).toBe(false)
	end)

	it("a subfolder of a fixture is refused", function()
		setUp()
		refused(function()
			fixture.git(`{fx}/sub`, { "status" })
		end)
	end)

	it("the real checkout is refused", function()
		setUp()
		refused(function()
			fixture.exec(root, "true", {})
		end)
	end)

	it("a repository outside any .cache folder is refused", function()
		setUp()
		refused(function()
			fixture.git(outside, { "status" })
		end)
	end)

	it("a repository under another .cache folder than this run's is refused", function()
		setUp()
		refused(function()
			fixture.git(foreign, { "status" })
		end)
	end)

	it(
		"git options or variables that point at another repository are refused; a command's own options are not",
		function()
			setUp()
			for _, args in
				{
					{ "-C", root, "status" },
					{ "--git-dir", `{root}/.git`, "status" },
					{ "--work-tree=/", "status" },
					{ "-c", "a.b=c", "-C", root, "status" },
				}
			do
				local err = refused(function()
					fixture.git(fx, args)
				end)
				t.expect(string.find(err, "another repository", 1, true) ~= nil).toBe(true)
			end
			refused(function()
				fixture.exec(fx, "git", { "status" }, { env = { GIT_DIR = `{root}/.git` } })
			end)
			refused(function()
				fixture.exec(fx, "sh", { "-c", "true" }, { env = { GIT_WORK_TREE = root } })
			end)
			fixture.git(fx, {
				"-c",
				"user.name=e2e",
				"-c",
				"user.email=e2e@example.invalid",
				"commit",
				"-q",
				"--allow-empty",
				"-C",
				"HEAD",
			})
		end
	)

	it("git raises with git's own output; exec reports a failure without raising", function()
		setUp()
		local err = refused(function()
			fixture.git(fx, { "rev-parse", "--verify", "no-such-ref" })
		end)
		t.expect(string.find(err, "no-such-ref", 1, true) ~= nil).toBe(true)
		t.expect(fixture.exec(fx, "git", { "rev-parse", "--verify", "no-such-ref" }).ok).toBe(false)
	end)

	it("exec passes the environment and standard input", function()
		setUp()
		local r = fixture.exec(
			fx,
			"sh",
			{ "-c", 'printf "%s/" "$C0660"; cat' },
			{ env = { C0660 = "y" }, stdin = "z" }
		)
		t.expect(r.stdout).toBe("y/z")
	end)

	it("cleans up", function()
		fs.removeDir(base)
		if outside ~= "" then
			fs.removeDir(outside)
		end
	end)
end)
