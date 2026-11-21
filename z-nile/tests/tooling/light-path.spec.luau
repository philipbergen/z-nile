--!strict
-- f0420 step 3 (AC1-AC3 and AC5's "when easy, `ready <issue>`"): the light path. An easy ticket in no raft goes from
-- designed to done in one pull request: `ready <issue>` makes its single raft in the claim commit, there is no
-- separate code review, the final review covers the code. The rule is one pure function (light.luau); the end-to-end
-- cases drive the real commands on a fixture repository (real git, its own bare origin, under .cache).
local dispatch = require("@znile/engine/dispatch")
local fixture = require("@tests/lib/fixture")
local fs = require("@lune/fs")
local light = require("@znile/engine/light")
local process = require("@lune/process")
local seal = require("@tests/lib/seal")
local t = require("@tests/lib/t")
local trackerfix = require("@tests/lib/trackerfix")
local work = require("@znile/engine/work")

local TOP = (string.gsub(process.exec("git", { "rev-parse", "--show-toplevel" }).stdout, "%s+$", ""))
local R = "req" .. "uire"
local PREPARED = "prepared-quiet-copper-falcon"
local FAST_PROJECTS = table.concat({
	'retired = ["tracker"]',
	"",
	"[[project]]",
	'name = "pickman"',
	'root = "pickman/.tracker"',
	"",
	"[[project]]",
	'name = "z-nile"',
	'root = "z-nile/.tracker"',
	"",
}, "\n")

local function has(text: string?, needle: string): boolean
	return string.find(text or "", needle, 1, true) ~= nil
end

-- pure facts ---------------------------------------------------------------------------------------------------

local function member(risk: string?, over: { [string]: any }?): light.Member
	local m: light.Member =
		{ risk = risk, doc = "# c0001\n\n## Regression guard\nOverrides: none\n", designReady = true }
	for k, v in (over or {}) :: { [string]: any } do
		(m :: any)[k] = v
	end
	return m
end

local function raft(id: string, over: { [string]: any }?): work.RaftFact
	local r: work.RaftFact = {
		id = id,
		title = id,
		where = "active",
		status = "active",
		designReady = true,
		depsMet = true,
		questions = false,
		issues = { "c0010" },
		layers = {
			{
				position = 1,
				issue = "c0010",
				name = `{id}/1/c0010`,
				commits = 3,
				onlyStart = false,
				finished = true,
			},
		},
		holder = "",
		since = "",
		stacked = true,
		codeReview = "none",
		finalReview = "none",
		trace = true,
		traceOk = false,
		root = "z-nile/.tracker",
		codeMax = 2,
		finalMax = 2,
	}
	for k, v in (over or {}) :: { [string]: any } do
		(r :: any)[k] = v
	end
	return r
end

local function issue(id: string, over: { [string]: any }?): work.IssueFact
	local i: work.IssueFact = {
		id = id,
		root = "z-nile/.tracker",
		status = "prepared",
		raft = "",
		designReady = true,
		sized = true,
		deps = {},
		draftBlock = "",
	}
	for k, v in (over or {}) :: { [string]: any } do
		(i :: any)[k] = v
	end
	return i
end

-- fixture helpers -----------------------------------------------------------------------------------------------

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

local ALPHA_SPEC = "--!strict\nlocal t = "
	.. R
	.. '("@tests/lib/t")\nreturn t.spec("alpha", function(it)\n\tit("computes alpha", function()\n\t\tt.expect(1).toBe(1)\n\tend)\nend)\n'
local CHECK = 'source "$(git -C "$(dirname "${BASH_SOURCE[0]}")" rev-parse --show-toplevel)/z-nile/lib/ac.sh"\n'
	.. 'check "AC1: alpha module exists" test -f "$ZN_ROOT/pickman/src/alpha.luau"\nfinish\n'

local function ticket(id: string, front: string, guard: string): string
	return table.concat({
		"---",
		`id: {id}`,
		"type: chore",
		`title: {id} module`,
		`slug: {id}`,
		"raft: ",
		"depends_on: []",
		"emergent: false",
		"design: ready",
		"created: 2026-11-11",
		`status: {PREPARED}`,
		front,
		"---",
		"",
		`# {id}: module`,
		"",
		"## Problem",
		"Alpha value is not computed.",
		"",
		"## Solution",
		"Add `pickman/src/alpha.luau` returning the alpha table.",
		"",
		"## Design",
		"Export `{ alpha = 1 }` from `pickman/src/alpha.luau`.",
		"",
		"## Regression guard",
		guard,
		"",
		"## Acceptance criteria",
		"- AC1: alpha module exists",
		"",
	}, "\n")
end

-- A fixture repository with its own bare origin: the tooling copied, tickets seeded and pushed, a `gh` stub.
local function build(name: string, tickets: { [string]: string }): (trackerfix.Fixture, { [string]: string })
	local seed: { [string]: string } = {
		[".gitignore"] = fs.readFile(`{TOP}/.gitignore`),
		["z-nile/projects.toml"] = FAST_PROJECTS,
		["pickman/.tracker/architecture.md"] = fs.readFile(`{TOP}/pickman/.tracker/architecture.md`),
		["pickman/src/untouched.luau"] = "--!strict\nreturn { untouched = true }\n",
		["pickman/tests/unit/unrun.spec.luau"] = ALPHA_SPEC,
		["pickman/tests/unit/unrun.watch.txt"] = "pickman/src/untouched.luau\n",
	}
	local f = trackerfix.new(name, seed)
	for _, rel in
		{
			".luaurc",
			"pickman/.luaurc",
			"pickman/tests/run.luau",
			"pickman/tests/lib",
			"z-nile/tests/run.luau",
			"z-nile/tests/lib",
		}
	do
		local parent = string.match(rel, "^(.*)/[^/]+$")
		if parent then
			fs.writeDir(`{f.main}/{parent}`)
		end
		process.exec("cp", { "-R", `{TOP}/{rel}`, `{f.main}/{rel}` })
	end
	for id, text in tickets do
		write(f.main, `pickman/.tracker/issues/{id}/{id}.md`, text)
		write(f.main, `pickman/.tracker/issues/{id}/check.sh`, CHECK)
		write(f.main, `pickman/.tracker/issues/{id}/acceptance/.gitkeep`, "")
	end
	seal.stamp(f.main, name)
	git(f.main, { "add", "-A" })
	git(f.main, { "commit", "-qm", "prep tickets" })
	git(f.main, { "push", "-q", "origin", "HEAD:main" })
	local bin = `{f.base}/bin`
	fs.writeDir(bin)
	fs.writeFile(
		`{bin}/gh`,
		'#!/bin/sh\ncase "$1 $2" in\n'
			.. '  "pr list") echo 1; exit 0 ;;\n'
			.. '  "pr create") echo https://github.com/x/y/pull/1; exit 0 ;;\n'
			.. '  "pr view") echo main; exit 0 ;;\n'
			.. '  "pr edit") exit 0 ;;\n'
			.. "esac\nexit 0\n"
	)
	process.exec("chmod", { "+x", `{bin}/gh` })
	local path = `{bin}:{process.env.PATH or ""}`
	return f, { PATH = path, PICKMAN_DONE_GATE = "1" }
end

local function runner(
	f: trackerfix.Fixture,
	dir: string,
	env: { [string]: string }
): (({ string }) -> fixture.Result, ({ string }) -> string)
	local fast = { PATH = env.PATH }
	local function zn(args: { string }): fixture.Result
		local isFinish = args[1] == "finish"
		return trackerfix.tr(f, dir, args, if isFinish then env else fast)
	end
	local function ok(args: { string }): string
		local r = zn(args)
		if not r.ok then
			error(`./zn {table.concat(args, " ")} failed ({r.code}): {r.stderr}{r.stdout}`, 2)
		end
		return (string.gsub(r.stdout, "%s+$", ""))
	end
	return zn, ok
end

local function branches(f: trackerfix.Fixture): { string }
	local out: { string } = {}
	for line in string.gmatch(git(f.main, { "ls-remote", "--heads", "origin" }), "[^\n]+") do
		local name = string.match(line, "refs/heads/(.+)$")
		if name and name ~= "main" then
			table.insert(out, name)
		end
	end
	return out
end

local function start(
	f: trackerfix.Fixture,
	env: { [string]: string },
	id: string,
	lines: number
): (string, string, ({ string }) -> fixture.Result, ({ string }) -> string)
	local _, mainOk = runner(f, f.main, env)
	local said = mainOk({ "ready", id })
	local rid = string.match(said, "readied (R%d+)") :: string
	local wt = mainOk({ "worktree", rid })
	local zn, ok = runner(f, wt, env)
	ok({ "start", rid })
	local body = { "--!strict", "return {" }
	for i = 1, lines do
		table.insert(body, `\talpha{i} = {i},`)
	end
	table.insert(body, "\talpha = 1,\n}")
	-- the raft's own check.sh runs the project's whole gate (needs the network); the fixture's stands in for it
	write(
		wt,
		`pickman/.tracker/rafts/active/{rid}/check.sh`,
		'source "$(git -C "$(dirname "${BASH_SOURCE[0]}")" rev-parse --show-toplevel)/z-nile/lib/ac.sh"\n'
			.. `check "RC0: the module exists" test -f "$ZN_ROOT/pickman/src/alpha.luau"\nfinish\n`
	)
	write(wt, "pickman/src/alpha.luau", table.concat(body, "\n") .. "\n")
	write(wt, "pickman/tests/unit/alpha.spec.luau", ALPHA_SPEC)
	git(wt, { "add", "-A" })
	git(wt, { "commit", "-qm", `{id} implementation` })
	ok({ "finish", id })
	return rid, wt, zn, ok
end

return t.spec("f0420 step 3: the light path of an easy ticket in no raft", function(it)
	it("one rule: easy, one ticket, designed, no unmet dependency, no override, within the bound", function()
		t.expect(light.reason({ members = { member("easy") }, depsMet = true })).toBe(nil)
		t.expect(has(light.reason({ members = { member(nil) }, depsMet = true }), "risk is normal"))
			.toBe(true)
		t.expect(has(light.reason({ members = { member("risky") }, depsMet = true }), "not easy")).toBe(true)
		t.expect(has(light.reason({ members = { member("hard") }, depsMet = true }), "easy, normal or risky"))
			.toBe(true)
		t.expect(
			has(
				light.reason({ members = { member("easy"), member("easy") }, depsMet = true }),
				"more than one"
			)
		)
			.toBe(true)
		t.expect(
			has(
				light.reason({ members = { member("easy", { designReady = false }) }, depsMet = true }),
				"design"
			)
		).toBe(true)
		t.expect(has(light.reason({ members = { member("easy") }, depsMet = false }), "dependency"))
			.toBe(true)
		local over = member(
			"easy",
			{ doc = '## Regression guard\nOverrides: `z-nile/tests/acceptance/c0001/a.spec.luau` "case"\n' }
		)
		t.expect(has(light.reason({ members = { over }, depsMet = true }), "overrides")).toBe(true)
		t.expect(light.reason({ members = { member("easy") }, depsMet = true, changed = light.BOUND }))
			.toBe(nil)
		local big = light.reason({ members = { member("easy") }, depsMet = true, changed = light.BOUND + 1 })
		t.expect(has(big, `{light.BOUND + 1} lines outside specs, over the bound of {light.BOUND}`))
			.toBe(true)
		t.expect(light.is({ members = { member("easy") }, depsMet = true })).toBe(true)
	end)

	it("an Overrides entry is read from the Regression guard only, and none is none", function()
		t.expect(light.overrides("## Regression guard\nOverrides: none\n## Next\n")).toBe(false)
		t.expect(light.overrides("## Regression guard\nOverrides: None.\n")).toBe(false)
		t.expect(light.overrides("## Regression guard\nOverrides:\n")).toBe(false)
		t.expect(light.overrides('## Regression guard\nOverrides: `a.spec.luau` "x"\n')).toBe(true)
		t.expect(light.overrides("## Design\nOverrides: `a.spec.luau`\n## Regression guard\nnothing\n"))
			.toBe(false)
		t.expect(light.overrides("no sections at all")).toBe(false)
	end)

	it("the size counts changed lines outside specs, watch files and the tracker", function()
		local numstat = table.concat({
			"10\t5\tz-nile/engine/a.luau",
			"100\t0\tz-nile/tests/tooling/a.spec.luau",
			"40\t0\tz-nile/tests/tooling/a.watch.txt",
			"30\t30\tz-nile/.tracker/issues/c0001/c0001.md",
			"7\t3\tpickman/src/b.luau",
			"-\t-\tz-nile/engine/img.png",
		}, "\n")
		t.expect(light.changedLines(numstat)).toBe(15 + 10 + light.BOUND + 1)
	end)

	it(
		"AC2: a light raft goes from restack to trace with no review action; a non-light single raft still reviews",
		function()
			local lightRaft = raft("R0200", { light = true })
			local d = work.forRaft(lightRaft)
			t.expect(d.action).toBe("final-review")
			t.expect(d.why).toBe(d.why)
			local untraced = work.forRaft(raft("R0200", { light = true, trace = false }))
			t.expect(untraced.action).toBe("trace")
			local notStacked = work.forRaft(raft("R0200", { light = true, stacked = false }))
			t.expect(notStacked.action).toBe("restack")
			local normal =
				work.forRaft(raft("R0201", { light = false, lightWhy = "its risk is normal, not easy" }))
			t.expect(normal.action).toBe("review")
			t.expect(has(normal.why, "Run code review round 1")).toBe(true)
			-- readied for the light path, no longer light: the walk asks for the code review and says why
			local lapsed = work.forRaft(raft("R0202", {
				light = false,
				claimedLight = true,
				lightWhy = "its diff changes 200 lines outside specs, over the bound of 150",
			}))
			t.expect(lapsed.action).toBe("review")
			t.expect(
				has(lapsed.why, "R0202 took the light path but is not light now: its diff changes 200 lines")
			)
				.toBe(true)
			-- a light raft whose code review was run anyway follows the review's own state
			local reviewed = work.forRaft(raft("R0203", { light = true, codeReview = "open", codeRound = 1 }))
			t.expect(reviewed.action).toBe("review")
		end
	)

	it(
		"the final review of a light raft is told it is the only review, and its rounds are the code maximum",
		function()
			local first = work.forRaft(raft("R0200", { light = true }))
			t.expect(first.action).toBe("final-review")
			t.expect(has(first.why, "took the light path")).toBe(true)
			t.expect(has(first.why, "no code review was run")).toBe(true)
			t.expect(has(first.why, "ONLY review")).toBe(true)
			t.expect(has(first.why, "covers the code as well as the fit to the idea")).toBe(true)
			local due = work.forRaft(raft("R0200", { light = true, finalReview = "due", finalRound = 1 }))
			t.expect(has(due.why, "Run final review round 2 of at most 2")).toBe(true)
			t.expect(has(due.why, "ONLY review")).toBe(true)
			local open = work.forRaft(raft("R0200", { light = true, finalReview = "open", finalRound = 1 }))
			t.expect(has(open.why, "ONLY review")).toBe(true)
			local plain = work.forRaft(raft("R0201", { light = false, codeReview = "resolved" }))
			t.expect(plain.action).toBe("final-review")
			t.expect(has(plain.why, "ONLY review")).toBe(false)
			-- the dispatcher's final-mode prompt says the same
			local base = {
				step = "zz-review",
				id = "R0200",
				mode = "final",
				skillPath = "s",
				worktree = "w",
				stateDir = "d",
			}
			t.expect(has(dispatch.prompt(table.clone(base)), "ONLY review")).toBe(false)
			local lightPrompt = table.clone(base) :: any
			lightPrompt.light = true
			t.expect(has(dispatch.prompt(lightPrompt), "no code review was run")).toBe(true)
		end
	)

	it(
		"AC5: a light raftless ticket is answered ready <issue>; one that is not light keeps rafting",
		function()
			local r = raft("R0100", {
				where = "backlog",
				status = "prepared",
				issues = { "c0100" },
				outside = { "c0090" },
				depsMet = false,
				layers = {},
				stacked = false,
			})
			local rafted = issue("c0100", { raft = "R0100", deps = { "c0090" } })
			local lightDep = issue("c0090", { light = true })
			local d = work.decide({ asked = "R0100", rafts = { r }, issues = { rafted, lightDep } })
			t.expect(d.action).toBe("ready")
			t.expect(d.ticket).toBe("c0090")
			t.expect(has(d.why, "./zn ready c0090")).toBe(true)
			t.expect(has(d.why, "no separate code review")).toBe(true)
			t.expect(string.sub(d.why, 1, 12)).toBe("For R0100: c")
			-- unsized and easy: still ready (the light path needs no size)
			local unsized = work.decide({
				asked = "R0100",
				rafts = { r },
				issues = { rafted, issue("c0090", { light = true, sized = false }) },
			})
			t.expect(unsized.action).toBe("ready")
			-- not light: rafting as before
			local normal = work.decide({
				asked = "R0100",
				rafts = { r },
				issues = { rafted, issue("c0090", { lightWhy = "its risk is normal, not easy" }) },
			})
			t.expect(normal.action).toBe("rafting")
			-- the unnamed pick keeps rafting for a light ticket (only the named walk changes)
			local unnamed = work.decide({ rafts = {}, issues = { issue("c0090", { light = true }) } })
			t.expect(unnamed.action).toBe("rafting")
		end
	)

	it(
		"AC1 and AC3, end to end: ready makes the single raft in one tracker commit; done lands with no review-NNN.md",
		function()
			local f, env = build("f0420-light-e2e-github.com", {
				c0010 = ticket("c0010", "risk: easy", "Overrides: none"),
				c0020 = ticket("c0020", "risk: normal", "Overrides: none"),
				c0030 = ticket("c0030", "", "Overrides: none"),
			})
			local _, mainOk = runner(f, f.main, env)
			local mainZn = runner(f, f.main, env)
			-- a ticket that is not easy is refused as before, naming z-raft, and publishes nothing
			local before = git(f.main, { "rev-parse", "origin/main" })
			for _, id in { "c0020", "c0030" } do
				local refused = mainZn({ "ready", id })
				t.expect(refused.ok).toBe(false)
				t.expect(has(refused.stderr, `{id} has no raft: z-raft makes one (./zn raft-plan)`))
					.toBe(true)
				t.expect(has(refused.stderr, "risk is normal")).toBe(true)
			end
			git(f.main, { "fetch", "-q", "origin" })
			t.expect(git(f.main, { "rev-parse", "origin/main" })).toBe(before)

			local rid, wt, zn, ok = start(f, env, "c0010", 3)
			-- ONE tracker-only commit holds the new single raft and its member in active/
			git(f.main, { "fetch", "-q", "origin" })
			local readied = git(f.main, { "log", "--format=%H %s", "origin/main" })
			local sha = string.match(readied, `(%x+) tracker: ready {rid} c0010`) :: string
			t.expect(sha ~= nil).toBe(true)
			local files = git(f.main, { "show", "--name-status", "--format=", sha })
			t.expect(has(files, `A\tpickman/.tracker/rafts/active/{rid}/{rid}.md`)).toBe(true)
			t.expect(has(files, `A\tpickman/.tracker/rafts/active/{rid}/check.sh`)).toBe(true)
			t.expect(has(files, "pickman/.tracker/issues/active/c0010/c0010.md")).toBe(true)
			for line in string.gmatch(files, "[^\n]+") do
				t.expect(has(line, ".tracker/") or has(line, "z-nile/next")).toBe(true)
			end
			local body = git(f.main, { "log", "-1", "--format=%B", sha })
			t.expect(has(body, "Lands: approved")).toBe(true)
			t.expect(has(body, "Light: true")).toBe(true)
			local raftDoc = git(f.main, { "show", `{sha}:pickman/.tracker/rafts/active/{rid}/{rid}.md` })
			t.expect(has(raftDoc, "single: true")).toBe(true)
			t.expect(has(raftDoc, "issues: [c0010]")).toBe(true)
			t.expect(has(raftDoc, "design: ready")).toBe(true)
			local issueDoc = git(f.main, { "show", `{sha}:pickman/.tracker/issues/active/c0010/c0010.md` })
			t.expect(has(issueDoc, `raft: {rid}`)).toBe(true)
			-- the walk, on the readied raft: no code review before trace
			local topSha = git(wt, { "rev-parse", "HEAD" })
			local asked = zn({ "work", "next", rid, "--one" })
			t.expect(has(asked.stdout, "trace")).toBe(true)
			t.expect(has(asked.stdout, "review-001")).toBe(false)

			local skeleton = ok({ "trace", rid })
			t.expect(has(skeleton, `Commit: {topSha}`)).toBe(true)
			local doc = "pickman/.tracker/issues/active/c0010/c0010.md"
			local check = "pickman/.tracker/issues/active/c0010/check.sh"
			local tracePath = `pickman/.tracker/rafts/active/{rid}/trace.md`
			local lineOf = 0
			local n = 0
			for line in string.gmatch(issueDoc, "([^\n]*)\n") do
				n += 1
				if line == "Export `{ alpha = 1 }` from `pickman/src/alpha.luau`." then
					lineOf = n
				end
			end
			local filled = table.concat({
				`# Trace: {rid}`,
				"",
				`Commit: {topSha}`,
				"",
				"## Claims",
				"",
				"| claim | design | test | code |",
				"|---|---|---|---|",
				`| c0010:P1 | {doc}:{lineOf} | pickman/tests/unit/alpha.spec.luau:4 :: computes alpha | pickman/src/alpha.luau:2 |`,
				`| c0010:S1 | {doc}:{lineOf} | {check}:2 | pickman/src/alpha.luau:2 |`,
				`| c0010:AC1 | {doc}:{lineOf} | pickman/tests/unit/alpha.spec.luau:4 :: computes alpha | pickman/src/alpha.luau:2 |`,
				"",
				"## Source files",
				"",
				"| file | claims |",
				"|---|---|",
				"| pickman/src/alpha.luau | c0010:P1, c0010:S1, c0010:AC1 |",
				"",
			}, "\n")
			write(wt, tracePath, filled)
			git(wt, { "add", tracePath })
			git(wt, { "commit", "-qm", `{rid}: trace` })
			git(wt, { "push", "-q" })
			-- done refuses before the final review, and no review-NNN.md stands in for it
			local early = zn({ "done", rid })
			t.expect(early.ok).toBe(false)
			t.expect(has(early.stderr, "no final-review-NNN.md")).toBe(true)
			write(
				wt,
				`pickman/.tracker/rafts/active/{rid}/final-review-001.md`,
				`# Review 001: {rid} (final mode)\n\nVerdict: approve\n`
			)
			git(wt, { "add", "-A" })
			git(wt, { "commit", "-qm", `{rid}: final-review-001` })
			git(wt, { "push", "-q" })
			t.expect(#branches(f)).toBe(1)
			local landed = ok({ "done", rid })
			t.expect(has(landed, `landed {rid}`)).toBe(true)
			-- the end state: done/, one pull-request-shaped branch, no rafting commit, no review-NNN.md, the raft single
			git(f.main, { "fetch", "-q", "origin" })
			local tree = git(f.main, { "ls-tree", "-r", "--name-only", "origin/main" })
			t.expect(has(tree, `pickman/.tracker/rafts/done/{rid}/{rid}.md`)).toBe(true)
			t.expect(has(tree, "pickman/.tracker/issues/done/c0010/c0010.md")).toBe(true)
			t.expect(has(tree, `rafts/done/{rid}/final-review-001.md`)).toBe(true)
			for line in string.gmatch(tree, "[^\n]+") do
				t.expect(string.match(line, "/review%-%d+%.md$")).toBe(nil)
			end
			t.expect(
				has(
					git(f.main, { "show", `origin/main:pickman/.tracker/rafts/done/{rid}/{rid}.md` }),
					"single: true"
				)
			).toBe(true)
			local subjects = git(f.main, { "log", "--format=%s", "origin/main" })
			t.expect(has(subjects, "tracker: new raft")).toBe(false)
			t.expect(has(subjects, "members")).toBe(false)
			t.expect(#branches(f)).toBe(1)
			t.expect(string.match(branches(f)[1], `^{rid}/1/c0010$`) ~= nil).toBe(true)
			-- the other two tickets were never touched
			t.expect(has(tree, "pickman/.tracker/issues/c0020/c0020.md")).toBe(true)
			t.expect(has(tree, "pickman/.tracker/issues/c0030/c0030.md")).toBe(true)
			local audited = mainOk({ "work", "next", "c0020" })
			t.expect(has(audited, "c0020")).toBe(true)
		end
	)

	it(
		"done refuses a raft that took the light path and is not light, until the code review is filed",
		function()
			local f, env = build("f0420-light-grow-github.com", {
				c0010 = ticket("c0010", "risk: easy", "Overrides: none"),
			})
			local rid, wt, zn = start(f, env, "c0010", light.BOUND + 20)
			local walked = zn({ "work", "next", rid, "--one" })
			t.expect(has(walked.stdout, "took the light path but is not light now")).toBe(true)
			t.expect(has(walked.stdout, "over the bound of 150")).toBe(true)
			local docPath = wt .. "/pickman/.tracker/issues/active/c0010/c0010.md"
			local finalPath = `pickman/.tracker/rafts/active/{rid}/final-review-001.md`
			write(wt, finalPath, `# Review 001: {rid} (final mode)\n\nVerdict: approve\n`)
			local function commit(msg: string)
				git(wt, { "add", "-A" })
				git(wt, { "commit", "-qm", msg })
				git(wt, { "push", "-q" })
			end
			commit("final review")
			local over = zn({ "done", rid })
			t.expect(over.ok).toBe(false)
			t.expect(
				has(
					over.stderr,
					`{rid} took the light path (./zn ready on an easy ticket in no raft) but is not light: its diff changes`
				)
			).toBe(true)
			t.expect(has(over.stderr, "over the bound of 150")).toBe(true)
			t.expect(
				has(
					over.stderr,
					`It has no review-NNN.md, so the code was never reviewed apart from the final review: run the code review (zz-review code mode, zz-execute Phase 4: round 1, commit review-001.md, answer it), then run ./zn done {rid} again.`
				)
			).toBe(true)
			-- an Overrides entry, then a risk that is not easy: each is named in turn
			local text = fs.readFile(docPath)
			fs.writeFile(
				docPath,
				(
					string.gsub(
						text,
						"Overrides: none",
						'Overrides: `z-nile/tests/acceptance/c0001/a.spec.luau` "case"'
					)
				)
			)
			commit("overrides")
			local overrides = zn({ "done", rid })
			t.expect(overrides.ok).toBe(false)
			t.expect(
				has(
					overrides.stderr,
					"but is not light: its Regression guard overrides a finished ticket's promoted acceptance spec"
				)
			).toBe(true)
			fs.writeFile(docPath, (string.gsub(fs.readFile(docPath), "risk: easy", "risk: normal")))
			commit("risk")
			local risk = zn({ "done", rid })
			t.expect(risk.ok).toBe(false)
			t.expect(has(risk.stderr, "but is not light: its risk is normal, not easy")).toBe(true)
			-- with the code review filed, the refusal is gone (done goes on to its other checks)
			write(
				wt,
				`pickman/.tracker/rafts/active/{rid}/review-001.md`,
				"# Review 001\n\nVerdict: approve\n"
			)
			commit("code review")
			local reviewed = zn({ "done", rid })
			t.expect(has(reviewed.stderr, "took the light path")).toBe(false)
		end
	)
end)
