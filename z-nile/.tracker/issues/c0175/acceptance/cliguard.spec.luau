--!strict
-- c0175 AC13: opencode keeps its project id in `<common git dir>/opencode` and rewrites it each run, in a worktree into the main
-- repository's `.git`. The runner makes an existing file read-only before and after an opencode step (probed: opencode runs the
-- same with it read-only), so no step rewrites it. Throwaway repositories under .cache/c0175-guard, real git with its own
-- identity (@example.invalid). No CLI starts: the opencode is a script the spec writes.
local adapters = require("@znile/engine/adapters")
local fs = require("@lune/fs")
local process = require("@lune/process")
local runner = require("@znile/engine/runner")
local t = require("@tests/lib/t")

local G: any = require("@znile/engine/cliguard")

local here = (string.gsub(process.exec("pwd", { "-P" }).stdout, "%s+$", ""))
local base = `{here}/.cache/c0175-guard`
local repo = `{base}/repo`
local wt = `{base}/wt`

local function git(dir: string, args: { string })
	local full = { "-C", dir, "-c", "user.name=c0175", "-c", "user.email=c0175@example.invalid" }
	for _, a in args do
		table.insert(full, a)
	end
	local r = process.exec("git", full)
	if not r.ok then
		error(`git {table.concat(args, " ")}: {r.stderr}`, 2)
	end
end
local function writable(path: string): boolean
	return process.exec("test", { "-w", path }).ok
end
local function reset()
	if fs.isDir(base) then
		process.exec("chmod", { "-R", "u+w", base })
		fs.removeDir(base)
	end
	process.exec("mkdir", { "-p", repo })
	git(repo, { "init", "-q", "." })
	git(repo, { "commit", "-q", "--allow-empty", "-m", "init" })
end
local STEP = [[{"type":"step_finish","sessionID":"ses_x","part":{"id":"a","tokens":{"input":5,"output":1}}}]]
local TEXT = [[{"type":"text","part":{"text":"x"}}]]
local ENV = { PATH = process.env.PATH or "/usr/bin:/bin", HOME = base }

local function runOpencode(script: string, cwd: string)
	local bin = `{base}/opencode`
	fs.writeFile(bin, `#!/bin/sh\n{script}\n`)
	process.exec("chmod", { "+x", bin })
	local state = `{base}/state`
	process.exec("mkdir", { "-p", state })
	return runner.run({
		argv = { bin, "run", "p" },
		cwd = cwd,
		env = ENV,
		adapter = adapters.get("opencode-cli"),
		cap = 1000000,
		stallSeconds = 30,
		toolSeconds = 30,
		stateDir = state,
	})
end

return t.spec("c0175 opencode's project file in the repository's git directory", function(it)
	it(
		"AC13: seal makes an existing project file read-only, in a repository and in a linked worktree's common directory",
		function()
			reset()
			fs.writeFile(`{repo}/.git/opencode`, "6dda3ed52d9b12797ec54dcbb1183b027268d703")
			t.expect(writable(`{repo}/.git/opencode`)).toBe(true)
			t.expect(G.seal("opencode-cli", repo, ENV)).toBe(true)
			t.expect(writable(`{repo}/.git/opencode`)).toBe(false)
			-- a linked worktree: the file in the main repository's .git is the one sealed
			process.exec("chmod", { "644", `{repo}/.git/opencode` })
			git(repo, { "worktree", "add", "-q", wt, "-b", "wtb" })
			t.expect(G.seal("opencode-cli", wt, ENV)).toBe(true)
			t.expect(writable(`{repo}/.git/opencode`)).toBe(false)
			t.expect(fs.readFile(`{repo}/.git/opencode`)).toBe("6dda3ed52d9b12797ec54dcbb1183b027268d703")
		end
	)

	it("AC13: seal does nothing without the file, outside a repository, or for another runtime", function()
		reset()
		t.expect(G.seal("opencode-cli", repo, ENV)).toBe(false)
		t.expect(fs.isFile(`{repo}/.git/opencode`)).toBe(false)
		local plain = `{base}/plain`
		process.exec("mkdir", { "-p", plain })
		t.expect(G.seal("opencode-cli", plain, ENV)).toBe(false)
		fs.writeFile(`{repo}/.git/opencode`, "x")
		t.expect(G.seal("claude-cli", repo, ENV)).toBe(false)
		t.expect(G.seal("agy-cli", repo, ENV)).toBe(false)
		t.expect(writable(`{repo}/.git/opencode`)).toBe(true)
	end)

	it(
		"AC13: a step that tries to rewrite the project file leaves it as it was, and the step still runs",
		function()
			reset()
			fs.writeFile(`{repo}/.git/opencode`, "original-id")
			local r = runOpencode(`echo changed > "{repo}/.git/opencode" 2>/dev/null\necho '{STEP}'`, repo)
			t.expect(r.outcome).toBe("ok")
			t.expect(r.tokens).toBe(6)
			t.expect(fs.readFile(`{repo}/.git/opencode`)).toBe("original-id")
		end
	)

	it("AC13: a step that creates the file where there was none finds it read-only afterwards", function()
		reset()
		t.expect(fs.isFile(`{repo}/.git/opencode`)).toBe(false)
		local r = runOpencode(`echo new-id > "{repo}/.git/opencode"\necho '{TEXT}'`, repo)
		t.expect(r.outcome).toBe("ok")
		t.expect(fs.readFile(`{repo}/.git/opencode`)).toBe("new-id\n")
		t.expect(writable(`{repo}/.git/opencode`)).toBe(false)
	end)
end)
