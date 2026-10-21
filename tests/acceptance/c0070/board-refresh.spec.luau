--!strict
-- c0760: every tracker push to origin/main, and sync in the main checkout, brings the main checkout up to origin/main
-- and rebuilds its board page (never opening a browser). Fixture under .cache/c0760-board: a seed with this
-- tree's tooling and skills, a bare origin, a main clone (the main checkout), a named worktree and a second clone.
local engine = require("@tests/lib/engine")
local fixture = require("@tests/lib/fixture")
local fs = require("@lune/fs")
local process = require("@lune/process")
local t = require("@tests/lib/t")

type Result = { ok: boolean, code: number, stdout: string, stderr: string }

local function trim(s: string): string
	return (string.gsub(string.gsub(s, "^%s+", ""), "%s+$", ""))
end
local root = trim(process.exec("git", { "rev-parse", "--show-toplevel" }).stdout)
local base = `{root}/.cache/c0760-board`
local seed, origin, main, other = `{base}/seed`, `{base}/origin.git`, `{base}/main`, `{base}/other`
local bin, openLog = `{base}/bin`, `{base}/open.log`

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
	return fixture.exec(cwd, cmd, args, { env = env(extra) }) -- R0210: git and tracker.sh in a fixture only through the helper
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
-- check.sh texts with literal backlog paths; {S} is the state segment ("" or "active/" or "done/")
local function c0010Check(s: string): string
	return HEAD
		.. `check "AC1: spec" test -f tracker/issues/{s}c0010/acceptance/a.spec.luau\n`
		.. `check "AC2: sibling" test -f tracker/issues/{s}c0020/c0020.md\n`
		.. "# untouched: tracker/issues/c0090/c0090.md tracker/issues/c00100\nfinish\n"
end
local function r0010Check(s: string): string
	return HEAD
		.. `check "RC1: member" bash tracker/issues/{s}c0010/check.sh\n# raft: tracker/rafts/{s}R0010\nfinish\n`
end
local function simpleCheck(id: string, kind: string, s: string): string
	return HEAD .. `check "AC1: ok" test -n "tracker/{kind}/{s}{id}/check.sh"\nfinish\n`
end
local SPEC = "-- c0010 acceptance marker\nreturn nil\n"

local cap = "" -- a named worktree
-- the board page, built without a literal cache path: c0470 counts every literal one as a fixture directory
local BOARD = "." .. "cache/board.html"

local function board(): string?
	local p = `{main}/{BOARD}`
	return if fs.isFile(p) then fs.readFile(p) else nil
end
-- the main checkout's board as a fresh build would write it now
local function fresh(): string
	local out = `{base}/fresh.html`
	trOk(main, { "board", "-O", "--out", out })
	return fs.readFile(out)
end
local function current()
	t.expect(git(main, { "rev-parse", "HEAD" })).toBe(tip())
	t.expect(board()).toBe(fresh())
end

