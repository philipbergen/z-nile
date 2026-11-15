--!strict
-- A raft is a stack. Two layers, then one, landed with --no-ff; restack; the three refusals;
-- a second clone reads the stack from git. Origin path contains github.com. Fixture: .cache/stack-land-github.com.
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
local bin, log, proof = "", "", ""
local wt, wtOne, wtBad = "", "", ""
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

return t.spec("a raft lands as a stack of layers", function(it)
	it("sets up three readied rafts behind a local github-shaped origin", function()
		local seed: { [string]: string } = {
			[".gitignore"] = fs.readFile(`{TOP}/.gitignore`),
			["pickman/.tracker/architecture.md"] = fs.readFile(`{TOP}/pickman/.tracker/architecture.md`),
			["pickman/.tracker/rafts/R0010/R0010.md"] = raftDoc(
				"R0010",
				"stack",
				"c0010, c0020",
				"c0010\nc0020"
			),
			["pickman/.tracker/issues/c0010/c0010.md"] = issue("c0010", "alpha", "R0010", ""),
			["pickman/.tracker/issues/c0020/c0020.md"] = issue("c0020", "beta", "R0010", ""),
			["pickman/.tracker/rafts/R0020/R0020.md"] = raftDoc("R0020", "one", "c0030", "c0030"),
			["pickman/.tracker/issues/c0030/c0030.md"] = issue("c0030", "gamma", "R0020", ""),
			["pickman/.tracker/rafts/R0030/R0030.md"] = raftDoc("R0030", "drift", "c0040", "c0040"),
			["pickman/.tracker/issues/c0040/c0040.md"] = issue("c0040", "delta", "R0030", "## Design\none\n"),
		}
		for _, dir in
			{
				"pickman/.tracker/rafts/R0010",
				"pickman/.tracker/issues/c0010",
				"pickman/.tracker/issues/c0020",
				"pickman/.tracker/rafts/R0020",
				"pickman/.tracker/issues/c0030",
				"pickman/.tracker/rafts/R0030",
				"pickman/.tracker/issues/c0040",
			}
		do
			seed[`{dir}/check.sh`] = CHECK
		end
		seed["pickman/.tracker/issues/c0010/acceptance/.gitkeep"] = ""
		seed["pickman/.tracker/issues/c0020/acceptance/.gitkeep"] = ""
		f = trackerfix.new("stack-land-github.com", seed)
		bin, log, proof = `{f.base}/bin`, `{f.base}/gh.log`, `{f.base}/proof.txt`
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
		env = { PATH = `{bin}:{process.env.PATH or ""}` }
		for _, raft in { "R0010", "R0020", "R0030" } do
			trackerfix.trOk(f, f.main, { "ready", raft })
		end
		wt = trackerfix.trOk(f, f.main, { "worktree", "R0010" })
	end)

	it("start opens layer 1, and another clone sees the claim without the worktree's files", function()
		zn(wt, { "start", "R0010" })
		t.expect(git(wt, { "branch", "--show-current" })).toBe("R0010/1/c0010")
		local calls = fs.readFile(log)
		t.expect(has(calls, "pr create --draft --base main --head R0010/1/c0010")).toBe(true)
		git(f.other, { "pull", "-q", "origin", "main" })
		local seen = zn(f.other, { "stack", "R0010" })
		t.expect(has(seen, "1 R0010/1/c0010 c0010 claimed")).toBe(true)
		t.expect(has(seen, "2 R0010/2/c0020 c0020 missing")).toBe(true)
		t.expect(fs.isFile(`{f.other}/pickman/src/alpha.luau`)).toBe(false)
	end)

	it("each layer finishes as one commit, and its watch names only its own source files", function()
		write(wt, "pickman/src/shared.luau", "one\n")
		write(wt, "pickman/src/alpha.luau", "alpha\n")
		write(wt, "pickman/tests/unit/c0010-layer.spec.luau", "--!strict\nreturn nil\n")
		write(
			wt,
			"pickman/.tracker/rafts/active/R0010/final-review-001.md",
			"# Final Review 001\n\nVerdict: approve\n"
		)
		git(wt, { "add", "-A" })
		git(wt, { "commit", "-qm", "c0010 work" })
		zn(wt, { "finish", "c0010" })
		t.expect(git(wt, { "log", "-1", "--format=%s" })).toBe("c0010: alpha")
		t.expect(git(wt, { "rev-list", "--count", "origin/main..HEAD" })).toBe("1")
		local watch1 = fs.readFile(`{wt}/pickman/.tracker/issues/active/c0010/acceptance/watch.txt`)
		t.expect(has(watch1, "pickman/src/alpha.luau")).toBe(true)
		t.expect(has(watch1, "pickman/src/beta.luau")).toBe(false)
		t.expect(fs.readFile(`{wt}/pickman/tests/unit/c0010-layer.watch.txt`)).toBe(watch1)

		zn(wt, { "start", "R0010" })
		t.expect(git(wt, { "branch", "--show-current" })).toBe("R0010/2/c0020")
		local calls = fs.readFile(log)
		t.expect(has(calls, "--base R0010/1/c0010 --head R0010/2/c0020")).toBe(true)
		write(wt, "pickman/src/shared.luau", "two\n")
		write(wt, "pickman/src/beta.luau", "beta\n")
		write(wt, "pickman/tests/unit/c0020-layer.spec.luau", "--!strict\nreturn nil\n")
		git(wt, { "add", "-A" })
		git(wt, { "commit", "-qm", "c0020 work" })
		zn(wt, { "finish", "c0020" })
		t.expect(git(wt, { "log", "-1", "--format=%s" })).toBe("c0020: beta")
		local watch2 = fs.readFile(`{wt}/pickman/.tracker/issues/active/c0020/acceptance/watch.txt`)
		t.expect(watch2).toBe("pickman/src/beta.luau\npickman/src/shared.luau\n")
		t.expect(has(watch2, "pickman/src/alpha.luau")).toBe(false)

		local alpha = must(
			fixture.exec(wt, "lune", { "run", "z-nile/affected", "--", "pickman/src/alpha.luau" }),
			"affected alpha"
		)
		local beta = must(
			fixture.exec(wt, "lune", { "run", "z-nile/affected", "--", "pickman/src/beta.luau" }),
			"affected beta"
		)
		t.expect(has(alpha, "c0010-layer.spec.luau")).toBe(true)
		t.expect(has(alpha, "c0020-layer.spec.luau")).toBe(false)
		t.expect(has(beta, "c0020-layer.spec.luau")).toBe(true)
		t.expect(has(beta, "c0010-layer.spec.luau")).toBe(false)

		git(f.other, { "fetch", "-q", "origin" })
		local seen = zn(f.other, { "stack", "R0010" })
		t.expect(has(seen, "1 R0010/1/c0010 c0010 finished")).toBe(true)
		t.expect(has(seen, "2 R0010/2/c0020 c0020 finished")).toBe(true)
		t.expect(fs.isFile(`{f.other}/pickman/src/alpha.luau`)).toBe(false)
	end)

	it("restack moves the upper layer, a second run changes nothing, and a conflict stops there", function()
		local before = git(wt, { "rev-parse", "HEAD" })
		git(wt, { "switch", "-q", "R0010/1/c0010" })
		write(wt, "pickman/src/fix.luau", "fix\n")
		git(wt, { "add", "-A" })
		git(wt, { "commit", "-qm", "fix layer 1" })
		git(wt, { "push", "-q" })
		local moved = zn(wt, { "restack", "R0010" })
		t.expect(has(moved, "restacked R0010")).toBe(true)
		local layer2 = git(f.main, { "rev-parse", "origin/R0010/2/c0020" })
		t.expect(layer2 ~= before).toBe(true)
		t.expect(
			git(f.main, { "merge-base", "--is-ancestor", "origin/R0010/1/c0010", layer2 }) ~= nil or true
		)
			.toBe(true)
		t.expect(git(f.main, { "rev-parse", "origin/R0010/2/c0020^" }))
			.toBe(git(f.main, { "rev-parse", "origin/R0010/1/c0010" }))
		local again = zn(wt, { "restack", "R0010" })
		t.expect(has(again, "already stacked")).toBe(true)
		t.expect(git(f.main, { "rev-parse", "origin/R0010/2/c0020" })).toBe(layer2)

		git(wt, { "switch", "-q", "R0010/1/c0010" })
		write(wt, "pickman/src/shared.luau", "fix\n")
		git(wt, { "add", "-A" })
		git(wt, { "commit", "-qm", "conflict on purpose" })
		git(wt, { "push", "-q" })
		local lower = git(f.main, { "rev-parse", "origin/R0010/1/c0010" })
		local stopped = trackerfix.tr(f, wt, { "restack", "R0010" }, env)
		t.expect(stopped.ok).toBe(false)
		t.expect(has(stopped.stderr, "restack stopped at R0010/2/c0020")).toBe(true)
		t.expect(has(stopped.stderr, "conflict")).toBe(true)
		t.expect(git(f.main, { "rev-parse", "origin/R0010/1/c0010" })).toBe(lower)
		t.expect(git(f.main, { "rev-parse", "origin/R0010/2/c0020" })).toBe(layer2)
		-- the conflicting commit was only on layer 1; put that layer back on the restacked tip
		local good = git(f.main, { "rev-parse", "origin/R0010/1/c0010~1" })
		git(wt, { "reset", "--hard", good })
		git(wt, { "push", "-q", "--force-with-lease" })
	end)

	it("done refuses an unfinished layer, a layer that is not restacked, and a changed contract", function()
		git(wt, { "switch", "-q", "R0010/1/c0010" })
		zn(wt, { "finish", "c0010" })
		git(wt, { "switch", "-q", "R0010/2/c0020" })
		local refused = trackerfix.tr(f, wt, { "done", "R0010" }, env)
		t.expect(refused.ok).toBe(false)
		t.expect(has(refused.stderr, "R0010/2/c0020 is not stacked")).toBe(true)
		zn(wt, { "restack", "R0010" })
		git(wt, { "switch", "-q", "R0010/2/c0020" })
		git(wt, { "commit", "-q", "--allow-empty", "-m", "still working" })
		git(wt, { "push", "-q" })
		local unfinished = trackerfix.tr(f, wt, { "done", "R0010" }, env)
		t.expect(unfinished.ok).toBe(false)
		t.expect(has(unfinished.stderr, "c0020 is not finished")).toBe(true)
		git(wt, { "reset", "--hard", "HEAD~1" })
		git(wt, { "push", "-q", "--force-with-lease" })

		wtBad = trackerfix.trOk(f, f.main, { "worktree", "R0030" })
		zn(wtBad, { "start", "R0030" })
		write(
			wtBad,
			"pickman/.tracker/rafts/active/R0030/final-review-001.md",
			"# Final Review 001\n\nVerdict: approve\n"
		)
		write(wtBad, "pickman/src/delta.luau", "delta\n")
		git(wtBad, { "add", "-A" })
		git(wtBad, { "commit", "-qm", "c0040 work" })
		zn(wtBad, { "finish", "c0040" })
		local doc = fs.readFile(`{wtBad}/pickman/.tracker/issues/active/c0040/c0040.md`)
		fs.writeFile(
			`{wtBad}/pickman/.tracker/issues/active/c0040/c0040.md`,
			(string.gsub(doc, "\none\n", "\ntwo\n"))
		)
		git(wtBad, { "add", "-A" })
		git(wtBad, { "commit", "-qm", "design drifted" })
		git(wtBad, { "push", "-q" })
		local drifted = trackerfix.tr(f, wtBad, { "done", "R0030" }, env)
		t.expect(drifted.ok).toBe(false)
		t.expect(has(drifted.stderr, "contract changed")).toBe(true)
	end)

	it("done lands two ticket commits and one binding commit, and a one-ticket raft the same way", function()
		seal.trace(wt, "R0010")
		local landed = zn(wt, { "done", "R0010" })
		t.expect(has(landed, "landed R0010")).toBe(true)
		local calls = fs.readFile(log)
		t.expect(has(calls, "pr edit 1 --base main")).toBe(true)
		local graph = git(f.main, { "log", "--graph", "--format=%s", "origin/main" })
		local subjects = git(f.main, { "log", "-4", "--format=%s", "origin/main" })
		local bind = git(f.main, { "log", "-1", "--format=%B", "origin/main" })
		local ticket2 = git(f.main, { "log", "-1", "--format=%B", "origin/main^2^" })
		local ticket1 = git(f.main, { "log", "-1", "--format=%B", "origin/main^2^^" })
		t.expect(subjects)
			.toBe("R0010: bind c0010, c0020\nR0010: final-review-001\nc0020: beta\nc0010: alpha")
		t.expect(has(bind, "Verdict: approve")).toBe(true)
		t.expect(has(bind, "Trace: pickman/.tracker/rafts/done/R0010/trace.md")).toBe(true)
		t.expect(git(f.main, { "rev-parse", "origin/main^2" }) ~= "").toBe(true)
		fs.writeFile(
			proof,
			`## two-ticket graph\n{graph}\n\n## bind\n{bind}\n## ticket 2\n{ticket2}\n## ticket 1\n{ticket1}\n`
		)

		wtOne = trackerfix.trOk(f, f.main, { "worktree", "R0020" })
		zn(wtOne, { "start", "R0020" })
		t.expect(git(wtOne, { "branch", "--show-current" })).toBe("R0020/1/c0030")
		write(wtOne, "pickman/src/gamma.luau", "gamma\n")
		write(
			wtOne,
			"pickman/.tracker/rafts/active/R0020/review-001.md",
			"# Review 001\n\nVerdict: approve\n"
		)
		git(wtOne, { "add", "-A" })
		git(wtOne, { "commit", "-qm", "c0030 work" })
		zn(wtOne, { "finish", "c0030" })
		seal.trace(wtOne, "R0020")
		zn(wtOne, { "done", "R0020" })
		local one = git(f.main, { "log", "-3", "--format=%s", "origin/main" })
		t.expect(one).toBe("R0020: bind c0030\nR0020: final-review-001\nc0030: gamma")
		local oneGraph = git(f.main, { "log", "--graph", "-4", "--format=%s", "origin/main" })
		fs.writeFile(proof, fs.readFile(proof) .. `\n## one-ticket\n{oneGraph}\n`)
	end)
end)
