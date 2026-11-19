--!strict
-- d0331: two ways a rejected push of the binding commit is not "main moved, try again". A push that reached origin
-- and reported failure has landed (a git shim on PATH exits 1 after the real push). A push lost to a moved main
-- whose pull request base cannot be put back (a gh stub that fails that one edit) stops, naming the command.
-- Fixture: .cache/d0331-done-push-github.com (its own origin and clones; the gate is the stub of done-moved.spec).
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

return t.spec("d0331 done and a push that is not what it seems", function(it)
	it(
		"sets up two one-ticket rafts, a stub gate, a gh stub that can fail one edit, and a git shim",
		function()
			local seed: { [string]: string } = {
				[".gitignore"] = fs.readFile(`{TOP}/.gitignore`),
				["pickman/.tracker/architecture.md"] = fs.readFile(`{TOP}/pickman/.tracker/architecture.md`),
				["z-nile/check.sh"] = STUB_GATE,
			}
			for n, id in { "c0010", "c0020" } do
				local raft = `R00{n}0`
				seed[`pickman/.tracker/rafts/{raft}/{raft}.md`] = raftDoc(raft, `one{n}`, id, id)
				seed[`pickman/.tracker/issues/{id}/{id}.md`] = issue(id, `title{n}`, raft)
				seed[`pickman/.tracker/rafts/{raft}/check.sh`] = CHECK
				seed[`pickman/.tracker/issues/{id}/check.sh`] = CHECK
				seed[`pickman/.tracker/issues/{id}/acceptance/.gitkeep`] = ""
			end
			f = trackerfix.new("d0331-done-push-github.com", seed)
			local bin = `{f.base}/bin`
			ghLog, gateLog, moves = `{f.base}/gh.log`, `{f.base}/gate.log`, `{f.base}/moves`
			fs.writeDir(bin)
			-- putting a base back fails while <base>/keep-base exists
			fs.writeFile(
				`{bin}/gh`,
				`#!/bin/sh\necho "$*" >> "{ghLog}"\n`
					.. 'case "$*" in *"--base layerbase"*) if [ -f "'
					.. f.base
					.. '/keep-base" ]; then exit 1; fi ;; esac\n'
					.. 'case "$1 $2" in\n  "pr list") case "$*" in *number*) echo 1 ;; esac; exit 0 ;;\n'
					.. '  "pr create") echo https://github.com/x/y/pull/1; exit 0 ;;\n  "pr view") echo layerbase; exit 0 ;;\nesac\nexit 0\n'
			)
			process.exec("chmod", { "+x", `{bin}/gh` })
			env = { PATH = `{bin}:{process.env.PATH or ""}` }
			-- the shim: every git call goes through; the push of the binding commit happens and then reports failure
			local real = (string.gsub(process.exec("sh", { "-c", "command -v git" }).stdout, "%s+$", ""))
			fs.writeDir(`{f.base}/shim`)
			fs.writeFile(
				`{f.base}/shim/git`,
				'#!/bin/sh\ncase "$*" in *"HEAD:refs/heads/main"*) "'
					.. real
					.. '" "$@" || exit $?; echo "the connection dropped" >&2; exit 1 ;; esac\nexec "'
					.. real
					.. '" "$@"\n'
			)
			process.exec("chmod", { "+x", `{f.base}/shim/git` })
			for _, raft in { "R0010", "R0020" } do
				trackerfix.trOk(f, f.main, { "ready", raft })
			end
		end
	)

	it(
		"AC12: a push that reached origin and reported failure has landed: one gate, one bind, the pull request left on main",
		function()
			local wt = built("R0010", "c0010", "pickman/src/one.luau", "one\n")
			local top = git(wt, { "rev-parse", "HEAD" })
			fs.writeFile(ghLog, "")
			local plain = env
			env = { PATH = `{f.base}/shim:{plain.PATH}` }
			local r = done(wt, "R0010", 0, 0)
			env = plain
			local out = must(r, "done R0010")
			t.expect(has(out, "reported a failure, and origin's main holds it: it landed")).toBe(true)
			t.expect(has(out, "landed R0010")).toBe(true)
			t.expect(has(out, "running the gate again")).toBe(false)
			t.expect(gateRuns()).toBe(1)
			git(f.main, { "fetch", "-q", "origin" })
			t.expect(git(f.main, { "log", "-1", "--format=%s", "origin/main" })).toBe("R0010: bind c0010")
			t.expect(git(f.main, { "rev-parse", "origin/main^2" })).toBe(top)
			local calls = fs.readFile(ghLog)
			t.expect(has(calls, "pr edit 1 --base main")).toBe(true)
			t.expect(has(calls, "--base layerbase")).toBe(false)
		end
	)

	it(
		"AC13: main moved and the pull request base cannot be put back: done stops at once, naming the command that puts it back",
		function()
			local wt = built("R0020", "c0020", "pickman/src/two.luau", "two\n")
			local top = git(wt, { "rev-parse", "HEAD" })
			fs.writeFile(`{f.base}/keep-base`, "")
			local r = done(wt, "R0020", 5, 0)
			t.expect(r.ok).toBe(false)
			t.expect(
				has(
					r.stderr,
					"a pull request base could not be put back (rolled back). Put it back with: gh pr edit 1 --base layerbase. Then run ./zn done R0020 again"
				)
			).toBe(true)
			t.expect(has(r.stderr, "each of 9 attempts")).toBe(false)
			t.expect(gateRuns()).toBe(1)
			t.expect(git(wt, { "branch", "--show-current" })).toBe("R0020/1/c0020")
			t.expect(git(wt, { "rev-parse", "HEAD" })).toBe(top)
			t.expect(git(wt, { "status", "--porcelain" })).toBe("")
		end
	)
end)
