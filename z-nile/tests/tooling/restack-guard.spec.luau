--!strict
-- d0434 (design review 001, F4 to F6): the fast guard of `./zn restack` on main. Three layers in real git, in the
-- fixture .cache/restack-guard (a bare origin and a worktree for R0010), every case from the same start:
--   M0 <- A1 (R0010/1/c0010: alpha.luau, shared.luau "one") <- B1 (R0010/2/c0020: beta.luau, shared.luau "two")
--      <- C1 (R0010/3/c0030: gamma.luau)
-- `--abort` puts a pushed layer that was rebased again back on the tip it pushed, whichever layer the run started on;
-- `--continue` refuses a layer that is no longer where the run left it (and goes on over a fix on top of it); a refused
-- push names the way on, and a plain restack over the stopped run's marker keeps that run's record, so the way on still
-- works. The ticket's own acceptance spec holds every other rule.
local fixture = require("@tests/lib/fixture")
local fs = require("@lune/fs")
local process = require("@lune/process")
local t = require("@tests/lib/t")
local trackerfix = require("@tests/lib/trackerfix")

local TOP = (string.gsub(process.exec("git", { "rev-parse", "--show-toplevel" }).stdout, "%s+$", ""))
local PREPARED = "prepared-quiet-copper-falcon"
local HEAD =
	'source "$(git -C "$(dirname "${BASH_SOURCE[0]}")" rev-parse --show-toplevel)/scripts/lib/ac.sh"\n'
local CHECK = HEAD .. 'check "AC1: ok" true\nfinish\n'
local CHECK_POISON1 = HEAD .. 'check "AC1: no poison1" test ! -f src/poison1.luau\nfinish\n'
local CAPTURED =
	"## Problem\nThe marker is missing.\n\n## Solution\nStore the marker.\n\n## Acceptance criteria\n- AC1: the marker is stored\n"
local L1, L2, L3 = "R0010/1/c0010", "R0010/2/c0020", "R0010/3/c0030"
local SHARED = "pickman/src/shared.luau"
local BETA = "pickman/src/beta.luau"

local f: trackerfix.Fixture = nil :: any
local wt = ""
local env: { [string]: string } = {}
local base: { [string]: string } = {}
local M0, MAIN0 = "", ""

local function git(dir: string, args: { string }): string
	return fixture.git(dir, args)
end

local function has(s: string, part: string): boolean
	return string.find(s, part, 1, true) ~= nil
end

local function say(r: fixture.Result): string
	return r.stderr .. r.stdout
end

local function zn(args: { string }): fixture.Result
	return trackerfix.tr(f, wt, args, env)
end

local function write(dir: string, path: string, text: string)
	local parent = string.match(path, "^(.*)/[^/]+$")
	if parent then
		fs.writeDir(`{dir}/{parent}`)
	end
	fs.writeFile(`{dir}/{path}`, text)
end

local function commit(dir: string, path: string, text: string, message: string): string
	write(dir, path, text)
	git(dir, { "add", "-A" })
	git(dir, { "commit", "-qm", message })
	return git(dir, { "rev-parse", "HEAD" })
end

local function remoteSha(name: string): string
	return string.match(git(wt, { "ls-remote", "origin", `refs/heads/{name}` }), "^(%x+)") or ""
end

local function localSha(name: string): string
	return git(wt, { "rev-parse", `refs/heads/{name}` })
end

local function gitDir(): string
	return git(wt, { "rev-parse", "--absolute-git-dir" })
end

local function rebasing(): boolean
	return fs.isDir(`{gitDir()}/rebase-merge`) or fs.isDir(`{gitDir()}/rebase-apply`)
end

local function pushes(): number
	local path = `{f.base}/pushes.log`
	local n = 0
	if fs.isFile(path) then
		for _ in string.gmatch(fs.readFile(path), "[^\n]+") do
			n += 1
		end
	end
	return n
end

local function clearPushes()
	if fs.isFile(`{f.base}/pushes.log`) then
		fs.removeFile(`{f.base}/pushes.log`)
	end
end

-- every layer back to its starting tip, on origin and locally; main back to where it started; no rebase, no marker
local function reset(on: string)
	if rebasing() then
		fixture.exec(wt, "git", { "rebase", "--abort" })
	end
	local markerPath = `{gitDir()}/zn-restack.state`
	if fs.isFile(markerPath) then
		fs.removeFile(markerPath)
	end
	git(wt, { "reset", "-q", "--hard" })
	git(wt, { "switch", "-q", "--detach", M0 })
	for name, sha in base do
		git(wt, { "update-ref", `refs/heads/{name}`, sha })
		git(wt, { "push", "-q", "--force", "origin", `{sha}:refs/heads/{name}` })
		git(wt, { "update-ref", `refs/remotes/origin/{name}`, sha })
		git(wt, { "update-ref", `refs/zn/pushed/{name}`, sha })
	end
	git(wt, { "push", "-q", "--force", "origin", `{MAIN0}:refs/heads/main` })
	git(wt, { "update-ref", "refs/remotes/origin/main", MAIN0 })
	git(wt, { "switch", "-q", on })
	clearPushes()
