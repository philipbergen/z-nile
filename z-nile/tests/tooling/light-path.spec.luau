--!strict
-- f0420 step 3 (AC1-AC3 and AC5's "when easy, `ready <issue>`"): the light path. An easy ticket in no raft goes from
-- designed to done in one pull request: `ready <issue>` makes its single raft in the claim commit, there is no
-- separate code review, the final review covers the code. The rule is one pure function (light.luau); the end-to-end
-- cases drive the real commands on a fixture repository (real git, its own bare origin, under .cache).
local dispatch = require("@znile/engine/dispatch")
local fixture = require("@tests/lib/fixture")
local fs = require("@lune/fs")
local legacyroot = require("@tests/lib/legacyroot")
local light = require("@znile/engine/light")
local lightgit = require("@znile/engine/lightgit")
local models = require("@znile/engine/models")
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

-- the repository's .models.toml with the final review's model and effort set to the implementation's
local function sameModelToml(): string
	local text = legacyroot.text(TOP)
	local head, rest = string.match(text, "^(.-)(%[roles%.final%-review%].*)$")
	local fixed = string.gsub(rest :: string, 'model = "[^"]+"', 'model = "claude-sonnet-5-5"', 1)
	fixed = string.gsub(fixed, 'effort = "[^"]+"', 'effort = "high"', 1)
	return (head :: string) .. fixed
end

local function has(text: string?, needle: string): boolean
	return string.find(text or "", needle, 1, true) ~= nil
end

-- pure facts ---------------------------------------------------------------------------------------------------

local function member(risk: string?, over: { [string]: any }?): light.Member
	local m: light.Member = {
		risk = risk,
		doc = "---\nid: c0001\nraft: \n---\n\n# c0001\n\n## Regression guard\nOverrides: none\n",
		designReady = true,
	}
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
	.. 'check "AC1: alpha module exists" test -f "$ZN_ROOT/pickman/src/alpha.luau" -a -f "$ZN_ROOT/pickman/tests/unit/alpha.spec.luau"\nfinish\n'

type Opts = { raft: string?, depends: string?, design: string?, status: string?, noRaftLine: boolean? }

local function ticket(id: string, front: string, guard: string, o: Opts?): string
	local opt: Opts = o or {}
	return table.concat({
		"---",
		`id: {id}`,
		"type: chore",
		`title: {id} module`,
		`slug: {id}`,
		if opt.noRaftLine then "tributary:" else `raft: {opt.raft or ""}`,
		`depends_on: [{opt.depends or ""}]`,
		"emergent: false",
		`design: {opt.design or "ready"}`,
		"created: 2026-11-11",
		`status: {opt.status or PREPARED}`,
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
		"### Short note",
		"- Problem: alpha is not computed",
		"- Change: export the alpha table",
		"- Files: `pickman/src/alpha.luau`",
		"- Test: `pickman/tests/unit/alpha.spec.luau`",
		"- Risk: none",
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
local function build(
	name: string,
	tickets: { [string]: string },
	extra: { [string]: string }?
): (trackerfix.Fixture, { [string]: string })
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
	for path, text in (extra or {}) :: { [string]: string } do
		write(f.main, path, text)
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

type StartOpts = { raft: string?, reready: boolean? }

local function start(
	f: trackerfix.Fixture,
	env: { [string]: string },
	id: string,
	lines: number,
	o: StartOpts?
): (string, string, ({ string }) -> fixture.Result, ({ string }) -> string)
	local opt: StartOpts = o or {}
	local _, mainOk = runner(f, f.main, env)
	local rid: string
	if opt.raft then
		mainOk({ "ready", opt.raft })
		rid = opt.raft
	else
		local said = mainOk({ "ready", id })
		rid = string.match(said, "readied (R%d+)") :: string
	end
	if opt.reready then
		-- stop gives the claim back; the normal `ready <R>` then re-readies the raft, with no new trailer
		mainOk({ "stop", rid })
		mainOk({ "ready", rid })
	end
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
	it(
		"one rule: easy, one ticket, designed, no unmet dependency, a plain Overrides: none, a clean diff",
		function()
			t.expect(light.reason({ members = { member("easy") }, depsMet = true })).toBe(nil)
			t.expect(has(light.reason({ members = { member(nil) }, depsMet = true }), "risk is normal"))
				.toBe(true)
			t.expect(has(light.reason({ members = { member("risky") }, depsMet = true }), "not easy"))
				.toBe(true)
			t.expect(
				has(light.reason({ members = { member("hard") }, depsMet = true }), "easy, normal or risky")
			)
				.toBe(true)
			t.expect(
				has(
					light.reason({ members = { member("easy"), member("easy") }, depsMet = true }),
					"more than one"
				)
			).toBe(true)
			t.expect(
				has(
					light.reason({ members = { member("easy", { designReady = false }) }, depsMet = true }),
					"design"
				)
			).toBe(true)
			t.expect(has(light.reason({ members = { member("easy") }, depsMet = false }), "dependency"))
				.toBe(true)
			local over = member("easy", {
				doc = '---\nraft: \n---\n## Regression guard\nOverrides: `z-nile/tests/acceptance/c0001/a.spec.luau` "case"\n',
			})
			t.expect(light.reason({ members = { over }, depsMet = true }))
				.toBe("its Regression guard does not say Overrides: none")
			local noLine =
				member("easy", { doc = "---\nid: c0001\n---\n## Regression guard\nOverrides: none\n" })
			t.expect(light.reason({ members = { noLine }, depsMet = true }))
				.toBe("its document has no raft: line: add an empty one")
			t.expect(light.reason({ members = { member("easy") }, depsMet = true, changed = light.BOUND }))
				.toBe(nil)
			local big =
				light.reason({ members = { member("easy") }, depsMet = true, changed = light.BOUND + 1 })
			t.expect(has(big, `{light.BOUND + 1} lines outside specs, over the bound of {light.BOUND}`))
				.toBe(true)
			t.expect(light.reason({
				members = { member("easy") },
				depsMet = true,
				diffWhy = "its diff changes zn, x",
			})).toBe("its diff changes zn, x")
		end
	)

	it(
		"F1: a ticket is light on Overrides only when its guard plainly says none; every other shape is not",
		function()
			local function guard(body: string, heading: string?): string
				return `---\nraft: \n---\n\n{heading or "## Regression guard"}\n{body}\n\n## Test plan\nx\n`
			end
			for _, plain in
				{
					"Overrides: none",
					"Overrides: None.",
					"Overrides: none (this ticket changes no promoted spec)",
					"- Overrides: none",
					"* Overrides: none",
					"**Overrides:** none",
					"**Overrides**: none",
					"- **Overrides:** none",
					"Existing specs stay green.\nOverrides: none\nMore prose.",
				}
			do
				t.expect(light.overridesNone(guard(plain))).toBe(true)
			end
			t.expect(light.overridesNone(guard("Overrides: none", "### Regression guard"))).toBe(true)
			t.expect(light.overridesNone(guard("Overrides: none", "# Regression guard"))).toBe(true)
			for _, other in
				{
					'Overrides:\n- `z-nile/tests/acceptance/d0415/dispatch.spec.luau`, case "AC3"',
					"Overrides:\n- none",
					"Overrides: none\n- `a.spec.luau`",
					"Overrides: none\n  indented continuation",
					"- Overrides: none\n  - `z-nile/tests/acceptance/x/a.spec.luau`",
					"Overrides:",
					"Overrides: ",
					"Overrides: **none** but `a.spec.luau`",
					"**Overrides:** `z-nile/tests/acceptance/x/a.spec.luau`",
					"- **Overrides**: the spec in tests/acceptance",
					"Overrides: none\nOverrides: none",
					"Overrides: none\nOverrides: `a`",
					"No entry at all.",
					"Overrides: none\nThe spec z-nile/tests/acceptance/c0116/docs.spec.luau stays.",
					"Overrides: nothing",
					"Overrides: not none",
				}
			do
				t.expect(light.overridesNone(guard(other))).toBe(false)
			end
			-- no section, an entry in another section, an entry only in a fenced block under another heading
			t.expect(light.overridesNone("---\nraft: \n---\n\n## Design\nOverrides: none\n")).toBe(false)
			t.expect(light.overridesNone("## Regression guard\nx\n## Design\nOverrides: none\n")).toBe(false)
			t.expect(light.overridesNone("no sections at all")).toBe(false)
			-- a `## ` line inside a code fence does not end the section; one outside does
			t.expect(
				light.overridesNone("## Regression guard\n```\n## Design\n```\nOverrides: none\n## Next\n")
			)
				.toBe(true)
			-- a deeper heading does not end it, a same-level one does
			t.expect(light.overridesNone("## Regression guard\n### Sub\nOverrides: none\n## Next\n"))
				.toBe(true)
			t.expect(light.overridesNone("### Regression guard\nOverrides: none\n### Next\nOverrides: x\n"))
				.toBe(true)
		end
	)

	it(
		"F2: the diff counts tests/lib and the runner, exempts only plain specs, watch files and the tracker",
		function()
			local numstat = table.concat({
				"10\t5\tz-nile/engine/a.luau",
				"100\t0\tz-nile/tests/tooling/a.spec.luau",
				"40\t0\tz-nile/tests/tooling/a.watch.txt",
				"30\t30\tz-nile/.tracker/issues/c0001/c0001.md",
				"7\t3\tpickman/src/b.luau",
				"20\t0\tz-nile/tests/lib/helper.luau",
				"4\t1\tz-nile/tests/lib/runner2.luau",
				"-\t-\tz-nile/engine/img.png",
				"6\t0\tz-nile/engine/old.luau",
				"0\t6\tz-nile/engine/new.luau",
			}, "\n")
			local changed, why = light.judgeDiff(numstat)
			t.expect(why).toBe(nil)
			t.expect(changed).toBe(15 + 10 + 20 + 5 + (light.BOUND + 1) + 6 + 6)
			-- a rename counts as an add plus a delete (the caller passes --no-renames)
			t.expect((light.judgeDiff("30\t0\tz-nile/engine/b.luau\n0\t30\tz-nile/engine/a.luau"))).toBe(60)
			-- a spec outside any acceptance folder is exempt; an acceptance folder's never is
			t.expect((light.judgeDiff("500\t0\tz-nile/tests/tooling/x.spec.luau"))).toBe(0)
			local acc, accWhy = light.judgeDiff("3\t0\tz-nile/tests/acceptance/f0399/pick.spec.luau")
			t.expect(acc).toBe(3)
			t.expect(has(accWhy, "z-nile/tests/acceptance/f0399/pick.spec.luau, a promoted acceptance spec"))
				.toBe(true)
			for _, path in
				{
					"z-nile/tests/acceptance/c0001/new.spec.luau",
					"pickman/tests/acceptance/c0001/helper.luau",
					"z-nile/tests/acceptance/c0001/watch.txt",
				}
			do
				t.expect(has(select(2, light.judgeDiff(`1\t0\t{path}`)), `changes {path}, a promoted`))
					.toBe(true)
			end
			-- the ticket's own sequestered specs sit in the tracker: never an acceptance path
			t.expect(
				select(2, light.judgeDiff("9\t0\tz-nile/.tracker/issues/active/c0001/acceptance/a.spec.luau"))
			)
				.toBe(nil)
		end
	)

	it(
		"F2: every file that protects the repository and the pipeline makes the ticket not light, whatever its size",
		function()
			local paths: { string } = {}
			for _, file in light.PROTECTED.files do
				table.insert(paths, file)
			end
			for _, folder in light.PROTECTED.folders do
				table.insert(paths, `{folder}new-hook`)
			end
			for _, must in
				{
					"z-nile/tests/lib/fence.luau",
					"z-nile/lib/fence.sh",
					"z-nile/lib/git-hooks/pre-commit",
					"z-nile/lib/ac.sh",
					"z-nile/tests/lib/seal.luau",
					"z-nile/tests/tooling/repo-fence.spec.luau",
					"scripts/hooks/pre-bash.sh",
					"z-nile/engine/publish.luau",
					"z-nile/engine/boundcmd.luau",
					"z-nile/check.sh",
					"zn",
				}
			do
				local found = false
				if table.find(light.PROTECTED.files, must) then
					found = true
				end
				for _, folder in light.PROTECTED.folders do
					if string.sub(must, 1, #folder) == folder then
						found = true
					end
				end
				t.expect(found).toBe(true)
			end
			for _, path in paths do
				local changed, why = light.judgeDiff(`1\t0\t{path}`)
				t.expect(changed <= 1).toBe(true)
				t.expect(
					has(why, `its diff changes {path}, a file that protects the repository and the pipeline`)
				)
					.toBe(true)
			end
			-- a near miss is not protected
			t.expect(select(2, light.judgeDiff("1\t0\tz-nile/engine/publish2.luau"))).toBe(nil)
			t.expect(select(2, light.judgeDiff("1\t0\tz-nile/lib/git-hooks"))).toBe(nil)
			t.expect(select(2, light.judgeDiff("1\t0\tscripts/hooks.sh"))).toBe(nil)
		end
	)

	it(
		"AC2: a light raft goes from restack to trace with no review action; a non-light single raft still reviews",
		function()
			local lightRaft = raft("R0200", { light = true })
			local d = work.forRaft(lightRaft)
			t.expect(d.action).toBe("final-review")
			t.expect(has(d.why, "ONLY review")).toBe(true)
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
			t.expect(has(first.why, "apply zz-review code mode's checks too")).toBe(true)
			t.expect(
				has(
					first.why,
					"Run it on a model other than the one that built it (./zn model final-review --for R0200 names it)"
				)
			).toBe(true)
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
			-- F10: the unnamed pick answers ready <issue> where it would have answered rafting; a ticket with no light
			-- fact (no risk: easy) keeps rafting, and the lowest id wins among the two
			local unnamed = work.decide({ rafts = {}, issues = { issue("c0090", { light = true }) } })
			t.expect(unnamed.action).toBe("ready")
			t.expect(unnamed.ticket).toBe("c0090")
			t.expect(has(unnamed.why, "./zn ready c0090")).toBe(true)
			local plain = work.decide({ rafts = {}, issues = { issue("c0090", {}) } })
			t.expect(plain.action).toBe("rafting")
			local mixed = { issue("c0090", {}), issue("c0095", { light = true }) }
			t.expect(work.decide({ rafts = {}, issues = mixed }).ticket).toBe("c0090")
			t.expect(work.decide({ rafts = {}, issues = mixed }).action).toBe("rafting")
			local lowLight = { issue("c0090", { light = true }), issue("c0095", {}) }
			t.expect(work.decide({ rafts = {}, issues = lowLight }).action).toBe("ready")
			-- an unsized light ticket is still ready, not sized first
			t.expect(
				work.decide({ rafts = {}, issues = { issue("c0090", { light = true, sized = false }) } }).action
			)
				.toBe("ready")
			-- F10: a named issue is answered the same way
			local named =
				work.decide({ asked = "c0090", rafts = {}, issues = { issue("c0090", { light = true }) } })
			t.expect(named.action).toBe("ready")
			t.expect(named.ticket).toBe("c0090")
			local namedPlain = work.decide({ asked = "c0090", rafts = {}, issues = { issue("c0090", {}) } })
			t.expect(namedPlain.action).toBe("rafting")
		end
	)

	it(
		"AC1 and AC3, end to end: ready makes the single raft in one tracker commit; done lands with no review-NNN.md",
		function()
			local f, env = build("f0420-light-e2e-github.com", {
				c0010 = ticket("c0010", "risk: easy", "Overrides: none"),
				c0020 = ticket("c0020", "risk: normal", "Overrides: none"),
				c0030 = ticket("c0030", "", "Overrides: none"),
			}, { [".models.toml"] = legacyroot.text(TOP) })
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

			-- F3: a layer that edits the ticket's risk to normal: the walk answers review, with the reason
			local docFile = `{wt}/pickman/.tracker/issues/active/c0010/c0010.md`
			local original = fs.readFile(docFile)
			fs.writeFile(docFile, (string.gsub(original, "risk: easy", "risk: normal")))
			git(wt, { "commit", "-qam", "edit risk" })
			local edited = zn({ "work", "next", rid, "--one" })
			t.expect(has(edited.stdout, "review")).toBe(true)
			t.expect(
				has(edited.stdout, "took the light path but is not light now: its risk is normal, not easy")
			)
				.toBe(true)
			git(wt, { "reset", "-q", "--hard", topSha })

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
			-- the dispatcher's final-mode review of this raft: its only review, never on the model that wrote the code
			local plan = zn({ "dispatch", "zz-review", rid, "--mode", "final", "--dry-run" })
			t.expect(plan.ok).toBe(true)
			t.expect(
				has(
					plan.stdout,
					`light path: this final review is the only review of {rid}; another model than claude-sonnet-5-5-high, the model that wrote the code, is preferred`
				)
			).toBe(true)
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

	it("ready <issue> writes the ticket's tributary on the single raft it makes", function()
		local f, env = build("f0420-light-tributary-github.com", {
			c0010 = ticket("c0010", "risk: easy\ntributary: worker", "Overrides: none"),
		}, { [".models.toml"] = sameModelToml() })
		local _, mainOk = runner(f, f.main, env)
		local said = mainOk({ "ready", "c0010" })
		local rid = string.match(said, "readied (R%d+)") :: string
		git(f.main, { "fetch", "-q", "origin" })
		local doc = git(f.main, { "show", `origin/main:pickman/.tracker/rafts/active/{rid}/{rid}.md` })
		t.expect(has(doc, "\ntributary: worker\n")).toBe(true)
	end)

	it(
		"done refuses a raft that took the light path and is not light, until the code review is filed",
		function()
			local f, env = build("f0420-light-grow-github.com", {
				c0010 = ticket("c0010", "risk: easy", "Overrides: none"),
			}, { [".models.toml"] = sameModelToml() })
			-- F4b: stop gives the claim back and `ready <R>` re-readies it by the normal path, with no trailer: the raft
			-- document still says light: true, so done still guards it
			local rid, wt, zn = start(f, env, "c0010", light.BOUND + 20, { reready = true })
			git(f.main, { "fetch", "-q", "origin" })
			local reready =
				git(f.main, { "log", "-1", "--format=%B", `--grep=^tracker: ready {rid} `, "origin/main" })
			t.expect(has(reready, "Light: true")).toBe(false)
			t.expect(has(reready, "Lands: approved")).toBe(true)
			t.expect(
				has(
					git(f.main, { "show", `origin/main:pickman/.tracker/rafts/active/{rid}/{rid}.md` }),
					"light: true"
				)
			).toBe(true)
			local plan = zn({ "dispatch", "zz-review", rid, "--mode", "final", "--dry-run" })
			t.expect(plan.ok).toBe(true)
			t.expect(has(plan.stdout, "light path:")).toBe(false)
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
			-- F4: a branch cannot unmark its raft: deleting the light: line from the layer's raft document changes nothing
			local raftDocPath = wt .. `/pickman/.tracker/rafts/active/{rid}/{rid}.md`
			fs.writeFile(raftDocPath, (string.gsub(fs.readFile(raftDocPath), "light: true\n", "")))
			commit("unmark")
			local unmarkedWalk = zn({ "work", "next", rid, "--one" })
			t.expect(has(unmarkedWalk.stdout, "took the light path but is not light now")).toBe(true)
			local unmarkedDone = zn({ "done", rid })
			t.expect(unmarkedDone.ok).toBe(false)
			t.expect(has(unmarkedDone.stderr, `{rid} took the light path`)).toBe(true)
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
				has(overrides.stderr, "but is not light: its Regression guard does not say Overrides: none")
			)
				.toBe(true)
			fs.writeFile(docPath, (string.gsub(fs.readFile(docPath), "risk: easy", "risk: normal")))
			commit("risk")
			local risk = zn({ "done", rid })
			t.expect(risk.ok).toBe(false)
			-- c0435: risk: is part of the approval contract, so the edit is refused as a changed approval before the light
			-- rule names it; either way the refusal names the risk
			t.expect(has(risk.stderr, "waits for approval: c0010 (changed: risk)")).toBe(true)
			-- F3: the walk reads the same copy of the ticket (the layer's), so it says the same, and asks for the review
			local sameWalk = zn({ "work", "next", rid, "--one" })
			t.expect(has(sameWalk.stdout, "review")).toBe(true)
			t.expect(has(sameWalk.stdout, "is not light now: its risk is normal, not easy")).toBe(true)
			-- with the code review filed, the refusal is gone (done goes on to its other checks)
			write(
				wt,
				`pickman/.tracker/rafts/active/{rid}/review-001.md`,
				"# Review 001\n\nVerdict: approve\n"
			)
			commit("code review")
			local reviewed = zn({ "done", rid })
			t.expect(has(reviewed.stderr, "took the light path")).toBe(false)
			-- N4: `./zn model final-review --for <R>` knows the implementation author of a light raft: its own model is allowed,
			-- not preferred, and the line says so (owner, 2026-11-24)
			local modeled = zn({ "model", "final-review", "--for", rid, "--cli", "claude" })
			t.expect(modeled.ok).toBe(true)
			-- the builder is only guessed here (no spend row names it): no same-model field, and a line saying so
			t.expect(has(modeled.stdout, "same-model")).toBe(false)
			t.expect(has(modeled.stderr, "the builder's model is a guess")).toBe(true)
			-- the builder's model unknown (no implementation role): the line, and a second line saying why
			local noImpl = string.gsub(sameModelToml(), "%[roles%.implementation%].-\n\n", "", 1)
			trackerfix.elsewhere(f, { [".models.toml"] = noImpl }, "no implementation role")
			git(f.main, { "fetch", "-q", "origin" })
			local unknown = zn({ "model", "final-review", "--for", rid, "--cli", "claude" })
			t.expect(unknown.ok).toBe(true)
			t.expect(has(unknown.stdout, "claude-sonnet-5-5")).toBe(true)
			t.expect(has(unknown.stderr, "the builder's model could not be read")).toBe(true)
		end
	)

	it("F4a: a single raft made the normal way for an easy ticket keeps its code review", function()
		local plainRaft = table.concat({
			"---",
			"id: R0040",
			"type: chore",
			"title: plain single",
			"slug: plain-single",
			"single: true",
			"issues: [c0040]",
			"design: ready",
			"created: 2026-11-11",
			`status: {PREPARED}`,
			"---",
			"",
			"# R0040: plain single",
			"",
			"## Order & dependencies",
			"c0040",
			"",
		}, "\n")
		local f, env = build("f0420-light-plain-github.com", {
			c0040 = ticket("c0040", "risk: easy", "Overrides: none", { raft = "R0040" }),
		}, {
			[".models.toml"] = sameModelToml(),
			["pickman/.tracker/rafts/R0040/R0040.md"] = plainRaft,
			["pickman/.tracker/rafts/R0040/check.sh"] = CHECK,
			-- c0435: an easy ticket that is not on the light path has the design review the full path asks for
			["pickman/.tracker/issues/c0040/design-review-001.md"] = "# Review 001\n\nVerdict: approve\n",
		})
		local rid, _, zn = start(f, env, "c0040", 3, { raft = "R0040" })
		local walked = zn({ "work", "next", rid, "--one" })
		t.expect(has(walked.stdout, "review")).toBe(true)
		t.expect(has(walked.stdout, "Run code review round 1")).toBe(true)
		t.expect(has(walked.stdout, "ONLY review")).toBe(false)
		t.expect(has(walked.stdout, "took the light path")).toBe(false)
		-- N4: a raft that is not marked light keeps today's `model` answer, even on the writer's model
		local modeled = zn({ "model", "final-review", "--for", rid, "--cli", "claude" })
		t.expect(modeled.ok).toBe(true)
		t.expect(has(modeled.stdout, "claude-sonnet-5-5")).toBe(true)
	end)

	it(
		"ready <issue> refuses what is not light, is listed by a raft, or has no raft: line, and publishes nothing",
		function()
			local listing = table.concat({
				"---",
				"id: R0007",
				"type: chore",
				"title: grouping",
				"slug: grouping",
				"single: false",
				"issues: [c0016]",
				"design: ready",
				"created: 2026-11-11",
				`status: preparing-quiet-copper-falcon`,
				"---",
				"",
				"# R0007: grouping",
				"",
			}, "\n")
			local guard = "Overrides: none"
			local f, env = build("f0420-light-refuse-github.com", {
				c0011 = ticket(
					"c0011",
					"risk: easy",
					"Overrides:\n- `z-nile/tests/acceptance/d0415/dispatch.spec.luau`"
				),
				c0012 = ticket("c0012", "risk: easy", guard, { depends = "c0099" }),
				c0013 = ticket("c0013", "risk: easy", guard, { design = "draft" }),
				c0014 = ticket("c0014", "risk: easy", guard, { status = "new-amber-otter-marble" }),
				c0015 = ticket("c0015", "risk: easy", guard),
				c0016 = ticket("c0016", "risk: easy", guard),
				c0017 = ticket("c0017", "risk: easy", guard, { noRaftLine = true }),
				c0018 = ticket("c0018", "risk: easy", guard),
				c0019 = ticket("c0019", "risk: easy", guard),
				c0099 = ticket("c0099", "", guard),
			}, {
				["pickman/.tracker/rafts/R0007/R0007.md"] = listing,
				["pickman/.tracker/rafts/R0007/check.sh"] = CHECK,
				["pickman/.tracker/issues/c0018/check.sh"] = "#!/usr/bin/env bash\nfinish\n",
			})
			local zn = runner(f, f.main, env)
			local before = git(f.main, { "rev-parse", "origin/main" })
			local function refused(args: { string }, needle: string, extraEnv: { [string]: string }?)
				local merged = table.clone(env)
				for k, v in (extraEnv or {}) :: { [string]: string } do
					merged[k] = v
				end
				local r = trackerfix.tr(f, f.main, args, merged)
				t.expect(r.ok).toBe(false)
				t.expect(has(r.stderr, needle)).toBe(true)
				git(f.main, { "fetch", "-q", "origin" })
				t.expect(git(f.main, { "rev-parse", "origin/main" })).toBe(before)
			end
			local prefix =
				" has no raft: z-raft makes one (./zn raft-plan). It does not take the light path: "
			refused({ "ready", "c0011" }, `c0011{prefix}its Regression guard does not say Overrides: none`)
			refused({ "ready", "c0012" }, `c0012{prefix}a dependency has not landed`)
			refused({ "ready", "c0013" }, `c0013{prefix}its design is not ready`)
			refused({ "ready", "c0014" }, `c0014{prefix}it is new in backlog, not prepared in the backlog`)
			refused({ "ready", "c0017" }, `c0017{prefix}its document has no raft: line: add an empty one`)
			refused({ "ready", "c0015", "--on", "R0007" }, "the light path (ready <issue>) takes no --on")
			refused({ "ready", "c0015" }, "not for ./zn dispatch", { ZN_DISPATCH = "1" })
			refused({ "ready", "c0016" }, "c0016 is listed by R0007: z-raft is grouping it")
			refused({ "ready", "c0018" }, "c0018 has no check")
			-- N1: the walk does not answer ready for what ready refuses (listed by a raft; no check line), and asking
			-- twice gives the same answer
			for _, id in { "c0016", "c0018" } do
				local first = zn({ "work", "next", id })
				local second = zn({ "work", "next", id })
				t.expect(has(first.stdout, `{id}: ready`)).toBe(false)
				t.expect(first.stdout).toBe(second.stdout)
			end
			t.expect(has(zn({ "work", "next", "c0016" }).stdout, "is being grouped by R0007 (z-raft)"))
				.toBe(true)
			-- the unnamed pick offers the one ticket ready accepts, never the refused ones
			local unnamed = zn({ "work", "next" })
			t.expect(has(unnamed.stdout, "ready")).toBe(true)
			for _, id in { "c0016", "c0018", "c0011", "c0012", "c0013", "c0014", "c0017" } do
				t.expect(has(unnamed.stdout, `{id}: ready`)).toBe(false)
			end
			-- and the one that is light is readied (the fixture is not spoiled by the refusals)
			t.expect(has(zn({ "ready", "c0019" }).stdout, "readied R")).toBe(true)
		end
	)

	it(
		"F8: the size is the diff from the merge base, so a moved main does not count its own commits",
		function()
			local base = `{TOP}/z-nile/.cache/f0420-light-diff`
			if fs.isDir(base) then
				fs.removeDir(base)
			end
			fs.writeDir(base)
			process.exec("git", { "init", "-q", "-b", "main", base }) -- raw: init to a named path
			git(base, { "config", "user.name", "t" })
			git(base, { "config", "user.email", "t@example.invalid" })
			write(base, "src/a.luau", "return 1\n")
			git(base, { "add", "-A" })
			git(base, { "commit", "-qm", "base" })
			local cut = git(base, { "rev-parse", "HEAD" })
			git(base, { "switch", "-q", "-c", "layer" })
			write(base, "src/b.luau", "return 2\n")
			git(base, { "add", "-A" })
			git(base, { "commit", "-qm", "layer" })
			local tip = git(base, { "rev-parse", "HEAD" })
			git(base, { "switch", "-q", "main" })
			local lines: { string } = {}
			for i = 1, 300 do
				table.insert(lines, `return {i}`)
			end
			write(base, "src/c.luau", table.concat(lines, "\n") .. "\n")
			git(base, { "add", "-A" })
			git(base, { "commit", "-qm", "main moved" })
			local moved = git(base, { "rev-parse", "HEAD" })
			local numstat = git(base, lightgit.diffArgs(moved, tip))
			t.expect((light.judgeDiff(numstat))).toBe(1)
			t.expect(lightgit.diffArgs(cut, tip))
				.toEqual({ "diff", "--numstat", "--no-renames", `{cut}...{tip}` })
			-- the two-dot diff is what counted main's commits reversed
			t.expect((light.judgeDiff(git(base, { "diff", "--numstat", `{moved}..{tip}` })))).toBe(301)
		end
	)

	it("F7: the light final review never runs on the model that wrote the code", function()
		local text = legacyroot.text(TOP)
		local layer = models.parse(text, ".models.toml")
		local plain = models.resolve({ layer }, "zz-review", "final")
		t.expect(plain.authorModel).toBe(nil)
		local lightFinal = models.resolve({ layer }, "zz-review", "final", true)
		local implementation = models.resolveRole({ layer }, "implementation")
		t.expect(lightFinal.authorModel).toBe(models.id(implementation.specs[implementation.order[1]]))
		-- the code-review role keeps its own exclusion, and a light flag changes no other role
		t.expect(models.resolve({ layer }, "zz-review", "code", true).authorModel)
			.toBe(models.resolve({ layer }, "zz-review", "code").authorModel)
		-- when the final role's only model is the writer's, it has no one to run on
		local same = string.gsub(
			text,
			'%[roles.final%-review%]\nmodel = "[^"]+"',
			`[roles.final-review]\nmodel = "{implementation.specs[implementation.order[1]].model}"`
		)
		local sameLayer = models.parse(same, ".models.toml")
		local excluded = models.tries(models.resolve({ sameLayer }, "zz-review", "final", true))
		for _, spec in excluded do
			t.expect(models.id(spec) == models.id(implementation.specs[implementation.order[1]])).toBe(false)
		end
	end)

	it(
		"the dispatcher's model step asks the same reader for the light flag, for its prompt and its model",
		function()
			local text = fs.readFile(`{TOP}/z-nile/engine/dispatcher.luau`)
			local at = string.find(text, "function dispatcher.modelStep", 1, true) :: number
			local body = string.sub(text, at, at + 3000)
			t.expect(has(body, "local lightFinal = dispatcher.lightFinal(step, mode, id)")).toBe(true)
			t.expect(has(body, "dispatcher.resolve(step, id, project, mode, lightFinal)")).toBe(true)
			t.expect(has(text, "light = lightFinal,")).toBe(true)
		end
	)

	it(
		"N2: the protected table lists every file that guards the repository and the pipeline, and every path exists",
		function()
			for _, must in
				{
					"zn",
					".models.toml",
					".claude/settings.json",
					"z-nile/check.sh",
					"z-nile/affected.luau",
					"z-nile/specs.luau",
					"z-nile/lib/fence.sh",
					"z-nile/lib/ac.sh",
					"z-nile/lib/watch.luau",
					"z-nile/lib/bounded.pl",
					"z-nile/lib/cpu.sh",
					"z-nile/tests/run.luau",
					"z-nile/tests/lib/fence.luau",
					"z-nile/tests/lib/seal.luau",
					"z-nile/tests/tooling/repo-fence.spec.luau",
					"z-nile/engine/light.luau",
					"z-nile/engine/lightgit.luau",
					"z-nile/engine/publish.luau",
					"z-nile/engine/boundcmd.luau",
					"z-nile/engine/trackerstate.luau",
					"z-nile/engine/broker.luau",
					"z-nile/engine/closing.luau",
					"z-nile/engine/paths.luau",
					"z-nile/engine/ids.luau",
					"z-nile/engine/credential.luau",
					"z-nile/engine/agentenv.luau",
					"z-nile/engine/reap.luau",
					"z-nile/engine/approval.luau",
					"z-nile/engine/contract.luau",
					"z-nile/engine/approvewalk.luau",
					"z-nile/engine/approverun.luau",
					"z-nile/engine/approveplace.luau",
					"scripts/check.sh",
					"z-nile/lib/git-hooks/pre-commit",
					"scripts/hooks/pre-bash.sh",
					"z-nile/bin/git",
					".github/workflows/deploy.yml",
					"z-nile/go/go.mod",
				}
			do
				t.expect(
					has(
						select(2, light.judgeDiff(`1\t0\t{must}`)),
						`its diff changes {must}, a file that protects`
					)
				).toBe(true)
			end
			-- a rename of a protected file cannot silently unprotect it: every path in the table is a real file or folder
			for _, file in light.PROTECTED.files do
				t.expect(fs.isFile(`{TOP}/{file}`)).toBe(true)
			end
			for _, folder in light.PROTECTED.folders do
				t.expect(fs.isDir(`{TOP}/{folder}`)).toBe(true)
			end
			-- every registered project's check.sh is protected, read from the registry (not a list of names)
			local homes = lightgit.homesOf(fs.readFile(`{TOP}/z-nile/projects.toml`))
			t.expect(#homes >= 6).toBe(true)
			for _, home in homes do
				t.expect(
					has(
						select(2, light.judgeDiff(`1\t0\t{home}/check.sh`, homes)),
						`its diff changes {home}/check.sh`
					)
				).toBe(true)
				t.expect(fs.isFile(`{TOP}/{home}/check.sh`)).toBe(true)
			end
			-- a 3-line edit to the light rule itself is not light, and names the file
			local why = select(2, light.judgeDiff("2\t1\tz-nile/engine/light.luau"))
			t.expect(has(why, "its diff changes z-nile/engine/light.luau")).toBe(true)
		end
	)

	it("F2 residual: a spec is exempt only under a tests/ folder or a ticket's own tracker folder", function()
		t.expect((light.judgeDiff("900\t0\tz-nile/engine/evil.spec.luau"))).toBe(900)
		t.expect((light.judgeDiff("900\t0\tpickman/src/evil.spec.luau"))).toBe(900)
		t.expect((light.judgeDiff("900\t0\tz-nile/tests/tooling/ok.spec.luau"))).toBe(0)
		t.expect((light.judgeDiff("900\t0\tpickman/tests/unit/ok.spec.luau"))).toBe(0)
		t.expect((light.judgeDiff("900\t0\tz-nile/.tracker/issues/active/c0001/acceptance/a.spec.luau")))
			.toBe(0)
	end)

	it("F1 residual: contradictory or odd guards are not light", function()
		local function guard(body: string): string
			return `---\nraft: \n---\n\n## Regression guard\n{body}\n\n## Test plan\nx\n`
		end
		for _, other in
			{
				"Overrides: none\n\n- `z-nile/tests/acceptance/a/b.spec.luau`",
				"Overrides: none\n\n- z-nile/tests/tooling/x.spec.luau is changed",
				"Override: none",
				"_Overrides_: none",
				"Overridden specs: none",
				"Overrides: none\nOverridden specs: `x`",
				"| Overrides | none |\n|---|---|",
				"overrides: none",
				"Overrides: none\nNo overrides, really.",
			}
		do
			t.expect(light.overridesNone(guard(other))).toBe(false)
		end
		t.expect(light.overridesNone(guard("Overrides: none") .. "\n## Regression guard\nOverrides: none\n"))
			.toBe(false)
		t.expect(light.overridesNone("## Regression guard\nOverrides: none\n### Regression guard\nx\n"))
			.toBe(false)
		t.expect(light.overridesNone(guard("Overrides: none"))).toBe(true)
	end)

	it(
		"N1: a ticket a not-done raft lists is waited on, not answered ready, and asking twice repeats nothing",
		function()
			local listed = issue("c0090", {
				light = false,
				lightWhy = "c0090 is listed by R0007: z-raft is grouping it",
				groupedBy = "R0007",
			})
			local one = work.decide({ rafts = {}, issues = { listed } })
			t.expect(one.action ~= "ready").toBe(true)
			t.expect(one.action ~= "rafting").toBe(true)
			t.expect(one.ticket ~= "c0090" or one.action == "none").toBe(true)
			local r = raft("R0100", {
				where = "backlog",
				status = "prepared",
				issues = { "c0100" },
				outside = { "c0090" },
				depsMet = false,
				layers = {},
				stacked = false,
			})
			local named = work.decide({
				asked = "R0100",
				rafts = { r },
				issues = { issue("c0100", { raft = "R0100", deps = { "c0090" } }), listed },
			})
			t.expect(named.action ~= "ready").toBe(true)
			t.expect(has(named.why, "c0090 is being grouped by R0007 (z-raft)")).toBe(true)
			local again = work.decide({
				asked = "R0100",
				rafts = { r },
				issues = { issue("c0100", { raft = "R0100", deps = { "c0090" } }), listed },
			})
			t.expect(again.action).toBe(named.action)
			t.expect(again.why).toBe(named.why)
		end
	)

	it(
		"c0435 review 2 F1: a final review that says Level: normal stops the raft, and the raise lives on main",
		function()
			local f, env = build("c0435-raise-github.com", {
				c0010 = ticket("c0010", "risk: easy", "Overrides: none"),
			})
			local rid, wt, zn, ok = start(f, env, "c0010", 3)
			write(
				wt,
				`pickman/.tracker/rafts/active/{rid}/final-review-001.md`,
				`# Review 001: {rid} (final mode)\n\nVerdict: changes\nLevel: normal\n\n## Findings\n- F1 (high): this changes a gate\n`
			)
			git(wt, { "add", "-A" })
			git(wt, { "commit", "-qm", "final review says not easy" })
			git(wt, { "push", "-q" })
			-- the walk does not ask for a code review round: it says to stop the raft, with the reason
			local walked = zn({ "work", "next", rid, "--one" })
			t.expect(has(walked.stdout, "Run code review round 1")).toBe(false)
			t.expect(has(walked.stdout, `./zn stop {rid}`)).toBe(true)
			t.expect(has(walked.stdout, "not easy")).toBe(true)
			-- done refuses it
			local refused = zn({ "done", rid })
			t.expect(refused.ok).toBe(false)
			t.expect(has(refused.stderr, "not easy")).toBe(true)
			-- stop publishes the raise in one move and takes the ticket out of the raft, back at the design step
			local _, mainOk = runner(f, f.main, env)
			mainOk({ "stop", rid })
			git(f.main, { "fetch", "-q", "origin" })
			local doc = git(f.main, { "show", "origin/main:pickman/.tracker/issues/c0010/c0010.md" })
			t.expect(has(doc, "\nrisk: normal\n")).toBe(true)
			t.expect(has(doc, "\ndesign: draft\n")).toBe(true)
			t.expect(has(doc, "\nraft: \n") or has(doc, "\nraft:\n")).toBe(true)
			local zmain = runner(f, f.main, env)
			local next = zmain({ "work", "next", "c0010" })
			t.expect(has(next.stdout, "c0010: draft")).toBe(true)
			-- the old branch cannot land it, whatever its final review says now
			write(
				wt,
				`pickman/.tracker/rafts/active/{rid}/final-review-002.md`,
				`# Review 002\n\nVerdict: approve\n`
			)
			git(wt, { "add", "-A" })
			git(wt, { "commit", "-qm", "an approving review without the Level line" })
			git(wt, { "push", "-q" })
			local landed = zn({ "done", rid })
			t.expect(landed.ok).toBe(false)
			t.expect(ok ~= nil).toBe(true)
		end
	)

	it(
		"c0435 review 3 A: a Level line that is no level refuses done, the walk and stop, never falls through",
		function()
			local f, env = build("c0435-levelbad-github.com", {
				c0010 = ticket("c0010", "risk: easy", "Overrides: none"),
			})
			local rid, wt, zn = start(f, env, "c0010", 3)
			write(
				wt,
				`pickman/.tracker/rafts/active/{rid}/final-review-001.md`,
				`# Review 001: {rid} (final mode)\n\nVerdict: approve\nLevel: hard\n`
			)
			git(wt, { "add", "-A" })
			git(wt, { "commit", "-qm", "a Level line that is no level" })
			git(wt, { "push", "-q" })
			local walked = zn({ "work", "next", rid, "--one" })
			t.expect(has(walked.stdout, "Level: hard")).toBe(true)
			t.expect(has(walked.stdout, "Run code review round 1")).toBe(false)
			local refused = zn({ "done", rid })
			t.expect(refused.ok).toBe(false)
			t.expect(has(refused.stderr, "Level: hard")).toBe(true)
			-- outright: it does not send the author to the code review
			t.expect(has(refused.stderr, "run the code review")).toBe(false)
			t.expect(has(refused.stderr, "fix the review's Level line")).toBe(true)
			local zmain = runner(f, f.main, env)
			local stopped = zmain({ "stop", rid })
			t.expect(stopped.ok).toBe(false)
			t.expect(has(stopped.stderr, "Level: hard")).toBe(true)
		end
	)

	it(
		"c0435 review 3 B/C: a risk already raised on main still stops, and the emptied raft is not offered",
		function()
			local f, env = build("c0435-already-github.com", {
				c0010 = ticket("c0010", "risk: easy", "Overrides: none"),
			})
			local rid, wt = start(f, env, "c0010", 3)
			write(
				wt,
				`pickman/.tracker/rafts/active/{rid}/final-review-001.md`,
				`# Review 001: {rid} (final mode)\n\nVerdict: changes\nLevel: normal\n\n## Findings\n- F1 (high): a gate\n`
			)
			git(wt, { "add", "-A" })
			git(wt, { "commit", "-qm", "not easy" })
			git(wt, { "push", "-q" })
			-- the author followed the old advice first: risk: raised by a tracker change on main
			local docPath = `{f.main}/pickman/.tracker/issues/active/c0010/c0010.md`
			git(f.main, { "pull", "-q", "origin", "main" })
			fs.writeFile(docPath, (string.gsub(fs.readFile(docPath), "risk: easy", "risk: normal")))
			git(f.main, { "add", "-A" })
			git(f.main, { "commit", "-qm", "tracker: raise c0010" })
			git(f.main, { "push", "-q", "origin", "HEAD:main" })
			local zmain, mainOk = runner(f, f.main, env)
			mainOk({ "stop", rid })
			git(f.main, { "fetch", "-q", "origin" })
			local doc = git(f.main, { "show", "origin/main:pickman/.tracker/issues/c0010/c0010.md" })
			t.expect(has(doc, "\nrisk: normal\n")).toBe(true)
			t.expect(has(doc, "\ndesign: draft\n")).toBe(true)
			local nextOne = zmain({ "work", "next" })
			t.expect(has(nextOne.stdout, rid)).toBe(false)
			t.expect(has(nextOne.stdout, "c0010: draft")).toBe(true)
		end
	)

	it(
		"c0435 review 3 G: a ticket captured with risk: easy resolves its design model at the easy level",
		function()
			local f, env = build("c0435-capture-github.com", {
				c0010 = ticket(
					"c0010",
					"risk: easy",
					"Overrides: none",
					{ design = "draft", status = "new-quiet-copper-falcon" }
				),
			}, { [".models.toml"] = sameModelToml() })
			local zn = runner(f, f.main, env)
			local said = zn({ "model", "design", "--for", "c0010", "--cli", "claude" })
			t.expect(said.ok).toBe(true)
			t.expect(has(said.stdout, "level=easy")).toBe(true)
		end
	)
end)
