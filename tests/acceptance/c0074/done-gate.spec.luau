--!strict
-- c0800: `tracker.sh done` runs the full gate on the final tree (acceptance specs promoted, raft and members moved
-- to done/) before it commits, and rolls everything back when the gate fails. Inside a spec run it doesn't (the
-- fixture specs that drive done clone tests/, so a gate there would run them again) unless PICKMAN_DONE_GATE=1
-- adds it, as here, where the gate is a stub; it then checks the promoted specs instead. Driven in a throwaway clone (no origin, so no gh) whose z-nile/check.sh is a stub that records
-- what it saw; each case starts from the same reviewed commit.
local engine = require("@tests/lib/engine")
local fixture = require("@tests/lib/fixture")
local fs = require("@lune/fs")
local gate = require("@scripts/tracker/gate")
local process = require("@lune/process")
local t = require("@tests/lib/t")

type Result = { ok: boolean, code: number, stdout: string, stderr: string }

local root = (string.gsub(process.exec("git", { "rev-parse", "--show-toplevel" }).stdout, "%s+$", ""))
local base = `{root}/.cache/c0800-done-gate`
local work = `{base}/work`
local gateLog = `{base}/gate.log`

local REQ = "req" .. "uire" -- keeps literal require text out of this file (graph scanner)
local TRIVIAL_CHECK = 'source "$(git -C "$(dirname "${BASH_SOURCE[0]}")" rev-parse --show-toplevel)/z-nile/lib/ac.sh"\n'
	.. 'check "RC1: fixture" true\nfinish\n'
-- the stub gate: records its arguments and the tree it saw, then exits with GATE_EXIT
local STUB_GATE = table.concat({
	"#!/usr/bin/env bash",
	'cd "$(dirname "$0")/.."',
	'{ echo "args: $*"',
	'  [[ -f tests/acceptance/f0010/alpha.spec.luau ]] && echo "promoted: yes" || echo "promoted: no"',
	'  [[ -d tracker/rafts/done/R0010 ]] && echo "raft: done" || echo "raft: not done"',
	'  [[ -d tracker/issues/done/f0010 ]] && echo "issue: done" || echo "issue: not done"',
	'} >> "$GATE_LOG"',
	'exit "${GATE_EXIT:-0}"',
	"",
}, "\n")

-- the fixture's identity rides in the environment: a nested runner refuses a fixture identity in git config
local ID: { [string]: string } = {
	GIT_AUTHOR_NAME = "e2e",
	GIT_AUTHOR_EMAIL = "e2e@example.invalid",
	GIT_COMMITTER_NAME = "e2e",
	GIT_COMMITTER_EMAIL = "e2e@example.invalid",
}

local function must(r: Result, what: string): string
	if not r.ok then
		error(`{what} failed ({r.code}): {r.stderr}{r.stdout}`, 2)
	end
	return (string.gsub(r.stdout, "%s+$", ""))
end

local function git(args: { string }): string
	return must(fixture.exec(work, "git", args, { env = ID }), "git " .. table.concat(args, " "))
end

local function tr(args: { string }, env: { [string]: string }?): Result
	local merged = table.clone(ID)
	if env then
		for k, v in env do
			merged[k] = v
		end
	end
	return fixture.exec(work, "bash", { "scripts/tracker.sh", table.unpack(args) }, { env = merged })
end

local function write(path: string, text: string)
	local parent = string.match(path, "^(.*)/[^/]+$")
	if parent then
		fs.writeDir(`{work}/{parent}`)
	end
	fs.writeFile(`{work}/{path}`, text)
end

local function edit(path: string, from: string, to: string)
	local text, n = string.gsub(fs.readFile(`{work}/{path}`), from, to)
	assert(n > 0, `pattern {from} not found in {path}`)
	write(path, text)
end

local function has(s: string, part: string): boolean
	return string.find(s, part, 1, true) ~= nil
end

local reviewed = ""

-- every case starts from the reviewed commit, with an empty gate log
local function fresh()
	git({ "reset", "-q", "--hard", reviewed })
	if fs.isFile(gateLog) then
		fs.removeFile(gateLog)
	end
end

-- Every case runs inside this spec run, its guards untouched. `withGate` adds PICKMAN_DONE_GATE=1, the switch that
-- can only make done run the gate (here the stub) inside a spec run; it never turns a guard off.
local function done(withGate: boolean, gateExit: number): Result
	return tr({ "done", "R0010" }, {
		PICKMAN_DONE_GATE = if withGate then "1" else "",
		GATE_LOG = gateLog,
		GATE_EXIT = tostring(gateExit),
	})
end

local function log(): string
	return if fs.isFile(gateLog) then fs.readFile(gateLog) else ""
end

