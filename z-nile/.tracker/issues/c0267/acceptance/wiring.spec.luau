--!strict
-- c0267 AC7, AC8: `./zn dispatch` reads a backlog raft's approvals from origin/main (workread.unapproved) and stops
-- before z-ready while one of its issues has none that matches: exit 3, nothing readied, no CLI started. Doing only
-- what the stop says (a worktree on origin/main, ./zn approve, ./zn approve --publish, in a terminal) gets it through;
-- a contract changed after the approval stops it again; a raft ready refuses for something else still goes to z-ready.
-- Fixture under .cache/c0267-approval-stop. `./zn approve` runs through `script`, which gives it a terminal, and
-- every `./zn` here runs with the ZN_ variables cleared and z-nile/bin off PATH, as a person's terminal has them.
-- Inside a dispatched step the runner's git fence still resolves the step's wrapper as the real git (as for
-- tests/tooling/approve.spec.luau on main): check.sh runs this file through acceptance/nostep.sh until d0298's
-- runner drops the step's environment for every spec.
local fakecli = require("@tests/lib/fakecli")
local fixture = require("@tests/lib/fixture")
local process = require("@lune/process")
local t = require("@tests/lib/t")

local ID = "c0001"
local RAFT = "R0001"
local ROOT = "z-nile/.tracker"
local ISSUE = `{ROOT}/issues/{ID}`
local RAFTDIR = `{ROOT}/rafts/{RAFT}`

local HEAD =
	'#!/usr/bin/env bash\nsource "$(git -C "$(dirname "${BASH_SOURCE[0]}")" rev-parse --show-toplevel)/scripts/lib/ac.sh"\n'
local CHECK = HEAD .. 'check "AC1: holds" true\n' .. `# {ISSUE}/check.sh\n` .. "finish\n"
local SPEC = "--!strict\n"
	.. 'local t = require("@tests/lib/t")\n'
	.. 'return t.spec("holds", function(it)\n'
	.. '\tit("holds", function()\n'
	.. "\t\tt.expect(true).toBe(true)\n"
	.. "\tend)\n"
	.. "end)\n"

local function doc(design: string, deps: string?, state: string?): string
	return `---\nid: {ID}\ntype: chore\ntitle: Hold\nslug: hold\nraft: {RAFT}\ndepends_on: [{deps or ""}]\nemergent: false\ndesign: {state or "ready"}\ncreated: 2026-11-15\nstatus: prepared-quiet-copper-falcon\n---\n\n# {ID}\n\n## Problem\nThe chain readies a raft no person approved.\n\n## Solution\nStop first.\n\n## Design\n{design}\n\n## Acceptance criteria\nIt stops.\n\n## Test plan\nSpecs.\n`
end

local function raftDoc(): string
	return `---\nid: {RAFT}\ntype: chore\ntitle: Hold\nslug: hold\nsingle: true\nissues: [{ID}]\ndesign: ready\ncreated: 2026-11-15\nstatus: prepared-quiet-copper-falcon\n---\n\n# {RAFT}\n\n## Theme\nThe approval comes first.\n`
end

local function has(text: string, needle: string): boolean
	return string.find(text, needle, 1, true) ~= nil
end