end

-- another clone pushes a commit with this file straight to origin's main
local function mainMoves(path: string, text: string, message: string)
	local o = f.other
	git(o, { "fetch", "-q", "origin" })
	git(o, { "switch", "-q", "--detach", "origin/main" })
	commit(o, path, text, message)
	git(o, { "push", "-q", "origin", "HEAD:refs/heads/main" })
end

local function resolve(path: string, text: string)
	write(wt, path, text)
	git(wt, { "add", path })
end

local function setup()
	local seed: { [string]: string } = {
		[".gitignore"] = fs.readFile(`{TOP}/.gitignore`),
		["pickman/.tracker/architecture.md"] = fs.readFile(`{TOP}/pickman/.tracker/architecture.md`),
		["pickman/.tracker/rafts/R0010/R0010.md"] = `---\nid: R0010\ntype: chore\ntitle: stack\nslug: stack\nsingle: false\nissues: [c0010, c0020, c0030]\ndesign: ready\ncreated: 2026-10-06\nstatus: {PREPARED}\n---\n\n# R0010\n\n## Order & dependencies\nc0010\nc0020\nc0030\n`,
		["pickman/.tracker/rafts/R0010/check.sh"] = CHECK,
	}
	for id, title in { c0010 = "alpha", c0020 = "beta", c0030 = "gamma" } do
		seed[`pickman/.tracker/issues/{id}/{id}.md`] =
			`---\nid: {id}\ntype: chore\ntitle: {title}\nslug: {id}\nraft: R0010\ndepends_on: []\nemergent: false\ndesign: ready\ncreated: 2026-10-06\nstatus: {PREPARED}\n---\n\n# {id}\n\n{CAPTURED}`
		seed[`pickman/.tracker/issues/{id}/check.sh`] = if id == "c0010" then CHECK_POISON1 else CHECK
		seed[`pickman/.tracker/issues/{id}/acceptance/.gitkeep`] = ""
	end
	f = trackerfix.new("restack-guard", seed)
	local bin = `{f.base}/bin`
	fs.writeDir(bin)
	fs.writeFile(`{bin}/gh`, "#!/bin/sh\nexit 0\n")
	process.exec("chmod", { "+x", `{bin}/gh` })
	env = { PATH = `{bin}:{process.env.PATH or ""}` }
	fs.writeFile(
		`{f.origin}/hooks/pre-receive`,
		`#!/bin/sh\nwhile read old new ref; do printf '%s ' "$ref"; done >> "{f.base}/pushes.log"\necho >> "{f.base}/pushes.log"\n`
	)
	process.exec("chmod", { "+x", `{f.origin}/hooks/pre-receive` })
	trackerfix.trOk(f, f.main, { "ready", "R0010" })
	wt = trackerfix.trOk(f, f.main, { "worktree", "R0010" })
	M0 = git(wt, { "rev-parse", "HEAD" })
	git(wt, { "switch", "-q", "-c", L1 })
	write(wt, SHARED, "one\n")
	base[L1] = commit(wt, "pickman/src/alpha.luau", "alpha\n", "c0010: alpha")
	git(wt, { "switch", "-q", "-c", L2 })
	write(wt, BETA, "beta\n")
	base[L2] = commit(wt, SHARED, "two\n", "c0020: beta")
	git(wt, { "switch", "-q", "-c", L3 })
	base[L3] = commit(wt, "pickman/src/gamma.luau", "gamma\n", "c0030: gamma")
	for _, name in { L1, L2, L3 } do
		git(wt, { "push", "-q", "-u", "origin", name })
	end
	MAIN0 = remoteSha("main")
end