return t.spec("c0800 done runs the full gate after promotion", function(it)
	it("sets up a clone with a prepared raft, started and reviewed, and a stub gate", function()
		if fs.isDir(base) then
			fs.removeDir(base)
		end
		fs.writeDir(base)
		must(process.exec("git", { "clone", "-q", "--no-hardlinks", root, work }), "clone")
		git({ "remote", "remove", "origin" })
		-- overlay the working tree's tooling so uncommitted tracker changes are what gets tested
		local listed = process.exec("git", {
			"ls-files",
			"-co",
			"--exclude-standard",
			"zn",
			"scripts",
			"z-nile",
			":(exclude)z-nile/.tracker",
			":(exclude)z-nile/next",
			":(exclude)z-nile/compaction.txt",
		}, { cwd = root })
		for path in string.gmatch(listed.stdout, "[^\n]+") do
			if fs.isFile(`{root}/{path}`) then
				write(path, fs.readFile(`{root}/{path}`))
			end
		end
		write("z-nile/check.sh", STUB_GATE)
		must(process.exec("chmod", { "+x", `{work}/z-nile/check.sh` }), "chmod")
		git({ "config", "gc.auto", "0" })
		-- c0114 override: every project root is emptied, and the counter moved to z-nile/next
		engine.empty(work)
		git({ "add", "-A" })
		git({ "commit", "-qm", "empty tracker, stub gate", "--allow-empty" })
		must(tr({ "new", "issue", "f", "alpha" }), "new issue")
		must(tr({ "new", "raft", "feature", "demo", "f0010", "--single" }), "new raft")
		for _, doc in { "tracker/issues/f0010/f0010.md", "tracker/rafts/R0010/R0010.md" } do
			edit(doc, "design: draft", "design: ready")
		end
		edit(
			"tracker/issues/f0010/f0010.md",
			"### Touched modules\n",
			"### Touched modules\n- `notes/alpha`\n"
		)
		write(
			"tracker/issues/f0010/acceptance/alpha.spec.luau",
			"--!strict\nlocal t = "
				.. REQ
				.. '("@tests/lib/t")\n\nreturn t.spec("alpha", function(it)\n\tit("holds", function()\n\t\tt.expect(1).toBe(1)\n\tend)\nend)\n'
		)
		write("tracker/issues/f0010/check.sh", TRIVIAL_CHECK)
		write("tracker/rafts/R0010/check.sh", TRIVIAL_CHECK)
		git({ "add", "-A" })
		git({ "commit", "-qm", "prep ready" })
		must(tr({ "start", "R0010" }), "start")
		write("tracker/rafts/active/R0010/review-001.md", "# Review 001\n\nVerdict: approve\n")
		must(tr({ "commit", "-m", "review 001", "--time", "1" }), "commit")
		reviewed = git({ "rev-parse", "HEAD" })
	end)

	it("a failing gate rolls everything back and leaves the raft active", function()
		fresh()
		local r = done(true, 1)
		t.expect(r.ok).toBe(false)
		t.expect(has(r.stderr, "full gate fails")).toBe(true)
		t.expect(has(log(), "args: --full")).toBe(true) -- it did run, and failed
		t.expect(git({ "rev-parse", "HEAD" })).toBe(reviewed)
		t.expect(git({ "status", "--porcelain" })).toBe("")
		t.expect(fs.isDir(`{work}/tracker/rafts/active/R0010`)).toBe(true)
		t.expect(fs.isDir(`{work}/tracker/issues/active/f0010`)).toBe(true)
		t.expect(fs.isFile(`{work}/tracker/issues/active/f0010/acceptance/alpha.spec.luau`)).toBe(true)
		t.expect(fs.isFile(`{work}/tests/acceptance/f0010/alpha.spec.luau`)).toBe(false)
		-- no empty done/ folder is left beside the active one (one id in two places breaks every tracker command)
		t.expect(fs.isDir(`{work}/tracker/rafts/done/R0010`)).toBe(false)
		t.expect(fs.isDir(`{work}/tracker/issues/done/f0010`)).toBe(false)
		must(tr({ "list" }), "tracker list after the rollback")
	end)

	it(
		"inside a spec run, without the switch, done checks the promoted specs and does not run the gate",
		function()
			fresh()
			local r = done(false, 1) -- a gate that would fail: without the switch it must not be called at all
			if not r.ok then
				error(r.stderr .. r.stdout)
			end
			t.expect(log()).toBe("")
			t.expect(has(r.stdout .. r.stderr, "full gate is skipped")).toBe(true)
			t.expect(fs.isFile(`{work}/tests/acceptance/f0010/alpha.spec.luau`)).toBe(true)
			t.expect(git({ "log", "-1", "--format=%s" })).toBe("tracker: done R0010")
		end
	)

	it("done runs the full gate on the promoted, moved tree, then commits", function()
		fresh()
		local r = done(true, 0)
		if not r.ok then
			error(r.stderr .. r.stdout)
		end
		local seen = log()
		local _, runs = string.gsub(seen, "args:", "")
		t.expect(runs).toBe(1)
		t.expect(has(seen, "args: --full")).toBe(true)
		t.expect(has(seen, "promoted: yes")).toBe(true)
		t.expect(has(seen, "raft: done")).toBe(true)
		t.expect(has(seen, "issue: done")).toBe(true)
		t.expect(git({ "log", "-1", "--format=%s" })).toBe("tracker: done R0010")
		t.expect(git({ "status", "--porcelain" })).toBe("")
		t.expect(fs.isDir(`{work}/tracker/rafts/done/R0010`)).toBe(true)
	end)

	it("the gate decision: full, unless inside a spec run without the switch", function()
		-- the branch an agent's real `tracker.sh done` takes (neither variable set) can't be driven from inside this
		-- spec run without dropping its guards, so the decision is a pure function, tested here with plain tables
		t.expect(gate.doneGate({})).toBe("full")
		t.expect(gate.doneGate({ PICKMAN_FENCE_SPECS = "1" })).toBe("promoted")
		t.expect(gate.doneGate({ PICKMAN_FENCE_SPECS = "1", PICKMAN_DONE_GATE = "1" })).toBe("full")
		t.expect(gate.doneGate({ PICKMAN_DONE_GATE = "1" })).toBe("full")
		t.expect(gate.doneGate({ PICKMAN_FENCE_SPECS = "", PICKMAN_DONE_GATE = "" })).toBe("full")
		-- and done decides through it, reading nothing else
		local main = fs.readFile(`{root}/z-nile/engine/main.luau`)
		t.expect(string.find(main, "doneGate(process.env)", 1, true) ~= nil).toBe(true)
		t.expect((string.find(main, "PICKMAN_DONE_GATE", 1, true))).toBe(nil)
	end)

	it("cleans up", function()
		fs.removeDir(base)
	end)
end)
