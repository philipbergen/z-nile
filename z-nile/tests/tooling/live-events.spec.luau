--!strict
-- f0424 (Who emits what): every step forward a tracker command records is told to the live layer, once, with the fields
-- the command knows, and every publish pokes it. A recording fake znlive (ZN_LIVE_BIN; ZN_LIVE is set to nothing, as the
-- fence turns the layer off for every other spec) logs each call. Fixture: .cache/live-events.
local fixture = require("@tests/lib/fixture")
local fs = require("@lune/fs")
local process = require("@lune/process")
local seal = require("@tests/lib/seal")
local t = require("@tests/lib/t")
local trackerfix = require("@tests/lib/trackerfix")

local TOP = (string.gsub(process.exec("git", { "rev-parse", "--show-toplevel" }).stdout, "%s+$", ""))
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

local function issue(id: string, title: string, raft: string, body: string): string
	local text = if body == "" then CAPTURED else `{body}\n{CAPTURED}`
	return `---\nid: {id}\ntype: chore\ntitle: {title}\nslug: {id}\nraft: {raft}\ndepends_on: []\nemergent: false\ndesign: ready\ncreated: 2026-10-06\nstatus: {PREPARED}\n---\n\n# {id}\n\n{text}`
end

local function raftDoc(id: string, slug: string, issues: string, order: string): string
	return `---\nid: {id}\ntype: chore\ntitle: {slug}\nslug: {slug}\nsingle: false\nissues: [{issues}]\ndesign: ready\ncreated: 2026-10-06\nstatus: {PREPARED}\n---\n\n# {id}\n\n## Order & dependencies\n{order}\n`
end

local f: trackerfix.Fixture
local bin, log = "", ""
local wt, wtS = "", ""
local env: { [string]: string } = {}

local function must(r: fixture.Result, what: string): string
	if not r.ok then
		error(`{what} failed ({r.code}): {r.stderr}{r.stdout}`, 2)
	end
	return (string.gsub(r.stdout, "%s+$", ""))
end

local function git(dir: string, args: { string }): string
	return fixture.git(dir, args)
end

local function zn(dir: string, args: { string }): string
	return must(trackerfix.tr(f, dir, args, env), "./zn " .. table.concat(args, " "))
end

local function write(dir: string, path: string, text: string)
	local parent = string.match(path, "^(.*)/[^/]+$")
	if parent then
		fs.writeDir(`{dir}/{parent}`)
	end
	fs.writeFile(`{dir}/{path}`, text)
end

local function has(s: string, part: string): boolean
	return string.find(s, part, 1, true) ~= nil
end

local rec, calls = "", ""

-- the recorded calls, one per line: `<op> <args>`
local function recorded(): { string }
	local out: { string } = {}
	if fs.isFile(calls) then
		for line in string.gmatch(fs.readFile(calls), "[^\n]+") do
			table.insert(out, line)
		end
	end
	return out
end

local function clearCalls()
	if fs.isFile(calls) then
		fs.removeFile(calls)
	end
end

