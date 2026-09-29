--!strict
-- c0041: rafts run in raft-named worktrees; hooks act on the right tree.
-- Fixture under .cache/wt-e2e: a bare `origin.git` (never GitHub, so gh is never called) and a
-- clone `main/` of it, seeded from the committed HEAD with the working tree's tooling overlaid.
local fs = require("@lune/fs")
local process = require("@lune/process")
local t = require("@tests/lib/t")

type Result = { ok: boolean, code: number, stdout: string, stderr: string }

local function trim(s: string): string
	return (string.gsub(string.gsub(s, "^%s+", ""), "%s+$", ""))
end

local root = trim(process.exec("git", { "rev-parse", "--show-toplevel" }).stdout)
local base = `{root}/.cache/wt-e2e`
local seed = `{base}/seed`
local origin = `{base}/origin.git`
local main = `{base}/main`
local wt1 = `{main}/.worktrees/R0010-demo`
local wt2 = `{main}/.worktrees/R0020-other`

local function run(cwd: string, cmd: string, args: { string }, stdin: string?): Result
	if stdin then
		return process.exec(cmd, args, { cwd = cwd, stdio = { stdin = stdin } })
	end
	return process.exec(cmd, args, { cwd = cwd })
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
	git(cwd, { "config", "user.name", "e2e" })
	git(cwd, { "config", "user.email", "e2e@example.invalid" })
end

local function edit(path: string, from: string, to: string)
	local text, n = string.gsub(fs.readFile(path), from, to)
	assert(n > 0, `pattern {from} not found in {path}`)
	fs.writeFile(path, text)
end

local function editJson(file: string): string
	return '{"tool_input":{"file_path":"' .. file .. '"}}'
end

local function stopJson(cwd: string): string
	return '{"cwd":"' .. cwd .. '","stop_hook_active":false}'
end

local startOut = ""

