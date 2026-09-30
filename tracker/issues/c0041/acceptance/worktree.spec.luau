--!strict
-- c0041: every change runs in a worktree; hooks act on the right tree.
-- Fixture under .cache/wt-e2e: a bare `origin.git` (never GitHub, except in the one case that fakes
-- both the URL and `gh`) and a clone `main/` of it, seeded from the committed HEAD with the working
-- tree's tooling overlaid. The fixture pins its own `main` branch, so this spec passes from any
-- branch and from a detached HEAD (CI's pull_request checkout).
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
local fakebin = `{base}/fakebin`
local ghlog = `{base}/gh.log`
local wt1 = `{main}/.worktrees/R0010-demo`
local wt2 = `{main}/.worktrees/R0020-other`
local wt3 = `{main}/.worktrees/R0030-third`
local wt4 = `{main}/.worktrees/R0040-fourth`
local named = `{main}/.worktrees/capture-demo`

local function run(
	cwd: string,
	cmd: string,
	args: { string },
	stdin: string?,
	env: { [string]: string }?
): Result
	local opts: any = { cwd = cwd }
	if stdin then
		opts.stdio = { stdin = stdin }
	end
	if env then
		opts.env = env
	end
	return process.exec(cmd, args, opts)
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

local function countWorktrees(): number
	local _, n = string.gsub(git(main, { "worktree", "list", "--porcelain" }), "worktree ", "")
	return n
end

-- Finish a raft on its own branch, as `tracker.sh done` would (plain git: this spec is about
-- worktrees, not done's checks). `from` is the raft's directory state: "" (backlog) or "active/".
local function finishOnBranch(wt: string, raft: string, issue: string, from: string)
	git(wt, { "mv", `tracker/rafts/{from}{raft}`, `tracker/rafts/done/{raft}` })
	git(wt, { "mv", `tracker/issues/{from}{issue}`, `tracker/issues/done/{issue}` })
	git(wt, { "commit", "-qm", `finish {raft}` })
	git(wt, { "push", "-q", "-u", "origin", "HEAD" })
end

-- Squash-merge a raft branch into main and push, as GitHub's squash button would.
local function squashMerge(branch: string)
	git(main, { "merge", "--squash", "-q", branch })
	git(main, { "commit", "-qm", `{branch} (squash)` })
	git(main, { "push", "-q", "origin", "main" })
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
		-- whatever the source was (a feature branch, or CI's detached HEAD), the fixture is on main
		git(seed, { "checkout", "-q", "-B", "main" })
		git(seed, { "remote", "remove", "origin" })
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
		-- empty tracker, then four ready fixture rafts
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
		local rafts =
			{ { "alpha", "demo" }, { "beta", "other" }, { "gamma", "third" }, { "delta", "fourth" } }
		for _, pair in rafts do
			must(tr(seed, { "new", "issue", "f", pair[1] }), "new issue " .. pair[1])
		end
		must(tr(seed, { "new", "issue", "f", "epsilon" }), "new issue epsilon") -- f0050: no raft
		for i, pair in rafts do
			must(tr(seed, { "new", "raft", "feature", pair[2], `f00{i}0` }), "new raft " .. pair[2])
		end
		edit(`{seed}/tracker/issues/f0050/f0050.md`, "design: draft", "design: ready")
		for i = 1, #rafts do
			edit(`{seed}/tracker/issues/f00{i}0/f00{i}0.md`, "design: draft", "design: ready")
			edit(`{seed}/tracker/rafts/R00{i}0/R00{i}0.md`, "design: draft", "design: ready")
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
		-- a new branch must not track origin/main: a bare `git push` would target the wrong ref
		t.expect(run(wt1, "git", { "rev-parse", "--abbrev-ref", "@{u}" }).ok).toBe(false)
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

	it("start and new are refused in the main checkout", function()
		local start = tr(main, { "start", "R0030" })
		t.expect(start.ok).toBe(false)
		t.expect(string.find(start.stderr, "inside a worktree", 1, true) ~= nil).toBe(true)
		local new = tr(main, { "new", "issue", "c", "probe" })
		t.expect(new.ok).toBe(false)
		t.expect(git(main, { "branch", "--show-current" })).toBe("main")
		t.expect(git(main, { "status", "--porcelain" })).toBe("")
	end)

	it("renumber is refused in the main checkout", function()
		for _, args in { { "renumber", "f0050", "f0060" }, { "migrate" } } do
			local r = tr(main, args)
			t.expect(r.ok).toBe(false)
			t.expect(string.find(r.stderr, "inside a worktree", 1, true) ~= nil).toBe(true)
		end
		t.expect(git(main, { "status", "--porcelain" })).toBe("")
	end)

	it("prompt does not create a placeholder raft in the main checkout", function()
		-- f0050 has no raft: `prompt` would wrap it in a placeholder raft
		local r = tr(main, { "prompt", "f0050", "--stdout" })
		t.expect(r.ok).toBe(false)
		t.expect(string.find(r.stderr, "inside a worktree", 1, true) ~= nil).toBe(true)
		t.expect(git(main, { "status", "--porcelain" })).toBe("")
	end)

	it("worktree resumes an existing branch after its worktree is deleted", function()
		-- the branch exists only on origin: push it, then delete the worktree and the local branch
		git(main, { "push", "-q", "origin", "R0010-demo" })
		git(main, { "worktree", "remove", wt1 })
		git(main, { "branch", "-D", "R0010-demo" })
		t.expect(must(tr(main, { "worktree", "R0010" }), "worktree resume")).toBe(wt1)
		t.expect(git(wt1, { "branch", "--show-current" })).toBe("R0010-demo")
		t.expect(git(wt1, { "rev-parse", "HEAD" })).toBe(git(main, { "rev-parse", "origin/R0010-demo" }))
	end)

	it("worktree refuses a branch checked out elsewhere", function()
		-- the main checkout is on main, so a worktree named main must be refused, creating nothing
		local before = countWorktrees()
		local r = tr(main, { "worktree", "main" })
		t.expect(r.ok).toBe(false)
		t.expect(string.find(r.stderr, "already used by worktree at", 1, true) ~= nil).toBe(true)
		t.expect(fs.isDir(`{main}/.worktrees/main`)).toBe(false)
		t.expect(countWorktrees()).toBe(before)
	end)

	it("start inside the worktree reuses the branch and pushes", function()
		startOut = must(tr(wt1, { "start", "R0010" }), "start")
		t.expect(git(wt1, { "branch", "--show-current" })).toBe("R0010-demo")
		t.expect(git(wt1, { "log", "-1", "--format=%s" })).toBe("tracker: start R0010 Demo")
		t.expect(git(wt1, { "rev-parse", "HEAD~1" })).toBe(git(main, { "rev-parse", "origin/main" }))
		t.expect(fs.isDir(`{wt1}/tracker/rafts/active/R0010`)).toBe(true)
		t.expect(git(origin, { "rev-parse", "R0010-demo" })).toBe(git(wt1, { "rev-parse", "HEAD" }))
		t.expect(git(main, { "branch", "--show-current" })).toBe("main")
	end)

	it("non-GitHub origin skips the draft PR", function()
		t.expect(string.find(startOut, "origin is not GitHub: skipped draft PR", 1, true) ~= nil).toBe(true)
	end)

	it("GitHub origin opens the draft PR", function()
		-- origin looks like GitHub for reads but pushes stay local; a fake gh records its arguments
		fs.writeDir(fakebin)
		fs.writeFile(
			fakebin .. "/gh",
			`#!/usr/bin/env bash\necho "$@" >> "{ghlog}"\necho https://github.com/x/y/pull/1\n`
		)
		must(process.exec("chmod", { "+x", fakebin .. "/gh" }), "chmod fake gh")
		git(main, { "remote", "set-url", "origin", "https://github.com/x/y.git" })
		git(main, { "remote", "set-url", "--push", "origin", origin })
		local env = { PATH = `{fakebin}:{process.env.PATH}`, GIT_TERMINAL_PROMPT = "0" }
		local r = run(wt2, "bash", { "scripts/tracker.sh", "start", "R0020" }, nil, env)
		git(main, { "remote", "set-url", "origin", origin })
		git(main, { "config", "--unset", "remote.origin.pushurl" })
		must(r, "start with a GitHub origin")
		local log = fs.readFile(ghlog)
		t.expect(string.find(log, "pr create", 1, true) ~= nil).toBe(true)
		t.expect(string.find(log, "--draft", 1, true) ~= nil).toBe(true)
	end)

	it("worktree branches from the fresh origin/main, not the invoking tree", function()
		-- someone else lands a commit: advance origin from a separate clone
		local other = `{base}/other`
		must(process.exec("git", { "clone", "-q", origin, other }), "clone other")
		identity(other)
		git(other, { "commit", "-q", "--allow-empty", "-m", "someone else" })
		git(other, { "push", "-q", "origin", "main" })
		local landed = string.match(git(main, { "ls-remote", origin, "refs/heads/main" }), "^(%x+)")
		-- wt2 has its own commit (start's); the main checkout's main is now stale
		local staleMain = git(main, { "rev-parse", "main" })
		local made = `{main}/.worktrees/capture-fresh`
		t.expect(must(tr(wt2, { "worktree", "capture-fresh" }), "worktree capture-fresh")).toBe(made)
		local head = git(made, { "rev-parse", "HEAD" })
		t.expect(head).toBe(landed)
		t.expect(head ~= git(wt2, { "rev-parse", "HEAD" })).toBe(true)
		t.expect(head ~= staleMain).toBe(true)
		git(main, { "pull", "-q", "--ff-only" }) -- keep the fixture's main in step for later pushes
	end)

	it("worktree creates a named worktree from origin/main", function()
		t.expect(must(tr(main, { "worktree", "capture-demo" }), "worktree capture-demo")).toBe(named)
		t.expect(git(named, { "branch", "--show-current" })).toBe("capture-demo")
		t.expect(git(named, { "rev-parse", "HEAD" })).toBe(git(main, { "rev-parse", "origin/main" }))
		t.expect(must(tr(main, { "worktree", "capture-demo" }), "again")).toBe(named)
		t.expect(git(main, { "status", "--porcelain" })).toBe("")
	end)

	it("new issue works in a named worktree", function()
		must(tr(named, { "new", "issue", "c", "probe" }), "new issue in a named worktree")
		t.expect(git(named, { "status", "--porcelain" }) ~= "").toBe(true)
		git(named, { "clean", "-fdq" })
		t.expect(git(named, { "status", "--porcelain" })).toBe("")
	end)

	it("duplicate ids are reported", function()
		-- the same id in two state directories
		must(
			process.exec(
				"cp",
				{ "-R", `{named}/tracker/issues/f0020`, `{named}/tracker/issues/active/f0020` }
			),
			"cp"
		)
		for _, args in { { "find", "f0020" }, { "list" } } do
			local r = tr(named, args)
			t.expect(r.ok).toBe(false)
			t.expect(string.find(r.stderr .. r.stdout, "f0020", 1, true) ~= nil).toBe(true)
		end
		git(named, { "clean", "-fdq" })
		t.expect(tr(named, { "find", "f0020" }).ok).toBe(true)
	end)

	it("a number shared by two prefixes is a warning", function()
		-- f0050 exists; a chore with the same number is harmless but worth a warning
		fs.writeDir(`{named}/tracker/issues/c0050`)
		fs.writeFile(
			`{named}/tracker/issues/c0050/c0050.md`,
			"---\nid: c0050\ntype: chore\ntitle: Twin\nslug: twin\n---\n"
		)
		local r = tr(named, { "list" })
		t.expect(r.ok).toBe(true)
		t.expect(string.find(r.stderr, "0050", 1, true) ~= nil).toBe(true)
		git(named, { "clean", "-fdq" })
		t.expect((string.find(tr(named, { "list" }).stderr, "warning", 1, true))).toBe(nil)
	end)

	it("worktree recreates a worktree whose directory was deleted", function()
		fs.removeDir(named)
		t.expect(must(tr(main, { "worktree", "capture-demo" }), "worktree after rm")).toBe(named)
		t.expect(fs.isDir(named)).toBe(true)
		t.expect(git(named, { "branch", "--show-current" })).toBe("capture-demo")
	end)

	it("worktree rejects bad names and non-raft ids", function()
		local before = countWorktrees()
		for _, bad in
			{ "Bad Name", "../x", "a/b", "UPPER", "f0010", "c0041", "-lead", "", string.rep("a", 61) }
		do
			local r = tr(main, { "worktree", bad })
			if r.ok then
				error(`worktree accepted {bad}`)
			end
		end
		local r = tr(main, { "worktree", "R9999" })
		t.expect(r.ok).toBe(false)
		t.expect(countWorktrees()).toBe(before)
	end)

	it("worktree-prune removes squash-merged done rafts and keeps unfinished ones", function()
		-- R0010 is done on its branch and squash-merged; R0030 is done only on its own pushed branch
		finishOnBranch(wt1, "R0010", "f0010", "active/")
		squashMerge("R0010-demo")
		must(tr(main, { "worktree", "R0030" }), "worktree R0030")
		finishOnBranch(wt3, "R0030", "f0030", "")

		must(tr(main, { "worktree-prune" }), "worktree-prune")
		t.expect(fs.isDir(wt1)).toBe(false)
		t.expect(git(main, { "branch", "--list", "R0010-demo" })).toBe("")
		t.expect(fs.isDir(wt2)).toBe(true)
		t.expect(git(main, { "branch", "--list", "R0020-other" }) ~= "").toBe(true)
	end)

	it("worktree-prune keeps a raft that is done only on its own unmerged branch", function()
		t.expect(fs.isDir(wt3)).toBe(true)
		t.expect(git(main, { "branch", "--list", "R0030-third" }) ~= "").toBe(true)
	end)

	it("worktree-prune lists a named worktree and leaves it", function()
		local r = tr(main, { "worktree-prune" })
		t.expect(r.ok).toBe(true)
		t.expect(string.find(r.stdout .. r.stderr, "capture-demo", 1, true) ~= nil).toBe(true)
		t.expect(fs.isDir(named)).toBe(true)
	end)

	it("worktree-prune never forces: a dirty finished worktree survives and the exit code is 1", function()
		must(tr(main, { "worktree", "R0040" }), "worktree R0040")
		finishOnBranch(wt4, "R0040", "f0040", "")
		squashMerge("R0040-fourth")
		fs.writeFile(`{wt4}/unsaved.txt`, "work in progress")
		local r = tr(main, { "worktree-prune" })
		t.expect(r.ok).toBe(false)
		t.expect(r.code).toBe(1)
		t.expect(string.find(r.stderr, "R0040-fourth", 1, true) ~= nil).toBe(true)
		t.expect(fs.isFile(`{wt4}/unsaved.txt`)).toBe(true)
		t.expect(git(main, { "branch", "--list", "R0040-fourth" }) ~= "").toBe(true)
	end)

	it("worktree-prune run from inside a finished worktree skips it", function()
		fs.removeFile(`{wt4}/unsaved.txt`)
		local r = tr(wt4, { "worktree-prune" })
		t.expect(r.ok).toBe(true)
		t.expect(fs.isDir(wt4)).toBe(true)
		-- from the main checkout the same worktree is removed
		must(tr(main, { "worktree-prune" }), "prune from main")
		t.expect(fs.isDir(wt4)).toBe(false)
		t.expect(git(main, { "branch", "--list", "R0040-fourth" })).toBe("")
	end)

	it("worktree refuses a done raft", function()
		local before = countWorktrees()
		local r = tr(main, { "worktree", "R0010" })
		t.expect(r.ok).toBe(false)
		t.expect(fs.isDir(wt1)).toBe(false)
		t.expect(countWorktrees()).toBe(before)
	end)

	it("post-edit hook lints with the edited file's worktree config", function()
		local hook = `{main}/scripts/hooks/post-edit.sh`
		local probe = "--!strict\nlocal unused = 1\nreturn nil\n"
		-- the worktree allows unused variables; the main checkout denies them
		fs.writeFile(`{wt2}/selene.toml`, 'std = "roblox"\n\n[rules]\nunused_variable = "allow"\n')
		fs.writeFile(`{main}/selene.toml`, 'std = "roblox"\n\n[rules]\nunused_variable = "deny"\n')
		fs.writeFile(`{wt2}/src/shared/Probe.luau`, probe)
		fs.writeFile(`{main}/src/shared/Probe.luau`, probe)
		local inWorktree = run(main, "bash", { hook }, editJson(`{wt2}/src/shared/Probe.luau`))
		local inMain = run(main, "bash", { hook }, editJson(`{main}/src/shared/Probe.luau`))
		fs.removeFile(`{wt2}/src/shared/Probe.luau`)
		fs.removeFile(`{main}/src/shared/Probe.luau`)
		git(wt2, { "checkout", "--", "selene.toml" })
		git(main, { "checkout", "--", "selene.toml" })
		t.expect(inWorktree.code).toBe(0)
		t.expect(inMain.code).toBe(2)
	end)

	it("post-edit hook ignores a file outside any repository", function()
		local hook = `{main}/scripts/hooks/post-edit.sh`
		local dir = must(process.exec("mktemp", { "-d" }), "mktemp")
		fs.writeFile(`{dir}/Probe.luau`, "--!strict\nlocal unused = 1\nreturn nil\n")
		local r = run(main, "bash", { hook }, editJson(`{dir}/Probe.luau`))
		fs.removeDir(dir)
		-- linted from the hook's own repo it would fail; outside a repo there is nothing to lint
		t.expect(r.code).toBe(0)
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

	it("stop hook gates the worktree root when cwd is a subdirectory", function()
		local hook = `{main}/scripts/hooks/stop.sh`
		fs.writeFile(`{wt2}/src/shared/Broken.luau`, "--!strict\nlocal = \n")
		local fromSubdir = run(main, "bash", { hook }, stopJson(`{wt2}/src/shared`))
		fs.removeFile(`{wt2}/src/shared/Broken.luau`)
		t.expect(fromSubdir.code).toBe(2)
	end)
end)
