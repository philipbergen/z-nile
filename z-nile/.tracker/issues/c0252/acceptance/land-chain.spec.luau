--!strict
-- c0252 AC10 to AC12 and AC14: the dispatcher's chain lands a finished raft, waits, runs the worker again and blocks, and lands
-- the green layers below a requested block first. Real dispatcher, fake CLIs and a fake gh (@tests/lib/fakecli), real
-- rafts with finished layers in a local github-shaped origin. Fixture: .cache/c0252-land-chain-github.com. Cases
-- build on each other.
local dispatcher: any = require("@znile/engine/dispatcher")
local escalation = require("@znile/engine/escalation")
local fakecli = require("@tests/lib/fakecli")
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
local MODELS = [[
[dispatch]
auto_merge = ["prep", "raft", "run"]
merge_attempts = 2
stall_seconds = 30

[roles.implementation]
model = "claude-opus-5-5"
cli = "claude"
runtime = "claude-cli"
rank = 3
max_tokens = 5000
effort = "high"
fallbacks = []
]]

local function issue(id: string, raft: string): string
	return `---\nid: {id}\ntype: chore\ntitle: {id}\nslug: {id}\nraft: {raft}\ndepends_on: []\nemergent: false\ndesign: ready\ncreated: 2026-10-06\nstatus: {PREPARED}\n---\n\n# {id}\n\n{CAPTURED}`
end
local function raft(id: string, issues: { string }): string
	return `---\nid: {id}\ntype: chore\ntitle: {id}\nslug: {id}\nsingle: false\nissues: [{table.concat(
		issues,
		", "
	)}]\ndesign: ready\ncreated: 2026-10-06\nstatus: {PREPARED}\n---\n\n# {id}\n\n## Order & dependencies\n{table.concat(
		issues,
		"\n"
	)}\n`
end

local h: fakecli.Harness
local function git(dir: string, args: { string }): string
	return fixture.git(dir, args)
end
local function zn(args: { string }, extra: { [string]: string }?): fixture.Result
	return fakecli.zn(h, args, extra)
end
-- ./zn in a raft's worktree (start and finish run there), with the fakes first on PATH
local function znAt(dir: string, args: { string }): fixture.Result
	local argv = { "scripts/tracker.sh" }
	for _, a in args do
		table.insert(argv, a)
	end
	return fixture.exec(dir, "bash", argv, {
		env = {
			FAKE_DIR = h.fakes,
			PATH = `{h.bin}:{process.env.PATH}`,
			ZN_AGENT_TOKEN_FILE = h.token,
			GH_TOKEN = "the-users-token",
		},
	})
end
local function must(r: fixture.Result, what: string): string
	if not r.ok then
		error(`{what} failed ({r.code}): {r.stderr}{r.stdout}`, 2)
	end
	return (string.gsub(r.stdout, "%s+$", ""))
end
local function has(s: string, part: string): boolean
	return string.find(s, part, 1, true) ~= nil
end
local function count(text: string, needle: string): number
	local n, i = 0, 1
	while true do
		local a, b = string.find(text, needle, i, true)
		if not a then
			return n
		end
		n += 1
		i = (b :: number) + 1
	end
end
local function write(dir: string, path: string, text: string)
	local parent = string.match(path, "^(.*)/[^/]+$")
	if parent then
		fs.writeDir(`{dir}/{parent}`)
	end
	fs.writeFile(`{dir}/{path}`, text)
end
local function onOrigin(path: string): string
	return git(h.f.origin, { "show", `main:{path}` })
end
local function mainSubjects(n: number): string
	return git(h.f.main, { "log", `-{n}`, "--format=%s", "--first-parent", "origin/main" })
end

local PENDING = '[{"name":"static","status":"IN_PROGRESS","conclusion":""}]'
local FAILED = '[{"name":"static","status":"COMPLETED","conclusion":"FAILURE"}]'
local GREEN =
	'[{"name":"static","status":"COMPLETED","conclusion":"SUCCESS"},{"name":"deploy","conclusion":"SKIPPED"}]'
