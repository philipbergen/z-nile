--!strict
-- f0421 AC8: `./zn work next <R>` names the review round. Real git in a fixture under .cache (a bare origin whose path
-- contains github.com, a `gh` stub), as f0399/land does. R0010 (an easy member) walks the code review: an unanswered
-- round, an answered serious round below the maximum, an answered low-only round, an answered round at the maximum and an
-- approval. R0020 (an easy and a risky member) is at its third final-review round. R0030 has a member with risk: high.
local fixture = require("@tests/lib/fixture")
local fs = require("@lune/fs")
local process = require("@lune/process")
local t = require("@tests/lib/t")
local trackerfix = require("@tests/lib/trackerfix")

local TOP = (string.gsub(process.exec("git", { "rev-parse", "--show-toplevel" }).stdout, "%s+$", ""))
local ROOT = "pickman/.tracker"
local PREPARED = "prepared-quiet-copper-falcon"
local CHECK = 'source "$(git -C "$(dirname "${BASH_SOURCE[0]}")" rev-parse --show-toplevel)/scripts/lib/ac.sh"\n'
	.. 'check "AC1: ok" true\nfinish\n'

local CAPTURED = table.concat({
	"## Problem",
	"The marker is missing.",
	"",
	"## Solution",
	"Store the marker.",
	"",
	"## Acceptance criteria",
	"- AC1: the marker is stored",
	"",
}, "\n")

local function issue(id: string, raft: string, body: string, extra: string?): string
	local text = if body == "" then CAPTURED else `{body}\n{CAPTURED}`
	return `---\nid: {id}\ntype: chore\ntitle: {id} title\nslug: {id}\nraft: {raft}\ndepends_on: []\nemergent: false\ndesign: ready\ncreated: 2026-11-16\n{extra or ""}status: {PREPARED}\n---\n\n# {id}\n\n{text}`
end

local function raftDoc(id: string, issues: string, extra: string?): string
	return `---\nid: {id}\ntype: chore\ntitle: {id} raft\nslug: {id}\nsingle: false\nissues: [{issues}]\ndesign: ready\ncreated: 2026-11-16\nstatus: {PREPARED}\n---\n\n# {id}\n\n## Order & dependencies\n{string.gsub(
		issues,
		", ",
		"\n"
	)}\n{extra or ""}`
end

local GH = [=[#!/bin/sh
echo "$*" >> "@LOG@"
case "$1 $2" in
  "pr list") case "$*" in *number*) echo 1 ;; esac; exit 0 ;;
  "pr create") echo https://github.com/x/y/pull/1; exit 0 ;;
  "pr edit") exit 0 ;;
  "pr view") echo body; exit 0 ;;
esac
exit 0
]=]

local function has(s: string, part: string): boolean
	return string.find(s, part, 1, true) ~= nil
end

local function say(r: fixture.Result): string
	return (string.gsub(r.stderr .. r.stdout, "\r", ""))
end

local function write(dir: string, path: string, text: string)
	local parent = string.match(path, "^(.*)/[^/]+$")
	if parent then
		fs.writeDir(`{dir}/{parent}`)
	end
	fs.writeFile(`{dir}/{path}`, text)
end

local function git(dir: string, args: { string }): string
	return fixture.git(dir, args)
end

local function commitAll(dir: string, message: string)
	git(dir, { "add", "-A" })
	git(dir, { "commit", "-qm", message })
end

-- A tracker fixture with a `gh` stub that logs its calls; returns it with its log and the environment to use.
local function build(
	name: string,
	seed: { [string]: string }
): (trackerfix.Fixture, string, { [string]: string })
	local fx = trackerfix.new(name, seed)
	local bin, log = `{fx.base}/bin`, `{fx.base}/gh.log`
	fs.writeDir(bin)
	fs.writeFile(`{bin}/gh`, (string.gsub(GH, "@LOG@", log)))
	process.exec("chmod", { "+x", `{bin}/gh` })
	return fx, log, { PATH = `{bin}:{process.env.PATH or ""}` }
end

local f: trackerfix.Fixture = nil :: any
local env: { [string]: string } = {}

local function tr(dir: string, args: { string }): fixture.Result
	return trackerfix.tr(f, dir, args, env)
end

local function zn(dir: string, args: { string }): string
	local r = tr(dir, args)
	if not r.ok then
		error(`fixture step ./zn {table.concat(args, " ")} failed ({r.code}): {say(r)}`, 2)
	end
	return (string.gsub(r.stdout, "%s+$", ""))
end

local function layerWork(dir: string, file: string, id: string)
	write(dir, `pickman/src/{file}.luau`, `return "{file}"\n`)
	commitAll(dir, `{id} work`)
end

local wt10, wt20 = "", ""
local setUp = false

