--!strict
-- c0252 AC10 to AC12, AC14 and AC16 to AC19: the dispatcher's chain lands a finished raft, waits, runs the worker again
-- and blocks, lands the green layers below a requested block first, judges and lands with the base's engine, gates a
-- game stack in a clean clone, and keeps an old single-branch raft's human gate. Real dispatcher, fake CLIs and a fake
-- gh (@tests/lib/fakecli), real rafts with finished layers in a local github-shaped origin. Fixture:
-- .cache/c0252-land-chain-github.com. Each raft is used by one case (its layers are started just before it, except
-- where a case moves main on purpose).
local dispatcher: any = require("@znile/engine/dispatcher")
local escalation = require("@znile/engine/escalation")
local fakecli = require("@tests/lib/fakecli")
local fixture = require("@tests/lib/fixture")
local fs = require("@lune/fs")
local process = require("@lune/process")
local seal = require("@tests/lib/seal")
local t = require("@tests/lib/t")

local TOP = (string.gsub(process.exec("git", { "rev-parse", "--show-toplevel" }).stdout, "%s+$", ""))
local PREPARED = "prepared-quiet-copper-falcon"
local CHECK = 'source "$(git -C "$(dirname "${BASH_SOURCE[0]}")" rev-parse --show-toplevel)/scripts/lib/ac.sh"\n'
	.. 'check "AC1: ok" true\nfinish\n'
local CAPTURED =
	"## Problem\nThe marker is missing.\n\n## Solution\nStore the marker.\n\n## Acceptance criteria\n- AC1: the marker is stored\n"
