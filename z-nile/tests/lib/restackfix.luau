--!strict
-- d0434: the fixture of the fast restack guards (`tests/tooling/restack-guard.spec.luau`, `restack-stray.spec.luau`).
-- Three layers in real git, under the caller's own `.cache/<name>` (a bare origin and a worktree for R0010):
--   M0 <- A1 (R0010/1/c0010: alpha.luau, shared.luau "one") <- B1 (R0010/2/c0020: beta.luau, shared.luau "two")
--      <- C1 (R0010/3/c0030: gamma.luau)
-- Layer n's check is red while `src/poison<n>.luau` exists and does not start (exit 75) while `src/busy<n>.luau` does.
-- Every case starts from that state (`reset`). One fixture per spec file: each spec runs in its own process.
local fixture = require("@tests/lib/fixture")
local fs = require("@lune/fs")
local process = require("@lune/process")
local trackerfix = require("@tests/lib/trackerfix")

local restackfix = {}

restackfix.L1, restackfix.L2, restackfix.L3 = "R0010/1/c0010", "R0010/2/c0020", "R0010/3/c0030"
restackfix.SHARED = "pickman/src/shared.luau"
restackfix.BETA = "pickman/src/beta.luau"

local L1, L2, L3 = restackfix.L1, restackfix.L2, restackfix.L3
local TOP = (string.gsub(process.exec("git", { "rev-parse", "--show-toplevel" }).stdout, "%s+$", ""))
local PREPARED = "prepared-quiet-copper-falcon"
local HEAD =
	'source "$(git -C "$(dirname "${BASH_SOURCE[0]}")" rev-parse --show-toplevel)/scripts/lib/ac.sh"\n'
local CAPTURED =
	"## Problem\nThe marker is missing.\n\n## Solution\nStore the marker.\n\n## Acceptance criteria\n- AC1: the marker is stored\n"

local function poisonCheck(n: number): string
	return HEAD
		.. `check "AC1: no poison{n}" test ! -f src/poison{n}.luau\n`
		.. `check "AC2: gate free" sh -c 'test ! -f src/busy{n}.luau || exit 75'\n`
		.. "finish\n"
end

export type Ctx = {
	f: trackerfix.Fixture,
	wt: string,
	env: { [string]: string },
	base: { [string]: string },
	M0: string,
	MAIN0: string,
}

local ctx: Ctx = nil :: any

function restackfix.ctx(): Ctx
	return ctx
end

function restackfix.git(dir: string, args: { string }): string
	return fixture.git(dir, args)
end
local git = restackfix.git

function restackfix.try(dir: string, args: { string }): fixture.Result
	return fixture.exec(dir, "git", args)
end

function restackfix.has(s: string, part: string): boolean
	return string.find(s, part, 1, true) ~= nil
end

-- where `part` first appears in `s`, or nil
function restackfix.at(s: string, part: string): number?
	return (string.find(s, part, 1, true))
end

function restackfix.say(r: fixture.Result): string
	return r.stderr .. r.stdout
end

-- `./zn <args>` in the raft's worktree
function restackfix.zn(args: { string }): fixture.Result
	return trackerfix.tr(ctx.f, ctx.wt, args, ctx.env)
end

-- the same with extra variables (a test seam such as ZN_RESTACK_KILL)
function restackfix.znWith(args: { string }, extra: { [string]: string }): fixture.Result
	local env = table.clone(ctx.env)
	for k, v in extra do
		env[k] = v
	end
	return trackerfix.tr(ctx.f, ctx.wt, args, env)
end

-- replaces the worktree's restack marker (a case that plants a state a crash leaves)
function restackfix.setMarker(text: string)
	fs.writeFile(`{restackfix.gitDir()}/zn-restack.state`, text)
end

function restackfix.write(dir: string, path: string, text: string)
	local parent = string.match(path, "^(.*)/[^/]+$")
	if parent then
		fs.writeDir(`{dir}/{parent}`)
	end
	fs.writeFile(`{dir}/{path}`, text)
end
local write = restackfix.write

function restackfix.commit(dir: string, path: string, text: string, message: string): string
	write(dir, path, text)
	git(dir, { "add", "-A" })
	git(dir, { "commit", "-qm", message })
	return git(dir, { "rev-parse", "HEAD" })
