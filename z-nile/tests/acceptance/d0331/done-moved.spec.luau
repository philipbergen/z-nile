--!strict
-- d0331: done checks the stack against current main in one place, the merge onto main's tip and the gate on that
-- merged tree. A push rejected because main gained commits during the gate is retried by done itself (merge,
-- gate, push), at most stack.DONE_ATTEMPTS times; a conflict and a red gate name ./zn restack.
-- The gate here is a stub (z-nile/check.sh in the fixture) that logs each run, records one measured line as the
-- real gate's wrapper does, and can land a commit on main. Origin's update hook can reject R0040's binding commit.
-- Fixture: .cache/d0331-done-moved-github.com (its own origin and clones).
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
local CAPTURED =
	"## Problem\nThe marker is missing.\n\n## Solution\nStore the marker.\n\n## Acceptance criteria\n- AC1: the marker is stored\n"

local function issue(id: string, title: string, raft: string): string
	return `---\nid: {id}\ntype: chore\ntitle: {title}\nslug: {id}\nraft: {raft}\ndepends_on: []\nemergent: false\ndesign: ready\ncreated: 2026-10-06\nstatus: {PREPARED}\n---\n\n# {id}\n\n{CAPTURED}`
end

local function raftDoc(id: string, slug: string, issues: string, order: string): string
	return `---\nid: {id}\ntype: chore\ntitle: {slug}\nslug: {slug}\nsingle: false\nissues: [{issues}]\ndesign: ready\ncreated: 2026-10-06\nstatus: {PREPARED}\n---\n\n# {id}\n\n## Order & dependencies\n{order}\n`
end

local STUB_GATE = table.concat({
	"#!/usr/bin/env bash",
	'echo "gate: $*" >> "$GATE_LOG"',
	-- what the real gate's wrapper does: one measured line for this run, in the checkout's buffer
	'bash scripts/tracker.sh record --phase test --wall 1 --subject "stub gate"',
	'left=0; [[ -s "$GATE_MOVES" ]] && left="$(cat "$GATE_MOVES")"',
	"if (( left > 0 )); then",
	'  echo $((left - 1)) > "$GATE_MOVES"',
	'  git -C "$GATE_OTHER" pull -q origin main',
	'  mkdir -p "$GATE_OTHER/pickman/src"',
	'  echo "$left" > "$GATE_OTHER/pickman/src/gate-moved-$left-$RANDOM.luau"',
	'  git -C "$GATE_OTHER" add -A',
	'  git -C "$GATE_OTHER" commit -q -m "elsewhere: during the gate"',
	'  git -C "$GATE_OTHER" push -q origin HEAD:main',
	"fi",
	'exit "${GATE_EXIT:-0}"',
	"",
}, "\n")

local f: trackerfix.Fixture
local env: { [string]: string } = {}
local ghLog, gateLog, moves = "", "", ""

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

-- done with the gate (the stub), which lands `n` commits on main, one per run, and exits `code`.
local function done(dir: string, raft: string, n: number, code: number): fixture.Result
	fs.writeFile(gateLog, "")
	fs.writeFile(moves, tostring(n))
	local e = table.clone(env)
	e.PICKMAN_DONE_GATE = "1"
	e.GATE_LOG = gateLog
	e.GATE_MOVES = moves
	e.GATE_OTHER = f.other
	e.GATE_EXIT = tostring(code)
	return trackerfix.tr(f, dir, { "done", raft }, e)
end

local function gateRuns(): number
	local _, n = string.gsub(fs.readFile(gateLog), "gate: %-%-affected", "")
	return n
end

-- A one-ticket raft built to the point where done can run: started, finished, traced. Returns its worktree.
local function built(raft: string, id: string, file: string, text: string): string
	local wt = trackerfix.trOk(f, f.main, { "worktree", raft })
	zn(wt, { "start", raft })
	write(wt, file, text)
	write(
		wt,
		`pickman/.tracker/rafts/active/{raft}/final-review-001.md`,
		"# Final Review 001\n\nVerdict: approve\n"
	)
	git(wt, { "add", "-A" })
	git(wt, { "commit", "-qm", `{id} work` })
	zn(wt, { "finish", id })
	seal.layerReview(wt, id) -- c0248: done lands only complete (reviewed) layers
	seal.trace(wt, raft)
	return wt
end