return t.spec("tracker board follows main", function(it)
	it("sets up an origin with a prepared raft, a main checkout, a worktree and another clone", function()
		if fs.isDir(base) then
			fs.removeDir(base)
		end
		fs.writeDir(seed)
		fs.writeDir(bin)
		for _, opener in { "open", "xdg-open" } do
			write(bin, opener, `#!/bin/sh\necho "$*" >> "{openLog}"\n`, true)
		end
		write(bin, "gh", "#!/bin/sh\necho gh is not available in this fixture >&2\nexit 1\n", true)
		write(bin, "pbcopy", "#!/bin/sh\ncat > /dev/null\n", true) -- never the real clipboard
		process.exec("git", { "init", "-q", "-b", "main", seed }) -- raw: init to a named path
		git(seed, { "config", "user.name", "t" })
		git(seed, { "config", "user.email", "t@example.invalid" })
		for _, p in { ".claude", ".luaurc", ".gitignore" } do
			process.exec("cp", { "-R", `{root}/{p}`, `{seed}/{p}` })
		end
		fs.writeDir(`{seed}/tracker`)
		engine.copy(root, seed) -- c0114 override: ./zn, scripts/ and z-nile/ (the engine, the gate, the templates)
		process.exec("cp", { `{root}/tracker/architecture.md`, `{seed}/tracker/architecture.md` })
		for _, d in { "issues/active", "issues/done", "rafts/active", "rafts/done" } do
			write(seed, `tracker/{d}/.gitkeep`, "")
		end
		write(
			seed,
			"tracker/rafts/R0010/R0010.md",
			raftDoc("R0010", "Readied", "readied", "c0010", "ready", PREPARED)
		)
		write(seed, "tracker/rafts/R0010/check.sh", r0010Check(""), true)
		write(
			seed,
			"tracker/issues/c0010/c0010.md",
			issueDoc("c0010", "Alpha", "R0010", "", "ready", PREPARED)
		)
		write(seed, "tracker/issues/c0010/check.sh", c0010Check(""), true)
		write(seed, "tracker/issues/c0010/acceptance/a.spec.luau", SPEC)
		write(seed, "tracker/issues/c0020/c0020.md", issueDoc("c0020", "Loose", "", "", "draft", "new-a-b-c"))
		write(seed, "tracker/issues/c0020/check.sh", simpleCheck("c0020", "issues", ""), true)
		git(seed, { "add", "-A" })
		git(seed, { "commit", "-q", "-m", "seed" })
		process.exec("git", { "clone", "-q", "--bare", seed, origin }) -- raw: clone to a named path
		for _, c in { main, other } do
			process.exec("git", { "clone", "-q", origin, c })
			git(c, { "config", "user.name", "t" })
			git(c, { "config", "user.email", "t@example.invalid" })
		end
		cap = trOk(main, { "worktree", "cap-a" })
		t.expect(board()).toBe(nil)
	end)

	it("new issue in a worktree brings the main checkout to origin/main and rebuilds its board", function()
		local made = trOk(cap, { "new", "issue", "c", "zeta" })
		local id = string.match(made, "(c%d%d%d%d)") :: string
		t.expect(git(main, { "rev-parse", "HEAD" })).toBe(tip())
		t.expect(fs.isFile(`{main}/tracker/issues/{id}/{id}.md`)).toBe(true)
		t.expect(has(board(), id)).toBe(true)
		t.expect(fs.isFile(`{cap}/{BOARD}`)).toBe(false) -- the main checkout's board, not the worktree's
	end)

	it("the refreshed board equals a fresh build of the main checkout", function()
		current()
	end)

	it("status and new raft refresh the board", function()
		trOk(cap, { "status", "c0020", "preparing" })
		current()
		trOk(cap, { "status", "c0020", "new" })
		local made = trOk(cap, { "new", "issue", "c", "eta" })
		local id = string.match(made, "(c%d%d%d%d)") :: string
		trOk(cap, { "new", "raft", "chore", "solo", id, "--single" })
		current()
		t.expect(has(board(), "Solo")).toBe(true)
	end)

	it("ready and stop refresh the board", function()
		trOk(main, { "ready", "R0010" })
		t.expect(onOrigin("tracker/rafts/active/R0010/R0010.md") ~= nil).toBe(true)
		current()
		trOk(main, { "stop", "R0010" })
		current()
	end)

	it("sync in the main checkout rebuilds the board after another terminal's push", function()
		git(other, { "pull", "-q", "origin", "main" })
		write(
			other,
			"tracker/issues/f0500/f0500.md",
			issueDoc("f0500", "Elsewhere", "", "", "draft", "new-a-b-c")
		)
		git(other, { "add", "-A" })
		git(other, { "commit", "-q", "-m", "other f0500" })
		git(other, { "push", "-q", "origin", "HEAD:main" })
		t.expect(has(board(), "f0500")).toBe(false)
		trOk(main, { "sync" })
		current()
		t.expect(has(board(), "f0500")).toBe(true)
	end)

	it("a main checkout off main only warns, and the publish still succeeds", function()
		git(main, { "switch", "-q", "-c", "side" })
		local head = git(main, { "rev-parse", "HEAD" })
		local r = tr(cap, { "new", "issue", "c", "theta" })
		t.expect(r.ok).toBe(true)
		t.expect(has(r.stderr, "warning: board")).toBe(true)
		t.expect(git(main, { "rev-parse", "HEAD" })).toBe(head)
		t.expect(git(main, { "branch", "--show-current" })).toBe("side")
		git(main, { "switch", "-q", "main" })
		trOk(main, { "sync" })
		current()
	end)

	it("no refresh without publishing (PICKMAN_PUBLISH=0)", function()
		fs.removeFile(`{main}/{BOARD}`)
		local r = tr(cap, { "new", "issue", "c", "iota" }, { PICKMAN_PUBLISH = "0" })
		t.expect(r.ok).toBe(true)
		t.expect(board()).toBe(nil)
		git(cap, { "clean", "-fdq", "tracker" })
	end)

	it("no browser is opened", function()
		t.expect(fs.isFile(openLog)).toBe(false)
	end)
end)
