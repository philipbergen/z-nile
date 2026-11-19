--!strict
-- c0750: `tracker.sh prompt <R>` reads a readied raft's prompt.md from the main checkout (the launch-raft skill's
-- input), and `tracker.sh launch` is gone. Fixture under .cache/c0750-prompt: a seed with this tree's tooling and
-- skills, a bare origin, a main clone (the main checkout), a named worktree. A recording `claude` is first on PATH.
local fixture = require("@tests/lib/fixture")
local fs = require("@lune/fs")
local process = require("@lune/process")
local t = require("@tests/lib/t")
local trackerfix = require("@tests/lib/trackerfix")

type Result = { ok: boolean, code: number, stdout: string, stderr: string }

local function trim(s: string): string
	return (string.gsub(string.gsub(s, "^%s+", ""), "%s+$", ""))
end
local root = trim(process.exec("git", { "rev-parse", "--show-toplevel" }).stdout)
-- c0120 override: fixtures live under the home's .cache (z-nile/.cache); root stays the checkout to copy from
local base = `{trim(process.exec("pwd", { "-P" }).stdout)}/.cache/c0750-prompt`
-- c0178: the folders are the shared fixture's (trackerfix.new makes them in the setup case); there is no seed folder
local origin, main = `{base}/origin.git`, `{base}/main`
local bin, agentLog = `{base}/bin`, `{base}/claude.log`

local function env(extra: { [string]: string }?): { [string]: string }
	local out = {
		PATH = `{bin}:{process.env.PATH or ""}`,
	}
	if extra then
		for k, v in extra do
			out[k] = v
		end
	end
	return out
end
local function run(cwd: string, cmd: string, args: { string }, extra: { [string]: string }?): Result
	return fixture.exec(cwd, cmd, args, { env = env(extra) }) -- R0210: git and ./zn in a fixture only through the helper
end
local function git(cwd: string, args: { string }): string
	local r = run(cwd, "git", args)
	if not r.ok then
		error(`git {table.concat(args, " ")} failed: {r.stderr}{r.stdout}`, 2)
	end
	return trim(r.stdout)
end
local function tr(cwd: string, args: { string }, extra: { [string]: string }?): Result
	return run(cwd, "bash", { "scripts/tracker.sh", table.unpack(args) }, extra)
end
local function trOk(cwd: string, args: { string }): string
	local r = tr(cwd, args)
	if not r.ok then
		error(`tracker.sh {table.concat(args, " ")} failed ({r.code}): {r.stderr}{r.stdout}`, 2)
	end
	return trim(r.stdout)
end
local function has(text: string?, needle: string): boolean
	return text ~= nil and string.find(text, needle, 1, true) ~= nil
end
local function onOrigin(path: string): string?
	local r = run(origin, "git", { "show", `main:{path}` })
	return if r.ok then r.stdout else nil
end
local function tip(): string
	return git(origin, { "rev-parse", "main" })
end
local function write(dir: string, path: string, text: string, exec: boolean?)
	local full = `{dir}/{path}`
	fs.writeDir(string.match(full, "^(.*)/[^/]+$") :: string)
	fs.writeFile(full, text)
	if exec then
		process.exec("chmod", { "+x", full })
	end
end

local PREPARED = "prepared-quiet-copper-falcon"
local function issueDoc(
	id: string,
	title: string,
	raft: string,
	deps: string,
	design: string,
	status: string
): string
	return `---\nid: {id}\ntype: chore\ntitle: {title}\nslug: {string.lower(title)}\nraft: {raft}\ndepends_on: [{deps}]\nemergent: false\ndesign: {design}\ncreated: 2026-10-03\nstatus: {status}\n---\n\n# {id}: {title}\n\n## Problem\nMarker {title}.\n`
end
local function raftDoc(
	id: string,
	title: string,
	slug: string,
	issues: string,
	design: string,
	status: string
): string
	return `---\nid: {id}\ntype: chore\ntitle: {title}\nslug: {slug}\nsingle: false\nissues: [{issues}]\ndesign: {design}\ncreated: 2026-10-03\nstatus: {status}\n---\n\n# {id}: {title}\n\n## Theme\nMarker {title}.\n`
end
local HEAD =
	'#!/usr/bin/env bash\nsource "$(git -C "$(dirname "${BASH_SOURCE[0]}")" rev-parse --show-toplevel)/scripts/lib/ac.sh"\n'