local MODELS = [[
[dispatch]
auto_merge = ["prep", "raft", "run"]
merge_retries = 2
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
local function raft(id: string, issues: { string }, slug: string?): string
	return `---\nid: {id}\ntype: chore\ntitle: {id}\nslug: {slug or id}\nsingle: false\nissues: [{table.concat(
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
local function mainHead(): string
	return git(h.f.main, { "ls-remote", "origin", "refs/heads/main" })
end
local function landed(rid: string): boolean
	return has(git(h.f.origin, { "log", "--first-parent", "--format=%s", "main" }), `{rid}: bind`)
end

local PENDING = '[{"name":"static","status":"IN_PROGRESS","conclusion":""}]'
local FAILED = '[{"name":"static","status":"COMPLETED","conclusion":"FAILURE"}]'
local GREEN =
	'[{"name":"static","status":"COMPLETED","conclusion":"SUCCESS"},{"name":"deploy","conclusion":"SKIPPED"}]'
local NOTIP = "0000000000000000000000000000000000000000"
-- the layer branch's pull request as the fake gh answers it (a non-draft one, MERGEABLE)
local function pr(branch: string, checks: string, head: string?)
	local sha = head or git(h.f.main, { "rev-parse", `origin/{branch}` })
	fs.writeFile(
		`{h.bin}/prview-{(string.gsub(branch, "/", "_"))}.json`,
		`\{"number":1,"state":"OPEN","isDraft":false,"headRefOid":"{sha}","mergeable":"MERGEABLE","statusCheckRollup":{checks}}`
	)
end
local worktrees: { [string]: string } = {}
-- a layer of `rid` for `iid`: started, one file under `dir` (a tooling path unless a case says otherwise), finished,
-- reviewed. `doc` is appended to the issue's document before the layer is finished.
local function layer(
	rid: string,
	iid: string,
	file: string,
	first: boolean,
	dir: string?,
	doc: string?,
	extra: { [string]: string }?
)
	local wt = worktrees[rid]
	must(znAt(wt, { "start", rid }), `start {iid}`)
	write(wt, `{dir or "z-nile/notes"}/{file}.md`, `{file}\n`)
	local more: { [string]: string } = extra or {}
	for path, text in more do
		write(wt, path, text)
	end
	if doc then
		local path = `{wt}/pickman/.tracker/issues/active/{iid}/{iid}.md`
		fs.writeFile(path, fs.readFile(path) .. doc)
	end
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
local function dispatchOut(id: string, extra: { [string]: string }?): fixture.Result
	return zn({ "dispatch", id }, extra)
end
local function stub(id: string): string
	return `---\nid: {id}\ntype: chore\ntitle: {id}\nslug: {id}\nraft: \ndepends_on: []\nemergent: false\ndesign: draft\ncreated: 2026-01-01\nstatus: new-quiet-copper-falcon\n---\n\n# {id}\n`
end
local NO_CICD = ""
local HAS_CICD = ""

return t.spec("c0252 the chain lands a finished raft", function(it)
	it(
		"sets up readied rafts, a fake gh and fake CLIs (each raft gets its layers just before its case: a layer is based on the main of that moment)",
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
				R0050 = { "c0060" },
				R0060 = { "c0070" },
				R0070 = { "c0080" },
				R0080 = { "c0090" },
				R0090 = { "c0100" },
				R0110 = { "c0120" },
				R0120 = { "c0130" },
				R0130 = { "c0140", "c0150" },
				R0140 = { "c0160" },
				R0099 = { "c0099" },
			}
			for rid, ids in rafts do
				seed[`pickman/.tracker/rafts/{rid}/{rid}.md`] =
					raft(rid, ids, if rid == "R0099" then "old" else nil)
				seed[`pickman/.tracker/rafts/{rid}/check.sh`] = CHECK
				for _, iid in ids do
					seed[`pickman/.tracker/issues/{iid}/{iid}.md`] = issue(iid, rid)
					seed[`pickman/.tracker/issues/{iid}/check.sh`] = CHECK
					seed[`pickman/.tracker/issues/{iid}/acceptance/.gitkeep`] = ""
				end
			end
			h = fakecli.new("c0252-land-chain-github.com", seed)
			-- the fake gh: a layer branch's pull request from prview-<branch>.json, the other calls as stack-land's stub;
			-- a `pr edit` (done's retarget) logs the environment it ran in
			fs.writeFile(
				`{h.bin}/gh`,
				table.concat({
					"#!/bin/sh",
					'echo "realgh $*" >> "$FAKE_DIR/log"',
					'case "$1 $2" in',
					`  "pr view") case "$*" in *statusCheckRollup*) b=$(printf "%s" "$3" | tr / _); [ -f "{h.bin}/prview-$b.json" ] && cat "{h.bin}/prview-$b.json" && exit 0; exit 1 ;; esac; echo main; exit 0 ;;`,
					'  "pr list") case "$*" in *number*) echo 1 ;; esac; exit 0 ;;',
					'  "pr create") echo https://github.com/x/y/pull/1; exit 0 ;;',
					'  "pr edit") echo "env GH_TOKEN=$GH_TOKEN ZN_DISPATCH=${ZN_DISPATCH:-} ZN_HEADLESS=${ZN_HEADLESS:-}" >> "$FAKE_DIR/log"; exit 0 ;;',
					"esac",
					"exit 0",
					"",
				}, "\n")
			)
			process.exec("chmod", { "+x", `{h.bin}/gh` })
			NO_CICD = `{h.f.base}/no-cicd.toml`
			HAS_CICD = `{h.f.base}/cicd.toml`
			fs.writeFile(HAS_CICD, "# fake\n")
			fs.writeDir(`{h.f.base}/tmp`) -- the clean clone is made under TMPDIR, which a check run keeps inside .cache
			for rid in rafts do
				must(zn({ "ready", rid }), `ready {rid}`)
				if rid ~= "R0099" then
					worktrees[rid] = must(zn({ "worktree", rid }), `worktree {rid}`)
				end
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
			local before = mainHead()
			local r = dispatchOut("R0020")
			t.expect(r.code).toBe(4)
			t.expect(has(r.stdout, "waiting to land R0020")).toBe(true)
			t.expect(has(r.stdout, "ci-pending")).toBe(true)
			t.expect(mainHead()).toBe(before)
		end
	)

	it(
		"AC11: a failure the worker can fix runs it again twice with the checks named in its prompt, then the raft blocks under red-gate with a note that recommends retry",
		function()
			-- the pull request's head is not the layer tip: a fixable problem (publish the layer), which this worker does not fix
			pr("R0020/1/c0020", GREEN, NOTIP)
			local zruns = count(fakecli.log(h), "claude step=z-run")
			local told = count(
				fakecli.log(h),
				"You are running again because the dispatcher's checks before landing R0020 failed"
			)
			local r = dispatchOut("R0020")
			t.expect(r.code).toBe(3)
			t.expect(count(fakecli.log(h), "claude step=z-run")).toBe(zruns + 2)
			t.expect(
				count(
					fakecli.log(h),
					"You are running again because the dispatcher's checks before landing R0020 failed"
				)
			).toBe(told + 2)
			t.expect(has(fakecli.log(h), "pr-head-moved (redo)")).toBe(true)
			t.expect(has(r.stdout, "R0020 is blocked (red-gate)")).toBe(true)
			local note = onOrigin("pickman/.tracker/rafts/R0020/escalation.md")
			t.expect(has(note, "pr-head-moved")).toBe(true)
			t.expect(has(note, "after 2 repeat(s)")).toBe(true)
			t.expect(has(note, "- retry: run the worker again for another round of fixes (recommended)"))
				.toBe(true)
			t.expect(has(note, "amend-design: the design has to change to make the check pass (recommended)"))
				.toBe(false)
		end
	)

	it(
		"AC10: a finished raft whose top layer is green is landed by the dispatcher with its own environment: one bind, the raft done, exit 0",
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
			-- the landing ran with the dispatcher's environment: the user's credential, no ZN_DISPATCH, no ZN_HEADLESS
			t.expect(has(fakecli.log(h), "env GH_TOKEN=the-users-token ZN_DISPATCH= ZN_HEADLESS=")).toBe(true)
			t.expect(fakecli.state(h, "R0010").outcome).toBe("ok")
			-- a second run finds it done
			local again = dispatchOut("R0010")
			t.expect(again.code).toBe(0)
			t.expect(has(again.stdout, "R0010 is done")).toBe(true)
		end
	)

	it(
		"AC11: a failed check is a fixable problem too: the worker runs again twice, then the raft blocks, the dispatcher files the note and runs block, and exits 3",
		function()
			layer("R0030", "c0030", "gamma", true)
			seal.trace(worktrees.R0030, "R0030")
			pr("R0030/1/c0030", FAILED)
			local zruns = count(fakecli.log(h), "claude step=z-run")
			local r = dispatchOut("R0030")
			t.expect(r.code).toBe(3)
			t.expect(has(r.stdout, "R0030 is blocked (red-gate)")).toBe(true)
			-- the run step, then two reruns of the same failure
			t.expect(count(fakecli.log(h), "claude step=z-run")).toBe(zruns + 3)
			local note = onOrigin("pickman/.tracker/rafts/R0030/escalation.md")
			local parsed, why = escalation.parse(note)
			t.expect(why).toBe(nil)
			t.expect(parsed ~= nil).toBe(true)
			t.expect(escalation.check(parsed :: any)).toBe(nil)
			t.expect(has(note, "ci-failed")).toBe(true)
			t.expect(has(note, "Reason: red-gate")).toBe(true)
			t.expect(has(note, "- retry: run the worker again for another round of fixes (recommended)"))
				.toBe(true)
		end
	)

	it(
		"AC12: a requested block waits at the gate while the green layers below still have CI running, then lands them first and files the block with the Layer's open findings and the worker's committed note",
		function()
			layer("R0040", "c0040", "delta", true)
			-- Phase 5 for the layers that are green, before the worker went on to c0050: the trace of the landing of c0040
			-- alone, committed on its layer (a landing has its own trace and final review)
			seal.trace(worktrees.R0040, "R0040", "c0040", 1)
			git(worktrees.R0040, { "push", "-q" })
			layer("R0040", "c0050", "epsilon", false)
			-- the layer's review left an open finding in the issue's document (after the layer was finished: the document is
			-- part of the approved contract until then)
			local wt = worktrees.R0040
			local doc = `{wt}/pickman/.tracker/issues/active/c0050/c0050.md`
			fs.writeFile(
				doc,
				fs.readFile(doc)
					.. "\n## Open to the human\n- F1: the reader is missing. Answer: none. Decision: take the library or write one\n"
			)
			git(wt, { "add", "-A" })
			git(wt, { "commit", "-qm", "c0050: the open finding" })
			git(wt, { "push", "-q" })
			pr("R0040/1/c0040", PENDING)
			-- the fake worker blocks the raft at layer c0050 the way z-run is told to: the note, committed on its layer
			-- (a habit of zz-execute), then ./zn block
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
					"git add -f pickman/.tracker/rafts/active/R0040/escalation.md",
					"git -c user.name=worker -c user.email=worker@example.invalid commit -q -m 'c0050: the note'",
					"git push -q origin R0040/2/c0050",
					"./zn block R0040 review-exhausted --layer c0050",
					"",
				}, "\n")
			)
			local before = mainHead()
			local waiting = dispatchOut("R0040")
			t.expect(waiting.code).toBe(4)
			t.expect(has(waiting.stdout, "waiting to land the layers below c0050 before it is filed"))
				.toBe(true)
			t.expect(has(waiting.stdout, "ci-pending")).toBe(true)
			t.expect(mainHead()).toBe(before)
			-- the request is kept: CI turns green and the next run lands the prefix, then files the block
			t.expect(fs.isFile(`{h.f.main}/.cache/dispatch/R0040/block-request`)).toBe(true)
			pr("R0040/1/c0040", GREEN)
			local r = dispatchOut("R0040")
			t.expect(has(r.stdout, "next: land R0040 through c0040")).toBe(true)
			t.expect(has(mainSubjects(8), "R0040: bind c0040")).toBe(true)
			t.expect(r.code).toBe(3)
			t.expect(has(r.stdout, "R0040 is blocked (review-exhausted)")).toBe(true)
			-- the first layer is in done/, the second waits, blocked, with the worker's own note and the Layer's open id
			onOrigin("pickman/.tracker/issues/done/c0040/c0040.md")
			local note = onOrigin("pickman/.tracker/rafts/R0040/escalation.md")
			t.expect(has(note, "Should c0050 wait for the library?")).toBe(true)
			t.expect(has(note, "Open: F1")).toBe(true)
			t.expect(has(note, "Layer: c0050")).toBe(true)
			fakecli.mode(h, "claude", "ok")
		end
	)

	it(
		"AC12: a worker's uncommitted note is put back on the Layer's tip when the block is filed after the green layers below landed",
		function()
			local wt = worktrees.R0130
			layer("R0130", "c0140", "nu", true)
			seal.trace(wt, "R0130", "c0140", 1)
			git(wt, { "push", "-q" })
			layer("R0130", "c0150", "xi", false)
			pr("R0130/1/c0140", GREEN)
			fakecli.mode(h, "claude", "script")
			fs.writeFile(
				`{h.fakes}/script.sh`,
				table.concat({
					"mkdir -p pickman/.tracker/rafts/active/R0130",
					"cat > pickman/.tracker/rafts/active/R0130/escalation.md <<'NOTE'",
					"## Question",
					"Is the pipe slower than the file?",
					"",
					"## What was tried",
					"Both, twice.",
					"",
					"## Open findings or error",
					"None open.",
					"",
					"## Options",
					"- retry: measure again (recommended)",
					"- approve: take the file",
					"NOTE",
					"./zn block R0130 design-gap --layer c0150",
					"",
				}, "\n")
			)
			local r = dispatchOut("R0130")
			fakecli.mode(h, "claude", "ok")
			t.expect(has(r.stdout, "next: land R0130 through c0140")).toBe(true)
			t.expect(landed("R0130")).toBe(true)
			t.expect(r.code).toBe(3)
			t.expect(
				has(
					onOrigin("pickman/.tracker/rafts/R0130/escalation.md"),
					"Is the pipe slower than the file?"
				)
			)
				.toBe(true)
		end
	)

	it(
		"AC16: after the layers finish, main gains a tracker commit and a non-conflicting code commit, and the dispatcher still lands one bind",
		function()
			layer("R0050", "c0060", "zeta", true)
			seal.trace(worktrees.R0050, "R0050")
			pr("R0050/1/c0060", GREEN)
			fakecli.advanceMain(
				h,
				{ ["pickman/.tracker/issues/c9001/c9001.md"] = stub("c9001") },
				nil,
				"tracker: another session claims c9001"
			)
			fakecli.advanceMain(
				h,
				{ ["z-nile/notes/other.md"] = "another raft landed\n" },
				nil,
				"another raft: code"
			)
			local r = dispatchOut("R0050")
			t.expect(r.code).toBe(0)
			t.expect(landed("R0050")).toBe(true)
			local log = git(h.f.origin, { "log", "--format=%s", "main" })
			t.expect(has(log, "tracker: another session claims c9001")).toBe(true)
			t.expect(has(log, "another raft: code")).toBe(true)
			-- one bind: the layer's finish commit is the bind's second parent, and main kept both commits it gained
			t.expect(
				count(git(h.f.origin, { "log", "--first-parent", "--format=%s", "main" }), "R0050: bind")
			)
				.toBe(1)
		end
	)

	it(
		"AC17: a layer that rewrites landcheck.luau so that it finds no problem does not judge its own landing: the base's engine still files the failed check",
		function()
			-- the stack's own landcheck would find nothing wrong
			local own = fs.readFile(`{worktrees.R0060}/z-nile/engine/landcheck.luau`)
			layer("R0060", "c0070", "eta", true, nil, nil, {
				["z-nile/engine/landcheck.luau"] = (string.gsub(
					own,
					"return landcheck\n$",
					"function landcheck.problems()\n\treturn {}\nend\nreturn landcheck\n"
				)),
			})
			seal.trace(worktrees.R0060, "R0060")
			pr("R0060/1/c0070", FAILED)
			local r = dispatchOut("R0060")
			t.expect(r.code).toBe(3)
			t.expect(has(r.stdout, "R0060 is blocked (red-gate)")).toBe(true)
			t.expect(landed("R0060")).toBe(false)
			t.expect(has(onOrigin("pickman/.tracker/rafts/R0060/escalation.md"), "ci-failed")).toBe(true)
		end
	)

	it(
		"AC17: the bind is made by the base's engine: a layer that changes how its own raft's bind is worded does not get its wording",
		function()
			local own = fs.readFile(`{worktrees.R0140}/z-nile/engine/stack.luau`)
			local signature =
				"function stack.bindMessage(raftId: string, issueIds: { string }, verdict: string, tracePath: string?): string\n"
			local at, to = string.find(own, signature, 1, true)
			t.expect(at ~= nil).toBe(true)
			local changed = string.sub(own, 1, to :: number)
				.. '\tif raftId == "R0140" then\n\t\treturn "R0140: OWN ENGINE bind"\n\tend\n'
				.. string.sub(own, (to :: number) + 1)
			layer("R0140", "c0160", "pi", true, nil, nil, { ["z-nile/engine/stack.luau"] = changed })
			-- the stack's own copy does word its bind that way
			t.expect(has(fs.readFile(`{worktrees.R0140}/z-nile/engine/stack.luau`), "OWN ENGINE")).toBe(true)
			seal.trace(worktrees.R0140, "R0140")
			pr("R0140/1/c0160", GREEN)
			local r = dispatchOut("R0140")
			t.expect(r.code).toBe(0)
			t.expect(landed("R0140")).toBe(true)
			t.expect(has(git(h.f.origin, { "log", "--format=%s", "main" }), "OWN ENGINE")).toBe(false)
		end
	)

	it(
		"AC17: a stack that changes the gate's own driver is a wait for a person (self-gating), whatever its checks say",
		function()
			local driver = fs.readFile(`{worktrees.R0070}/z-nile/check.sh`)
			layer("R0070", "c0080", "theta", true, nil, nil, {
				["z-nile/check.sh"] = driver .. "# a stack that edits its own judge\n",
			})
			seal.trace(worktrees.R0070, "R0070")
			pr("R0070/1/c0080", GREEN)
			local before = mainHead()
			local r = dispatchOut("R0070")
			t.expect(r.code).toBe(4)
			t.expect(has(r.stdout, "self-gating")).toBe(true)
			t.expect(has(r.stdout, "z-nile/check.sh")).toBe(true)
			t.expect(mainHead()).toBe(before)
		end
	)

	it(
		"AC18: a game stack waits without cicd.toml and while a cicd lease is held, and lands after the clean-clone full gate and the cicd run pass on the bind's tree",
		function()
			layer("R0080", "c0090", "iota", true, "pickman/src")
			seal.trace(worktrees.R0080, "R0080")
			pr("R0080/1/c0090", GREEN)
			local before = mainHead()
			local none = dispatchOut("R0080", { ZN_CICD_TOML = NO_CICD })
			t.expect(none.code).toBe(4)
			t.expect(has(none.stdout, "cicd-missing")).toBe(true)
			t.expect(mainHead()).toBe(before)
			local lease = dispatchOut("R0080", {
				ZN_CICD_TOML = HAS_CICD,
				TMPDIR = `{h.f.base}/tmp`,
				ZN_LANDGATE_FULL = "true",
				ZN_LANDGATE_CICD = "echo cicd lease held by someone else >&2; exit 3",
			})
			t.expect(lease.code).toBe(4)
			t.expect(has(lease.stdout, "waiting to land R0080")).toBe(true)
			t.expect(mainHead()).toBe(before)
			-- the full gate runs in a clean clone outside this checkout, on the tree with the stack merged in
			local seen = `{h.f.base}/gate-seen.txt`
			local ok = dispatchOut("R0080", {
				ZN_CICD_TOML = HAS_CICD,
				TMPDIR = `{h.f.base}/tmp`,
				ZN_LANDGATE_FULL = `pwd > "{seen}" && test -f pickman/src/iota.md && test -d .git`,
				ZN_LANDGATE_CICD = "true",
			})
			t.expect(ok.code).toBe(0)
			t.expect(landed("R0080")).toBe(true)
			local where = (string.gsub(fs.readFile(seen), "%s+$", ""))
			t.expect(string.sub(where, 1, #h.f.main + 1) == `{h.f.main}/`).toBe(false)
			t.expect(where ~= h.f.main).toBe(true)
		end
	)

	it(
		"AC18: a red clean-clone full gate is a failure the worker can fix: it runs again twice and the raft then blocks under red-gate, landing nothing",
		function()
			layer("R0090", "c0100", "kappa", true, "pickman/src")
			seal.trace(worktrees.R0090, "R0090")
			pr("R0090/1/c0100", GREEN)
			local before = mainHead()
			local zruns = count(fakecli.log(h), "claude step=z-run")
			local r = dispatchOut("R0090", {
				ZN_CICD_TOML = HAS_CICD,
				TMPDIR = `{h.f.base}/tmp`,
				ZN_LANDGATE_FULL = "echo a spec failed >&2; exit 1",
				ZN_LANDGATE_CICD = "true",
			})
			t.expect(r.code).toBe(3)
			t.expect(has(r.stdout, "R0090 is blocked (red-gate)")).toBe(true)
			t.expect(count(fakecli.log(h), "claude step=z-run")).toBe(zruns + 3)
			t.expect(has(onOrigin("pickman/.tracker/rafts/R0090/escalation.md"), "full-gate-red")).toBe(true)
			t.expect(landed("R0090")).toBe(false)
			t.expect(git(h.f.main, { "ls-remote", "origin", "refs/heads/main" }) ~= before).toBe(true) -- the block is tracker state
		end
	)

	it("AC11: a land-check that prints garbage is a wait (exit 4) and nothing is landed", function()
		layer("R0110", "c0120", "lambda", true)
		seal.trace(worktrees.R0110, "R0110")
		pr("R0110/1/c0120", GREEN)
		-- the base's zn, replaced for this case by one whose land-check answers garbage
		local zpath = `{h.f.main}/zn`
		fs.writeFile(`{h.f.main}/zn.real`, fs.readFile(zpath))
		process.exec("chmod", { "+x", `{h.f.main}/zn.real` })
		fs.writeFile(
			zpath,
			'#!/bin/bash\nif [[ "${3:-}" == land-check ]]; then echo "this is not json"; exit 0; fi\nexec "$(dirname "$0")/zn.real" "$@"\n'
		)
		local before = mainHead()
		local r = dispatchOut("R0110")
		fs.writeFile(zpath, fs.readFile(`{h.f.main}/zn.real`))
		fs.removeFile(`{h.f.main}/zn.real`)
		t.expect(r.code).toBe(4)
		t.expect(has(r.stdout, "land-check gave no answer")).toBe(true)
		t.expect(mainHead()).toBe(before)
	end)

	it(
		"AC11: a worker that fixes one failure per run is not capped by the count: it lands after more reruns than merge_retries",
		function()
			layer("R0120", "c0130", "mu", true)
			seal.trace(worktrees.R0120, "R0120")
			local branch = "R0120/1/c0130"
			local tip = git(h.f.main, { "rev-parse", `origin/{branch}` })
			local file = `{h.bin}/prview-R0120_1_c0130.json`
			local function state(n: number, checks: string, head: string)
				fs.writeFile(
					`{h.fakes}/seq-{n}.json`,
					`\{"number":1,"state":"OPEN","isDraft":false,"headRefOid":"{head}","mergeable":"MERGEABLE","statusCheckRollup":{checks}}`
				)
			end
			-- after run k the pull request shows: 1 head moved, 2 failed, 3 head moved, 4 green
			state(1, GREEN, NOTIP)
			state(2, FAILED, tip)
			state(3, GREEN, NOTIP)
			state(4, GREEN, tip)
			pr(branch, FAILED)
			fakecli.mode(h, "claude", "script")
			fs.writeFile(
				`{h.fakes}/script.sh`,
				table.concat({
					`n=$(cat "$FAKE_DIR/runs" 2>/dev/null || echo 0); n=$((n+1)); echo $n > "$FAKE_DIR/runs"`,
					`[ -f "$FAKE_DIR/seq-$n.json" ] && cp "$FAKE_DIR/seq-$n.json" "{file}"`,
					"",
				}, "\n")
			)
			local told = count(
				fakecli.log(h),
				"You are running again because the dispatcher's checks before landing R0120 failed"
			)
			local r = dispatchOut("R0120")
			t.expect(r.code).toBe(0)
			t.expect(landed("R0120")).toBe(true)
			-- three reruns, one more than merge_retries = 2: each rerun was for a different failure than the one before
			t.expect(
				count(
					fakecli.log(h),
					"You are running again because the dispatcher's checks before landing R0120 failed"
				)
			).toBe(told + 3)
			fakecli.mode(h, "claude", "ok")
		end
	)

	it(
		"AC19: an old single-branch raft with an open pull request keeps its human's merge end to end: the chain stops at it without running the worker",
		function()
			fakecli.mode(h, "claude", "ok")
			fs.writeFile(
				`{h.bin}/prview-R0099-old.json`,
				`\{"number":9,"state":"OPEN","isDraft":false,"headRefOid":"{NOTIP}","mergeable":"MERGEABLE","statusCheckRollup":{GREEN}}`
			)
			local zruns = count(fakecli.log(h), "claude step=z-run")
			local before = mainHead()
			local r = dispatchOut("R0099")
			t.expect(r.code).toBe(4)
			t.expect(has(r.stdout, "human's to merge")).toBe(true)
			t.expect(count(fakecli.log(h), "claude step=z-run")).toBe(zruns)
			t.expect(mainHead()).toBe(before)
		end
	)

	it(
		"AC14: after the dispatcher's own bind the guard's mark moves to it, so main is vetted; tracker commits other sessions published after the bind do not trip it, and a foreign commit still does",
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
			local scratch = h.f.other
			local function merge(name: string, file: string): string
				git(scratch, { "pull", "-q", "origin", "main" })
				git(scratch, { "checkout", "-q", "-B", name, "origin/main" })
				write(scratch, file, "x\n")
				git(scratch, { "add", "-A" })
				git(scratch, { "commit", "-qm", `{name} side` })
				local side = git(scratch, { "rev-parse", "HEAD" })
				git(scratch, { "checkout", "-q", "main" })
				git(scratch, { "reset", "-q", "--hard", "origin/main" })
				git(scratch, { "merge", "--no-ff", "-m", `{name} bind`, side })
				git(scratch, { "push", "-q", "origin", "HEAD:main" })
				return side
			end
			local function push(file: string, message: string, content: string?)
				git(scratch, { "pull", "-q", "origin", "main" })
				write(scratch, file, content or "y\n")
				git(scratch, { "add", "-A" })
				git(scratch, { "commit", "-qm", message })
				git(scratch, { "push", "-q", "origin", "HEAD:main" })
			end
			-- a new landing, in this process: the mark is main before the bind
			git(h.f.main, { "fetch", "-q", "origin" })
			t.expect(dispatcher.vetMain(ctx)).toBe(nil)
			local side = merge("first", "z-nile/notes/first.md")
			-- a tip that is nowhere on main's first-parent line is not the bind: it trips, and the mark stays
			local tripped = dispatcher.afterLand(ctx, "1111111111111111111111111111111111111111")
			t.expect(tripped ~= nil).toBe(true)
			t.expect(has(tostring(tripped), "first-parent line")).toBe(true)
			local vet = dispatcher.vetMain(ctx)
			t.expect(vet ~= nil).toBe(true)
			t.expect(has(tostring(vet), "arrived during this run")).toBe(true)
			-- the commit announced as the dispatcher's own bind, with a tracker commit another session published after it
			push(
				"pickman/.tracker/issues/c9002/c9002.md",
				"tracker: another session publishes after the bind",
				stub("c9002")
			)
			t.expect(dispatcher.afterLand(ctx, side)).toBe(nil)
			t.expect(dispatcher.vetMain(ctx)).toBe(nil)
			-- a code commit after the bind is not the dispatcher's, and not tracker state: it trips, with the bind found
			local second = merge("second", "z-nile/notes/second.md")
			push("z-nile/notes/foreign.md", "foreign code after the bind")
			local late = dispatcher.afterLand(ctx, second)
			t.expect(late ~= nil).toBe(true)
			t.expect(has(tostring(late), "beside the bind")).toBe(true)
		end
	)
end)