-- the recorded calls that start with `prefix`
local function only(prefix: string): { string }
	local out: { string } = {}
	for _, line in recorded() do
		if string.sub(line, 1, #prefix) == prefix then
			table.insert(out, line)
		end
	end
	return out
end

local function one(prefix: string): string
	local found = only(prefix)
	if #found ~= 1 then
		error(`expected one call "{prefix}", got {#found}: {table.concat(recorded(), " | ")}`, 2)
	end
	return found[1]
end

return t.spec("f0424 the tracker commands tell the live layer", function(it)
	it("sets up a stack of two layers and a backlog issue, with a recording fake znlive", function()
		local seed: { [string]: string } = {
			[".gitignore"] = fs.readFile(`{TOP}/.gitignore`),
			["pickman/.tracker/architecture.md"] = fs.readFile(`{TOP}/pickman/.tracker/architecture.md`),
			["pickman/.tracker/rafts/R0010/R0010.md"] = raftDoc("R0010", "stack", "c0010, c0020", "c0010\nc0020"),
			["pickman/.tracker/issues/c0010/c0010.md"] = issue("c0010", "alpha", "R0010", ""),
			["pickman/.tracker/issues/c0020/c0020.md"] = issue("c0020", "beta", "R0010", ""),
			["pickman/.tracker/issues/c0050/c0050.md"] = trackerfix.stub("c0050", "gamma", "new-quiet-copper-falcon"),
		}
		for _, dir in {
			"pickman/.tracker/rafts/R0010",
			"pickman/.tracker/issues/c0010",
			"pickman/.tracker/issues/c0020",
		} do
			seed[`{dir}/check.sh`] = CHECK
		end
		seed["pickman/.tracker/issues/c0010/acceptance/.gitkeep"] = ""
		seed["pickman/.tracker/issues/c0020/acceptance/.gitkeep"] = ""
		f = trackerfix.new("live-events", seed)
		bin, log = `{f.base}/bin`, `{f.base}/gh.log`
		fs.writeDir(bin)
		local script = `#!/bin/sh\necho "$*" >> "{log}"\n`
			.. 'case "$1 $2" in\n'
			.. '  "pr list") case "$*" in *number*) echo 1 ;; esac; exit 0 ;;\n'
			.. '  "pr create") echo https://github.com/x/y/pull/1; exit 0 ;;\n'
			.. '  "pr edit") exit 0 ;;\n'
			.. '  "pr view") echo body; exit 0 ;;\n'
			.. "esac\nexit 0\n"
		fs.writeFile(`{bin}/gh`, script)
		process.exec("chmod", { "+x", `{bin}/gh` })
		calls = `{f.base}/calls.log`
		rec = `{bin}/znlive`
		fs.writeFile(rec, `#!/bin/sh\necho "$*" >> "{calls}"\n` .. 'echo \'{"ok":true,"seq":1}\'\nexit 0\n')
		process.exec("chmod", { "+x", rec })
		env = { PATH = `{bin}:{process.env.PATH or ""}`, ZN_LIVE = "", ZN_LIVE_BIN = rec, ZN_LIVE_ROOT = "" }
	end)

	it("ready tells readied with the raft and project, and its publish poked", function()
		clearCalls()
		zn(f.main, { "ready", "R0010" })
		local e = one("emit readied")
		t.expect(has(e, "--raft R0010")).toBe(true)
		t.expect(has(e, "--project pickman")).toBe(true)
		t.expect(#only("poke") >= 1).toBe(true)
	end)

	it("a publish pokes once, with the commit subject", function()
		wtS = trackerfix.trOk(f, f.main, { "worktree", "live-status" })
		clearCalls()
		zn(wtS, { "status", "c0050", "preparing" })
		local poke = one("poke")
		t.expect(has(poke, "--reason tracker: c0050 preparing")).toBe(true)
	end)

	it("status preparing tells design-started, with the unit", function()
		local e = one("emit design-started")
		t.expect(has(e, "--unit c0050")).toBe(true)
		t.expect(has(e, "--project pickman")).toBe(true)
	end)

	it("spend tells spent with the phase and the model", function()
		clearCalls()
		zn(wtS, { "spend", "c0050", "--phase", "prep", "--model", "test-model" })
		local sp = one("emit spent")
		t.expect(has(sp, "--activity prep")).toBe(true)
		t.expect(has(sp, "--model test-model")).toBe(true)
		t.expect(has(sp, "--unit c0050")).toBe(true)
	end)

	it("the commands of a layer tell spent, review-filed, layer-finished and restacked", function()
		wt = trackerfix.trOk(f, f.main, { "worktree", "R0010" })
		zn(wt, { "start", "R0010" })
		clearCalls()
		write(wt, "pickman/src/shared.luau", "one\n")
		write(wt, "pickman/src/alpha.luau", "alpha\n")
		write(wt, "pickman/.tracker/rafts/active/R0010/final-review-001.md", "# Final Review 001\n\nVerdict: approve\n")
		write(wt, "pickman/.tracker/issues/active/c0010/review-001.md", "# Review 001\n\nVerdict: approve\n")
		zn(wt, { "commit", "-m", "c0010: work", "--issue", "c0010" })
		local review = one("emit review-filed --activity review ")
		t.expect(has(review, "--round 1")).toBe(true)
		t.expect(has(review, "--unit c0010")).toBe(true)
		t.expect(#only("emit spent") >= 1).toBe(true)
		clearCalls()
		zn(wt, { "finish", "c0010" })
		local fin = one("emit layer-finished")
		t.expect(has(fin, "--unit c0010")).toBe(true)
		t.expect(has(fin, "--raft R0010")).toBe(true)
		t.expect(has(fin, "--round 1")).toBe(true)
		t.expect(#only("emit spent")).toBe(1)
		zn(wt, { "start", "R0010" })
		write(wt, "pickman/src/beta.luau", "beta\n")
		git(wt, { "add", "-A" })
		git(wt, { "commit", "-qm", "c0020 work" })
		zn(wt, { "finish", "c0020" })
		git(wt, { "switch", "-q", "R0010/1/c0010" })
		write(wt, "pickman/src/fix.luau", "fix\n")
		git(wt, { "add", "-A" })
		git(wt, { "commit", "-qm", "fix layer 1" })
		git(wt, { "push", "-q" })
		clearCalls()
		zn(wt, { "restack", "R0010" })
		t.expect(has(one("emit restacked"), "--raft R0010")).toBe(true)
		clearCalls()
		zn(wt, { "restack", "R0010" }) -- already stacked: nothing moved, nothing told
		t.expect(#only("emit restacked")).toBe(0)
	end)

	it("done tells landed and its spent row", function()
		git(wt, { "switch", "-q", "R0010/1/c0010" })
		zn(wt, { "finish", "c0010" })
		zn(wt, { "restack", "R0010" })
		git(wt, { "switch", "-q", "R0010/2/c0020" })
		seal.trace(wt, "R0010")
		clearCalls()
		zn(wt, { "done", "R0010" })
		t.expect(has(one("emit landed"), "--raft R0010")).toBe(true)
		t.expect(#only("emit spent") >= 1).toBe(true)
	end)

	it("a command that tells two events asks the layer twice, never more, and an unavailable layer once", function()
		local dead = `{bin}/dead`
		fs.writeFile(dead, `#!/bin/sh\necho "$*" >> "{calls}"\nexit 3\n`)
		process.exec("chmod", { "+x", dead })
		local saved = env.ZN_LIVE_BIN
		env.ZN_LIVE_BIN = dead
		clearCalls()
		local r = trackerfix.tr(f, wtS, { "status", "c0050", "new" }, env)
		t.expect(r.ok).toBe(true)
		local n = #recorded()
		t.expect(n <= 2).toBe(true) -- one poke (no daemon) and one emit that failed: nothing after the first failure
		env.ZN_LIVE_BIN = saved
	end)

	it("with ZN_LIVE=off a command makes no call at all", function()
		clearCalls()
		env.ZN_LIVE = "off"
		local r = trackerfix.tr(f, wtS, { "status", "c0050", "preparing" }, env)
		env.ZN_LIVE = ""
		t.expect(r.ok).toBe(true)
		t.expect(#recorded()).toBe(0)
	end)
end)