return t.spec("d0331 done lands on a main that moves", function(it)
	it("sets up four one-ticket rafts behind a local github-shaped origin, with a stub gate", function()
		local seed: { [string]: string } = {
			[".gitignore"] = fs.readFile(`{TOP}/.gitignore`),
			["pickman/.tracker/architecture.md"] = fs.readFile(`{TOP}/pickman/.tracker/architecture.md`),
			["z-nile/check.sh"] = STUB_GATE,
		}
		for n, id in { "c0010", "c0020", "c0030", "c0040" } do
			local raft = `R00{n}0`
			seed[`pickman/.tracker/rafts/{raft}/{raft}.md`] = raftDoc(raft, `one{n}`, id, id)
			seed[`pickman/.tracker/issues/{id}/{id}.md`] = issue(id, `title{n}`, raft)
			seed[`pickman/.tracker/rafts/{raft}/check.sh`] = CHECK
			seed[`pickman/.tracker/issues/{id}/check.sh`] = CHECK
			seed[`pickman/.tracker/issues/{id}/acceptance/.gitkeep`] = ""
		end
		f = trackerfix.new("d0331-done-moved-github.com", seed)
		local bin = `{f.base}/bin`
		ghLog, gateLog, moves = `{f.base}/gh.log`, `{f.base}/gate.log`, `{f.base}/moves`
		fs.writeDir(bin)
		fs.writeFile(
			`{bin}/gh`,
			`#!/bin/sh\necho "$*" >> "{ghLog}"\n`
				.. 'case "$1 $2" in\n  "pr list") case "$*" in *number*) echo 1 ;; esac; exit 0 ;;\n'
				.. '  "pr create") echo https://github.com/x/y/pull/1; exit 0 ;;\n  "pr view") echo layerbase; exit 0 ;;\nesac\nexit 0\n'
		)
		process.exec("chmod", { "+x", `{bin}/gh` })
		env = { PATH = `{bin}:{process.env.PATH or ""}` }
		-- origin refuses R0040's binding commit while <base>/reject-bind exists; every other push to main goes through
		fs.writeFile(
			`{f.origin}/hooks/update`,
			'#!/bin/sh\nif [ "$1" = refs/heads/main ] && [ -f "'
				.. f.base
				.. '/reject-bind" ]; then\n  case "$(git log -1 --format=%s "$3")" in "R0040: bind"*) echo "bind rejected on purpose" >&2; exit 1 ;; esac\nfi\nexit 0\n'
		)
		process.exec("chmod", { "+x", `{f.origin}/hooks/update` })
		for _, raft in { "R0010", "R0020", "R0030", "R0040" } do
			trackerfix.trOk(f, f.main, { "ready", raft })
		end
	end)

	it(
		"AC6: main gains a commit during the gate, and done merges onto the new tip, gates again and lands by itself",
		function()
			local wt = built("R0010", "c0010", "pickman/src/one.luau", "one\n")
			local top = git(wt, { "rev-parse", "HEAD" })
			local r = done(wt, "R0010", 1, 0)
			local out = must(r, "done R0010")
			t.expect(has(out, "landed R0010")).toBe(true)
			if not has(out, "running the gate again (attempt 2 of 9)") then
				error(`done did not say it gated again: {out} / {r.stderr}`)
			end
			t.expect(has(r.stdout .. r.stderr, "restack")).toBe(false)
			t.expect(gateRuns()).toBe(2)
			git(f.main, { "fetch", "-q", "origin" })
			t.expect(git(f.main, { "log", "-1", "--format=%s", "origin/main" })).toBe("R0010: bind c0010")
			t.expect(git(f.main, { "log", "-1", "--format=%s", "origin/main^1" }))
				.toBe("elsewhere: during the gate")
			t.expect(git(f.main, { "rev-parse", "origin/main^2" })).toBe(top)
			-- one binding commit, not one per attempt
			local _, binds =
				string.gsub(git(f.main, { "log", "--format=%s", "origin/main" }), "R0010: bind", "")
			t.expect(binds).toBe(1)
			-- the gate ran twice and both runs are in the landed ticket's cost rows: the discarded attempt's is not lost
			local dir = "pickman/.tracker/issues/done/c0010/spend.d"
			local rows = ""
			for name in
				string.gmatch(git(f.main, { "ls-tree", "--name-only", "origin/main", dir .. "/" }), "[^\n]+")
			do
				rows ..= git(f.main, { "show", `origin/main:{name}` }) .. "\n"
			end
			local _, gates = string.gsub(rows, "stub gate", "")
			t.expect(gates).toBe(2)
			t.expect(
				git(
					f.main,
					{ "ls-tree", "-d", "--name-only", "origin/main", "pickman/.tracker/rafts/done/R0010" }
				)
			).toBe("pickman/.tracker/rafts/done/R0010")
		end
	)

	it(
		"AC7: main gains a commit during every gate, and done stops after nine attempts, rolled back, asking for done again",
		function()
			local wt = built("R0020", "c0020", "pickman/src/two.luau", "two\n")
			local top = git(wt, { "rev-parse", "HEAD" })
			fs.writeFile(ghLog, "")
			local r = done(wt, "R0020", 12, 0)
			t.expect(r.ok).toBe(false)
			t.expect(
				has(
					r.stderr,
					"main gained commits during each of 9 attempts (rolled back): run ./zn done R0020 again"
				)
			).toBe(true)
			t.expect(has(r.stderr, "restack")).toBe(false)
			t.expect(gateRuns()).toBe(9)
			-- rolled back: on the layer, clean, the raft still active on main, every pull request base put back
			t.expect(git(wt, { "branch", "--show-current" })).toBe("R0020/1/c0020")
			t.expect(git(wt, { "rev-parse", "HEAD" })).toBe(top)
			t.expect(git(wt, { "status", "--porcelain" })).toBe("")
			git(f.main, { "fetch", "-q", "origin" })
			t.expect(
				git(
					f.main,
					{ "ls-tree", "-d", "--name-only", "origin/main", "pickman/.tracker/rafts/active/R0020" }
				)
			).toBe("pickman/.tracker/rafts/active/R0020")
			local calls = fs.readFile(ghLog)
			local _, toMain = string.gsub(calls, "pr edit 1 %-%-base main", "")
			local _, back = string.gsub(calls, "pr edit 1 %-%-base layerbase", "")
			t.expect(toMain).toBe(9)
			t.expect(back).toBe(9)
			-- and the same command lands it once main holds still
			local again = done(wt, "R0020", 0, 0)
			t.expect(has(must(again, "done R0020 again"), "landed R0020")).toBe(true)
			t.expect(gateRuns()).toBe(1)
		end
	)

	it(
		"AC8: a red gate on the merged tree and a merge conflict both refuse naming ./zn restack, and leave the layer as it was",
		function()
			local wt = built("R0030", "c0030", "pickman/src/clash.luau", "layer\n")
			local top = git(wt, { "rev-parse", "HEAD" })
			local red = done(wt, "R0030", 0, 1)
			t.expect(red.ok).toBe(false)
			t.expect(
				has(red.stderr, "the affected gate fails on the done tree (rolled back); fix and retry done")
			)
				.toBe(true)
			t.expect(has(red.stderr, "./zn restack R0030")).toBe(true)
			t.expect(gateRuns()).toBe(1)
			t.expect(git(wt, { "rev-parse", "HEAD" })).toBe(top)
			trackerfix.elsewhere(f, { ["pickman/src/clash.luau"] = "main\n" }, "elsewhere: the same file")
			local clash = done(wt, "R0030", 0, 0)
			t.expect(clash.ok).toBe(false)
			t.expect(has(clash.stderr, "R0030/1/c0030 does not merge onto main: ./zn restack R0030"))
				.toBe(true)
			t.expect(gateRuns()).toBe(0)
			t.expect(git(wt, { "branch", "--show-current" })).toBe("R0030/1/c0030")
			t.expect(git(wt, { "rev-parse", "HEAD" })).toBe(top)
			t.expect(git(wt, { "status", "--porcelain" })).toBe("")
		end
	)

	it(
		"AC7: a push origin rejects while main stands still is not tried again: one gate, the push refusal, the base put back",
		function()
			local wt = built("R0040", "c0040", "pickman/src/four.luau", "four\n")
			local top = git(wt, { "rev-parse", "HEAD" })
			fs.writeFile(`{f.base}/reject-bind`, "")
			fs.writeFile(ghLog, "")
			local r = done(wt, "R0040", 0, 0)
			t.expect(r.ok).toBe(false)
			t.expect(has(r.stderr, "could not push the binding commit to main (rolled back)")).toBe(true)
			t.expect(has(r.stderr, "bind rejected on purpose")).toBe(true)
			t.expect(has(r.stderr, "attempts")).toBe(false)
			t.expect(has(r.stdout, "running the gate again")).toBe(false)
			t.expect(gateRuns()).toBe(1)
			local _, back = string.gsub(fs.readFile(ghLog), "pr edit 1 %-%-base layerbase", "")
			t.expect(back).toBe(1)
			t.expect(git(wt, { "rev-parse", "HEAD" })).toBe(top)
		end
	)

	it(
		"AC7: main moves once and origin then rejects the push for another reason: two gates, then the push refusal, not nine",
		function()
			local wt = `{f.main}/.worktree/R0040`
			local r = done(wt, "R0040", 1, 0)
			t.expect(r.ok).toBe(false)
			t.expect(has(r.stdout, "running the gate again (attempt 2 of 9)")).toBe(true)
			t.expect(has(r.stderr, "could not push the binding commit to main (rolled back)")).toBe(true)
			t.expect(has(r.stderr, "bind rejected on purpose")).toBe(true)
			t.expect(has(r.stderr, "each of 9 attempts")).toBe(false)
			t.expect(gateRuns()).toBe(2)
			fs.removeFile(`{f.base}/reject-bind`)
			t.expect(has(must(done(wt, "R0040", 0, 0), "done R0040"), "landed R0040")).toBe(true)
		end
	)
end)