end
local commit = restackfix.commit

function restackfix.remoteSha(name: string): string
	return string.match(git(ctx.wt, { "ls-remote", "origin", `refs/heads/{name}` }), "^(%x+)") or ""
end

-- the local branch's tip, or "" when there is no such branch
function restackfix.localSha(name: string): string
	local r = restackfix.try(ctx.wt, { "rev-parse", "--verify", "--quiet", `refs/heads/{name}` })
	return if r.ok then (string.gsub(r.stdout, "%s+$", "")) else ""
end

function restackfix.gitDir(): string
	return git(ctx.wt, { "rev-parse", "--absolute-git-dir" })
end

function restackfix.rebasing(): boolean
	local dir = restackfix.gitDir()
	return fs.isDir(`{dir}/rebase-merge`) or fs.isDir(`{dir}/rebase-apply`)
end

function restackfix.marker(): string
	local path = `{restackfix.gitDir()}/zn-restack.state`
	return if fs.isFile(path) then fs.readFile(path) else ""
end

-- the refs that hold a commit ("" when only the reflog does)
function restackfix.holders(sha: string): string
	return (
		string.gsub(
			restackfix.try(ctx.wt, { "for-each-ref", "--contains", sha, "--format=%(refname)" }).stdout,
			"%s+$",
			""
		)
	)
end

function restackfix.pushes(): number
	local path = `{ctx.f.base}/pushes.log`
	local n = 0
	if fs.isFile(path) then
		for _ in string.gmatch(fs.readFile(path), "[^\n]+") do
			n += 1
		end
	end
	return n
end

function restackfix.clearPushes()
	if fs.isFile(`{ctx.f.base}/pushes.log`) then
		fs.removeFile(`{ctx.f.base}/pushes.log`)
	end
end

-- every layer back to its starting tip, on origin and locally (refs/zn/pushed too); main back to where it started; no
-- rebase, no marker; the worktree on `on`
function restackfix.reset(on: string)
	local wt = ctx.wt
	if restackfix.rebasing() then
		restackfix.try(wt, { "rebase", "--abort" })
	end
	local markerPath = `{restackfix.gitDir()}/zn-restack.state`
	if fs.isFile(markerPath) then
		fs.removeFile(markerPath)
	end
	restackfix.try(wt, { "checkout", "-q", "-f", "--detach", ctx.M0 })
	git(wt, { "reset", "-q", "--hard", ctx.M0 })
	git(wt, { "clean", "-qfd" })
	for name, sha in ctx.base do
		git(wt, { "update-ref", `refs/heads/{name}`, sha })
		git(wt, { "push", "-q", "--force", "origin", `{sha}:refs/heads/{name}` })
		git(wt, { "update-ref", `refs/remotes/origin/{name}`, sha })
		git(wt, { "update-ref", `refs/zn/pushed/{name}`, sha })
	end
	git(wt, { "push", "-q", "--force", "origin", `{ctx.MAIN0}:refs/heads/main` })
	git(wt, { "update-ref", "refs/remotes/origin/main", ctx.MAIN0 })
	git(wt, { "switch", "-q", on })
	restackfix.clearPushes()
end

-- another clone pushes a commit with these files straight to origin's main
function restackfix.mainMoves(files: { [string]: string }, message: string)
	local o = ctx.f.other
	git(o, { "fetch", "-q", "origin" })
	git(o, { "switch", "-q", "--detach", "origin/main" })
	for path, text in files do
		if text == "" then
			git(o, { "rm", "-q", path })
		else
			write(o, path, text)
		end
	end
	git(o, { "add", "-A" })
	git(o, { "commit", "-qm", message })
	git(o, { "push", "-q", "origin", "HEAD:refs/heads/main" })
end

-- another clone fast-forwards a layer on origin
function restackfix.otherPushes(name: string, path: string): string
	local o = ctx.f.other
	git(o, { "fetch", "-q", "origin" })
	git(o, { "switch", "-q", "--detach", `origin/{name}` })
	commit(o, path, "theirs\n", "someone else's commit")
	git(o, { "push", "-q", "origin", `HEAD:refs/heads/{name}` })
	return restackfix.remoteSha(name)