-- c0120 override: pickman's items live in pickman/.tracker (the fixtures' final layout)
-- check.sh texts with literal backlog paths; {S} is the state segment ("" or "active/" or "done/")
local function c0010Check(s: string): string
	-- c0120 override: pickman's items live in pickman/.tracker (the fixtures' final layout)
	return HEAD
		.. `check "AC1: spec" test -f pickman/.tracker/issues/{s}c0010/acceptance/a.spec.luau\n`
		.. `check "AC2: sibling" test -f pickman/.tracker/issues/{s}c0020/c0020.md\n`
		.. "# untouched: pickman/.tracker/issues/c0090/c0090.md pickman/.tracker/issues/c00100\nfinish\n"
end
local function r0010Check(s: string): string
	-- c0120 override: pickman's items live in pickman/.tracker (the fixtures' final layout)
	return HEAD
		.. `check "RC1: member" bash pickman/.tracker/issues/{s}c0010/check.sh\n# raft: pickman/.tracker/rafts/{s}R0010\nfinish\n`
end
local function simpleCheck(id: string, kind: string, s: string): string
	return HEAD .. `check "AC1: ok" test -n "tracker/{kind}/{s}{id}/check.sh"\nfinish\n`
end
local SPEC = "-- c0010 acceptance marker\nreturn nil\n"

local cap = "" -- a named worktree
local promptFile = ""