-- the layer branch's pull request as the fake gh answers it
local function pr(branch: string, checks: string, head: string?)
	local sha = head or git(h.f.main, { "rev-parse", `origin/{branch}` })
	fs.writeFile(
		`{h.bin}/prview-{(string.gsub(branch, "/", "_"))}.json`,
		`\{"state":"OPEN","isDraft":false,"headRefOid":"{sha}","mergeable":"MERGEABLE","statusCheckRollup":{checks}}`
	)
end
local worktrees: { [string]: string } = {}
-- a layer of `rid` for `iid`: started, one source file, finished, reviewed
local function layer(rid: string, iid: string, file: string, first: boolean)
	local wt = worktrees[rid]
	must(znAt(wt, { "start", rid }), `start {iid}`)
	write(wt, `pickman/src/{file}.luau`, `{file}\n`)
	if first then
		write(
			wt,
			`pickman/.tracker/rafts/active/{rid}/final-review-001.md`,
			"# Final Review 001\n\nVerdict: approve\n"
		)
	end
	git(wt, { "add", "-A" })
	git(wt, { "commit", "-qm", `{iid} work` })
	must(znAt(wt, { "finish", iid }), `finish {iid}`)
	seal.layerReview(wt, iid)
end
local function dispatchOut(id: string): fixture.Result
	return zn({ "dispatch", id })
end

