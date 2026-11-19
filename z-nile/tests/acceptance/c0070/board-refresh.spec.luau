--!strict
-- c0760: a tracker push does not move the main checkout or rebuild its board. `./zn sync` fast-forwards the main
-- checkout and rebuilds the board (never opening a browser). `./zn ready` and `./zn stop` fast-forward it and do not.
-- Fixture under .cache/c0760-board: a seed with this
-- tree's tooling and skills, a bare origin, a main clone (the main checkout), a named worktree and a second clone.
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
-- c0120 override: the fixture lives under the home's .cache (the spec's working directory); root stays for reading
local base = `{trim(process.exec("pwd", { "-P" }).stdout)}/.cache/c0760-board`
-- c0178: the folders are the shared fixture's (trackerfix.new makes them in the setup case); there is no seed folder
local origin, main, other = `{base}/origin.git`, `{base}/main`, `{base}/other`
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
-- c0120 override: pickman's items live in pickman/.tracker (the fixtures' final layout)
local function c0010Check(s: string): string
	return HEAD
		.. `check "AC1: spec" test -f pickman/.tracker/issues/{s}c0010/acceptance/a.spec.luau\n`
		.. `check "AC2: sibling" test -f pickman/.tracker/issues/{s}c0020/c0020.md\n`
		.. "# untouched: pickman/.tracker/issues/c0090/c0090.md pickman/.tracker/issues/c00100\nfinish\n"
end
-- c0120 override: pickman's items live in pickman/.tracker (the fixtures' final layout)
local function r0010Check(s: string): string
	return HEAD
		.. `check "RC1: member" bash pickman/.tracker/issues/{s}c0010/check.sh\n# raft: pickman/.tracker/rafts/{s}R0010\nfinish\n`
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
		add(
			"pickman/.tracker/issues/c0020/c0020.md",
			issueDoc("c0020", "Loose", "", "", "draft", "new-a-b-c")
		)
		add("pickman/.tracker/issues/c0020/check.sh", simpleCheck("c0020", "issues", ""), true)
		-- c0178: one trackerfix.new replaces git init/add/commit, the bare origin and the main clone; its main clone is
		-- committed as <name> (the old setup's "t" identity is not pinned by a case)
		-- (`other`, the second clone, is made at the seed by the first helper that works in it)
		trackerfix.new("c0760-board", extras, {
			copy = { ".claude", ".luaurc", "pickman/.tracker/architecture.md" },
			executable = executable,
		})
		fs.writeDir(bin)
		for _, opener in { "open", "xdg-open" } do
			write(bin, opener, `#!/bin/sh\necho "$*" >> "{openLog}"\n`, true)
		end
		write(bin, "gh", "#!/bin/sh\necho gh is not available in this fixture >&2\nexit 1\n", true)
		write(bin, "pbcopy", "#!/bin/sh\ncat > /dev/null\n", true) -- never the real clipboard
		cap = trOk(main, { "worktree", "cap-a" })
		t.expect(board()).toBe(nil)
	end)

	it("a publish does not move the main checkout or rebuild its board; sync does both", function()
		-- c0120 override: pickman's items live in pickman/.tracker (the fixtures' final layout)
		local held = git(main, { "rev-parse", "HEAD" })
		local made = trOk(cap, { "new", "issue", "c", "zeta", "--project", "pickman" })
		local id = string.match(made, "(c%d%d%d%d)") :: string
		t.expect(git(main, { "rev-parse", "HEAD" })).toBe(held)
		t.expect(board()).toBe(nil)
		t.expect(fs.isFile(`{cap}/{BOARD}`)).toBe(false)
		trOk(main, { "sync" })
		t.expect(git(main, { "rev-parse", "HEAD" })).toBe(tip())
		-- c0120 override: pickman's items live in pickman/.tracker (the fixtures' final layout)
		t.expect(fs.isFile(`{main}/pickman/.tracker/issues/{id}/{id}.md`)).toBe(true)
		t.expect(has(board(), id)).toBe(true)
	end)

	it("sync's board equals a fresh build of the main checkout", function()
		current()
	end)

	it("status and new raft publish without rebuilding the board", function()
		local held = board()
		trOk(cap, { "status", "c0020", "preparing" })
		t.expect(board()).toBe(held)
		trOk(cap, { "status", "c0020", "new" })
		local made = trOk(cap, { "new", "issue", "c", "eta", "--project", "pickman" })
		local id = string.match(made, "(c%d%d%d%d)") :: string
		trOk(cap, { "new", "raft", "chore", "solo", id, "--single", "--project", "pickman" })
		t.expect(board()).toBe(held)
		trOk(main, { "sync" })
		current()
		t.expect(has(board(), "Solo")).toBe(true)
	end)

	it("ready and stop fast-forward the main checkout and do not rebuild the board", function()
		-- c0120 override: pickman's items live in pickman/.tracker (the fixtures' final layout)
		local held = board()
		trOk(main, { "ready", "R0010" })
		t.expect(onOrigin("pickman/.tracker/rafts/active/R0010/R0010.md") ~= nil).toBe(true)
		t.expect(git(main, { "rev-parse", "HEAD" })).toBe(tip())
		t.expect(board()).toBe(held)
		trOk(main, { "sync" })
		current()
		held = board()
		trOk(main, { "stop", "R0010" })
		t.expect(git(main, { "rev-parse", "HEAD" })).toBe(tip())
		t.expect(board()).toBe(held)
		trOk(main, { "sync" })
		current()
	end)

	it("sync in the main checkout rebuilds the board after another terminal's push", function()
		-- c0120 override: pickman's items live in pickman/.tracker (the fixtures' final layout)
		git(other, { "pull", "-q", "origin", "main" })
		-- c0120 override: pickman's items live in pickman/.tracker (the fixtures' final layout)
		write(
			other,
			"pickman/.tracker/issues/f0500/f0500.md",
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

	it("a publish leaves a main checkout that is not on main untouched", function()
		git(main, { "switch", "-q", "-c", "side" })
		local head = git(main, { "rev-parse", "HEAD" })
		local held = board()
		local r = tr(cap, { "new", "issue", "c", "theta", "--project", "pickman" })
		t.expect(r.ok).toBe(true)
		t.expect(has(r.stderr, "warning: board")).toBe(false)
		t.expect(git(main, { "rev-parse", "HEAD" })).toBe(head)
		t.expect(git(main, { "branch", "--show-current" })).toBe("side")
		t.expect(board()).toBe(held)
		git(main, { "switch", "-q", "main" })
		trOk(main, { "sync" })
		current()
	end)

	it("no refresh without publishing (PICKMAN_PUBLISH=0)", function()
		fs.removeFile(`{main}/{BOARD}`)
		local r = tr(cap, { "new", "issue", "c", "iota", "--project", "pickman" }, { PICKMAN_PUBLISH = "0" })
		t.expect(r.ok).toBe(true)
		t.expect(board()).toBe(nil)
		git(cap, { "clean", "-fdq", "pickman/.tracker" }) -- c0120 override: the new issue is under pickman/.tracker
	end)

	it("no browser is opened", function()
		t.expect(fs.isFile(openLog)).toBe(false)
	end)
end)