return t.spec("tracker prompt", function(it)
	it("sets up an origin with a readied and a prepared raft", function()
		-- c0120 override: pickman's items live in pickman/.tracker (the fixtures' final layout)
		-- c0178: the item documents are collected and written over the shared fixture (trackerfix.new) below, which
		-- replaces the hand-built seed repository (git init, engine.copy, the copied .claude/.luaurc/.gitignore/architecture.md,
		-- engine.roots' folders, the seed commit and the bare/main clones)
		local extras: { [string]: string } = {}
		local executable: { string } = {}
		local function add(path: string, text: string, exec: boolean?)
			extras[path] = text
			if exec then
				table.insert(executable, path)
			end
		end
		-- c0178: the checkout's real .gitignore stays the fixture's (the default is only ".cache/" and ".worktree/")
		extras[".gitignore"] = fs.readFile(`{root}/.gitignore`)
		-- c0120 override: pickman's items live in pickman/.tracker (the fixtures' final layout)
		add(
			"pickman/.tracker/rafts/R0010/R0010.md",
			raftDoc("R0010", "Readied", "readied", "c0010", "ready", PREPARED)
		)
		-- c0120 override: pickman's items live in pickman/.tracker (the fixtures' final layout)
		add("pickman/.tracker/rafts/R0010/check.sh", r0010Check(""), true)
		-- c0120 override: pickman's items live in pickman/.tracker (the fixtures' final layout)
		add(
			"pickman/.tracker/issues/c0010/c0010.md",
			issueDoc("c0010", "Alpha", "R0010", "", "ready", PREPARED)
		)
		-- c0120 override: pickman's items live in pickman/.tracker (the fixtures' final layout)
		add("pickman/.tracker/issues/c0010/check.sh", c0010Check(""), true)
		add("pickman/.tracker/issues/c0010/acceptance/a.spec.luau", SPEC)
		-- c0120 override: pickman's items live in pickman/.tracker (the fixtures' final layout)
		add(
			"pickman/.tracker/rafts/R0020/R0020.md",
			raftDoc("R0020", "Waiting", "waiting", "c0020", "ready", PREPARED)
		)
		-- c0120 override: pickman's items live in pickman/.tracker (the fixtures' final layout)
		add("pickman/.tracker/rafts/R0020/check.sh", simpleCheck("R0020", "rafts", ""), true)
		-- c0120 override: pickman's items live in pickman/.tracker (the fixtures' final layout)
		add(
			"pickman/.tracker/issues/c0020/c0020.md",
			issueDoc("c0020", "Beta", "R0020", "", "ready", PREPARED)
		)
		-- c0120 override: pickman's items live in pickman/.tracker (the fixtures' final layout)
		add("pickman/.tracker/issues/c0020/check.sh", simpleCheck("c0020", "issues", ""), true)
		-- c0178: one trackerfix.new replaces git init/add/commit, the bare origin and the main clone; its main clone is
		-- committed as <name> (the old setup's "t" identity is not pinned by a case)
		trackerfix.new("c0750-prompt", extras, {
			copy = { ".claude", ".luaurc", "pickman/.tracker/architecture.md" },
			executable = executable,
		})
		fs.writeDir(bin)
		write(bin, "claude", `#!/bin/sh\necho "$PWD $*" >> "{agentLog}"\n`, true)
		write(bin, "gh", "#!/bin/sh\necho gh is not available in this fixture >&2\nexit 1\n", true)
		write(bin, "pbcopy", "#!/bin/sh\ncat > /dev/null\n", true) -- never the real clipboard
		cap = trOk(main, { "worktree", "cap-a" })
		trOk(main, { "ready", "R0010" })
		-- c0120 override: pickman's items live in pickman/.tracker (the fixtures' final layout)
		promptFile =
			`{git(main, { "rev-parse", "--show-toplevel" })}/pickman/.tracker/rafts/active/R0010/prompt.md`
		t.expect(fs.isFile(promptFile)).toBe(true)
		-- c0120 override: pickman's items live in pickman/.tracker (the fixtures' final layout)
		t.expect(onOrigin("pickman/.tracker/rafts/active/R0010/R0010.md") ~= nil).toBe(true)
		trOk(cap, { "sync" })
	end)

	it("prompt refuses a raft that is not readied and names ready-raft", function()
		-- c0120 override: pickman's items live in pickman/.tracker (the fixtures' final layout)
		-- even with a stale prompt.md left for it in the main checkout: origin/main decides
		local stale = `{main}/pickman/.tracker/rafts/active/R0020`
		write(main, "pickman/.tracker/rafts/active/R0020/prompt.md", "stale prompt\n")
		for _, cwd in { main, cap } do
			local r = tr(cwd, { "prompt", "R0020" })
			t.expect(r.ok).toBe(false)
			t.expect(has(r.stderr, "/z-ready")).toBe(true)
			t.expect(r.stdout).toBe("")
		end
		fs.removeDir(stale)
	end)

	it(
		"prompt prints the readied raft's prompt.md exactly, from the main checkout and from a worktree",
		function()
			local want = fs.readFile(promptFile)
			t.expect(has(want, "Marker Readied.")).toBe(true)
			for _, cwd in { main, cap } do
				local r = tr(cwd, { "prompt", "R0010" })
				t.expect(r.ok).toBe(true)
				t.expect(r.stdout).toBe(want)
			end
		end
	)

	it("prompt --path prints the absolute path of prompt.md", function()
		for _, cwd in { main, cap } do
			t.expect(trOk(cwd, { "prompt", "R0010", "--path" })).toBe(promptFile)
		end
	end)

	it("prompt writes nothing", function()
		-- c0120 override: pickman's items live in pickman/.tracker (the fixtures' final layout)
		local before = {
			git(main, { "status", "--porcelain", "--ignored", "--", "pickman/.tracker" }),
			fs.readFile(promptFile),
			tip(),
		}
		trOk(cap, { "prompt", "R0010" })
		trOk(main, { "prompt", "R0010", "--path" })
		-- c0120 override: pickman's files live in pickman/ (its home)
		t.expect({
			git(main, { "status", "--porcelain", "--ignored", "--", "pickman/.tracker" }),
			fs.readFile(promptFile),
			tip(),
		}).toEqual(before)
		t.expect(git(cap, { "status", "--porcelain" })).toBe("")
		-- c0120 override: pickman's items live in pickman/.tracker (the fixtures' final layout)
		t.expect(fs.isFile(`{cap}/pickman/.tracker/rafts/active/R0010/prompt.md`)).toBe(false)
	end)

	it("prompt refuses a missing prompt.md and names ready", function()
		fs.removeFile(promptFile)
		local r = tr(cap, { "prompt", "R0010" })
		t.expect(r.ok).toBe(false)
		t.expect(has(r.stderr, "./zn ready")).toBe(true)
		t.expect(fs.isFile(promptFile)).toBe(false) -- the reader never regenerates
		trOk(main, { "ready", "R0010" })
		t.expect(fs.isFile(promptFile)).toBe(true)
	end)

	it("prompt takes only a raft id", function()
		local before = tip()
		local r = tr(main, { "prompt", "c0010" })
		t.expect(r.ok).toBe(false)
		t.expect(has(r.stderr, "raft id")).toBe(true)
		t.expect(tip()).toBe(before)
		t.expect(git(main, { "status", "--porcelain" })).toBe("")
	end)

	it("./zn launch is gone and starts nothing", function()
		local r = tr(main, { "launch", "R0010" })
		t.expect(r.ok).toBe(false)
		local withCmd = tr(main, { "launch", "R0010", "--", "claude", "x" })
		t.expect(withCmd.ok).toBe(false)
		t.expect(fs.isFile(agentLog)).toBe(false)
		t.expect(fs.isDir(`{main}/.worktree/R0010`)).toBe(false)
		local usage = tr(main, {})
		t.expect(has(usage.stdout .. usage.stderr, "launch")).toBe(false)
		t.expect(has(usage.stdout .. usage.stderr, "prompt <R-id> [--path]")).toBe(true)
	end)
end)