local function setup()
	if setUp then
		return
	end
	setUp = true
	local seed: { [string]: string } = {
		[".gitignore"] = fs.readFile(`{TOP}/.gitignore`),
		[`{ROOT}/architecture.md`] = fs.readFile(`{TOP}/pickman/.tracker/architecture.md`),
	}
	local rafts: { [string]: string } = { R0010 = "c0010", R0020 = "c0020, c0021", R0030 = "c0030" }
	local risk: { [string]: string } = { c0010 = "easy", c0020 = "easy", c0021 = "risky", c0030 = "high" }
	for rid, members in rafts do
		seed[`{ROOT}/rafts/{rid}/{rid}.md`] = raftDoc(rid, members)
		seed[`{ROOT}/rafts/{rid}/check.sh`] = CHECK
		for mid in string.gmatch(members, "c%d+") do
			seed[`{ROOT}/issues/{mid}/{mid}.md`] = issue(mid, rid, "", `risk: {risk[mid]}\n`)
			seed[`{ROOT}/issues/{mid}/check.sh`] = CHECK
		end
	end
	local made, _log, madeEnv = build("f0421-work-github.com", seed)
	f, env = made, madeEnv
	for _, rid in { "R0010", "R0020", "R0030" } do
		zn(f.main, { "ready", rid })
	end
	wt10 = zn(f.main, { "worktree", "R0010" })
	zn(wt10, { "start", "R0010" })
	layerWork(wt10, "alpha", "c0010")
	zn(wt10, { "finish", "c0010" })
	wt20 = zn(f.main, { "worktree", "R0020" })
	zn(wt20, { "start", "R0020" })
	layerWork(wt20, "beta", "c0020")
	zn(wt20, { "finish", "c0020" })
	zn(wt20, { "start", "R0020" })
	layerWork(wt20, "gamma", "c0021")
	zn(wt20, { "finish", "c0021" })
end

local function next(raft: string): string
	return say(tr(f.main, { "work", "next", raft }))
end

local function put(wt: string, raft: string, files: { [string]: string }, message: string)
	for name, text in files do
		write(wt, `{ROOT}/rafts/active/{raft}/{name}`, text)
	end
	commitAll(wt, message)
end

local function review(n: number, verdict: string, ...: string): string
	local out = `# Review {n}\n\n`
	for i, sev in { ... } do
		out ..= `### F{i} [{sev}] a finding\nEvidence: x\n\n`
	end
	return out .. `Verdict: {verdict}\n`
end

local FIXED = "- F1: fixed abc; consequences: none\n"

return t.spec("f0421: work next names the review round", function(it)
	it("an unanswered changes review asks for its answer", function()
		setup()
		put(wt10, "R0010", { ["review-001.md"] = review(1, "changes", "medium") }, "review 1")
		local out = next("R0010")
		t.expect(has(out, "R0010: review - ")).toBe(true)
		t.expect(has(out, "Answer review-001.md in refute-001.md")).toBe(true)
		t.expect(has(out, "Do not guess a ruling under ./zn dispatch")).toBe(true)
		t.expect(has(out, "the last")).toBe(false)
	end)

	it("an answered serious round below the maximum files the next round", function()
		setup()
		put(wt10, "R0010", { ["refute-001.md"] = FIXED }, "answer 1")
		local out = next("R0010")
		t.expect(has(out, "R0010: review - ")).toBe(true)
		t.expect(has(out, "run code review round 2 of at most 2")).toBe(true)
	end)

	it("an answered round with only low findings is settled: the next action is trace", function()
		setup()
		put(wt10, "R0010", { ["review-001.md"] = review(1, "changes", "low") }, "review 1 is low only")
		t.expect(has(next("R0010"), "R0010: trace - ")).toBe(true)
		put(wt10, "R0010", { ["review-001.md"] = review(1, "changes", "medium") }, "review 1 is medium again")
	end)

	it("an answered round at the maximum is settled, and an approval settles", function()
		setup()
		put(wt10, "R0010", {
			["review-002.md"] = review(2, "changes", "high"),
			["refute-002.md"] = FIXED,
		}, "round 2, answered")
		t.expect(has(next("R0010"), "R0010: trace - ")).toBe(true)
		put(wt10, "R0010", { ["refute-002.md"] = "" }, "round 2, unanswered")
		local open = next("R0010")
		t.expect(has(open, "Answer review-002.md in refute-002.md")).toBe(true)
		t.expect(has(open, "This is round 2 of 2, the last.")).toBe(true)
		put(wt10, "R0010", { ["review-002.md"] = review(2, "approve") }, "round 2 approves")
		t.expect(has(next("R0010"), "R0010: trace - ")).toBe(true)
	end)

	it("a raft with an easy and a risky member takes the risky maximum: final round 3", function()
		setup()
		put(wt20, "R0020", {
			["review-001.md"] = review(1, "approve"),
			["trace.md"] = "# trace\n",
			["final-review-001.md"] = review(1, "changes", "high"),
			["final-refute-001.md"] = FIXED,
			["final-review-002.md"] = review(2, "changes", "high"),
			["final-refute-002.md"] = FIXED,
		}, "two final rounds")
		local out = next("R0020")
		t.expect(has(out, "R0020: final-review - ")).toBe(true)
		t.expect(has(out, "Run final review round 3 of at most 9")).toBe(true)
	end)

	it("a member with risk: high stops the raft and names the problem", function()
		setup()
		local out = next("R0030")
		t.expect(has(out, "R0030: none - ")).toBe(true)
		t.expect(has(out, "risk is high: easy, normal or risky")).toBe(true)
	end)
end)