return t.spec("c0252 the chain lands a finished raft", function(it)
	it(
		"sets up four readied rafts, a fake gh and fake CLIs (each raft gets its layers just before its case: a layer is based on the main of that moment)",
		function()
			local seed: { [string]: string } = {
				[".models.toml"] = MODELS,
				[".gitignore"] = fs.readFile(`{TOP}/.gitignore`),
				["pickman/.tracker/architecture.md"] = fs.readFile(`{TOP}/pickman/.tracker/architecture.md`),
			}
			local rafts: { [string]: { string } } = {
				R0010 = { "c0010" },
				R0020 = { "c0020" },
				R0030 = { "c0030" },
				R0040 = { "c0040", "c0050" },
			}
			for rid, ids in rafts do
				seed[`pickman/.tracker/rafts/{rid}/{rid}.md`] = raft(rid, ids)
				seed[`pickman/.tracker/rafts/{rid}/check.sh`] = CHECK
				for _, iid in ids do
					seed[`pickman/.tracker/issues/{iid}/{iid}.md`] = issue(iid, rid)
					seed[`pickman/.tracker/issues/{iid}/check.sh`] = CHECK
					seed[`pickman/.tracker/issues/{iid}/acceptance/.gitkeep`] = ""
				end
			end
			h = fakecli.new("c0252-land-chain-github.com", seed)
			-- the fake gh: a layer branch's pull request from prview-<branch>.json, the other calls as stack-land's stub
			fs.writeFile(
				`{h.bin}/gh`,
				table.concat({
					"#!/bin/sh",
					'echo "realgh $*" >> "$FAKE_DIR/log"',
					'case "$1 $2" in',
					`  "pr view") case "$*" in *statusCheckRollup*) b=$(printf "%s" "$3" | tr / _); [ -f "{h.bin}/prview-$b.json" ] && cat "{h.bin}/prview-$b.json" && exit 0; exit 1 ;; esac; echo main; exit 0 ;;`,
					'  "pr list") case "$*" in *number*) echo 1 ;; esac; exit 0 ;;',
					'  "pr create") echo https://github.com/x/y/pull/1; exit 0 ;;',
					"esac",
					"exit 0",
					"",
				}, "\n")
			)
			process.exec("chmod", { "+x", `{h.bin}/gh` })
			for rid in rafts do
				must(zn({ "ready", rid }), `ready {rid}`)
				worktrees[rid] = must(zn({ "worktree", rid }), `worktree {rid}`)
			end
		end
	)

	it(
		"AC11: a pending check stops the chain at the gate with exit 4 and the reason, and lands nothing",
		function()
			fakecli.mode(h, "claude", "ok")
			layer("R0020", "c0020", "beta", true)
			seal.trace(worktrees.R0020, "R0020")
			pr("R0020/1/c0020", PENDING)
			local before = git(h.f.main, { "ls-remote", "origin", "refs/heads/main" })
			local r = dispatchOut("R0020")
			t.expect(r.code).toBe(4)
			t.expect(has(r.stdout, "waiting to land R0020")).toBe(true)
			t.expect(has(r.stdout, "ci-pending")).toBe(true)
			t.expect(git(h.f.main, { "ls-remote", "origin", "refs/heads/main" })).toBe(before)
		end
	)

	it("AC11: a problem the worker can fix runs it again twice, then blocks under its reason", function()
		-- the pull request's head is not the layer tip: a fixable problem (publish the layer), which this worker does not fix
		pr("R0020/1/c0020", GREEN, "0000000000000000000000000000000000000000")
		local zruns = count(fakecli.log(h), "claude step=z-run")
		local r = dispatchOut("R0020")
		t.expect(r.code).toBe(3)
		t.expect(count(fakecli.log(h), "claude step=z-run")).toBe(zruns + 2)
		t.expect(has(r.stdout, "R0020 is blocked (red-gate)")).toBe(true)
		local note = onOrigin("pickman/.tracker/rafts/R0020/escalation.md")
		t.expect(has(note, "pr-head-moved")).toBe(true)
		t.expect(has(note, "after 2 tries")).toBe(true)
	end)

	it(
		"AC10: a finished raft whose top layer is green is landed by the dispatcher: one bind, the raft done, exit 0",
		function()
			fakecli.mode(h, "claude", "ok")
			layer("R0010", "c0010", "alpha", true)
			seal.trace(worktrees.R0010, "R0010")
			pr("R0010/1/c0010", GREEN)
			local r = dispatchOut("R0010")
			t.expect(r.code).toBe(0)
			t.expect(has(r.stdout, "next: land R0010")).toBe(true)
			t.expect(has(r.stdout, "R0010 is done")).toBe(true)
			t.expect(has(mainSubjects(6), "R0010: bind c0010")).toBe(true)
			t.expect(git(h.f.main, { "rev-parse", "origin/main^2" }) ~= "").toBe(true)
			onOrigin("pickman/.tracker/rafts/done/R0010/R0010.md")
			-- the landing ran with the dispatcher's environment: no agent credential, no ZN_DISPATCH
			local state = fakecli.state(h, "R0010")
			t.expect(state.outcome).toBe("ok")
			-- a second run finds it done
			local again = dispatchOut("R0010")
			t.expect(again.code).toBe(0)
			t.expect(has(again.stdout, "R0010 is done")).toBe(true)
		end
	)

	it(
		"AC11: a failed check blocks the raft at once: the dispatcher files the note, runs block, and exits 3",
		function()
			layer("R0030", "c0030", "gamma", true)
			seal.trace(worktrees.R0030, "R0030")
			pr("R0030/1/c0030", FAILED)
			local zruns = count(fakecli.log(h), "claude step=z-run")
			local r = dispatchOut("R0030")
			t.expect(r.code).toBe(3)
			t.expect(has(r.stdout, "R0030 is blocked (red-gate)")).toBe(true)
			-- the worker ran once (the run step); the failed check was not a second try
			t.expect(count(fakecli.log(h), "claude step=z-run")).toBe(zruns + 1)
			local note = onOrigin("pickman/.tracker/rafts/R0030/escalation.md")
			local parsed, why = escalation.parse(note)
			t.expect(why).toBe(nil)
			t.expect(parsed ~= nil).toBe(true)
			t.expect(escalation.check(parsed :: any)).toBe(nil)
			t.expect(has(note, "ci-failed")).toBe(true)
			t.expect(has(note, "Reason: red-gate")).toBe(true)
		end
	)

	it("AC12: a requested block lands the green layers below it first, then files the block", function()
		layer("R0040", "c0040", "delta", true)
		-- Phase 5 for the layers that are green, before the worker went on to c0050: the trace of the landing of c0040
		-- alone, committed on its layer (a landing has its own trace and final review)
		seal.trace(worktrees.R0040, "R0040", "c0040", 1)
		git(worktrees.R0040, { "push", "-q" })
		layer("R0040", "c0050", "epsilon", false)
		pr("R0040/1/c0040", GREEN)
		-- the fake worker blocks the raft at layer c0050 the way z-run is told to: the note, then ./zn block
		fakecli.mode(h, "claude", "script")
		fs.writeFile(
			`{h.fakes}/script.sh`,
			table.concat({
				"mkdir -p pickman/.tracker/rafts/active/R0040",
				"cat > pickman/.tracker/rafts/active/R0040/escalation.md <<'NOTE'",
				"## Question",
				"Should c0050 wait for the library?",
				"",
				"## What was tried",
				"Two drafts.",
				"",
				"## Open findings or error",
				"F1: no reader.",
				"",
				"## Options",
				"- approve: take the library (recommended)",
				"- retry: one more round",
				"NOTE",
				"./zn block R0040 design-gap --layer c0050",
				"",
			}, "\n")
		)
		-- the trace and final review of the landing of c0040 alone (a landing has its own)
		local r = dispatchOut("R0040")
		t.expect(has(r.stdout, "next: land R0040 through c0040")).toBe(true)
		t.expect(has(mainSubjects(8), "R0040: bind c0040")).toBe(true)
		t.expect(r.code).toBe(3)
		t.expect(has(r.stdout, "R0040 is blocked (design-gap)")).toBe(true)
		-- the first layer is in done/, the second waits, blocked, with the worker's own note
		onOrigin("pickman/.tracker/issues/done/c0040/c0040.md")
		t.expect(
			has(onOrigin("pickman/.tracker/rafts/R0040/escalation.md"), "Should c0050 wait for the library?")
		)
			.toBe(true)
		t.expect(fs.isFile(`{h.fakes}/../dispatch-ignored`)).toBe(false)
	end)

	it(
		"AC14: after the dispatcher's own bind the guard's mark moves to it, so main is vetted, and a foreign commit still trips",
		function()
			local ctx: any = {
				fail = function(m: string): never
					error(m, 0)
				end,
				mainRoot = function(): string
					return h.f.main
				end,
				onGitHub = function(): boolean
					return false
				end,
				checking = function(): boolean
					return true
				end,
				origin = function(): any
					return nil
				end,
				prView = function(): string?
					return nil
				end,
				prMerged = function(): boolean
					return false
				end,
			}
			-- a new raft's landing, in this process: the mark is main before the bind
			git(h.f.main, { "fetch", "-q", "origin" })
			t.expect(dispatcher.vetMain(ctx)).toBe(nil)
			local tip = git(h.f.main, { "rev-parse", "origin/main" })
			-- the bind of R0010 is already behind that mark; make a second bind with another raft's layer by hand
			local before = tip
			-- a foreign merge commit on main (not a pull request, not tracker state)
			local scratch = h.f.other
			git(scratch, { "pull", "-q", "origin", "main" })
			git(scratch, { "checkout", "-q", "-b", "side" })
			write(scratch, "pickman/src/foreign.luau", "x\n")
			git(scratch, { "add", "-A" })
			git(scratch, { "commit", "-qm", "foreign side" })
			local side = git(scratch, { "rev-parse", "HEAD" })
			git(scratch, { "checkout", "-q", "main" })
			git(scratch, { "merge", "--no-ff", "-m", "foreign bind", side })
			git(scratch, { "push", "-q", "origin", "HEAD:main" })
			-- afterLand of a tip that is not the bind's second parent trips; the mark stays
			local tripped = dispatcher.afterLand(ctx, "1111111111111111111111111111111111111111")
			t.expect(tripped ~= nil).toBe(true)
			t.expect(has(tostring(tripped), "is not the bind")).toBe(true)
			local vet = dispatcher.vetMain(ctx)
			t.expect(vet ~= nil).toBe(true)
			t.expect(has(tostring(vet), "arrived during this run")).toBe(true)
			-- the same commit announced as the dispatcher's own bind of `side` is accepted and moves the mark
			t.expect(dispatcher.afterLand(ctx, side)).toBe(nil)
			t.expect(dispatcher.vetMain(ctx)).toBe(nil)
			t.expect(before ~= git(h.f.origin, { "rev-parse", "main" })).toBe(true)
		end
	)
end)
