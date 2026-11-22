--!strict
-- d0434: a conflict during `./zn restack` leaves the rebase in progress and names the files; `--continue` finishes the
-- stack; `--abort` puts every branch back; a layer already based on the layer below, or a local tip a hand rebase made,
-- is never reset from origin; `./zn work next` names the resolve-and-continue action. Real git in the fixture
-- .cache/restack-conflict (a bare origin, a worktree for R0010 and a recording fake znlive), layers built by hand:
--   M0 <- A1 (R0010/1/c0010: alpha.luau, shared.luau "one") <- B1 (R0010/2/c0020: beta.luau, shared.luau "two")
--      <- C1 (R0010/3/c0030: gamma.luau). Every case starts from that state (reset) and amends layer 1.
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
local CHECK_POISON = HEAD .. 'check "AC1: no poison" test ! -f src/poison.luau\nfinish\n'
local CAPTURED =
	"## Problem\nThe marker is missing.\n\n## Solution\nStore the marker.\n\n## Acceptance criteria\n- AC1: the marker is stored\n"
local L1, L2, L3 = "R0010/1/c0010", "R0010/2/c0020", "R0010/3/c0030"
local SHARED = "pickman/src/shared.luau"

local function issue(id: string, title: string): string
	return `---\nid: {id}\ntype: chore\ntitle: {title}\nslug: {id}\nraft: R0010\ndepends_on: []\nemergent: false\ndesign: ready\ncreated: 2026-10-06\nstatus: {PREPARED}\n---\n\n# {id}\n\n{CAPTURED}`
end

local f: trackerfix.Fixture = nil :: any
local wt, calls = "", ""
local env: { [string]: string } = {}
local base: { [string]: string } = {} -- layer branch -> sha at the start of every case
local M0 = ""

local function git(dir: string, args: { string }): string
	return fixture.git(dir, args)
end

local function has(s: string, part: string): boolean
	return string.find(s, part, 1, true) ~= nil
end

local function say(r: fixture.Result): string
	return (string.gsub(r.stderr .. r.stdout, "\r", ""))
end

local function tr(dir: string, args: { string }): fixture.Result
	return trackerfix.tr(f, dir, args, env)
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
	local out = git(wt, { "ls-remote", "origin", `refs/heads/{name}` })
	return string.match(out, "^(%x+)") or ""
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

local function show(ref: string, path: string): string
	return fixture.git(wt, { "show", `{ref}:{path}` })
end

