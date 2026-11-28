--!strict
-- d0434: a conflict during `./zn restack` leaves the rebase in progress and names the files; `--continue` finishes the
-- stack; `--abort` puts every branch back; a layer already based on the layer below, or a local tip a hand rebase made,
-- is never reset from origin; a layer is pushed on its own once its check.sh passes, before the next layer is restacked
-- (the owner's ruling of 2026-11-22), so a stop leaves the layers below it on origin; `./zn work next` names the
-- resolve-and-continue action. Real git in the fixture
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
local CHECK_POISON3 = HEAD .. 'check "AC1: no poison3" test ! -f src/poison3.luau\nfinish\n'
local CHECK_POISON1 = HEAD .. 'check "AC1: no poison1" test ! -f src/poison1.luau\nfinish\n'
local CHECK_POISON = HEAD
	.. 'check "AC1: no poison" test ! -f src/poison.luau\n'
	.. "check \"AC2: gate free\" sh -c 'test ! -f src/busy.luau || exit 75'\n" -- a check that did not start (exit 75)
	.. "finish\n"
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
local MAIN0 = "" -- origin's main as the cases start

local function git(dir: string, args: { string }): string
	return fixture.git(dir, args)
end

local function has(s: string, part: string): boolean
	return string.find(s, part, 1, true) ~= nil
end

local function say(r: fixture.Result): string
	return r.stderr .. r.stdout
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

-- one line per push origin received, the refs it carried (a recording pre-receive hook in the bare origin)
local function pushLog(): { string }
	local path = `{f.base}/pushes.log`
	local out: { string } = {}
	if fs.isFile(path) then
		for line in string.gmatch(fs.readFile(path), "[^\n]+") do
			table.insert(out, line)
		end
	end
	return out
end

local function clearPushes()
	if fs.isFile(`{f.base}/pushes.log`) then
		fs.removeFile(`{f.base}/pushes.log`)
	end
end

local function pushedRef(name: string): string
	local r = fixture.exec(wt, "git", { "rev-parse", "--verify", "--quiet", `refs/zn/pushed/{name}` })
	return if r.ok then (string.gsub(r.stdout, "%s+$", "")) else ""
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

local function marker(): string
	local path = `{gitDir()}/zn-restack.state`
	return if fs.isFile(path) then fs.readFile(path) else ""
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
		git(wt, { "update-ref", `refs/zn/pushed/{name}`, sha }) -- what zn finish or restack pushed from this clone
	end
	git(wt, { "push", "-q", "--force", "origin", `{MAIN0}:refs/heads/main` }) -- a case that moved main puts it back
	git(wt, { "update-ref", "refs/remotes/origin/main", MAIN0 })
	git(wt, { "switch", "-q", L1 })
	git(wt, { "reset", "-q", "--hard" })
	if fs.isFile(calls) then
		fs.removeFile(calls)
	end
	if fs.isFile(`{f.base}/pushes.log`) then
		fs.removeFile(`{f.base}/pushes.log`)
	end
end

-- layer 1 gains a commit that is only local (not pushed): the next restack publishes it before it restacks layer 2
local function localLower(): string
	git(wt, { "switch", "-q", L1 })
	return commit(wt, SHARED, "fix\n", "fix layer 1")
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
	write(o, "pickman/notes.md", "Title\n=======\n") -- a setext underline is not a conflict marker
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
		seed[`pickman/.tracker/issues/{id}/check.sh`] = if id == "c0020"
			then CHECK_POISON
			elseif id == "c0030" then CHECK_POISON3
			else CHECK_POISON1
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
	fs.writeFile(
		`{f.origin}/hooks/pre-receive`,
		`#!/bin/sh\nwhile read old new ref; do printf '%s ' "$ref"; done >> "{f.base}/pushes.log"\necho >> "{f.base}/pushes.log"\n`
	)
	process.exec("chmod", { "+x", `{f.origin}/hooks/pre-receive` })
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
	MAIN0 = remoteSha("main")
end

-- the other clone pushes `path` to layer `name` on top of origin's tip (a fast-forward), returning the new sha
local function otherPushes(name: string, path: string): string
	local o = f.other
	git(o, { "fetch", "-q", "origin" })
	git(o, { "switch", "-q", "--detach", `origin/{name}` })
	commit(o, path, "theirs\n", "someone else's commit")
	git(o, { "push", "-q", "origin", `HEAD:refs/heads/{name}` })
	return remoteSha(name)
end

-- another clone pushes a commit with these files straight to origin's main (not a pull: a case may have put main back)
local function mainMoves(files: { [string]: string }, message: string)
	local o = f.other
	git(o, { "fetch", "-q", "origin" })
	git(o, { "switch", "-q", "--detach", "origin/main" })
	for path, text in files do
		write(o, path, text)
	end
	git(o, { "add", "-A" })
	git(o, { "commit", "-qm", message })
	git(o, { "push", "-q", "origin", "HEAD:refs/heads/main" })
end

-- tr with a test-only kill point: zn exits where the variable says (restackcmd's crash seam)
local function trKill(point: string, args: { string }): fixture.Result
	local withKill = table.clone(env)
	withKill.ZN_RESTACK_KILL = point
	return trackerfix.tr(f, wt, args, withKill)
end

local function resolve(text: string)
	write(wt, SHARED, text)
	git(wt, { "add", SHARED })
end

local function conflicted(): string -- reset, amend layer 1, stop on the conflict; returns layer 1's new tip
	reset()
	local lower = amendLower()
	t.expect(tr(wt, { "restack", "R0010" }).code).toBe(3)
	return lower
end

local function originUnchanged(lower: string)
	t.expect(remoteSha(L1)).toBe(lower)
	t.expect(remoteSha(L2)).toBe(base[L2])
	t.expect(remoteSha(L3)).toBe(base[L3])
end

return t.spec("d0434: a restack conflict is the worker's to resolve", function(it)
	it("sets up three layers on a local origin", function()
		setup()
		t.expect(remoteSha(L3)).toBe(base[L3])
	end)

	it(
		"AC1: a conflict leaves the rebase of that layer in progress and names the files and the command",
		function()
			-- layer 1 passes and is pushed on its own before layer 2 conflicts: it is on origin, layers 2 and 3 are not
			reset()
			local first = localLower()
			local early = tr(wt, { "restack", "R0010" })
			t.expect(early.code).toBe(3)
			t.expect(has(say(early), L2)).toBe(true)
			t.expect(remoteSha(L1)).toBe(first)
			t.expect(pushedRef(L1)).toBe(first)
			t.expect(has(marker(), `pushed {L1} {first}`)).toBe(true)
			t.expect(remoteSha(L2)).toBe(base[L2])
			t.expect(remoteSha(L3)).toBe(base[L3])
			t.expect(#pushLog()).toBe(1)
			t.expect(has(say(early), L1)).toBe(true) -- the stop names what is already pushed
			t.expect(restackedEvents()).toBe(0)
			reset()
			local lower = amendLower()
			clearPushes() -- the test's own push of layer 1 is not zn's
			local r = tr(wt, { "restack", "R0010" })
			local out = say(r)
			t.expect(r.code).toBe(3)
			t.expect(has(out, L2)).toBe(true)
			t.expect(has(out, SHARED)).toBe(true)
			t.expect(has(out, "./zn restack R0010 --continue")).toBe(true)
			t.expect(has(out, "./zn restack R0010 --abort")).toBe(true)
			t.expect(rebasing()).toBe(true)
			t.expect(has(git(wt, { "status" }), `rebasing branch '{L2}'`)).toBe(true)
			t.expect(has(marker(), `conflict {L2} `)).toBe(true)
			t.expect(git(wt, { "diff", "--name-only", "--diff-filter=U" })).toBe(SHARED)
			originUnchanged(lower) -- this layer and every layer above it are not pushed
			t.expect(#pushLog()).toBe(0)
			t.expect(localSha(L3)).toBe(base[L3])
			t.expect(restackedEvents()).toBe(0)
		end
	)

	it(
		"AC2: a second restack while one is in progress refuses, names the two commands, and changes nothing",
		function()
			conflicted()
			write(wt, "pickman/src/partial.luau", "partial\n")
			git(wt, { "add", "pickman/src/partial.luau" }) -- a partial resolution, staged
			local headBefore, markerBefore = git(wt, { "rev-parse", "HEAD" }), marker()
			local ok, err = pcall(function()
				local r = tr(wt, { "restack", "R0010" })
				local out = say(r)
				t.expect(r.code).toBe(1)
				t.expect(has(out, "in progress")).toBe(true)
				t.expect(has(out, "./zn restack R0010 --continue")).toBe(true)
				t.expect(has(out, "./zn restack R0010 --abort")).toBe(true)
				t.expect(rebasing()).toBe(true)
				t.expect(marker()).toBe(markerBefore)
				t.expect(has(markerBefore, `back {L1}`)).toBe(true)
				t.expect(git(wt, { "rev-parse", "HEAD" })).toBe(headBefore)
				t.expect(git(wt, { "show", ":pickman/src/partial.luau" })).toBe("partial")
				t.expect(git(wt, { "diff", "--name-only", "--diff-filter=U" })).toBe(SHARED)
				t.expect(remoteSha(L3)).toBe(base[L3])
			end)
			-- the staged partial file goes whether or not an assertion above failed
			git(wt, { "rm", "-q", "--cached", "pickman/src/partial.luau" })
			fs.removeFile(`{wt}/pickman/src/partial.luau`)
			if not ok then
				error(err, 0)
			end
		end
	)

	it("AC2: a rebase in progress that is not a restack's is refused, named, and left as it is", function()
		reset()
		local lower = amendLower()
		git(wt, { "switch", "-q", L2 })
		t.expect(fixture.exec(wt, "git", { "rebase", "--onto", lower, base[L1], L2 }).ok).toBe(false) -- by hand
		local headBefore = git(wt, { "rev-parse", "HEAD" })
		local r = tr(wt, { "restack", "R0010" })
		t.expect(r.code).toBe(1)
		t.expect(has(say(r), "not a restack's")).toBe(true)
		t.expect(has(say(r), "git rebase --abort")).toBe(true)
		t.expect(rebasing()).toBe(true)
		t.expect(git(wt, { "rev-parse", "HEAD" })).toBe(headBefore)
		t.expect(marker()).toBe("")
		t.expect(remoteSha(L2)).toBe(base[L2])
	end)

	it("AC3: work next names resolving the files and continuing the restack, never a dead end", function()
		conflicted()
		local r = tr(f.main, { "work", "next", "R0010" })
		local out = say(r)
		t.expect(has(out, "R0010: restack - ")).toBe(true)
		t.expect(has(out, SHARED)).toBe(true)
		t.expect(has(out, "./zn restack R0010 --continue")).toBe(true)
		t.expect(has(out, "R0010 --abort")).toBe(true)
		t.expect(has(out, "lune run z-nile/affected")).toBe(true)
		t.expect(has(out, "emptie")).toBe(true)
	end)

	it(
		"AC4: --continue refuses while a path is unmerged, and while a conflict marker is staged, naming each",
		function()
			conflicted()
			local r = tr(wt, { "restack", "R0010", "--continue" })
			t.expect(r.ok).toBe(false)
			t.expect(has(say(r), `unmerged: {SHARED}`)).toBe(true)
			t.expect(rebasing()).toBe(true)
			write(wt, SHARED, "merged\n") -- no markers any more, but not staged: the path is still unmerged
			local unstaged = tr(wt, { "restack", "R0010", "--continue" })
			t.expect(unstaged.ok).toBe(false)
			t.expect(has(say(unstaged), `unmerged: {SHARED}`)).toBe(true)
			t.expect(rebasing()).toBe(true)
			resolve("<<<<<<< ours\nfoo\n=======\nbar\n>>>>>>> theirs\n") -- staged, but the markers are in it
			local marked = tr(wt, { "restack", "R0010", "--continue" })
			t.expect(marked.ok).toBe(false)
			t.expect(has(say(marked), `conflict marker: {SHARED}:`)).toBe(true)
			t.expect(rebasing()).toBe(true)
			t.expect(remoteSha(L2)).toBe(base[L2])
		end
	)

	it(
		"AC5: after the resolution, --continue restacks the layers above, equal to a by-hand rebase, and pushes each layer on its own",
		function()
			local lower = conflicted()
			clearPushes()
			local wantTwo, wantThree = byHand(lower, "merged\n")
			write(wt, SHARED, "merged\n")
			write(wt, "pickman/notes.md", "Title\n=======\n")
			git(wt, { "add", SHARED, "pickman/notes.md" })
			local r = tr(wt, { "restack", "R0010", "--continue" })
			t.expect(r.code).toBe(0)
			t.expect(has(say(r), "restacked R0010")).toBe(true)
			t.expect(rebasing()).toBe(false)
			t.expect(marker()).toBe("")
			t.expect(git(wt, { "rev-parse", L2 .. "^{tree}" })).toBe(wantTwo)
			t.expect(git(wt, { "rev-parse", L3 .. "^{tree}" })).toBe(wantThree)
			t.expect(git(wt, { "rev-parse", L2 .. "^" })).toBe(lower)
			t.expect(git(wt, { "rev-parse", L3 .. "^" })).toBe(localSha(L2))
			t.expect(git(wt, { "log", "-1", "--format=%s", L3 })).toBe("c0030: gamma")
			t.expect(remoteSha(L1)).toBe(lower)
			t.expect(remoteSha(L2)).toBe(localSha(L2))
			t.expect(remoteSha(L3)).toBe(localSha(L3))
			-- each layer went in a push of its own, layer 2 before layer 3 was restacked
			local pushes = pushLog()
			t.expect(#pushes).toBe(2)
			t.expect(has(pushes[1], `refs/heads/{L2}`) and not has(pushes[1], `refs/heads/{L3}`)).toBe(true)
			t.expect(has(pushes[2], `refs/heads/{L3}`) and not has(pushes[2], `refs/heads/{L2}`)).toBe(true)
			t.expect(pushedRef(L2)).toBe(remoteSha(L2)) -- the restack notes what it pushed
			t.expect(pushedRef(L3)).toBe(remoteSha(L3))
			t.expect(restackedEvents()).toBe(1)
			t.expect(git(wt, { "branch", "--show-current" })).toBe(L1)
			local again = say(tr(wt, { "restack", "R0010" }))
			t.expect(has(again, "already stacked")).toBe(true)
			t.expect(remoteSha(L3)).toBe(localSha(L3))
			t.expect(restackedEvents()).toBe(1)
		end
	)

	it("AC5: a run started on a detached commit goes back to that commit", function()
		reset()
		git(wt, { "switch", "-q", L1 })
		commit(wt, "pickman/src/alpha.luau", "alpha 2\n", "alpha changed") -- layers 2 and 3 rebase cleanly
		git(wt, { "push", "-q", "origin", L1 })
		git(wt, { "switch", "-q", "--detach", M0 })
		local r = tr(wt, { "restack", "R0010" })
		t.expect(r.code).toBe(0)
		t.expect(git(wt, { "branch", "--show-current" })).toBe("")
		t.expect(git(wt, { "rev-parse", "HEAD" })).toBe(M0)
		t.expect(remoteSha(L3)).toBe(localSha(L3))
	end)

	it(
		"AC6: --abort puts every layer not yet pushed back, and leaves the layers it pushed as pushed",
		function()
			local lower = conflicted()
			local before = { [L1] = localSha(L1), [L2] = localSha(L2), [L3] = localSha(L3) }
			local r = tr(wt, { "restack", "R0010", "--abort" })
			t.expect(r.code).toBe(0)
			t.expect(rebasing()).toBe(false)
			t.expect(marker()).toBe("")
			for name, sha in before do
				t.expect(localSha(name)).toBe(sha)
			end
			originUnchanged(lower)
			t.expect(has(say(r), "nothing had been pushed")).toBe(true)
			t.expect(git(wt, { "status", "--porcelain" })).toBe("")
			t.expect(git(wt, { "branch", "--show-current" })).toBe(L1)
			t.expect(restackedEvents()).toBe(0)
			local none = tr(wt, { "restack", "R0010", "--continue" })
			t.expect(none.ok).toBe(false)
			t.expect(has(say(none), "no restack")).toBe(true)
			-- layer 2 is restacked and pushed before layer 3 conflicts with the file layer 1 now has: abort puts layer 3 back
			-- and leaves layer 2 at the tip it pushed (origin is never moved back)
			reset()
			git(wt, { "switch", "-q", L1 })
			local lowerGamma = commit(wt, "pickman/src/gamma.luau", "other\n", "gamma on layer 1")
			git(wt, { "push", "-q", "origin", L1 })
			local stopped = tr(wt, { "restack", "R0010" })
			t.expect(stopped.code).toBe(3)
			t.expect(has(say(stopped), L3)).toBe(true)
			t.expect(git(wt, { "diff", "--name-only", "--diff-filter=U" })).toBe("pickman/src/gamma.luau")
			local pushedTwo = localSha(L2)
			t.expect(pushedTwo ~= base[L2]).toBe(true)
			t.expect(remoteSha(L2)).toBe(pushedTwo)
			t.expect(remoteSha(L3)).toBe(base[L3])
			t.expect(has(marker(), `pushed {L2} {pushedTwo}`)).toBe(true) -- the tip it pushed, not the one it started from
			local aborted = tr(wt, { "restack", "R0010", "--abort" })
			t.expect(aborted.code).toBe(0)
			t.expect(has(say(aborted), L2)).toBe(true) -- names the layer that stays published
			t.expect(localSha(L1)).toBe(lowerGamma)
			t.expect(localSha(L2)).toBe(pushedTwo)
			t.expect(localSha(L3)).toBe(base[L3])
			t.expect(remoteSha(L1)).toBe(lowerGamma)
			t.expect(remoteSha(L2)).toBe(pushedTwo)
			t.expect(remoteSha(L3)).toBe(base[L3])
			t.expect(git(wt, { "status", "--porcelain" })).toBe("")
			t.expect(git(wt, { "branch", "--show-current" })).toBe(L1)
		end
	)

	it(
		"AC7: a layer hand rebased onto the layer below keeps its tip, and the layer above it is restacked on it",
		function()
			reset()
			local lower = amendLower()
			git(wt, { "switch", "-q", L2 })
			t.expect(fixture.exec(wt, "git", { "rebase", "--onto", lower, base[L1], L2 }).ok).toBe(false)
			write(wt, SHARED, "merged\n")
			git(wt, { "add", SHARED })
			git(wt, { "-c", "core.editor=true", "rebase", "--continue" })
			local tipTwo = localSha(L2)
			git(wt, { "switch", "-q", L1 }) -- layer 3 is left as it was: it is the layer above that must move
			local done = tr(wt, { "restack", "R0010" })
			t.expect(done.code).toBe(0)
			t.expect(localSha(L2)).toBe(tipTwo)
			t.expect(remoteSha(L2)).toBe(tipTwo)
			t.expect(localSha(L3) ~= base[L3]).toBe(true)
			t.expect(git(wt, { "rev-parse", L3 .. "^" })).toBe(tipTwo)
			t.expect(remoteSha(L3)).toBe(localSha(L3))
			t.expect(show(L2, SHARED)).toBe("merged")
			-- a hand rebased layer whose check.sh is red is not pushed either
			reset()
			lower = amendLower()
			git(wt, { "switch", "-q", L2 })
			t.expect(fixture.exec(wt, "git", { "rebase", "--onto", lower, base[L1], L2 }).ok).toBe(false)
			write(wt, SHARED, "merged\n")
			write(wt, "pickman/src/poison.luau", "poison\n")
			git(wt, { "add", "-A" })
			git(wt, { "-c", "core.editor=true", "rebase", "--continue" })
			tipTwo = localSha(L2)
			git(wt, { "switch", "-q", L1 })
			local red = tr(wt, { "restack", "R0010" })
			t.expect(red.code).toBe(1)
			t.expect(has(say(red), "check.sh failed")).toBe(true)
			t.expect(localSha(L2)).toBe(tipTwo)
			t.expect(has(marker(), "raft R0010")).toBe(true) -- written when the run started, though nothing was rebased
			originUnchanged(lower)
		end
	)

	it(
		"AC8: a restack that died after its rebase was continued is finished by a plain restack, keeping that rebase",
		function()
			local lower = conflicted()
			resolve("merged\n")
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
		"AC9: a commit of someone else on origin's layer stops the restack naming the layer and both tips, changing nothing",
		function()
			reset()
			amendLower()
			git(wt, { "switch", "-q", L2 })
			commit(wt, "pickman/src/mine.luau", "mine\n", "my local commit")
			local mine = localSha(L2)
			local theirs = otherPushes(L2, "pickman/src/theirs.luau")
			git(wt, { "switch", "-q", L1 })
			local r = tr(wt, { "restack", "R0010" })
			local out = say(r)
			t.expect(r.code).toBe(1)
			t.expect(has(out, L2)).toBe(true)
			t.expect(has(out, theirs)).toBe(true)
			t.expect(has(out, mine)).toBe(true)
			t.expect(localSha(L2)).toBe(mine)
			t.expect(localSha(L3)).toBe(base[L3])
			t.expect(remoteSha(L2)).toBe(theirs)
			t.expect(remoteSha(L3)).toBe(base[L3])
			t.expect(rebasing()).toBe(false)
		end
	)

	it(
		"AC10: a red check.sh stops the restack at its layer, pushes nothing for it or any layer above, and leaves the local branch",
		function()
			reset()
			git(wt, { "switch", "-q", L1 })
			local lower = commit(wt, "pickman/src/poison.luau", "poison\n", "poison layer 1")
			git(wt, { "push", "-q", "origin", L1 })
			clearPushes()
			local r = tr(wt, { "restack", "R0010" })
			t.expect(r.code).toBe(1)
			t.expect(has(say(r), L2)).toBe(true)
			t.expect(has(say(r), "check.sh failed")).toBe(true)
			originUnchanged(lower)
			t.expect(#pushLog()).toBe(0)
			-- the red layer keeps its restacked tip locally, unpushed; layer 3 above it, which would move, is not reached
			t.expect(git(wt, { "rev-parse", L2 .. "^" })).toBe(lower)
			t.expect(has(marker(), `red {L2} {localSha(L2)}`)).toBe(true)
			t.expect(pushedRef(L2)).toBe(base[L2])
			t.expect(localSha(L3)).toBe(base[L3])
			t.expect(rebasing()).toBe(false)
			-- a red layer above a green one: the green layer 2 was pushed already (it passed), layer 3 and nothing above is
			reset()
			git(wt, { "switch", "-q", L1 })
			lower = commit(wt, "pickman/src/poison3.luau", "poison\n", "poison3 on layer 1")
			git(wt, { "push", "-q", "origin", L1 })
			clearPushes()
			local late = tr(wt, { "restack", "R0010" })
			t.expect(late.code).toBe(1)
			t.expect(has(say(late), L3)).toBe(true)
			t.expect(has(say(late), "check.sh failed")).toBe(true)
			t.expect(localSha(L2) ~= base[L2]).toBe(true)
			t.expect(remoteSha(L2)).toBe(localSha(L2))
			t.expect(pushedRef(L2)).toBe(localSha(L2))
			t.expect(remoteSha(L3)).toBe(base[L3])
			t.expect(pushedRef(L3)).toBe(base[L3])
			t.expect(localSha(L3) ~= base[L3]).toBe(true) -- the red layer keeps its restacked tip, unpushed
			t.expect(git(wt, { "rev-parse", L3 .. "^" })).toBe(localSha(L2))
			t.expect(#pushLog()).toBe(1)
			t.expect(has(pushLog()[1], `refs/heads/{L2}`) and not has(pushLog()[1], `refs/heads/{L3}`))
				.toBe(true)
			t.expect(restackedEvents()).toBe(0)
		end
	)

	it("AC11: the skills tell the worker to resolve a restack conflict itself, and when to ask", function()
		local text = fs.readFile(`{TOP}/z-nile/skills/zz-execute/SKILL.md`)
		for _, part in
			{
				"is yours to resolve, not the person's",
				"./zn restack <R-id> --continue",
				"./zn restack <R-id> --abort",
				"lune run z-nile/affected -- <files>",
				"later layer may stop again",
				"If the check goes red after the continue",
				"If the resolution empties a commit",
				"cannot tell which the owner wants, stop and ask, naming the files and both intents",
				"Never `git rebase --skip`, never drop a commit, never force-push by hand",
			}
		do
			t.expect(has(text, part)).toBe(true)
		end
		t.expect(has(fs.readFile(`{TOP}/z-nile/skills/z-work/SKILL.md`), "zz-execute, Phase 5 step 2"))
			.toBe(true)
	end)

	it(
		"AC12: origin's layer re-finished with the same subject by someone else is refused, not overwritten",
		function()
			reset()
			amendLower()
			git(wt, { "switch", "-q", L2 })
			commit(wt, "pickman/src/mine.luau", "mine\n", "my local commit")
			local mine = localSha(L2)
			local o = f.other
			git(o, { "fetch", "-q", "origin" })
			git(o, { "switch", "-q", "--detach", `origin/{L2}` })
			write(o, "pickman/src/beta.luau", "beta, re-finished\n")
			git(o, { "add", "-A" })
			git(o, { "commit", "-q", "--amend", "-m", "c0020: beta" }) -- the same subject, other content
			git(o, { "push", "-q", "--force", "origin", `HEAD:refs/heads/{L2}` })
			local theirs = remoteSha(L2)
			git(wt, { "switch", "-q", L1 })
			local r = tr(wt, { "restack", "R0010" })
			t.expect(r.code).toBe(1)
			t.expect(has(say(r), theirs)).toBe(true)
			t.expect(has(say(r), mine)).toBe(true)
			t.expect(remoteSha(L2)).toBe(theirs)
			t.expect(remoteSha(L3)).toBe(base[L3])
			t.expect(localSha(L2)).toBe(mine)
		end
	)

	it(
		"AC13: a push to a layer between the stop and --continue is not overwritten: that layer's push fails its lease and stops the run",
		function()
			local lower = conflicted()
			local theirs = otherPushes(L3, "pickman/src/theirs.luau")
			clearPushes()
			resolve("merged\n")
			local r = tr(wt, { "restack", "R0010", "--continue" })
			t.expect(r.ok).toBe(false)
			t.expect(has(say(r), L3)).toBe(true)
			t.expect(has(say(r), "origin.git")).toBe(false) -- git's own words carry the remote's address: never printed
			t.expect(has(say(r), f.base)).toBe(false)
			-- the refusal names the way on: --abort, then a plain restack (--continue does not fetch)
			local abortAt = string.find(say(r), "./zn restack R0010 --abort", 1, true)
			local plainAt = string.find(say(r), "then ./zn restack R0010", 1, true)
			t.expect(abortAt ~= nil and plainAt ~= nil and (abortAt :: number) < (plainAt :: number))
				.toBe(true)
			t.expect(remoteSha(L3)).toBe(theirs) -- their commit is not overwritten, nothing above layer 3 exists
			t.expect(remoteSha(L2)).toBe(localSha(L2)) -- layer 2 passed and was pushed before layer 3 was reached
			t.expect(remoteSha(L2) ~= base[L2]).toBe(true)
			t.expect(#pushLog()).toBe(1) -- layer 2 only: layer 3's push was refused before it left
			t.expect(has(pushLog()[1], `refs/heads/{L2}`)).toBe(true)
			t.expect(remoteSha(L1)).toBe(lower)
			t.expect(restackedEvents()).toBe(0)
			t.expect(pushedRef(L2)).toBe(remoteSha(L2))
			t.expect(pushedRef(L3)).toBe(base[L3]) -- a refused push is not noted as pushed
			t.expect(show(L2, SHARED)).toBe("merged")
		end
	)

	it(
		"AC14: a rebase or resolution that empties a layer's commit stops and asks, and pushes nothing",
		function()
			reset()
			git(wt, { "switch", "-q", L1 })
			local lower = commit(wt, "pickman/src/gamma.luau", "gamma\n", "gamma already below") -- layer 3's whole change
			git(wt, { "push", "-q", "origin", L1 })
			clearPushes()
			local r = tr(wt, { "restack", "R0010" })
			t.expect(r.code).toBe(1)
			t.expect(has(say(r), "emptied")).toBe(true)
			t.expect(has(say(r), "stop and ask")).toBe(true)
			t.expect(remoteSha(L1)).toBe(lower)
			t.expect(remoteSha(L2)).toBe(localSha(L2)) -- layer 2 was restacked and passed: pushed
			t.expect(remoteSha(L2) ~= base[L2]).toBe(true)
			t.expect(#pushLog()).toBe(1)
			t.expect(has(pushLog()[1], `refs/heads/{L2}`) and not has(pushLog()[1], `refs/heads/{L3}`))
				.toBe(true)
			t.expect(remoteSha(L3)).toBe(base[L3]) -- the emptied layer is not
			t.expect(localSha(L3)).toBe(base[L3]) -- layer 3 still has its commit
			-- a resolution that drops the layer's own change
			lower = conflicted()
			clearPushes()
			resolve("fix\n")
			git(wt, { "rm", "-q", "-f", "pickman/src/beta.luau" })
			local c = tr(wt, { "restack", "R0010", "--continue" })
			t.expect(c.code).toBe(1)
			t.expect(has(say(c), "emptied")).toBe(true)
			originUnchanged(lower)
			t.expect(#pushLog()).toBe(0)
			t.expect(restackedEvents()).toBe(0)
		end
	)

	it(
		"AC15: --continue with no rebase and --abort with no rebase refuse a dirty worktree, and a mid-walk stop is resumable with the passed layers pushed",
		function()
			reset()
			git(wt, { "switch", "-q", L1 })
			local lower = commit(wt, "pickman/src/poison3.luau", "poison\n", "poison3 on layer 1")
			git(wt, { "push", "-q", "origin", L1 })
			clearPushes()
			local red = tr(wt, { "restack", "R0010" })
			t.expect(red.code).toBe(1) -- layer 3's check is red; layer 2 was restacked locally
			t.expect(has(say(red), L3)).toBe(true)
			t.expect(rebasing()).toBe(false)
			t.expect(has(marker(), "raft R0010")).toBe(true)
			local pushedTwo = localSha(L2)
			t.expect(pushedTwo ~= base[L2]).toBe(true)
			t.expect(remoteSha(L1)).toBe(lower)
			t.expect(remoteSha(L2)).toBe(pushedTwo) -- layer 2 passed: pushed on its own
			t.expect(remoteSha(L3)).toBe(base[L3]) -- layer 3 is red: not pushed
			t.expect(localSha(L3) ~= base[L3]).toBe(true) -- it keeps its restacked tip, unpushed
			t.expect(#pushLog()).toBe(1)
			t.expect(has(pushLog()[1], `refs/heads/{L2}`)).toBe(true)
			write(wt, "pickman/src/alpha.luau", "dirty\n")
			for _, mode in { "--continue", "--abort" } do
				local d = tr(wt, { "restack", "R0010", mode })
				t.expect(d.code).toBe(1)
				t.expect(has(say(d), "uncommitted")).toBe(true)
				t.expect(fs.readFile(`{wt}/pickman/src/alpha.luau`)).toBe("dirty\n")
			end
			-- a plain restack refuses it too, before it touches the stopped run's marker
			local markerBefore = marker()
			local plain = tr(wt, { "restack", "R0010" })
			t.expect(plain.code).toBe(1)
			t.expect(has(say(plain), "not clean")).toBe(true)
			t.expect(fs.readFile(`{wt}/pickman/src/alpha.luau`)).toBe("dirty\n")
			t.expect(marker()).toBe(markerBefore)
			t.expect(remoteSha(L3)).toBe(base[L3])
			git(wt, { "checkout", "--", "pickman/src/alpha.luau" })
			t.expect(tr(wt, { "restack", "R0010", "--abort" }).code).toBe(0)
			t.expect(localSha(L2)).toBe(pushedTwo) -- a layer the run pushed stays at the tip it pushed
			t.expect(localSha(L3)).toBe(base[L3])
			t.expect(remoteSha(L1)).toBe(lower)
			t.expect(remoteSha(L2)).toBe(pushedTwo)
			t.expect(remoteSha(L3)).toBe(base[L3])
			t.expect(git(wt, { "branch", "--show-current" })).toBe(L1)
		end
	)

	it(
		"AC16: --abort refuses a branch that moved since the run left it, naming it, and deletes nothing",
		function()
			local lower = conflicted()
			git(wt, { "update-ref", `refs/heads/{L3}`, M0 }) -- somebody moved layer 3 meanwhile
			local r = tr(wt, { "restack", "R0010", "--abort" })
			t.expect(r.code).toBe(1)
			t.expect(has(say(r), L3)).toBe(true)
			t.expect(localSha(L3)).toBe(M0)
			t.expect(rebasing()).toBe(true)
			git(wt, { "update-ref", `refs/heads/{L3}`, base[L3] })
			t.expect(tr(wt, { "restack", "R0010", "--abort" }).code).toBe(0)
			originUnchanged(lower)
		end
	)

	it(
		"AC17: a layer someone else fast-forwarded before the run is built on, and the first push succeeds with their commit",
		function()
			reset()
			git(wt, { "switch", "-q", L1 })
			local lower = commit(wt, "pickman/src/alpha.luau", "alpha 2\n", "alpha changed") -- layers 2 and 3 rebase cleanly
			git(wt, { "push", "-q", "origin", L1 })
			otherPushes(L3, "pickman/src/theirs.luau") -- the run's own fetch will see it
			local r = tr(wt, { "restack", "R0010" })
			t.expect(r.code).toBe(0)
			t.expect(remoteSha(L1)).toBe(lower)
			t.expect(show(L3, "pickman/src/theirs.luau")).toBe("theirs")
			t.expect(remoteSha(L3)).toBe(localSha(L3))
			t.expect(git(wt, { "rev-parse", L3 .. "~2" })).toBe(remoteSha(L2)) -- layer 3 and their commit, on layer 2
			t.expect(pushedRef(L3)).toBe(remoteSha(L3))
		end
	)

	it("AC18: a re-finish by someone else, fetched before the run, is not overwritten", function()
		reset()
		git(wt, { "switch", "-q", L2 })
		commit(wt, "pickman/src/mine.luau", "mine\n", "my local commit")
		local mine = localSha(L2)
		local o = f.other
		git(o, { "fetch", "-q", "origin" })
		git(o, { "switch", "-q", "--detach", `origin/{L2}` })
		write(o, "pickman/src/beta.luau", "beta, re-finished\n")
		git(o, { "add", "-A" })
		git(o, { "commit", "-q", "--amend", "-m", "c0020: beta" })
		git(o, { "push", "-q", "--force", "origin", `HEAD:refs/heads/{L2}` })
		local theirs = remoteSha(L2)
		git(wt, { "fetch", "-q", "origin" }) -- any earlier fetch in this clone (./zn sync --fetch, git fetch)
		git(wt, { "switch", "-q", L1 })
		local r = tr(wt, { "restack", "R0010" })
		t.expect(r.code).toBe(1)
		t.expect(has(say(r), theirs)).toBe(true)
		t.expect(has(say(r), mine)).toBe(true)
		t.expect(remoteSha(L2)).toBe(theirs)
		t.expect(localSha(L2)).toBe(mine)
	end)

	it(
		"AC19: after an abort, a local amend does not overwrite a commit the first run had only fetched",
		function()
			reset()
			git(wt, { "switch", "-q", L1 })
			commit(wt, "pickman/src/poison3.luau", "poison\n", "poison3 on layer 1")
			git(wt, { "push", "-q", "origin", L1 })
			local theirs = otherPushes(L3, "pickman/src/theirs.luau") -- a fast-forward of layer 3 by someone else
			t.expect(tr(wt, { "restack", "R0010" }).code).toBe(1) -- layer 2 is pushed; layer 3 is red, built on theirs locally
			t.expect(remoteSha(L3)).toBe(theirs)
			t.expect(tr(wt, { "restack", "R0010", "--abort" }).code).toBe(0)
			t.expect(localSha(L3)).toBe(base[L3]) -- not pushed by the run, so put back
			git(wt, { "switch", "-q", L3 })
			write(wt, "pickman/src/gamma.luau", "gamma, mine amended\n")
			git(wt, { "add", "-A" })
			git(wt, { "commit", "-q", "--amend", "--no-edit" })
			local mine = localSha(L3)
			git(wt, { "switch", "-q", L1 })
			git(wt, { "rm", "-q", "pickman/src/poison3.luau" })
			git(wt, { "commit", "-qm", "unpoison" })
			git(wt, { "push", "-q", "origin", L1 })
			local r = tr(wt, { "restack", "R0010" })
			t.expect(r.code).toBe(1)
			t.expect(has(say(r), L3)).toBe(true) -- the refusal names the layer and both tips
			t.expect(has(say(r), theirs)).toBe(true)
			t.expect(has(say(r), mine)).toBe(true)
			t.expect(remoteSha(L3)).toBe(theirs)
			t.expect(fixture.exec(wt, "git", { "cat-file", "-e", `origin/{L3}:pickman/src/theirs.luau` }).ok)
				.toBe(true)
		end
	)

	it(
		"AC20: abort after a continue and a later red check puts every unpushed branch back and keeps the pushed one",
		function()
			reset()
			git(wt, { "switch", "-q", L1 })
			commit(wt, "pickman/src/poison3.luau", "poison\n", "poison3 on layer 1")
			local lower = amendLower() -- layer 2 conflicts, layer 3 will be red
			t.expect(tr(wt, { "restack", "R0010" }).code).toBe(3)
			resolve("merged\n")
			clearPushes()
			t.expect(tr(wt, { "restack", "R0010", "--continue" }).code).toBe(1)
			t.expect(#pushLog()).toBe(1)
			t.expect(has(pushLog()[1], `refs/heads/{L2}`)).toBe(true)
			local pushedTwo = localSha(L2)
			t.expect(pushedTwo ~= base[L2]).toBe(true)
			local a = tr(wt, { "restack", "R0010", "--abort" })
			t.expect(a.code).toBe(0)
			t.expect(localSha(L2)).toBe(pushedTwo) -- resolved, checked and pushed by the continue: stays
			t.expect(localSha(L3)).toBe(base[L3])
			t.expect(remoteSha(L1)).toBe(lower)
			t.expect(remoteSha(L2)).toBe(pushedTwo)
			t.expect(remoteSha(L3)).toBe(base[L3])
			t.expect(git(wt, { "branch", "--show-current" })).toBe(L1)
		end
	)

	it(
		"AC21: a layer this clone did not push (a fresh clone) is refused when it has diverged, naming both tips and what to do",
		function()
			reset()
			local lower = amendLower()
			git(wt, { "switch", "-q", L2 })
			t.expect(fixture.exec(wt, "git", { "rebase", "--onto", lower, base[L1], L2 }).ok).toBe(false)
			write(wt, SHARED, "merged\n")
			git(wt, { "add", SHARED })
			git(wt, { "-c", "core.editor=true", "rebase", "--continue" })
			local mine = localSha(L2)
			git(wt, { "switch", "-q", L1 })
			git(wt, { "update-ref", "-d", `refs/zn/pushed/{L2}` }) -- nothing says this clone pushed layer 2
			local r = tr(wt, { "restack", "R0010" })
			t.expect(r.code).toBe(1)
			t.expect(has(say(r), mine)).toBe(true)
			t.expect(has(say(r), base[L2])).toBe(true)
			t.expect(has(say(r), "fetch")).toBe(true)
			t.expect(remoteSha(L2)).toBe(base[L2])
			t.expect(localSha(L2)).toBe(mine)
		end
	)

	it(
		"AC22: a layer this clone pushed and then amended locally is trusted: it is restacked and pushed",
		function()
			reset()
			git(wt, { "switch", "-q", L2 })
			write(wt, "pickman/src/beta.luau", "beta amended\n")
			git(wt, { "add", "-A" })
			git(wt, { "commit", "-q", "--amend", "--no-edit" })
			local amended = localSha(L2)
			git(wt, { "switch", "-q", L1 })
			commit(wt, "pickman/src/alpha.luau", "alpha 2\n", "alpha changed")
			git(wt, { "push", "-q", "origin", L1 })
			local r = tr(wt, { "restack", "R0010" })
			t.expect(r.code).toBe(0)
			t.expect(show(L2, "pickman/src/beta.luau")).toBe("beta amended")
			t.expect(remoteSha(L2)).toBe(localSha(L2))
			t.expect(localSha(L2) ~= amended).toBe(true) -- rebased onto the new layer 1
			t.expect(git(wt, { "rev-parse", L3 .. "^" })).toBe(remoteSha(L2))
			t.expect(pushedRef(L2)).toBe(remoteSha(L2))
		end
	)

	it(
		"AC23: someone pushes and a fetch follows between the stop and --continue: that layer's push fails its lease and origin keeps their commit",
		function()
			local lower = conflicted()
			local theirs = otherPushes(L3, "pickman/src/theirs.luau")
			git(wt, { "fetch", "-q", "origin" })
			resolve("merged\n")
			clearPushes()
			local r = tr(wt, { "restack", "R0010", "--continue" })
			t.expect(r.ok).toBe(false)
			t.expect(remoteSha(L3)).toBe(theirs)
			t.expect(remoteSha(L2)).toBe(localSha(L2)) -- layer 2 was pushed before layer 3 was reached
			t.expect(remoteSha(L2) ~= base[L2]).toBe(true)
			t.expect(#pushLog()).toBe(1)
			t.expect(has(pushLog()[1], `refs/heads/{L2}`)).toBe(true)
			t.expect(remoteSha(L1)).toBe(lower)
			t.expect(pushedRef(L3)).toBe(base[L3])
			-- followed literally, the way on the refusal names keeps their commit and finishes the stack
			local pushedTwo = remoteSha(L2)
			t.expect(tr(wt, { "restack", "R0010", "--abort" }).code).toBe(0)
			local again = tr(wt, { "restack", "R0010" })
			t.expect(again.code).toBe(0)
			t.expect(remoteSha(L2)).toBe(pushedTwo)
			t.expect(remoteSha(L3)).toBe(localSha(L3))
			t.expect(show(L3, "pickman/src/theirs.luau")).toBe("theirs")
			t.expect(git(wt, { "rev-parse", L3 .. "~2" })).toBe(pushedTwo)
		end
	)

	it("AC24: a marker with no conflict recorded and a rebase in progress is a stopped restack", function()
		conflicted()
		local keep: { string } = {}
		for line in string.gmatch(marker(), "[^\n]+") do
			if string.sub(line, 1, 8) ~= "conflict" and string.sub(line, 1, 4) ~= "file" then
				table.insert(keep, line)
			end
		end
		fs.writeFile(`{gitDir()}/zn-restack.state`, table.concat(keep, "\n") .. "\n")
		local again = say(tr(wt, { "restack", "R0010" }))
		t.expect(has(again, "./zn restack R0010 --continue")).toBe(true)
		t.expect(has(again, "./zn restack R0010 --abort")).toBe(true)
		t.expect(has(say(tr(f.main, { "work", "next", "R0010" })), "./zn restack R0010 --continue"))
			.toBe(true)
		resolve("merged\n")
		t.expect(tr(wt, { "restack", "R0010", "--continue" }).code).toBe(0)
		t.expect(remoteSha(L3)).toBe(localSha(L3))
	end)

	it(
		"AC25: after an abort that left pushed layers, a plain restack picks up from them and finishes the stack",
		function()
			-- --continue from the half-published state (layer 2 pushed, layer 3 conflicted) pushes layer 3 alone
			reset()
			git(wt, { "switch", "-q", L1 })
			commit(wt, "pickman/src/gamma.luau", "other\n", "gamma on layer 1")
			git(wt, { "push", "-q", "origin", L1 })
			t.expect(tr(wt, { "restack", "R0010" }).code).toBe(3)
			local pushedBefore = remoteSha(L2)
			clearPushes()
			write(wt, "pickman/src/gamma.luau", "merged gamma\n")
			git(wt, { "add", "pickman/src/gamma.luau" })
			t.expect(tr(wt, { "restack", "R0010", "--continue" }).code).toBe(0)
			t.expect(remoteSha(L2)).toBe(pushedBefore)
			t.expect(#pushLog()).toBe(1)
			t.expect(has(pushLog()[1], `refs/heads/{L3}`) and not has(pushLog()[1], `refs/heads/{L2}`))
				.toBe(true)
			reset()
			git(wt, { "switch", "-q", L1 })
			local lowerGamma = commit(wt, "pickman/src/gamma.luau", "other\n", "gamma on layer 1")
			git(wt, { "push", "-q", "origin", L1 })
			t.expect(tr(wt, { "restack", "R0010" }).code).toBe(3) -- layer 2 pushed, layer 3 conflicts
			local pushedTwo = localSha(L2)
			t.expect(remoteSha(L2)).toBe(pushedTwo)
			t.expect(tr(wt, { "restack", "R0010", "--abort" }).code).toBe(0)
			t.expect(remoteSha(L2)).toBe(pushedTwo)
			t.expect(remoteSha(L3)).toBe(base[L3])
			-- origin's stack is half moved: layer 1 and 2 are new, layer 3 still rests on the old layer 2. A later restack
			-- starts from the pushed layers: it rebases only layer 3, and stops on the same conflict
			clearPushes()
			local again = tr(wt, { "restack", "R0010" })
			t.expect(again.code).toBe(3)
			t.expect(has(say(again), L3)).toBe(true)
			t.expect(remoteSha(L2)).toBe(pushedTwo)
			t.expect(localSha(L2)).toBe(pushedTwo)
			t.expect(#pushLog()).toBe(0)
			write(wt, "pickman/src/gamma.luau", "merged gamma\n")
			git(wt, { "add", "pickman/src/gamma.luau" })
			local done = tr(wt, { "restack", "R0010", "--continue" })
			t.expect(done.code).toBe(0)
			t.expect(remoteSha(L1)).toBe(lowerGamma)
			t.expect(remoteSha(L2)).toBe(pushedTwo)
			t.expect(remoteSha(L3)).toBe(localSha(L3))
			t.expect(git(wt, { "rev-parse", L3 .. "^" })).toBe(pushedTwo)
			t.expect(git(wt, { "rev-parse", L2 .. "^" })).toBe(lowerGamma)
			t.expect(#pushLog()).toBe(1) -- only layer 3 went
			t.expect(has(say(tr(wt, { "restack", "R0010" })), "already stacked")).toBe(true)
		end
	)

	it(
		"AC26: a red check above a pushed layer leaves the restacked tip to fix: fix, finish and restack complete it without a loop",
		function()
			reset()
			git(wt, { "switch", "-q", L1 })
			local lower = commit(wt, "pickman/src/poison.luau", "poison\n", "poison layer 1")
			git(wt, { "push", "-q", "origin", L1 })
			clearPushes()
			local red = tr(wt, { "restack", "R0010" })
			t.expect(red.code).toBe(1)
			t.expect(has(say(red), "./zn finish c0020")).toBe(true)
			t.expect(has(say(red), "not pushed")).toBe(true)
			local redTip = localSha(L2)
			t.expect(git(wt, { "rev-parse", L2 .. "^" })).toBe(lower)
			t.expect(remoteSha(L2)).toBe(base[L2])
			-- work next names the fix on that tip, not the restack that would hit the same red check again
			local asked = say(tr(f.main, { "work", "next", "R0010" }))
			t.expect(has(asked, "R0010: restack - ")).toBe(true)
			t.expect(has(asked, "./zn finish c0020")).toBe(true)
			t.expect(has(asked, "Run ./zn restack R0010, then ask again.")).toBe(false)
			-- a plain restack with nothing fixed stops at the same layer and loses nothing
			local again = tr(wt, { "restack", "R0010" })
			t.expect(again.code).toBe(1)
			t.expect(has(say(again), "check.sh failed")).toBe(true)
			t.expect(localSha(L2)).toBe(redTip)
			t.expect(remoteSha(L2)).toBe(base[L2])
			-- the fix: drop the poison on the layer, then finish it
			git(wt, { "switch", "-q", L2 })
			git(wt, { "rm", "-q", "pickman/src/poison.luau" })
			git(wt, { "commit", "-qm", "fix layer 2" })
			local fin = tr(wt, { "finish", "c0020" })
			t.expect(fin.code).toBe(0)
			t.expect(remoteSha(L2)).toBe(localSha(L2))
			local fixed = localSha(L2)
			git(wt, { "switch", "-q", L1 })
			local after = say(tr(f.main, { "work", "next", "R0010" }))
			t.expect(has(after, "./zn finish c0020")).toBe(false)
			clearPushes()
			local done = tr(wt, { "restack", "R0010" })
			t.expect(done.code).toBe(0)
			t.expect(localSha(L2)).toBe(fixed) -- the fixed layer is not rebuilt
			t.expect(remoteSha(L1)).toBe(lower)
			t.expect(remoteSha(L2)).toBe(fixed)
			t.expect(remoteSha(L3)).toBe(localSha(L3))
			t.expect(git(wt, { "rev-parse", L3 .. "^" })).toBe(fixed)
			t.expect(show(L2, "pickman/src/beta.luau")).toBe("beta")
			t.expect(#pushLog()).toBe(1)
			t.expect(has(pushLog()[1], `refs/heads/{L3}`)).toBe(true)
			t.expect(has(say(tr(wt, { "restack", "R0010" })), "already stacked")).toBe(true)
		end
	)

	it(
		"AC27: --continue after main moved again re-pushes a layer it pushed under the lease of its own push, and --abort puts it back on its pushed tip",
		function()
			-- main moves: layer 1 rebases cleanly and is pushed, layer 2 conflicts on the file main added
			reset()
			mainMoves({ ["pickman/src/beta.luau"] = "main beta\n" }, "main adds beta")
			t.expect(tr(wt, { "restack", "R0010" }).code).toBe(3)
			t.expect(git(wt, { "diff", "--name-only", "--diff-filter=U" })).toBe("pickman/src/beta.luau")
			local n1 = remoteSha(L1)
			t.expect(n1 ~= base[L1]).toBe(true)
			t.expect(has(marker(), `pushed {L1} {n1}`)).toBe(true)
			-- main moves again and a fetch follows: the continue rebases layer 1 again and pushes it
			mainMoves({ ["pickman/src/other.luau"] = "other\n" }, "main adds other")
			git(wt, { "fetch", "-q", "origin" })
			write(wt, "pickman/src/beta.luau", "merged beta\n")
			git(wt, { "add", "pickman/src/beta.luau" })
			clearPushes()
			local done = tr(wt, { "restack", "R0010", "--continue" })
			t.expect(done.code).toBe(0)
			t.expect(has(say(done), "was refused")).toBe(false)
			t.expect(remoteSha(L1)).toBe(localSha(L1))
			t.expect(remoteSha(L1) ~= n1).toBe(true)
			t.expect(git(wt, { "rev-parse", L1 .. "^" })).toBe(remoteSha("main"))
			t.expect(remoteSha(L2)).toBe(localSha(L2))
			t.expect(remoteSha(L3)).toBe(localSha(L3))
			t.expect(git(wt, { "rev-parse", L2 .. "^" })).toBe(remoteSha(L1))
			t.expect(git(wt, { "rev-parse", L3 .. "^" })).toBe(remoteSha(L2))
			t.expect(#pushLog()).toBe(3)
			-- the same, but main's second move makes layer 1's check red: abort puts layer 1 back on the tip it pushed
			reset()
			mainMoves({ ["pickman/src/beta.luau"] = "main beta\n" }, "main adds beta")
			t.expect(tr(wt, { "restack", "R0010" }).code).toBe(3)
			local pushedOne = remoteSha(L1)
			mainMoves({ ["pickman/src/poison1.luau"] = "poison\n" }, "main adds poison1")
			git(wt, { "fetch", "-q", "origin" })
			write(wt, "pickman/src/beta.luau", "merged beta\n")
			git(wt, { "add", "pickman/src/beta.luau" })
			local red = tr(wt, { "restack", "R0010", "--continue" })
			t.expect(red.code).toBe(1)
			t.expect(has(say(red), L1)).toBe(true)
			t.expect(has(say(red), "check.sh failed")).toBe(true)
			t.expect(localSha(L1) ~= pushedOne).toBe(true) -- rebased again, red, kept locally
			t.expect(remoteSha(L1)).toBe(pushedOne)
			local aborted = tr(wt, { "restack", "R0010", "--abort" })
			t.expect(aborted.code).toBe(0)
			t.expect(localSha(L1)).toBe(pushedOne)
			t.expect(remoteSha(L1)).toBe(pushedOne)
			t.expect(has(say(aborted), L1)).toBe(true)
			t.expect(localSha(L2)).toBe(base[L2])
			t.expect(localSha(L3)).toBe(base[L3])
			t.expect(remoteSha(L2)).toBe(base[L2])
			t.expect(remoteSha(L3)).toBe(base[L3])
			-- the same with the run started on layer 3: layer 1 is not the branch the abort ends on, and still goes back
			-- to the tip it pushed (review 001 F4)
			reset()
			git(wt, { "switch", "-q", L3 })
			mainMoves({ ["pickman/src/beta.luau"] = "main beta\n" }, "main adds beta")
			t.expect(tr(wt, { "restack", "R0010" }).code).toBe(3)
			pushedOne = remoteSha(L1)
			mainMoves({ ["pickman/src/poison1.luau"] = "poison\n" }, "main adds poison1")
			git(wt, { "fetch", "-q", "origin" })
			write(wt, "pickman/src/beta.luau", "merged beta\n")
			git(wt, { "add", "pickman/src/beta.luau" })
			t.expect(tr(wt, { "restack", "R0010", "--continue" }).code).toBe(1)
			t.expect(localSha(L1) ~= pushedOne).toBe(true)
			t.expect(tr(wt, { "restack", "R0010", "--abort" }).code).toBe(0)
			t.expect(git(wt, { "branch", "--show-current" })).toBe(L3)
			t.expect(localSha(L1)).toBe(pushedOne)
			t.expect(remoteSha(L1)).toBe(pushedOne)
			t.expect(localSha(L2)).toBe(base[L2])
		end
	)

	it(
		"AC28: a restack killed around its push leaves a marker that --continue, --abort and the next restack reconcile with origin",
		function()
			local function moved(): string
				reset()
				git(wt, { "switch", "-q", L1 })
				local lower = commit(wt, "pickman/src/alpha.luau", "alpha 2\n", "alpha changed")
				git(wt, { "push", "-q", "origin", L1 })
				return lower
			end
			-- killed after the push, before it was noted: the next restack notes it
			moved()
			t.expect(trKill("after-push", { "restack", "R0010" }).ok).toBe(false)
			local two = remoteSha(L2)
			t.expect(two ~= base[L2]).toBe(true)
			t.expect(pushedRef(L2)).toBe(base[L2])
			t.expect(tr(wt, { "restack", "R0010" }).code).toBe(0)
			t.expect(pushedRef(L2)).toBe(two)
			t.expect(remoteSha(L2)).toBe(two)
			t.expect(remoteSha(L3)).toBe(localSha(L3))
			-- killed after the push, then --continue (no rebase in progress): it notes the push and pushes only what is left
			moved()
			t.expect(trKill("after-push", { "restack", "R0010" }).ok).toBe(false)
			two = remoteSha(L2)
			t.expect(pushedRef(L2)).toBe(base[L2])
			clearPushes()
			t.expect(tr(wt, { "restack", "R0010", "--continue" }).code).toBe(0)
			t.expect(pushedRef(L2)).toBe(two)
			t.expect(remoteSha(L2)).toBe(two)
			t.expect(remoteSha(L3)).toBe(localSha(L3))
			t.expect(#pushLog()).toBe(1)
			t.expect(has(pushLog()[1], `refs/heads/{L3}`) and not has(pushLog()[1], `refs/heads/{L2}`))
				.toBe(true)
			-- killed between the note and the marker line, then --abort: the layer stays, it is not reset
			moved()
			t.expect(trKill("after-note", { "restack", "R0010" }).ok).toBe(false)
			two = remoteSha(L2)
			t.expect(two ~= base[L2]).toBe(true)
			local abortB = tr(wt, { "restack", "R0010", "--abort" })
			t.expect(abortB.code).toBe(0)
			t.expect(localSha(L2)).toBe(two)
			t.expect(has(say(abortB), L2)).toBe(true)
			t.expect(has(say(abortB), "nothing had been pushed")).toBe(false)
			t.expect(localSha(L3)).toBe(base[L3])
			-- killed after the push and before both records, then --abort: the layer stays and is noted
			moved()
			t.expect(trKill("after-push", { "restack", "R0010" }).ok).toBe(false)
			two = remoteSha(L2)
			local abortC = tr(wt, { "restack", "R0010", "--abort" })
			t.expect(abortC.code).toBe(0)
			t.expect(localSha(L2)).toBe(two)
			t.expect(pushedRef(L2)).toBe(two)
			t.expect(has(say(abortC), "nothing had been pushed")).toBe(false)
			-- killed before the push: nothing reached origin, so the abort puts the layer back
			moved()
			t.expect(trKill("before-push", { "restack", "R0010" }).ok).toBe(false)
			t.expect(remoteSha(L2)).toBe(base[L2])
			t.expect(tr(wt, { "restack", "R0010", "--abort" }).code).toBe(0)
			t.expect(localSha(L2)).toBe(base[L2])
			t.expect(pushedRef(L2)).toBe(base[L2])
		end
	)

	it(
		"AC29: a layer not on origin is pushed under a must-not-exist lease, and a layer a run created and pushed stays after --abort",
		function()
			reset()
			git(wt, { "push", "-q", "origin", `:refs/heads/{L3}` }) -- layer 3 is not on origin
			git(wt, { "update-ref", "-d", `refs/remotes/origin/{L3}` })
			amendLower()
			t.expect(tr(wt, { "restack", "R0010" }).code).toBe(3)
			local o = f.other -- somebody creates layer 3 on origin before the continue
			git(o, { "fetch", "-q", "origin" })
			git(o, { "switch", "-q", "--detach", `origin/{L2}` })
			commit(o, "pickman/src/theirs.luau", "theirs\n", "someone else's layer 3")
			git(o, { "push", "-q", "origin", `HEAD:refs/heads/{L3}` })
			local theirs = remoteSha(L3)
			resolve("merged\n")
			local r = tr(wt, { "restack", "R0010", "--continue" })
			t.expect(r.ok).toBe(false)
			t.expect(remoteSha(L3)).toBe(theirs)
			t.expect(pushedRef(L3)).toBe(base[L3])
			-- a layer with no local branch, created and pushed by the run, is kept by --abort
			reset()
			git(wt, { "switch", "-q", L1 })
			commit(wt, "pickman/src/poison3.luau", "poison\n", "poison3 on layer 1")
			git(wt, { "push", "-q", "origin", L1 })
			git(wt, { "branch", "-D", "-q", L2 })
			t.expect(tr(wt, { "restack", "R0010" }).code).toBe(1) -- layer 3 is red
			local created = remoteSha(L2)
			t.expect(created ~= base[L2]).toBe(true)
			t.expect(localSha(L2)).toBe(created)
			t.expect(tr(wt, { "restack", "R0010", "--abort" }).code).toBe(0)
			t.expect(localSha(L2)).toBe(created)
			t.expect(remoteSha(L2)).toBe(created)
			-- a layer with no local branch that a run created and did not push is deleted again by --abort
			reset()
			git(wt, { "branch", "-D", "-q", L2 })
			amendLower()
			t.expect(tr(wt, { "restack", "R0010" }).code).toBe(3) -- layer 2 is created from origin and conflicts
			t.expect(tr(wt, { "restack", "R0010", "--abort" }).code).toBe(0)
			t.expect(fixture.exec(wt, "git", { "rev-parse", "--verify", "--quiet", `refs/heads/{L2}` }).ok)
				.toBe(false)
			t.expect(remoteSha(L2)).toBe(base[L2])
		end
	)

	it(
		"AC30: a check that did not start (exit 75) is not a red check: restack exits 75, records no red, pushes nothing, and the next restack runs the check again",
		function()
			reset()
			git(wt, { "switch", "-q", L1 })
			commit(wt, "pickman/src/busy.luau", "busy\n", "gate busy on layer 1") -- layer 2's check exits 75
			git(wt, { "push", "-q", "origin", L1 })
			clearPushes()
			local r = tr(wt, { "restack", "R0010" })
			t.expect(r.code).toBe(75)
			t.expect(has(say(r), "did not start")).toBe(true)
			t.expect(has(say(r), "./zn restack R0010")).toBe(true)
			t.expect(has(say(r), "check.sh failed")).toBe(false)
			t.expect(has(marker(), "red ")).toBe(false)
			t.expect(has(marker(), "raft R0010")).toBe(true) -- a marker a later run can resume from
			t.expect(rebasing()).toBe(false)
			t.expect(git(wt, { "branch", "--show-current" })).toBe(L1)
			t.expect(remoteSha(L2)).toBe(base[L2])
			t.expect(remoteSha(L3)).toBe(base[L3])
			t.expect(#pushLog()).toBe(0)
			t.expect(has(say(tr(f.main, { "work", "next", "R0010" })), "./zn finish c0020")).toBe(false)
			-- the machine is free again (the layer below drops the file): the next restack runs the check and finishes
			git(wt, { "rm", "-q", "pickman/src/busy.luau" })
			git(wt, { "commit", "-qm", "gate free" })
			git(wt, { "push", "-q", "origin", L1 })
			local again = tr(wt, { "restack", "R0010" })
			t.expect(again.code).toBe(0)
			t.expect(remoteSha(L2)).toBe(localSha(L2))
			t.expect(remoteSha(L3)).toBe(localSha(L3))
			t.expect(git(wt, { "rev-parse", L3 .. "^" })).toBe(remoteSha(L2))
			t.expect(marker()).toBe("")
		end
	)

	it(
		"AC32: --continue refuses a layer the run moved that is back at its tip from before the run, and git branch -f to the tip it left keeps the staged resolution",
		function()
			reset()
			mainMoves({ ["pickman/src/beta.luau"] = "main beta\n" }, "main adds beta") -- layer 1 pushed, layer 2 conflicts
			t.expect(tr(wt, { "restack", "R0010" }).code).toBe(3)
			local left = remoteSha(L1)
			t.expect(left ~= base[L1]).toBe(true)
			git(wt, { "update-ref", `refs/heads/{L1}`, base[L1] }) -- what an older engine or a hand reset leaves
			write(wt, "pickman/src/beta.luau", "the worker's resolution\n")
			git(wt, { "add", "pickman/src/beta.luau" })
			clearPushes()
			local r = tr(wt, { "restack", "R0010", "--continue" })
			local out = say(r)
			t.expect(r.code).toBe(1)
			for _, part in { L1, left, base[L1], "c0010: alpha", "git log --oneline", "discards" } do
				t.expect(has(out, part)).toBe(true)
			end
			local moveAt = string.find(out, `git branch -f {L1} {left}`, 1, true)
			local continueAt = string.find(out, "./zn restack R0010 --continue", 1, true)
			local abortAt = string.find(out, "./zn restack R0010 --abort", 1, true)
			t.expect(moveAt ~= nil and continueAt ~= nil and abortAt ~= nil).toBe(true)
			t.expect(
				(moveAt :: number) < (continueAt :: number) and (continueAt :: number) < (abortAt :: number)
			)
				.toBe(true)
			t.expect(has(out, "reset")).toBe(false) -- never a reset as the way on
			t.expect(has(out, L3)).toBe(false) -- the untouched layer is not named
			t.expect(rebasing()).toBe(true)
			t.expect(has(git(wt, { "diff", "--cached", "--name-only" }), "pickman/src/beta.luau")).toBe(true) -- still staged
			t.expect(#pushLog()).toBe(0)
			t.expect(remoteSha(L1)).toBe(left)
			-- the first way it names, followed literally: the resolution reaches origin
			git(wt, { "branch", "-f", L1, left })
			t.expect(tr(wt, { "restack", "R0010", "--continue" }).code).toBe(0)
			t.expect(remoteSha(L1)).toBe(left)
			t.expect(show(`origin/{L2}`, "pickman/src/beta.luau")).toBe("the worker's resolution")
			t.expect(remoteSha(L3)).toBe(localSha(L3))
			-- the second way: --abort puts the pushed layer on the tip it pushed, and names the move
			reset()
			mainMoves({ ["pickman/src/beta.luau"] = "main beta\n" }, "main adds beta")
			t.expect(tr(wt, { "restack", "R0010" }).code).toBe(3)
			left = remoteSha(L1)
			git(wt, { "update-ref", `refs/heads/{L1}`, base[L1] })
			t.expect(tr(wt, { "restack", "R0010", "--continue" }).code).toBe(1)
			local aborted = tr(wt, { "restack", "R0010", "--abort" })
			t.expect(aborted.code).toBe(0)
			t.expect(localSha(L1)).toBe(left)
			t.expect(has(say(aborted), `{L1}: {base[L1]} -> {left}`)).toBe(true)
			-- an amend of the layer the run pushed, made while its rebase is in progress, is the worker's change
			reset()
			mainMoves({ ["pickman/src/beta.luau"] = "main beta\n" }, "main adds beta")
			t.expect(tr(wt, { "restack", "R0010" }).code).toBe(3)
			left = remoteSha(L1)
			-- made in the main checkout, which shares the worktree's repository: the worktree is mid-rebase
			git(f.main, { "switch", "-q", "--detach", left })
			write(f.main, "pickman/src/alpha.luau", "alpha amended\n")
			git(f.main, { "add", "-A" })
			git(f.main, { "commit", "-q", "--amend", "--no-edit" })
			local amended = git(f.main, { "rev-parse", "HEAD" })
			git(f.main, { "switch", "-q", "main" })
			git(wt, { "update-ref", `refs/heads/{L1}`, amended })
			write(wt, "pickman/src/beta.luau", "merged beta\n")
			git(wt, { "add", "pickman/src/beta.luau" })
			t.expect(tr(wt, { "restack", "R0010", "--continue" }).code).toBe(0)
			t.expect(remoteSha(L1)).toBe(amended)
			t.expect(git(wt, { "rev-parse", L2 .. "^" })).toBe(amended)
			t.expect(remoteSha(L3)).toBe(localSha(L3))
		end
	)

	it(
		"AC33: --abort after a plain restack over a stopped run's marker keeps every commit the worker made or resolved",
		function()
			local function lowerPoisonsTwo(
				text: string
			): string -- layer 1 changes shared.luau and poisons layer 2's check
				git(wt, { "switch", "-q", L1 })
				write(wt, SHARED, text)
				local sha = commit(wt, "pickman/src/poison.luau", "poison\n", "fix layer 1, poison layer 2")
				git(wt, { "push", "-q", "origin", L1 })
				git(wt, { "update-ref", `refs/zn/pushed/{L1}`, sha })
				return sha
			end
			-- a resolution a red check kept, then a plain restack with nothing fixed, then --abort (code review 001 probe B)
			reset()
			lowerPoisonsTwo("fix\n")
			t.expect(tr(wt, { "restack", "R0010" }).code).toBe(3)
			resolve("merged\n")
			t.expect(tr(wt, { "restack", "R0010", "--continue" }).code).toBe(1)
			local resolved = localSha(L2)
			t.expect(tr(wt, { "restack", "R0010" }).code).toBe(1)
			t.expect(has(marker(), `orig {L2} {resolved}`)).toBe(true) -- the new run starts from where it finds it
			local aborted = tr(wt, { "restack", "R0010", "--abort" })
			t.expect(aborted.code).toBe(0)
			t.expect(localSha(L2)).toBe(resolved)
			-- the same with layer 1 fixed again between the runs, so the second run conflicts again (probe B2)
			reset()
			lowerPoisonsTwo("fix\n")
			t.expect(tr(wt, { "restack", "R0010" }).code).toBe(3)
			resolve("merged\n")
			t.expect(tr(wt, { "restack", "R0010", "--continue" }).code).toBe(1)
			resolved = localSha(L2)
			git(wt, { "switch", "-q", L1 })
			git(wt, { "rm", "-q", "pickman/src/poison.luau" })
			write(wt, SHARED, "fix again\n")
			git(wt, { "add", "-A" })
			git(wt, { "commit", "-qm", "fix layer 1 again" })
			git(wt, { "push", "-q", "origin", L1 })
			git(wt, { "update-ref", `refs/zn/pushed/{L1}`, localSha(L1) })
			t.expect(tr(wt, { "restack", "R0010" }).code).toBe(3)
			t.expect(tr(wt, { "restack", "R0010", "--abort" }).code).toBe(0)
			t.expect(localSha(L2)).toBe(resolved)
			-- the run created layer 2 (this worktree had no branch for it); the worker switches to it and restacks again
			-- (probe E): --abort keeps the branch the worktree is on, and the worktree
			reset()
			git(wt, { "branch", "-D", "-q", L2 })
			git(wt, { "switch", "-q", L1 })
			local lower = commit(wt, "pickman/src/poison.luau", "poison\n", "poison layer 2's check")
			git(wt, { "push", "-q", "origin", L1 })
			git(wt, { "update-ref", `refs/zn/pushed/{L1}`, lower })
			t.expect(tr(wt, { "restack", "R0010" }).code).toBe(1) -- layer 2 created from origin, rebased, red
			local created = localSha(L2)
			git(wt, { "switch", "-q", L2 })
			t.expect(tr(wt, { "restack", "R0010" }).code).toBe(1)
			t.expect(tr(wt, { "restack", "R0010", "--abort" }).code).toBe(0)
			t.expect(git(wt, { "branch", "--show-current" })).toBe(L2)
			t.expect(localSha(L2)).toBe(created)
			t.expect(fixture.exec(wt, "git", { "rev-parse", "--verify", "HEAD" }).ok).toBe(true)
			t.expect(git(wt, { "status", "--porcelain" })).toBe("")
		end
	)

	it(
		"AC34: a recorded resolution is never reused, and a layer with a commit above its finish commit stops on each conflict",
		function()
			reset()
			git(wt, { "switch", "-q", L2 }) -- layer 2 gains a worker commit above its finish commit, pushed by this clone
			local more = commit(wt, SHARED, "three\n", "R0010: more beta")
			git(wt, { "push", "-q", "origin", L2 })
			git(wt, { "update-ref", `refs/zn/pushed/{L2}`, more })
			local common = git(wt, { "rev-parse", "--path-format=absolute", "--git-common-dir" })
			local ok, err = pcall(function()
				git(wt, { "config", "rerere.enabled", "true" })
				local lower = amendLower()
				-- both resolutions recorded by rerere, by hand: a rerere that ran would apply them
				git(wt, { "switch", "-q", "--detach", lower })
				t.expect(fixture.exec(wt, "git", { "cherry-pick", base[L2] }).ok).toBe(false)
				resolve("merged\n")
				git(wt, { "-c", "core.editor=true", "cherry-pick", "--continue" })
				t.expect(fixture.exec(wt, "git", { "cherry-pick", more }).ok).toBe(false)
				resolve("merged three\n")
				git(wt, { "-c", "core.editor=true", "cherry-pick", "--continue" })
				git(wt, { "switch", "-q", L1 })
				t.expect(tr(wt, { "restack", "R0010" }).code).toBe(3)
				t.expect(has(fs.readFile(`{wt}/{SHARED}`), "<<<<<<<")).toBe(true) -- not the recorded "merged"
				t.expect(has(marker(), `conflict {L2} 2`)).toBe(true)
				resolve("merged\n")
				local second = tr(wt, { "restack", "R0010", "--continue" })
				t.expect(second.code).toBe(3) -- the layer's second commit conflicts inside the same continue
				t.expect(has(say(second), SHARED)).toBe(true)
				t.expect(rebasing()).toBe(true)
				t.expect(has(fs.readFile(`{wt}/{SHARED}`), "<<<<<<<")).toBe(true) -- not the recorded "merged three"
				t.expect(remoteSha(L2)).toBe(more)
				local aborted = tr(wt, { "restack", "R0010", "--abort" })
				t.expect(aborted.code).toBe(0)
				t.expect(localSha(L2)).toBe(more)
				t.expect(remoteSha(L2)).toBe(more)
				t.expect(localSha(L3)).toBe(base[L3])
			end)
			fixture.exec(wt, "git", { "config", "--unset", "rerere.enabled" })
			if fs.isDir(`{common}/rr-cache`) then
				fs.removeDir(`{common}/rr-cache`)
			end
			if not ok then
				error(err, 0)
			end
		end
	)
end)