end

function restackfix.resolve(path: string, text: string)
	write(ctx.wt, path, text)
	git(ctx.wt, { "add", path })
end

-- this clone commits these files on a layer and pushes it as `./zn finish` would (the ref noted)
function restackfix.pushLayer(name: string, files: { [string]: string }, message: string): string
	local wt = ctx.wt
	git(wt, { "switch", "-q", name })
	for path, text in files do
		write(wt, path, text)
	end
	git(wt, { "add", "-A" })
	git(wt, { "commit", "-qm", message })
	local sha = git(wt, { "rev-parse", "HEAD" })
	git(wt, { "push", "-q", "origin", name })
	git(wt, { "update-ref", `refs/zn/pushed/{name}`, sha })
	return sha
end

function restackfix.setup(name: string)
	local seed: { [string]: string } = {
		[".gitignore"] = fs.readFile(`{TOP}/.gitignore`),
		["pickman/.tracker/architecture.md"] = fs.readFile(`{TOP}/pickman/.tracker/architecture.md`),
		["pickman/.tracker/rafts/R0010/R0010.md"] = `---\nid: R0010\ntype: chore\ntitle: stack\nslug: stack\nsingle: false\nissues: [c0010, c0020, c0030]\ndesign: ready\ncreated: 2026-10-06\nstatus: {PREPARED}\n---\n\n# R0010\n\n## Order & dependencies\nc0010\nc0020\nc0030\n`,
		["pickman/.tracker/rafts/R0010/check.sh"] = HEAD .. 'check "AC1: ok" true\nfinish\n',
	}
	for n, id in { "c0010", "c0020", "c0030" } do
		local title = ({ c0010 = "alpha", c0020 = "beta", c0030 = "gamma" } :: { [string]: string })[id]
		seed[`pickman/.tracker/issues/{id}/{id}.md`] =
			`---\nid: {id}\ntype: chore\ntitle: {title}\nslug: {id}\nraft: R0010\ndepends_on: []\nemergent: false\ndesign: ready\ncreated: 2026-10-06\nstatus: {PREPARED}\n---\n\n# {id}\n\n{CAPTURED}`
		seed[`pickman/.tracker/issues/{id}/check.sh`] = poisonCheck(n)
		seed[`pickman/.tracker/issues/{id}/acceptance/.gitkeep`] = ""
	end
	local f = trackerfix.new(name, seed)
	local bin = `{f.base}/bin`
	fs.writeDir(bin)
	fs.writeFile(`{bin}/gh`, "#!/bin/sh\nexit 0\n")
	process.exec("chmod", { "+x", `{bin}/gh` })
	fs.writeFile(
		`{f.origin}/hooks/pre-receive`,
		`#!/bin/sh\nwhile read old new ref; do printf '%s ' "$ref"; done >> "{f.base}/pushes.log"\necho >> "{f.base}/pushes.log"\n`
	)
	process.exec("chmod", { "+x", `{f.origin}/hooks/pre-receive` })
	trackerfix.trOk(f, f.main, { "ready", "R0010" })
	local wt = trackerfix.trOk(f, f.main, { "worktree", "R0010" })
	ctx =
		{ f = f, wt = wt, env = { PATH = `{bin}:{process.env.PATH or ""}` }, base = {}, M0 = "", MAIN0 = "" }
	ctx.M0 = git(wt, { "rev-parse", "HEAD" })
	git(wt, { "switch", "-q", "-c", L1 })
	write(wt, restackfix.SHARED, "one\n")
	ctx.base[L1] = commit(wt, "pickman/src/alpha.luau", "alpha\n", "c0010: alpha")
	git(wt, { "switch", "-q", "-c", L2 })
	write(wt, restackfix.BETA, "beta\n")
	ctx.base[L2] = commit(wt, restackfix.SHARED, "two\n", "c0020: beta")
	git(wt, { "switch", "-q", "-c", L3 })
	ctx.base[L3] = commit(wt, "pickman/src/gamma.luau", "gamma\n", "c0030: gamma")
	for _, layer in { L1, L2, L3 } do
		git(wt, { "push", "-q", "-u", "origin", layer })
	end
	ctx.MAIN0 = restackfix.remoteSha("main")
end

return restackfix