local function restackedEvents(): number
	local n = 0
	if fs.isFile(calls) then
		for line in string.gmatch(fs.readFile(calls), "[^\n]+") do
			if string.sub(line, 1, #"emit restacked") == "emit restacked" then
				n += 1
			end
		end
	end
	return n
end

-- every layer back to its starting tip, on origin and locally; the worktree on layer 1, clean, no rebase, no marker
local function reset()
	if rebasing() then
		fixture.exec(wt, "git", { "rebase", "--abort" })
	end
	local marker = `{gitDir()}/zn-restack.state`
	if fs.isFile(marker) then
		fs.removeFile(marker)
	end
	git(wt, { "reset", "-q", "--hard" })
	git(wt, { "switch", "-q", "--detach", M0 })
	for name, sha in base do
		git(wt, { "update-ref", `refs/heads/{name}`, sha })
		git(wt, { "push", "-q", "--force", "origin", `{sha}:refs/heads/{name}` })
		git(wt, { "update-ref", `refs/remotes/origin/{name}`, sha })
	end
	git(wt, { "switch", "-q", L1 })
	git(wt, { "reset", "-q", "--hard" })
	if fs.isFile(calls) then
		fs.removeFile(calls)
	end
end

-- layer 1 gains a commit that changes shared.luau the way layer 2's commit does not expect, pushed
local function amendLower(): string
	git(wt, { "switch", "-q", L1 })
	local sha = commit(wt, SHARED, "fix\n", "fix layer 1")
	git(wt, { "push", "-q", "origin", L1 })
	return sha
end

-- by hand, in the other clone, with the resolution `merged`: the trees the restacked layers 2 and 3 must have
local function byHand(lowerTip: string, merged: string): (string, string)
	local o = f.other
	git(o, { "fetch", "-q", "origin" })
	git(o, { "switch", "-q", "--detach", lowerTip })
	local r = fixture.exec(o, "git", { "cherry-pick", base[L2] })
	if r.ok then
		error("the by-hand cherry-pick was expected to conflict", 2)
	end
	write(o, SHARED, merged)
	git(o, { "add", "-A" })
	git(o, { "-c", "core.editor=true", "cherry-pick", "--continue" })
	local two = git(o, { "rev-parse", "HEAD^{tree}" })
	git(o, { "cherry-pick", base[L3] })
	return two, git(o, { "rev-parse", "HEAD^{tree}" })
end

local function setup()
	local seed: { [string]: string } = {
		[".gitignore"] = fs.readFile(`{TOP}/.gitignore`),
		["pickman/.tracker/architecture.md"] = fs.readFile(`{TOP}/pickman/.tracker/architecture.md`),
		["pickman/.tracker/rafts/R0010/R0010.md"] = `---\nid: R0010\ntype: chore\ntitle: stack\nslug: stack\nsingle: false\nissues: [c0010, c0020, c0030]\ndesign: ready\ncreated: 2026-10-06\nstatus: {PREPARED}\n---\n\n# R0010\n\n## Order & dependencies\nc0010\nc0020\nc0030\n`,
	}
	local titles: { [string]: string } = { c0010 = "alpha", c0020 = "beta", c0030 = "gamma" }
	for id, title in titles do
		seed[`pickman/.tracker/issues/{id}/{id}.md`] = issue(id, title)
		seed[`pickman/.tracker/issues/{id}/check.sh`] = if id == "c0020" then CHECK_POISON else CHECK
		seed[`pickman/.tracker/issues/{id}/acceptance/.gitkeep`] = ""
	end
	seed["pickman/.tracker/rafts/R0010/check.sh"] = CHECK
	f = trackerfix.new("restack-conflict", seed)
	local bin = `{f.base}/bin`
	calls = `{f.base}/calls.log`
	fs.writeDir(bin)
	fs.writeFile(`{bin}/gh`, "#!/bin/sh\nexit 0\n")
	fs.writeFile(
		`{bin}/znlive`,
		`#!/bin/sh\necho "$*" >> "{calls}"\n` .. 'echo \'{"ok":true,"seq":1}\'\nexit 0\n'
	)
	process.exec("chmod", { "+x", `{bin}/gh`, `{bin}/znlive` })
	env = {
		PATH = `{bin}:{process.env.PATH or ""}`,
		ZN_LIVE = "",
		ZN_LIVE_BIN = `{bin}/znlive`,
		ZN_LIVE_ROOT = "",
	}
	trackerfix.trOk(f, f.main, { "ready", "R0010" })
	wt = trackerfix.trOk(f, f.main, { "worktree", "R0010" })
	M0 = git(wt, { "rev-parse", "HEAD" })
	git(wt, { "switch", "-q", "-c", L1 })
	base[L1] = commit(wt, "pickman/src/alpha.luau", "alpha\n", "c0010: alpha")
	write(wt, SHARED, "one\n")
	git(wt, { "add", "-A" })
	git(wt, { "commit", "-q", "--amend", "--no-edit" })
	base[L1] = git(wt, { "rev-parse", "HEAD" })
	git(wt, { "switch", "-q", "-c", L2 })
	write(wt, "pickman/src/beta.luau", "beta\n")
	base[L2] = commit(wt, SHARED, "two\n", "c0020: beta")
	git(wt, { "switch", "-q", "-c", L3 })
	base[L3] = commit(wt, "pickman/src/gamma.luau", "gamma\n", "c0030: gamma")
	for _, name in { L1, L2, L3 } do
		git(wt, { "push", "-q", "-u", "origin", name })
	end
end

return t.spec("d0434: a restack conflict is the worker's to resolve", function(it)
	it("sets up three layers on a local origin", function()
		setup()
		t.expect(remoteSha(L3)).toBe(base[L3])
	end)

	it(
		"AC1: a conflict leaves the rebase in progress on the layer and names the files and the command",
		function()
			reset()
			local lower = amendLower()
			local r = tr(wt, { "restack", "R0010" })
			local out = say(r)
			t.expect(r.code).toBe(3)
			t.expect(has(out, L2)).toBe(true)
			t.expect(has(out, SHARED)).toBe(true)
			t.expect(has(out, "./zn restack R0010 --continue")).toBe(true)
			t.expect(has(out, "./zn restack R0010 --abort")).toBe(true)
			t.expect(rebasing()).toBe(true)
			t.expect(git(wt, { "diff", "--name-only", "--diff-filter=U" })).toBe(SHARED)
			-- nothing was pushed, no branch of origin moved, layer 3 is untouched, and nothing was told as restacked
			t.expect(remoteSha(L1)).toBe(lower)
			t.expect(remoteSha(L2)).toBe(base[L2])
			t.expect(remoteSha(L3)).toBe(base[L3])
			t.expect(localSha(L3)).toBe(base[L3])
			t.expect(restackedEvents()).toBe(0)
		end
	)

	it(
		"AC2: a second restack while one is in progress says so and names the two commands, and changes nothing",
		function()
			local r = tr(wt, { "restack", "R0010" })
			local out = say(r)
			t.expect(r.ok).toBe(false)
			t.expect(has(out, "in progress")).toBe(true)
			t.expect(has(out, "./zn restack R0010 --continue")).toBe(true)
			t.expect(has(out, "./zn restack R0010 --abort")).toBe(true)
			t.expect(rebasing()).toBe(true)
			t.expect(git(wt, { "diff", "--name-only", "--diff-filter=U" })).toBe(SHARED)
			t.expect(remoteSha(L3)).toBe(base[L3])
		end
	)

	it("AC3: work next names resolving the files and continuing the restack, never a dead end", function()
		local r = tr(f.main, { "work", "next", "R0010" })
		local out = say(r)
		t.expect(has(out, "R0010: restack - ")).toBe(true)
		t.expect(has(out, SHARED)).toBe(true)
		t.expect(has(out, "./zn restack R0010 --continue")).toBe(true)
		t.expect(has(out, "R0010 --abort")).toBe(true)
	end)

	it(
		"AC4: --continue refuses while a path is unmerged, and while a conflict marker is staged, naming each",
		function()
			local r = tr(wt, { "restack", "R0010", "--continue" })
			local out = say(r)
			t.expect(r.ok).toBe(false)
			t.expect(has(out, `unmerged: {SHARED}`)).toBe(true)
			t.expect(rebasing()).toBe(true)
			git(wt, { "add", SHARED }) -- staged, but the markers are still in it
			local marked = tr(wt, { "restack", "R0010", "--continue" })
			local mout = say(marked)
			t.expect(marked.ok).toBe(false)
			t.expect(has(mout, `conflict marker: {SHARED}:`)).toBe(true)
			t.expect(rebasing()).toBe(true)
			t.expect(remoteSha(L2)).toBe(base[L2])
		end
	)

	it(
		"AC5: after the resolution, --continue restacks the layers above on the resolved layer, equal to a by-hand rebase",
		function()
			local lower = remoteSha(L1)
			local wantTwo, wantThree = byHand(lower, "merged\n")
			write(wt, SHARED, "merged\n")
			git(wt, { "add", SHARED })
			local r = tr(wt, { "restack", "R0010", "--continue" })
			t.expect(r.code).toBe(0)
			t.expect(has(say(r), "restacked R0010")).toBe(true)
			t.expect(rebasing()).toBe(false)
			t.expect(fs.isFile(`{gitDir()}/zn-restack.state`)).toBe(false)
			t.expect(git(wt, { "rev-parse", L2 .. "^{tree}" })).toBe(wantTwo)
			t.expect(git(wt, { "rev-parse", L3 .. "^{tree}" })).toBe(wantThree)
			t.expect(git(wt, { "rev-parse", L2 .. "^" })).toBe(lower)
			t.expect(git(wt, { "rev-parse", L3 .. "^" })).toBe(localSha(L2))
			t.expect(git(wt, { "log", "-1", "--format=%s", L3 })).toBe("c0030: gamma")
			t.expect(remoteSha(L1)).toBe(lower)
			t.expect(remoteSha(L2)).toBe(localSha(L2))
			t.expect(remoteSha(L3)).toBe(localSha(L3))
			t.expect(restackedEvents()).toBe(1)
			t.expect(git(wt, { "branch", "--show-current" })).toBe(L1)
			-- run again: nothing moves
			local again = say(tr(wt, { "restack", "R0010" }))
			t.expect(has(again, "already stacked")).toBe(true)
			t.expect(remoteSha(L3)).toBe(localSha(L3))
			t.expect(restackedEvents()).toBe(1)
		end
	)

	it("AC6: --abort puts every branch and the worktree back exactly as before the run", function()
		reset()
		local lower = amendLower()
		local before = { [L1] = localSha(L1), [L2] = localSha(L2), [L3] = localSha(L3) }
		t.expect(tr(wt, { "restack", "R0010" }).code).toBe(3)
		local r = tr(wt, { "restack", "R0010", "--abort" })
		t.expect(r.code).toBe(0)
		t.expect(rebasing()).toBe(false)
		t.expect(fs.isFile(`{gitDir()}/zn-restack.state`)).toBe(false)
		for name, sha in before do
			t.expect(localSha(name)).toBe(sha)
		end
		t.expect(remoteSha(L1)).toBe(lower)
		t.expect(remoteSha(L2)).toBe(base[L2])
		t.expect(remoteSha(L3)).toBe(base[L3])
		t.expect(git(wt, { "status", "--porcelain" })).toBe("")
		t.expect(git(wt, { "branch", "--show-current" })).toBe(L1)
		t.expect(restackedEvents()).toBe(0)
		local none = tr(wt, { "restack", "R0010", "--continue" })
		t.expect(none.ok).toBe(false)
		t.expect(has(say(none), "no restack")).toBe(true)
	end)

	it(
		"AC7: a layer already hand rebased onto the layer below is never reset from origin, and the stack is published",
		function()
			reset()
			local lower = amendLower()
			git(wt, { "switch", "-q", L2 })
			local r = fixture.exec(wt, "git", { "rebase", "--onto", lower, base[L1], L2 })
			t.expect(r.ok).toBe(false)
			write(wt, SHARED, "merged\n")
			git(wt, { "add", SHARED })
			git(wt, { "-c", "core.editor=true", "rebase", "--continue" })
			local tipTwo = localSha(L2)
			git(wt, { "rebase", "--onto", tipTwo, base[L2], L3 })
			local tipThree = localSha(L3)
			git(wt, { "switch", "-q", L1 })
			local done = tr(wt, { "restack", "R0010" })
			t.expect(done.code).toBe(0)
			t.expect(localSha(L2)).toBe(tipTwo)
			t.expect(localSha(L3)).toBe(tipThree)
			t.expect(remoteSha(L2)).toBe(tipTwo)
			t.expect(remoteSha(L3)).toBe(tipThree)
			t.expect(show(L2, SHARED)).toBe("merged")
		end
	)

	it(
		"AC8: a restack that died after its rebase was continued is finished by a plain restack, keeping that rebase",
		function()
			reset()
			local lower = amendLower()
			t.expect(tr(wt, { "restack", "R0010" }).code).toBe(3)
			write(wt, SHARED, "merged\n")
			git(wt, { "add", SHARED })
			git(wt, { "-c", "core.editor=true", "rebase", "--continue" }) -- the worker's own continue; zn never ran
			local tipTwo = localSha(L2)
			t.expect(remoteSha(L2)).toBe(base[L2])
			local r = tr(wt, { "restack", "R0010" })
			t.expect(r.code).toBe(0)
			t.expect(localSha(L2)).toBe(tipTwo)
			t.expect(remoteSha(L2)).toBe(tipTwo)
			t.expect(git(wt, { "rev-parse", L3 .. "^" })).toBe(tipTwo)
			t.expect(remoteSha(L3)).toBe(localSha(L3))
			t.expect(remoteSha(L1)).toBe(lower)
		end
	)

	it(
		"AC9: a commit on origin's layer that is neither local nor below stops the restack naming the layer, changing nothing",
		function()
			reset()
			amendLower()
			git(wt, { "switch", "-q", L2 })
			commit(wt, "pickman/src/mine.luau", "mine\n", "my local commit")
			local mine = localSha(L2)
			local o = f.other
			git(o, { "fetch", "-q", "origin" })
			git(o, { "switch", "-q", "--detach", `origin/{L2}` })
			commit(o, "pickman/src/theirs.luau", "theirs\n", "someone else's commit")
			git(o, { "push", "-q", "origin", `HEAD:refs/heads/{L2}` })
			local theirs = remoteSha(L2)
			git(wt, { "switch", "-q", L1 })
			local r = tr(wt, { "restack", "R0010" })
			local out = say(r)
			t.expect(r.ok).toBe(false)
			t.expect(r.code).toBe(1)
			t.expect(has(out, L2)).toBe(true)
			t.expect(has(out, "origin")).toBe(true)
			t.expect(localSha(L2)).toBe(mine)
			t.expect(localSha(L3)).toBe(base[L3])
			t.expect(remoteSha(L2)).toBe(theirs)
			t.expect(remoteSha(L3)).toBe(base[L3])
			t.expect(rebasing()).toBe(false)
		end
	)

	it(
		"AC10: a red check.sh stops the restack at its layer, pushes nothing for it or later, and leaves the local branch",
		function()
			reset()
			git(wt, { "switch", "-q", L1 })
			local lower = commit(wt, "pickman/src/poison.luau", "poison\n", "poison layer 1")
			git(wt, { "push", "-q", "origin", L1 })
			local r = tr(wt, { "restack", "R0010" })
			t.expect(r.ok).toBe(false)
			t.expect(r.code).toBe(1)
			t.expect(has(say(r), L2)).toBe(true)
			t.expect(has(say(r), "check.sh failed")).toBe(true)
			t.expect(remoteSha(L1)).toBe(lower)
			t.expect(remoteSha(L2)).toBe(base[L2])
			t.expect(remoteSha(L3)).toBe(base[L3])
			t.expect(localSha(L2)).toBe(base[L2])
			t.expect(rebasing()).toBe(false)
		end
	)

	it("AC11: the skills tell the worker to resolve a restack conflict itself, and when to ask", function()
		local text = fs.readFile(`{TOP}/z-nile/skills/zz-execute/SKILL.md`)
		for _, part in
			{
				"is yours to resolve, not the person's",
				"./zn restack <R-id> --continue",
				"./zn restack <R-id> --abort",
				"run the specs the resolved files select, by name",
				"cannot tell which the owner wants, stop and ask, naming the files and both intents",
				"Never `git rebase --skip`, never drop a commit, never force-push by hand",
			}
		do
			t.expect(has(text, part)).toBe(true)
		end
		t.expect(has(fs.readFile(`{TOP}/z-nile/skills/z-work/SKILL.md`), "zz-execute, Phase 5 step 2"))
			.toBe(true)
	end)
end)
