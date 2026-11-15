--!strict
-- c0267 AC7, AC8: `./zn dispatch` reads a backlog raft's approvals from origin/main (workread.unapproved) and stops
-- before z-ready while one of its issues has none that matches: exit 3, nothing readied, no CLI started. The stop's
-- printed lines, run as printed from the main checkout, get the raft through and leave no worktree or branch behind;
-- a contract changed after the approval stops it again; an unreadable approval is removed by its own line; a two-issue
-- raft is named in its layer order; a raft ready refuses for something else still goes to z-ready.
--
-- The printed line's `./zn approve <id> && ./zn approve <id> --publish` is run as `approve-as <id> <file>`: approval.md
-- as `./zn approve` writes it for the contract on origin/main (contract.build and contract.render, the parts and row
-- approval.append writes), committed and pushed to origin/main, which is what those two commands publish
-- (tests/tooling/approve.spec.luau and approve-publish.spec.luau pin that they do). The rest of the line runs as printed. This keeps the case off approve's own prompts, which f0339 changes (design review 001 F1).
--
-- Fixture under .cache/c0267-approval-stop. Every command here runs with the ZN_ variables cleared and z-nile/bin
-- off PATH, as a person's terminal has them. Inside a dispatched step the runner's git fence still resolves the
-- step's wrapper as the real git (as for tests/tooling/approve.spec.luau on main): check.sh runs this file through
-- its `nostep` function until d0298's runner drops the step's environment for every spec.
local contract = require("@znile/engine/contract")
local fakecli = require("@tests/lib/fakecli")
local fixture = require("@tests/lib/fixture")
local fs = require("@lune/fs")
local process = require("@lune/process")
local raftplan = require("@znile/engine/raftplan")
local t = require("@tests/lib/t")

local ROOT = "z-nile/.tracker"

local HEAD =
	'#!/usr/bin/env bash\nsource "$(git -C "$(dirname "${BASH_SOURCE[0]}")" rev-parse --show-toplevel)/scripts/lib/ac.sh"\n'
local SPEC = "--!strict\n"
	.. 'local t = require("@tests/lib/t")\n'
	.. 'return t.spec("holds", function(it)\n'
	.. '\tit("holds", function()\n'
	.. "\t\tt.expect(true).toBe(true)\n"
	.. "\tend)\n"
	.. "end)\n"

local function issueDir(id: string): string
	return `{ROOT}/issues/{id}`
end

local function checkOf(id: string): string
	return HEAD .. 'check "AC1: holds" true\n' .. `# {issueDir(id)}/check.sh\n` .. "finish\n"
end

local function doc(id: string, raft: string, design: string, deps: string?, state: string?): string
	return `---\nid: {id}\ntype: chore\ntitle: Hold {id}\nslug: hold-{id}\nraft: {raft}\ndepends_on: [{deps or ""}]\nemergent: false\ndesign: {state or "ready"}\ncreated: 2026-11-15\nstatus: prepared-quiet-copper-falcon\n---\n\n# {id}\n\n## Problem\nThe chain readies a raft no person approved.\n\n## Solution\nStop first.\n\n## Design\n{design}\n\n## Acceptance criteria\nIt stops.\n\n## Test plan\nSpecs.\n`
end

local function raftDoc(id: string, issues: string, extra: string?, order: string?): string
	return `---\nid: {id}\ntype: chore\ntitle: Hold {id}\nslug: hold-{id}\n{extra or "single: true\n"}issues: [{issues}]\ndesign: ready\ncreated: 2026-11-15\nstatus: prepared-quiet-copper-falcon\n---\n\n# {id}\n\n## Theme\nThe approval comes first.\n{order or ""}`
end

local function has(text: string, needle: string): boolean
	return string.find(text, needle, 1, true) ~= nil
end

-- every ZN_ variable of a dispatched session cleared
local function cleared(): { [string]: string }
	local out: { [string]: string } = {}
	for k in process.env do
		if string.sub(k, 1, 3) == "ZN_" then
			out[k] = ""
		end
	end
	return out
end

-- PATH without the z-nile wrapper a dispatched step puts first
local function plainPath(): string
	local kept: { string } = {}
	for dir in string.gmatch(process.env.PATH or "", "[^:]+") do
		if not string.find(dir, "/z-nile/bin", 1, true) then
			table.insert(kept, dir)
		end
	end
	return table.concat(kept, ":")
end

-- approval.md as `./zn approve` writes it for this contract (approval.append's row over approval.collect's parts)
local function approvalOf(id: string, text: string): string
	local parts = contract.build(text, checkOf(id), { ["hold.spec.luau"] = SPEC }) :: contract.Parts
	return contract.render({
		{
			when = "2026-11-15T20:00:00Z",
			who = contract.who("A Person"),
			hash = contract.hash(parts),
			parts = contract.partHashes(parts),
		},
	})
end

