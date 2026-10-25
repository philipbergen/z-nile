--!strict
-- R0025 review 001 F3, review 003 F2: a readied raft's `start` reuses the open pull request of its branch (a raft
-- stopped and readied again keeps both), and opens a draft only when there is none. The fixture's origin path holds
-- `github.com`, so `onGitHub()` is true while every fetch and push stays local; a fake gh, first on PATH, logs its
-- arguments. Fixture under .cache/start-pr-reuse-github.com (tests/lib/trackerfix).
local fixture = require("@tests/lib/fixture")
local fs = require("@lune/fs")
local process = require("@lune/process")
local t = require("@tests/lib/t")
local trackerfix = require("@tests/lib/trackerfix")

-- the checkout's top, for reading repository files: specs run in their home (c0120)
local TOP = (string.gsub(process.exec("git", { "rev-parse", "--show-toplevel" }).stdout, "%s+$", ""))

local PREPARED = "prepared-quiet-copper-falcon"
local CHECK = 'source "$(git -C "$(dirname "${BASH_SOURCE[0]}")" rev-parse --show-toplevel)/scripts/lib/ac.sh"\n'
	.. 'check "AC1: ok" true\nfinish\n'

local function issue(id: string, raft: string): string
	return `---\nid: {id}\ntype: chore\ntitle: {id}\nslug: {id}\nraft: {raft}\ndepends_on: []\nemergent: false\ndesign: ready\ncreated: 2026-10-06\nstatus: {PREPARED}\n---\n\n# {id}\n`
end
local function raftDoc(id: string, slug: string, issues: string): string
	return `---\nid: {id}\ntype: chore\ntitle: {slug}\nslug: {slug}\nsingle: false\nissues: [{issues}]\ndesign: ready\ncreated: 2026-10-06\nstatus: {PREPARED}\n---\n\n# {id}\n`
end

local f: trackerfix.Fixture
local bin, log = "", ""

-- a fake gh: `pr list` prints `listed` (a URL, or nothing), anything else prints a new PR's URL; every call is logged
local function fakeGh(listed: string)
	local script = `#!/bin/sh\necho "$*" >> "{log}"\n`
		.. `if [ "$1 $2" = "pr list" ]; then printf '%s' "{listed}"; exit 0; fi\n`
		.. "echo https://github.com/x/y/pull/9\n"
	fs.writeFile(`{bin}/gh`, script)
	process.exec("chmod", { "+x", `{bin}/gh` })
	if fs.isFile(log) then
		fs.removeFile(log)
	end
end

local function start(raft: string): fixture.Result
	local wt = trackerfix.trOk(f, f.main, { "worktree", raft })
	return trackerfix.tr(f, wt, { "start", raft }, { PATH = `{bin}:{process.env.PATH or ""}` })
end

return t.spec("a readied raft's start reuses its open pull request", function(it)
	it("sets up two readied rafts behind an origin whose path names github.com", function()
		local seed: { [string]: string } = {
			[".gitignore"] = fs.readFile(`{TOP}/.gitignore`),
			["pickman/.tracker/architecture.md"] = fs.readFile(`{TOP}/pickman/.tracker/architecture.md`),
			["pickman/.tracker/rafts/R0010/R0010.md"] = raftDoc("R0010", "kept", "c0010"),
			["pickman/.tracker/issues/c0010/c0010.md"] = issue("c0010", "R0010"),
			["pickman/.tracker/rafts/R0020/R0020.md"] = raftDoc("R0020", "fresh", "c0020"),
			["pickman/.tracker/issues/c0020/c0020.md"] = issue("c0020", "R0020"),
		}
		for _, dir in
			{
				"pickman/.tracker/rafts/R0010",
				"pickman/.tracker/issues/c0010",
				"pickman/.tracker/rafts/R0020",
				"pickman/.tracker/issues/c0020",
			}
		do
			seed[`{dir}/check.sh`] = CHECK
		end
		for _, s in { "execute-raft", "tracker", "architecture", "testing", "review" } do
			seed[`.claude/skills/{s}/SKILL.md`] = fs.readFile(`{TOP}/.claude/skills/{s}/SKILL.md`)
		end
		f = trackerfix.new("start-pr-reuse-github.com", seed)
		bin, log = `{f.base}/bin`, `{f.base}/gh.log`
		fs.writeDir(bin)
		t.expect(
			string.find(fixture.git(f.main, { "remote", "get-url", "origin" }), "github.com", 1, true) ~= nil
		)
			.toBe(true)
		trackerfix.trOk(f, f.main, { "ready", "R0010" })
		trackerfix.trOk(f, f.main, { "ready", "R0020" })
	end)

	it("an open pull request for the branch is reused: no new one is opened", function()
		fakeGh("https://github.com/x/y/pull/7")
		local r = start("R0010")
		t.expect(r.ok).toBe(true)
		t.expect(string.find(r.stdout, "already open", 1, true) ~= nil).toBe(true)
		t.expect(string.find(r.stdout, "pull/7", 1, true) ~= nil).toBe(true)
		local calls = fs.readFile(log)
		t.expect(string.find(calls, "pr list --head R0010-kept", 1, true) ~= nil).toBe(true)
		t.expect(string.find(calls, "pr create", 1, true) == nil).toBe(true)
	end)

	it("with no open pull request, exactly one draft is opened", function()
		fakeGh("")
		local r = start("R0020")
		t.expect(r.ok).toBe(true)
		local calls = fs.readFile(log)
		local _, creates = string.gsub(calls, "pr create %-%-draft", "")
		t.expect(creates).toBe(1)
		t.expect(string.find(r.stdout, "pull/9", 1, true) ~= nil).toBe(true)
	end)
end)