return t.spec("worktrees", function(it)
	it("worktree creates a raft-named worktree and branch from origin/main", function()
		if fs.isDir(base) then
			fs.removeDir(base)
		end
		fs.writeDir(base)
		must(process.exec("git", { "clone", "-q", root, seed }), "clone seed")
		identity(seed)
		-- overlay the working tree's tooling so uncommitted changes are what gets tested
		local listed = run(
			root,
			"git",
			{ "ls-files", "-co", "--exclude-standard", "scripts", "tracker/templates", ".gitignore" }
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
		-- empty tracker, then two ready fixture rafts
		for _, kind in { "issues", "rafts" } do
			for _, state in { "", "active/", "done/" } do
				local dir = `{seed}/tracker/{kind}/{state}`
				for _, name in fs.readDir(dir) do
					if string.match(name, "^[fdcR]%d%d%d%d$") then
						fs.removeDir(dir .. name)
					end
				end
			end
		end
		must(tr(seed, { "new", "issue", "f", "alpha" }), "new f0010")
		must(tr(seed, { "new", "issue", "f", "beta" }), "new f0020")
		must(tr(seed, { "new", "raft", "feature", "demo", "f0010" }), "new R0010")
		must(tr(seed, { "new", "raft", "feature", "other", "f0020" }), "new R0020")
		for _, doc in
			{
				"tracker/issues/f0010/f0010-alpha.md",
				"tracker/issues/f0020/f0020-beta.md",
				"tracker/rafts/R0010/R0010-demo.md",
				"tracker/rafts/R0020/R0020-other.md",
			}
		do
			edit(`{seed}/{doc}`, "design: draft", "design: ready")
		end
		git(seed, { "add", "-A" })
		git(seed, { "commit", "-qm", "fixture" })
		must(process.exec("git", { "clone", "-q", "--bare", seed, origin }), "bare origin")
		must(process.exec("git", { "clone", "-q", origin, main }), "clone main")
		identity(main)

		local r = tr(main, { "worktree", "R0010" })
		t.expect(must(r, "worktree R0010")).toBe(wt1)
		t.expect(fs.isDir(wt1)).toBe(true)
		t.expect(git(wt1, { "branch", "--show-current" })).toBe("R0010-demo")
		t.expect(git(wt1, { "rev-parse", "HEAD" })).toBe(git(main, { "rev-parse", "origin/main" }))
	end)

	it("worktree is idempotent and works from inside another worktree", function()
		t.expect(must(tr(main, { "worktree", "R0010" }), "worktree again")).toBe(wt1)
		-- invoked from inside R0010's worktree, R0020's worktree still lands under the main checkout
		t.expect(must(tr(wt1, { "worktree", "R0020" }), "worktree R0020")).toBe(wt2)
		t.expect(git(wt2, { "branch", "--show-current" })).toBe("R0020-other")
	end)

	it("main checkout stays on main and clean", function()
		t.expect(git(main, { "branch", "--show-current" })).toBe("main")
		t.expect(git(main, { "status", "--porcelain" })).toBe("")
	end)

	it("start inside the worktree reuses the branch and pushes", function()
		startOut = must(tr(wt1, { "start", "R0010" }), "start")
		t.expect(git(wt1, { "branch", "--show-current" })).toBe("R0010-demo")
		t.expect(git(wt1, { "log", "-1", "--format=%s" })).toBe("tracker: start R0010 Demo")
		t.expect(fs.isDir(`{wt1}/tracker/rafts/active/R0010`)).toBe(true)
		t.expect(git(origin, { "rev-parse", "R0010-demo" })).toBe(git(wt1, { "rev-parse", "HEAD" }))
		t.expect(git(main, { "branch", "--show-current" })).toBe("main")
	end)

	it("non-GitHub origin skips the draft PR", function()
		t.expect(string.find(startOut, "origin is not GitHub: skipped draft PR", 1, true) ~= nil).toBe(true)
	end)

	it("worktree-prune removes squash-merged done rafts and keeps unfinished ones", function()
		-- finish R0010 on its branch (plain git: this spec is about worktrees, not done's checks)
		git(wt1, { "mv", "tracker/rafts/active/R0010", "tracker/rafts/done/R0010" })
		git(wt1, { "mv", "tracker/issues/active/f0010", "tracker/issues/done/f0010" })
		git(wt1, { "commit", "-qm", "finish R0010" })
		git(wt1, { "push", "-q" })
		-- squash-merge into main, as GitHub's squash button would
		git(main, { "merge", "--squash", "-q", "R0010-demo" })
		git(main, { "commit", "-qm", "R0010 (squash)" })
		git(main, { "push", "-q", "origin", "main" })

		must(tr(main, { "worktree-prune" }), "worktree-prune")
		t.expect(fs.isDir(wt1)).toBe(false)
		t.expect(git(main, { "branch", "--list", "R0010-demo" })).toBe("")
		t.expect(fs.isDir(wt2)).toBe(true)
		t.expect(git(main, { "branch", "--list", "R0020-other" }) ~= "").toBe(true)
	end)

	it("post-edit hook lints with the edited file's worktree config", function()
		local hook = `{main}/scripts/hooks/post-edit.sh`
		local probe = "--!strict\nlocal unused = 1\nreturn nil\n"
		-- the worktree allows unused variables; the main checkout denies them
		edit(`{wt2}/selene.toml`, 'unused_variable = "deny"', 'unused_variable = "allow"')
		fs.writeFile(`{wt2}/src/shared/Probe.luau`, probe)
		fs.writeFile(`{main}/src/shared/Probe.luau`, probe)
		local inWorktree = run(main, "bash", { hook }, editJson(`{wt2}/src/shared/Probe.luau`))
		local inMain = run(main, "bash", { hook }, editJson(`{main}/src/shared/Probe.luau`))
		fs.removeFile(`{wt2}/src/shared/Probe.luau`)
		fs.removeFile(`{main}/src/shared/Probe.luau`)
		git(wt2, { "checkout", "--", "selene.toml" })
		t.expect(inWorktree.code).toBe(0)
		t.expect(inMain.code).toBe(2)
	end)

	it("stop hook gates the session's cwd worktree", function()
		local hook = `{main}/scripts/hooks/stop.sh`
		fs.writeFile(`{wt2}/src/shared/Broken.luau`, "--!strict\nlocal = \n")
		local inWorktree = run(main, "bash", { hook }, stopJson(wt2))
		local inMain = run(main, "bash", { hook }, stopJson(main))
		fs.removeFile(`{wt2}/src/shared/Broken.luau`)
		t.expect(inWorktree.code).toBe(2)
		t.expect(inMain.code).toBe(0)
	end)
end)