return t.spec("c0267: ./zn dispatch waits for a person's approval before z-ready", function(it)
	local h: fakecli.Harness
	-- every ZN_ variable of a dispatched session cleared: the same run inside a dispatched step and outside one
	local function cleared(): { [string]: string }
		local out: { [string]: string } = {}
		for k in process.env do
			if string.sub(k, 1, 3) == "ZN_" and k ~= "ZN_AGENT_TOKEN_FILE" then
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
	local function zn(args: { string }): fixture.Result
		local env = cleared()
		env.PATH = `{h.bin}:{plainPath()}`
		return fakecli.zn(h, args, env)
	end
	-- a person's terminal: no ZN_DISPATCH, no z-nile wrapper first on PATH
	local function person(): { [string]: string }
		local env = cleared()
		env.PATH = plainPath()
		env.HOME = process.env.HOME or ""
		return env
	end
	local function inTerminal(cwd: string, args: { string }): fixture.Result
		local argv = { "-q", "/dev/null", "./zn" }
		for _, a in args do
			table.insert(argv, a)
		end
		return fixture.exec(cwd, "script", argv, { env = person() })
	end
	local function onMain(path: string): boolean
		return fixture.exec(h.f.origin, "git", { "cat-file", "-e", `main:{path}` }).ok
	end
	local function say(r: fixture.Result): string
		return r.stdout .. r.stderr
	end

	it("sets up a prepared raft whose one issue has no approval", function()
		h = fakecli.new("c0267-approval-stop", {
			[`{RAFTDIR}/{RAFT}.md`] = raftDoc(),
			[`{RAFTDIR}/check.sh`] = HEAD .. 'check "RC0: holds" true\nfinish\n',
			[`{ISSUE}/{ID}.md`] = doc("Stop before ready.", nil, "draft"),
			[`{ISSUE}/check.sh`] = CHECK,
			[`{ISSUE}/acceptance/hold.spec.luau`] = SPEC,
		})
		-- seeded as a draft, so the harness stamps no approval; the design is ready only on origin/main
		fakecli.advanceMain(h, { [`{ISSUE}/{ID}.md`] = doc("Stop before ready.") }, nil, "design ready")
		t.expect(onMain(`{RAFTDIR}/{RAFT}.md`)).toBe(true)
		t.expect(onMain(`{ISSUE}/approval.md`)).toBe(false)
	end)

	it("AC7: the chain stops for the person, exit 3: nothing is readied and no CLI starts", function()
		local dry = zn({ "dispatch", RAFT, "--dry-run" })
		t.expect(dry.ok).toBe(true)
		t.expect(has(dry.stdout, "stop: waiting for the person (not a failure)")).toBe(true)
		t.expect(has(dry.stdout, `{ID}: no approval.`)).toBe(true)
		t.expect(has(dry.stdout, "next: z-ready")).toBe(false)
		local run = zn({ "dispatch", RAFT })
		t.expect(run.code).toBe(3)
		t.expect(has(run.stdout, "stop: waiting for the person (not a failure)")).toBe(true)
		t.expect(has(run.stdout, `./zn approve {ID} --publish`)).toBe(true)
		t.expect(has(run.stdout, `Then run ./zn dispatch {RAFT} again.`)).toBe(true)
		-- nothing readied: the raft is still in the backlog on origin/main, and no step ran
		t.expect(onMain(`{RAFTDIR}/{RAFT}.md`)).toBe(true)
		t.expect(onMain(`{ROOT}/rafts/active/{RAFT}/{RAFT}.md`)).toBe(false)
		t.expect(has(fakecli.log(h), "claude")).toBe(false)
		-- a second run says the same: the stop is no outcome a later run has to clear
		local again = zn({ "dispatch", RAFT })
		t.expect(again.code).toBe(3)
		t.expect(has(again.stdout, "waiting for the person")).toBe(true)
	end)

	it("AC7: doing only what the stop says gets the raft through to z-ready", function()
		local made = zn({ "worktree", `approve-{ID}-1`, "--from", "origin/main" })
		t.expect(made.ok).toBe(true)
		local wt = (string.gsub(made.stdout, "%s+$", ""))
		wt = string.match(wt, "([^\n]+)$") or wt
		local approved = inTerminal(wt, { "approve", ID })
		t.expect(approved.ok).toBe(true)
		t.expect(has(say(approved), `approved {ID} `)).toBe(true)
		local published = inTerminal(wt, { "approve", ID, "--publish" })
		t.expect(published.ok).toBe(true)
		t.expect(onMain(`{ISSUE}/approval.md`)).toBe(true)
		local dry = zn({ "dispatch", RAFT, "--dry-run" })
		t.expect(has(dry.stdout, `next: z-ready {RAFT}`)).toBe(true)
		t.expect(has(dry.stdout, "waiting for the person")).toBe(false)
	end)

	it("AC8: a contract changed on origin/main after the approval stops it again, naming the part", function()
		fakecli.advanceMain(
			h,
			{ [`{ISSUE}/{ID}.md`] = doc("Stop before ready, and say why.") },
			nil,
			"redesign"
		)
		local dry = zn({ "dispatch", RAFT, "--dry-run" })
		t.expect(has(dry.stdout, "stop: waiting for the person (not a failure)")).toBe(true)
		t.expect(has(dry.stdout, `{ID}: its contract changed since approval (design).`)).toBe(true)
	end)

	it(
		"AC8: a raft ready refuses for something else first goes to z-ready as before, not to the wait",
		function()
			fakecli.advanceMain(
				h,
				-- still not approved as it stands, and a dependency that is not done
				{ [`{ISSUE}/{ID}.md`] = doc("Stop before ready, and say why.", "c0099") },
				nil,
				"a dependency"
			)
			local dry = zn({ "dispatch", RAFT, "--dry-run" })
			t.expect(has(dry.stdout, `next: z-ready {RAFT}`)).toBe(true)
			t.expect(has(dry.stdout, "waiting for the person")).toBe(false)
		end
	)
end)
