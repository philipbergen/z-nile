--!strict
-- c0440: `tracker.sh launch` starts a command inside the target's worktree, and `worktree-prune` flags
-- worktrees outside .worktree/. A fake agent on PATH records its working directory and arguments.
-- Fixture under .cache/launch-e2e: a seed clone of the repo (no origin, `main` forced, the working
-- tree's tooling overlaid, tracker emptied) with raft R0010, a done raft R0020 and issues f0010,
-- f0020; then a bare origin and a clone `main/`.
local clone = require("@tests/lib/clone")
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
local base = `{root}/.cache/launch-e2e`
local seed = `{base}/seed`
local origin = `{base}/origin.git`
local main = `{base}/main`
local fakebin = `{base}/fakebin`
local log = `{base}/agent.log`
local fakehome = `{base}/fakehome`
local wt1 = `{main}/.worktree/R0010`
local named = `{main}/.worktree/capture-demo`
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
	local opts: any = { cwd = cwd, env = merged }
	if stdin then
		opts.stdio = { stdin = stdin }
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

local function tr(cwd: string, args: { string }, env: { [string]: string }?, stdin: string?): Result
	return run(cwd, "bash", { "scripts/tracker.sh", table.unpack(args) }, env, stdin)
end

local function has(text: string, needle: string): boolean
	return string.find(text, needle, 1, true) ~= nil
end

-- The environment that puts the fake agents first on PATH.
local function agentEnv(exitCode: string?): { [string]: string }
	return {
		PATH = `{fakebin}:{process.env.PATH}`,
		FAKE_LOG = log,
		FAKE_EXIT = exitCode or "0",
	}
end

-- A fake `lune` first on the wrapper's PATH (it puts $HOME/.rokit/bin first): it stands in for the
-- worktree step and prints whatever FAKE_LUNE asks for.
local function badWorktreeEnv(mode: string): { [string]: string }
	local env = agentEnv()
	env.HOME = fakehome
	env.FAKE_LUNE = mode
	return env
end

-- What the last fake agent run recorded: its physical working directory, then one line per argument.
local function recorded(): { string }
	local lines = string.split(fs.readFile(log), "\n")
	if lines[#lines] == "" then
		table.remove(lines)
	end
	return lines
end

local function countWorktrees(): number
	local _, n = string.gsub(git(main, { "worktree", "list", "--porcelain" }), "worktree ", "")
	return n
end

return t.spec("launch", function(it)
	it("launch runs the command inside the raft's worktree", function()
		if fs.isDir(base) then
			fs.removeDir(base)
		end
		fs.writeDir(base)
		clone.isolated(root, seed)
		git(seed, { "config", "user.name", "e2e" })
		git(seed, { "config", "user.email", "e2e@example.invalid" })
		git(seed, { "checkout", "-q", "-B", "main" })
		git(seed, { "remote", "remove", "origin" })
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
		for _, kind in { "issues", "rafts" } do
			for _, state in { "", "active/", "done/" } do
				local dir = `{seed}/tracker/{kind}/{state}`
				if fs.isDir(dir) then
					for _, name in fs.readDir(dir) do
						if string.match(name, "^[fdcR]%d%d%d%d$") then
							fs.removeDir(dir .. name)
						end
					end
				end
			end
		end
		must(tr(seed, { "new", "issue", "f", "alpha" }), "new f0010")
		must(tr(seed, { "new", "issue", "f", "beta" }), "new f0020")
		must(tr(seed, { "new", "raft", "feature", "demo", "f0010" }), "raft demo")
		must(tr(seed, { "new", "raft", "feature", "old", "f0020" }), "raft old")
		-- R0020 is finished
		git(seed, { "add", "-A" })
		git(seed, { "commit", "-qm", "fixture" })
		fs.writeDir(`{seed}/tracker/rafts/done`)
		fs.writeDir(`{seed}/tracker/issues/done`)
		git(seed, { "mv", "tracker/rafts/R0020", "tracker/rafts/done/R0020" })
		git(seed, { "mv", "tracker/issues/f0020", "tracker/issues/done/f0020" })
		git(seed, { "commit", "-qm", "R0020 is done" })
		must(process.exec("git", { "clone", "-q", "--bare", seed, origin }), "bare origin")
		must(process.exec("git", { "clone", "-q", origin, main }), "clone main")
		git(main, { "config", "user.name", "e2e" })
		git(main, { "config", "user.email", "e2e@example.invalid" })
		-- two fake agents: they record where and how they were run
		fs.writeDir(fakebin)
		for _, name in { "claude", "agent" } do
			fs.writeFile(
				`{fakebin}/{name}`,
				'#!/usr/bin/env bash\n{ pwd -P; for a in "$@"; do echo "$a"; done; if [ -n "${FAKE_READ:-}" ]; then read -r line; echo "stdin:$line"; fi; } > "$FAKE_LOG"\nexit "${FAKE_EXIT:-0}"\n'
			)
			must(process.exec("chmod", { "+x", `{fakebin}/{name}` }), "chmod")
		end

		fs.writeDir(`{fakehome}/.rokit/bin`)
		fs.writeFile(
			`{fakehome}/.rokit/bin/lune`,
			'#!/usr/bin/env bash\ncase "${FAKE_LUNE:-}" in\n  empty) exit 0 ;;\n  multi) printf "a warning line\\n/somewhere/else\\n"; exit 0 ;;\n  rel) echo .; exit 0 ;;\n  *) exit 99 ;;\nesac\n'
		)
		must(process.exec("chmod", { "+x", `{fakehome}/.rokit/bin/lune` }), "chmod fake lune")

		local r = tr(main, { "launch", "R0010", "--", "agent" }, agentEnv())
		must(r, "launch R0010")
		t.expect(recorded()).toEqual({ wt1 })
		t.expect(git(wt1, { "branch", "--show-current" })).toBe("R0010-demo")
		-- a second launch reuses the worktree
		local before = countWorktrees()
		must(tr(main, { "launch", "R0010", "--", "agent" }, agentEnv()), "launch again")
		t.expect(countWorktrees()).toBe(before)
		t.expect(recorded()).toEqual({ wt1 })
	end)

	it("launch defaults to claude and passes arguments after -- through untouched", function()
		must(tr(main, { "launch", "capture-demo" }, agentEnv()), "launch capture-demo")
		t.expect(recorded()).toEqual({ named }) -- the default command, no arguments
		-- options, an argument with spaces, an empty string, a glob, a quoted string and a second --
		local awkward = { "--from", "origin/main", "a b", "", "*", '"q"', "--", "y" }
		local args = { "launch", "capture-demo", "--", "agent" }
		for _, a in awkward do
			table.insert(args, a)
		end
		must(tr(main, args, agentEnv()), "launch with arguments")
		local want = { named }
		for _, a in awkward do
			table.insert(want, a)
		end
		t.expect(recorded()).toEqual(want)
	end)

	it("launch forwards stdin to the command", function()
		local env = agentEnv()
		env.FAKE_READ = "1"
		must(tr(main, { "launch", "capture-demo", "--", "agent" }, env, "hello\n"), "launch with stdin")
		t.expect(recorded()).toEqual({ named, "stdin:hello" })
	end)

	it("launch returns the command's exit code and reports a command that can't start", function()
		local seven = tr(main, { "launch", "capture-demo", "--", "agent" }, agentEnv("7"))
		t.expect(seven.code).toBe(7)
		local missing = tr(main, { "launch", "capture-demo", "--", "no-such-agent-xyz" }, agentEnv())
		t.expect(missing.ok).toBe(false)
		t.expect(has(missing.stderr, "cannot run no-such-agent-xyz")).toBe(true)
		-- a typo in the command must not leave a worktree behind
		local typo = tr(main, { "launch", "capture-typo", "--", "no-such-agent-xyz" }, agentEnv())
		t.expect(typo.ok).toBe(false)
		t.expect(fs.isDir(`{main}/.worktree/capture-typo`)).toBe(false)
	end)

	it("launch rejects an unknown target, a done raft, a stray argument or a bad command", function()
		local before = countWorktrees()
		if fs.isFile(log) then
			fs.removeFile(log)
		end
		for _, target in { "R9999", "Bad_Name", "f0010", "R0020" } do
			local r = tr(main, { "launch", target, "--", "agent" }, agentEnv())
			if r.ok then
				error(`launch accepted {target}`)
			end
		end
		-- a token after the target that isn't -- is a usage error, not a command
		t.expect(tr(main, { "launch", "R0010", "agent" }, agentEnv()).ok).toBe(false)
		t.expect(tr(main, { "launch" }, agentEnv()).ok).toBe(false)
		-- an empty command and a relative command are refused; so is a file that isn't executable
		t.expect(tr(main, { "launch", "capture-demo", "--", "" }, agentEnv()).ok).toBe(false)
		-- a relative command that exists would mean the repo root before the cd and the worktree after it
		fs.writeFile(`{main}/relagent`, fs.readFile(`{fakebin}/agent`))
		must(process.exec("chmod", { "+x", `{main}/relagent` }), "chmod relagent")
		local relative = tr(main, { "launch", "capture-demo", "--", "./relagent" }, agentEnv())
		t.expect(relative.ok).toBe(false)
		t.expect(has(relative.stderr, "absolute path")).toBe(true)
		fs.removeFile(`{main}/relagent`)
		t.expect(tr(main, { "launch", "capture-demo", "--", "/etc/hosts" }, agentEnv()).ok).toBe(false)
		t.expect(fs.isFile(log)).toBe(false) -- nothing ran
		t.expect(countWorktrees()).toBe(before)
		t.expect(fs.isDir(`{main}/.worktree/R0020`)).toBe(false)
	end)

	it("launch stops when the worktree step returns no usable path", function()
		-- nothing, several lines, or a relative path: the agent must not run, anywhere
		for _, mode in { "empty", "multi", "rel" } do
			if fs.isFile(log) then
				fs.removeFile(log)
			end
			local r = tr(main, { "launch", "capture-demo", "--", "agent" }, badWorktreeEnv(mode))
			if r.ok then
				error(`launch went ahead on a {mode} worktree path`)
			end
			t.expect(has(r.stderr, "no usable worktree path")).toBe(true)
			t.expect(fs.isFile(log)).toBe(false)
		end
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