return t.spec("c0267: ./zn dispatch waits for a person's approval before z-ready", function(it)
	local h: fakecli.Harness
	local helper = ""
	local function zn(args: { string }): fixture.Result
		local env = cleared()
		env.PATH = `{h.bin}:{plainPath()}`
		return fakecli.zn(h, args, env)
	end
	local function onMain(path: string): boolean
		return fixture.exec(h.f.origin, "git", { "cat-file", "-e", `main:{path}` }).ok
	end
	-- the stop's command line for `id`, from what `./zn dispatch` printed
	local function lineFor(out: string, id: string): string?
		local start = `w="$(./zn worktree approve-{id}-`
		for line in string.gmatch(out, "[^\n]+") do
			if string.sub(line, 1, #start) == start then
				return line
			end
		end
		return nil
	end
	-- runs the printed line from the fixture's main checkout, as a person would, approve-as standing in for approve:
	-- it puts `text`'s approval in place in the worktree the line made, commits it and pushes it to origin/main
	local function runLine(line: string, id: string, text: string): fixture.Result
		local approve = `./zn approve {id} && ./zn approve {id} --publish`
		t.expect(has(line, approve)).toBe(true)
		local file = `{h.f.base}/approval-{id}.md`
		fs.writeFile(file, approvalOf(id, text))
		local a, b = string.find(line, approve, 1, true)
		local run = string.sub(line, 1, (a :: number) - 1)
			.. `bash {helper} {id} {file}`
			.. string.sub(line, (b :: number) + 1)
		local env = cleared()
		env.PATH = plainPath()
		env.HOME = process.env.HOME or ""
		return fixture.exec(h.f.main, "bash", { "-c", run }, { env = env })
	end
	local function leftovers(): string
		return fixture.git(h.f.main, { "worktree", "list" })
			.. fixture.git(h.f.main, { "branch", "--list", "approve-*" })
	end

	it("sets up a one-issue raft and a two-issue raft, designed and not approved", function()
		local two = "## Order & dependencies\n1. c0003\n2. c0002\n"
		-- the two-issue raft's grouping record and its coherence review, over the members' design files as they will
		-- be on origin/main
		local map: { [string]: string } = {}
		for _, id in { "c0002", "c0003" } do
			map[id] = raftplan.recordHash(id, {
				[`{id}.md`] = doc(id, "R0002", "Stop before ready."),
				["check.sh"] = checkOf(id),
				["acceptance/hold.spec.luau"] = SPEC,
			})
		end
		local grouped = raftplan.renderGrouped(map)
		local seed: { [string]: string } = {
			[`{ROOT}/rafts/R0001/R0001.md`] = raftDoc("R0001", "c0001"),
			[`{ROOT}/rafts/R0001/check.sh`] = HEAD .. 'check "RC0: holds" true\nfinish\n',
			[`{ROOT}/rafts/R0002/R0002.md`] = raftDoc("R0002", "c0002, c0003", `grouped: {grouped}\n`, two),
			[`{ROOT}/rafts/R0002/check.sh`] = HEAD .. 'check "RC0: holds" true\nfinish\n',
			[`{ROOT}/rafts/R0002/design-review-001.md`] = `# Review 001: R0002 (raft mode)\n\nGrouped: {grouped}\n\nVerdict: approve\n`,
		}
		local ready: { [string]: string } = {}
		local rafts: { [string]: string } = { c0001 = "R0001", c0002 = "R0002", c0003 = "R0002" }
		for id, raft in rafts do
			-- seeded as drafts, so the harness stamps no approval; the designs are ready only on origin/main
			seed[`{issueDir(id)}/{id}.md`] = doc(id, raft, "Stop before ready.", nil, "draft")
			seed[`{issueDir(id)}/check.sh`] = checkOf(id)
			seed[`{issueDir(id)}/acceptance/hold.spec.luau`] = SPEC
			ready[`{issueDir(id)}/{id}.md`] = doc(id, raft, "Stop before ready.")
		end
		h = fakecli.new("c0267-approval-stop", seed)
		fakecli.advanceMain(h, ready, nil, "designs ready")
		helper = `{h.f.base}/approve-as.sh`
		fs.writeFile(
			helper,
			'#!/usr/bin/env bash\nset -euo pipefail\ncp "$2" "z-nile/.tracker/issues/$1/approval.md"\ngit add -- "z-nile/.tracker/issues/$1/approval.md"\ngit commit -qm "tracker: approve $1"\ngit push -q origin HEAD:main\n'
		)
		t.expect(onMain(`{ROOT}/rafts/R0001/R0001.md`)).toBe(true)
		t.expect(onMain(`{issueDir("c0001")}/approval.md`)).toBe(false)
	end)

	it("AC7: the chain stops for the person, exit 3: nothing is readied and no CLI starts", function()
		local dry = zn({ "dispatch", "R0001", "--dry-run" })
		t.expect(dry.ok).toBe(true)
		t.expect(has(dry.stdout, "stop: waiting for the person (not a failure)")).toBe(true)
		t.expect(has(dry.stdout, "\nc0001: no approval.\n")).toBe(true)
		t.expect(has(dry.stdout, "next: z-ready")).toBe(false)
		local run = zn({ "dispatch", "R0001" })
		t.expect(run.code).toBe(3)
		t.expect(has(run.stdout, "stop: waiting for the person (not a failure)")).toBe(true)
		t.expect(lineFor(run.stdout, "c0001") ~= nil).toBe(true)
		t.expect(has(run.stdout, "\nThen run ./zn dispatch R0001 again.")).toBe(true)
		-- nothing readied: the raft is still in the backlog on origin/main, and no step ran
		t.expect(onMain(`{ROOT}/rafts/R0001/R0001.md`)).toBe(true)
		t.expect(onMain(`{ROOT}/rafts/active/R0001/R0001.md`)).toBe(false)
		t.expect(has(fakecli.log(h), "claude")).toBe(false)
		-- a second run says the same: the stop is no outcome a later run has to clear
		local again = zn({ "dispatch", "R0001" })
		t.expect(again.code).toBe(3)
		t.expect(has(again.stdout, "waiting for the person")).toBe(true)
	end)

	it(
		"AC7: the printed line, run as printed from the main checkout, gets the raft to z-ready and leaves nothing",
		function()
			local line = lineFor(zn({ "dispatch", "R0001", "--dry-run" }).stdout, "c0001") :: string
			local ran = runLine(line, "c0001", doc("c0001", "R0001", "Stop before ready."))
			t.expect(ran.ok).toBe(true)
			t.expect(onMain(`{issueDir("c0001")}/approval.md`)).toBe(true)
			t.expect(has(leftovers(), "approve-c0001-")).toBe(false)
			local dry = zn({ "dispatch", "R0001", "--dry-run" })
			t.expect(has(dry.stdout, "next: z-ready R0001")).toBe(true)
			t.expect(has(dry.stdout, "waiting for the person")).toBe(false)
		end
	)

	it("AC8: a contract changed on origin/main after the approval stops it again, naming the part", function()
		fakecli.advanceMain(
			h,
			{ [`{issueDir("c0001")}/c0001.md`] = doc("c0001", "R0001", "Stop before ready, and say why.") },
			nil,
			"redesign"
		)
		local dry = zn({ "dispatch", "R0001", "--dry-run" })
		t.expect(has(dry.stdout, "stop: waiting for the person (not a failure)")).toBe(true)
		t.expect(has(dry.stdout, "\nc0001: its contract changed since approval (design).\n")).toBe(true)
	end)

	it(
		"AC8: an unreadable approval is named with why, and its own line removes it and gets through",
		function()
			fakecli.advanceMain(
				h,
				{ [`{issueDir("c0001")}/approval.md`] = "not an approval\n" },
				nil,
				"garbled"
			)
			local dry = zn({ "dispatch", "R0001", "--dry-run" })
			t.expect(has(dry.stdout, "\nc0001: its approval.md does not parse (")).toBe(true)
			local line = lineFor(dry.stdout, "c0001") :: string
			t.expect(has(line, `git rm -q {issueDir("c0001")}/approval.md && `)).toBe(true)
			local ran = runLine(line, "c0001", doc("c0001", "R0001", "Stop before ready, and say why."))
			t.expect(ran.ok).toBe(true)
			t.expect(has(leftovers(), "approve-c0001-")).toBe(false)
			t.expect(has(zn({ "dispatch", "R0001", "--dry-run" }).stdout, "next: z-ready R0001")).toBe(true)
		end
	)

	it("AC8: a two-issue raft names its issues in its layer order, not by id", function()
		local dry = zn({ "dispatch", "R0002", "--dry-run" })
		t.expect(has(dry.stdout, "stop: waiting for the person (not a failure)")).toBe(true)
		local a3 = string.find(dry.stdout, "\nc0003: no approval.", 1, true)
		local a2 = string.find(dry.stdout, "\nc0002: no approval.", 1, true)
		t.expect(a3 ~= nil and a2 ~= nil and (a3 :: number) < (a2 :: number)).toBe(true)
		local l3 = string.find(dry.stdout, 'w="$(./zn worktree approve-c0003-', 1, true)
		local l2 = string.find(dry.stdout, 'w="$(./zn worktree approve-c0002-', 1, true)
		t.expect(l3 ~= nil and l2 ~= nil and (l3 :: number) < (l2 :: number)).toBe(true)
	end)

	it(
		"AC8: a raft ready refuses for something else first goes to z-ready as before, not to the wait",
		function()
			fakecli.advanceMain(h, {
				-- not approved as it stands, and a dependency that is not done
				[`{issueDir("c0001")}/c0001.md`] = doc(
					"c0001",
					"R0001",
					"Stop before ready, and once more.",
					"c0099"
				),
			}, nil, "a dependency")
			local dry = zn({ "dispatch", "R0001", "--dry-run" })
			t.expect(has(dry.stdout, "next: z-ready R0001")).toBe(true)
			t.expect(has(dry.stdout, "waiting for the person")).toBe(false)
		end
	)
end)