return t.spec("d0434: restack keeps what a stopped run left, and names the way on", function(it)
	it("sets up three layers on a local origin", function()
		setup()
		t.expect(remoteSha(L3)).toBe(base[L3])
	end)

	it(
		"--abort puts a pushed layer that was rebased again back on the tip it pushed, when the run started on another layer",
		function()
			reset(L3) -- the run starts on layer 3, so layer 1 is not the branch the abort is on
			mainMoves(BETA, "main beta\n", "main adds beta") -- layer 1 rebases and is pushed, layer 2 conflicts
			t.expect(zn({ "restack", "R0010" }).code).toBe(3)
			local pushedOne = remoteSha(L1)
			t.expect(pushedOne ~= base[L1]).toBe(true)
			mainMoves("pickman/src/poison1.luau", "poison\n", "main adds poison1") -- layer 1's second pass is red
			git(wt, { "fetch", "-q", "origin" })
			resolve(BETA, "merged beta\n")
			local red = zn({ "restack", "R0010", "--continue" })
			t.expect(red.code).toBe(1)
			t.expect(has(say(red), "check.sh failed")).toBe(true)
			t.expect(localSha(L1) ~= pushedOne).toBe(true)
			local aborted = zn({ "restack", "R0010", "--abort" })
			t.expect(aborted.code).toBe(0)
			t.expect(git(wt, { "branch", "--show-current" })).toBe(L3)
			t.expect(localSha(L1)).toBe(pushedOne)
			t.expect(remoteSha(L1)).toBe(pushedOne)
			t.expect(localSha(L2)).toBe(base[L2])
			t.expect(localSha(L3)).toBe(base[L3])
		end
	)

	it(
		"--continue refuses a pushed layer that is back at its tip from before the run, and goes on over a fix on top of it",
		function()
			reset(L1)
			mainMoves(BETA, "main beta\n", "main adds beta")
			t.expect(zn({ "restack", "R0010" }).code).toBe(3)
			local left = remoteSha(L1)
			git(wt, { "update-ref", `refs/heads/{L1}`, base[L1] }) -- put back as an older engine or a hand reset would
			resolve(BETA, "merged beta\n")
			clearPushes()
			local r = zn({ "restack", "R0010", "--continue" })
			local out = say(r)
			t.expect(r.code).toBe(1)
			for _, part in
				{ L1, left, base[L1], "c0010: alpha", "git log --oneline", "./zn restack R0010 --abort" }
			do
				t.expect(has(out, part)).toBe(true)
			end
			t.expect(has(out, "reset")).toBe(false)
			t.expect(rebasing()).toBe(true) -- nothing was changed
			t.expect(pushes()).toBe(0)
			t.expect(remoteSha(L1)).toBe(left)
			-- a fix on top of what the run left is the worker's change: --continue goes on and publishes it
			git(f.main, { "switch", "-q", "--detach", left })
			local fix = commit(f.main, "pickman/src/alpha.luau", "alpha fixed\n", "R0010: fix on layer 1")
			git(f.main, { "switch", "-q", "main" })
			git(wt, { "update-ref", `refs/heads/{L1}`, fix })
			local done = zn({ "restack", "R0010", "--continue" })
			t.expect(done.code).toBe(0)
			t.expect(remoteSha(L1)).toBe(fix)
			t.expect(git(wt, { "rev-parse", L2 .. "^" })).toBe(fix)
			t.expect(remoteSha(L2)).toBe(localSha(L2))
			t.expect(remoteSha(L3)).toBe(localSha(L3))
		end
	)

	it(
		"a refused push names --abort then restack, and a plain restack between them keeps the stopped run's record",
		function()
			reset(L1)
			write(wt, SHARED, "fix\n")
			git(wt, { "commit", "-qam", "fix layer 1" })
			git(wt, { "push", "-q", "origin", L1 })
			t.expect(zn({ "restack", "R0010" }).code).toBe(3) -- layer 2 conflicts on shared.luau
			local o = f.other -- another clone fast-forwards layer 3 before the continue
			git(o, { "fetch", "-q", "origin" })
			git(o, { "switch", "-q", "--detach", `origin/{L3}` })
			local theirs = commit(o, "pickman/src/theirs.luau", "theirs\n", "someone else's commit")
			git(o, { "push", "-q", "origin", `HEAD:refs/heads/{L3}` })
			resolve(SHARED, "merged\n")
			local refused = say(zn({ "restack", "R0010", "--continue" }))
			local abortAt = string.find(refused, "./zn restack R0010 --abort", 1, true)
			local plainAt = string.find(refused, "then ./zn restack R0010", 1, true)
			t.expect(abortAt ~= nil and plainAt ~= nil and (abortAt :: number) < (plainAt :: number))
				.toBe(true)
			local pushedTwo = remoteSha(L2)
			t.expect(pushedTwo).toBe(localSha(L2))
			t.expect(remoteSha(L3)).toBe(theirs)
			-- the natural next command: a plain restack, which refuses layer 3 and writes a marker of its own
			t.expect(zn({ "restack", "R0010" }).code).toBe(1)
			local aborted = zn({ "restack", "R0010", "--abort" })
			t.expect(aborted.code).toBe(0)
			t.expect(has(say(aborted), L2)).toBe(true) -- the first run's push is still named
			t.expect(has(say(aborted), "nothing had been pushed")).toBe(false)
			t.expect(localSha(L3)).toBe(base[L3]) -- back where the first run found it
			t.expect(localSha(L2)).toBe(pushedTwo)
			local again = zn({ "restack", "R0010" })
			t.expect(again.code).toBe(0)
			t.expect(remoteSha(L3)).toBe(localSha(L3))
			t.expect(git(wt, { "show", `{L3}:pickman/src/theirs.luau` })).toBe("theirs")
			t.expect(remoteSha(L2)).toBe(pushedTwo)
		end
	)
end)
