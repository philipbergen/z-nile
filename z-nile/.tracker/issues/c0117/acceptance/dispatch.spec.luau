--!strict
-- c0117 AC3, AC4, AC5: which steps are scripts and which need a model (every z-nile skill classified, an unknown
-- name an error), the prompt a model step gets (the skill's file and the lessons command, nothing pasted), and the
-- chain: from an item's tracker state, the next step, merge or stop. Pure: dispatch.luau.
local dispatch = require("@znile/engine/dispatch")
local fs = require("@lune/fs")
local t = require("@tests/lib/t")

local function has(text: string, needle: string): boolean
	return string.find(text, needle, 1, true) ~= nil
end
local function errorOf(f: () -> ()): string
	local ok: boolean, e: any = pcall(f)
	if ok then
		error("expected an error", 2)
	end
	return tostring(e)
end

-- a fact sheet with every field, defaulting to a new issue with nothing open
local function facts(over: { [string]: any }): dispatch.Facts
	local f: { [string]: any } = {
		id = "c0010",
		kind = "issue",
		where = "backlog",
		status = "new",
		design = "draft",
		raft = "",
		ownClaim = false,
		localRaft = "",
		pr = nil,
		questions = false,
		last = nil,
		uncovered = {},
		autoMerge = { "prep", "raft" },
		description = nil,
	}
	for k, v in over do
		f[k] = v
	end
	return f :: any
end
local function pr(over: { [string]: any }?): dispatch.Pr
	local p: { [string]: any } = { number = 7, state = "OPEN", draft = false, green = true, mergeable = true }
	local more_over: { [string]: any } = over or {}
	for k, v in more_over do
		p[k] = v
	end
	return p :: any
end
local function act(f: dispatch.Facts): string
	local a = dispatch.next(f)
	if a.kind == "step" then
		return `step {a.step} {a.target}`
	elseif a.kind == "merge" then
		return `merge {a.gate} {a.pr}`
	end
	return `stop {a.code}{if a.gate then " " .. a.gate else ""}`
end

return t.spec("c0117 dispatch rules", function(it)
	it(
		"ready, stop, recombine and spend are script steps; every z-nile skill is a step or read inside one",
		function()
			for _, name in
				{ "z-ready", "z-stop", "recombine", "spend", "raft-plan", "fold", "release", "zz-stats" }
			do
				t.expect(dispatch.step(name).kind).toBe("script")
			end
			for _, name in { "z-ticket", "z-design", "z-raft", "z-run", "zz-review" } do
				t.expect(dispatch.step(name).kind).toBe("model")
			end
			for _, name in fs.readDir("z-nile/skills") do
				if fs.isFile(`z-nile/skills/{name}/SKILL.md`) then
					local ok, e = pcall(dispatch.step, name)
					t.expect(ok or (dispatch.READ_INSIDE[name] == true and has(tostring(e), "read inside")))
						.toBe(true)
				end
			end
			t.expect(has(
				errorOf(function()
					dispatch.step("zz-rules")
				end),
				"not a step"
			)).toBe(true)
			t.expect(has(
				errorOf(function()
					dispatch.step("pickman-arch")
				end),
				"project's skill"
			)).toBe(true)
			t.expect(has(
				errorOf(function()
					dispatch.step("z-deploy")
				end),
				"unknown step z-deploy"
			)).toBe(true)
		end
	)

	it("a script step is a ./zn command, and takes no model", function()
		t.expect(dispatch.scriptArgv("z-ready", "R0040")).toEqual({ "./zn", "ready", "R0040" })
		t.expect(dispatch.scriptArgv("z-stop", "R0040")).toEqual({ "./zn", "stop", "R0040" })
		t.expect(dispatch.scriptArgv("raft-plan", "c0010")).toEqual({ "./zn", "raft-plan", "--apply" })
		t.expect(has(
			errorOf(function()
				dispatch.lessonsOf("z-ready")
			end),
			"takes no model"
		)).toBe(true)
		t.expect(has(
			errorOf(function()
				dispatch.scriptArgv("z-design", "c0010")
			end),
			"model step"
		)).toBe(true)
	end)

	it("a model step reads the design or build lessons, and its row has its phase", function()
		t.expect(dispatch.lessonsOf("z-ticket")).toBe("design")
		t.expect(dispatch.lessonsOf("z-design")).toBe("design")
		t.expect(dispatch.lessonsOf("z-raft")).toBe("design")
		t.expect(dispatch.lessonsOf("z-run")).toBe("build")
		t.expect(dispatch.lessonsOf("zz-review", "design")).toBe("design")
		t.expect(dispatch.lessonsOf("zz-review", "raft")).toBe("design")
		t.expect(dispatch.lessonsOf("zz-review", "code")).toBe("build")
		t.expect(dispatch.phaseOf("z-ticket")).toBe("capture")
		t.expect(dispatch.phaseOf("z-design")).toBe("prep")
		t.expect(dispatch.phaseOf("z-run")).toBe("deliver")
		t.expect(dispatch.phaseOf("zz-review", "design")).toBe("design-review")
		t.expect(dispatch.phaseOf("zz-review", "code")).toBe("code-review")
		-- a stream's review under the dispatcher: the review model of the CLI, its row printed for the author
		t.expect(dispatch.lessonsOf("zz-review", "stream")).toBe("build")
		t.expect(dispatch.phaseOf("zz-review", "stream")).toBe("code-review")
		t.expect(has(
			errorOf(function()
				dispatch.lessonsOf("zz-review", "bogus")
			end),
			"no mode bogus"
		)).toBe(true)
	end)

	it("the prompt names the skill's file and the lessons command, and pastes no skill text", function()
		local p = dispatch.prompt({
			step = "z-design",
			id = "c0010",
			skillPath = "z-nile/skills/z-design/SKILL.md",
			worktree = "/w/.worktree/prep-x",
			stateDir = "/w/.cache/dispatch/c0010",
		})
		t.expect(has(p, "`z-nile/skills/z-design/SKILL.md`")).toBe(true)
		t.expect(has(p, "`./zn lessons --when design --full`")).toBe(true)
		t.expect(has(p, "for c0010")).toBe(true)
		t.expect(has(p, "`/w/.worktree/prep-x`")).toBe(true)
		t.expect(has(p, "`/w/.cache/dispatch/c0010/questions.md`")).toBe(true)
		t.expect(has(p, "Never merge a pull request and never push to main")).toBe(true)
		t.expect(has(p, "without --tokens")).toBe(true)
		-- no line of the skill itself
		local skill = fs.readFile("z-nile/skills/z-design/SKILL.md")
		t.expect(has(p, string.match(skill, "\n(The goal is[^\n]+)") :: string)).toBe(false)
		local review = dispatch.prompt({
			step = "zz-review",
			id = "R0040",
			mode = "code",
			skillPath = "z-nile/skills/zz-review/SKILL.md",
			worktree = "/w/.worktree/R0040",
			stateDir = "/w/.cache/dispatch/R0040",
		})
		t.expect(has(review, "`./zn lessons --when build --full`")).toBe(true)
		t.expect(has(review, "in code mode")).toBe(true)
		local run = dispatch.prompt({
			step = "z-run",
			id = "R0040",
			skillPath = "z-nile/skills/z-run/SKILL.md",
			worktree = "/w/.worktree/R0040",
			stateDir = "/w/.cache/dispatch/R0040",
			promptPath = "/w/z-nile/.tracker/rafts/active/R0040/prompt.md",
		})
		t.expect(has(run, "`/w/z-nile/.tracker/rafts/active/R0040/prompt.md`")).toBe(true)
		t.expect(has(run, "`./zn lessons --when build --full`")).toBe(true)
	end)

	it(
		"stops first for questions.md, a failed step, and an unharvested finding after a review step",
		function()
			t.expect(act(facts({ questions = true }))).toBe("stop 3")
			t.expect(act(facts({ last = { step = "z-design", outcome = "cap" } }))).toBe("stop 1")
			t.expect(act(facts({ last = { step = "z-design", outcome = "quota" } }))).toBe("stop 1")
			local after = { step = "z-design", outcome = "ok" }
			t.expect(act(facts({
				status = "preparing",
				ownClaim = true,
				last = after,
				pr = pr(),
				uncovered = { "design-review-001 F1" },
			}))).toBe("stop 1")
			-- the same finding after a script step does not stop the chain
			t.expect(act(facts({
				status = "prepared",
				design = "ready",
				last = { step = "raft-plan", outcome = "ok" },
				localRaft = "R0050",
				uncovered = { "x" },
			}))).toBe("step z-raft R0050")
			t.expect(act(facts({ last = { step = "z-design", outcome = "tripwire" } }))).toBe("stop 5")
			t.expect(act(facts({ last = { step = "z-design", outcome = "lost" } }))).toBe("stop 1")
			t.expect(dispatch.MAX_ACTIONS).toBe(30)
			local a = dispatch.next(facts({ questions = true }))
			t.expect(has(a.why or "", "questions.md")).toBe(true)
		end
	)

	it("captures, designs, and waits at or passes the prep gate", function()
		t.expect(act(facts({ kind = "none", where = "none", status = "none", description = "words" })))
			.toBe("step z-ticket ")
		t.expect(act(facts({ kind = "none", where = "none", status = "none" }))).toBe("stop 1")
		t.expect(act(facts({}))).toBe("step z-design c0010")
		t.expect(act(facts({ status = "preparing", ownClaim = true }))).toBe("step z-design c0010")
		t.expect(act(facts({ status = "preparing", ownClaim = false }))).toBe("stop 1")
		t.expect(act(facts({ status = "preparing", ownClaim = true, pr = pr() }))).toBe("merge prep 7")
		t.expect(act(facts({ status = "preparing", ownClaim = true, pr = pr({ green = false }) })))
			.toBe("stop 4 prep")
		t.expect(act(facts({ status = "preparing", ownClaim = true, pr = pr({ draft = true }) })))
			.toBe("stop 4 prep")
		t.expect(act(facts({ status = "preparing", ownClaim = true, pr = pr({ mergeable = false }) })))
			.toBe("stop 4 prep")
		t.expect(act(facts({ status = "preparing", ownClaim = true, pr = pr(), autoMerge = { "raft" } })))
			.toBe("stop 4 prep")
		-- a merged PR origin does not show yet, or a closed one, stops instead of designing again
		t.expect(act(facts({ status = "preparing", ownClaim = true, pr = pr({ state = "MERGED" }) })))
			.toBe("stop 1")
		t.expect(act(facts({ status = "preparing", ownClaim = true, pr = pr({ state = "CLOSED" }) })))
			.toBe("stop 1")
		t.expect(act(facts({ status = "preparing", ownClaim = true, pr = pr(), autoMerge = {} })))
			.toBe("stop 4 prep")
	end)

	it("a step that ended ok but moved nothing stops the chain", function()
		local ok = function(step: string)
			return { step = step, outcome = "ok" }
		end
		t.expect(act(facts({ last = ok("z-design") }))).toBe("stop 1")
		t.expect(act(facts({ status = "preparing", ownClaim = true, last = ok("z-design") }))).toBe("stop 1")
		t.expect(act(facts({ status = "prepared", design = "ready", last = ok("raft-plan") }))).toBe("stop 1")
		t.expect(act(facts({ kind = "raft", id = "R0050", status = "prepared", last = ok("z-ready") })))
			.toBe("stop 1")
		t.expect(act(facts({
			kind = "raft",
			id = "R0050",
			where = "active",
			status = "active",
			last = ok("z-run"),
			pr = pr({ draft = true }),
		}))).toBe("stop 1")
	end)

	it("rafts a prepared issue: raft-plan, then z-raft, then the raft gate, then follows the raft", function()
		local prepared = { status = "prepared", design = "ready" }
		local function with(over: { [string]: any }): dispatch.Facts
			local all = table.clone(prepared) :: { [string]: any }
			for k, v in over do
				all[k] = v
			end
			return facts(all)
		end
		t.expect(act(with({}))).toBe("step raft-plan c0010")
		t.expect(act(with({ localRaft = "R0050", last = { step = "raft-plan", outcome = "ok" } })))
			.toBe("step z-raft R0050")
		t.expect(act(with({ localRaft = "R0050", last = { step = "z-raft", outcome = "ok" }, pr = pr() })))
			.toBe("merge raft 7")
		t.expect(act(with({ localRaft = "R0050", last = { step = "z-raft", outcome = "ok" } })))
			.toBe("stop 1")
		t.expect(act(with({ raft = "R0050" }))).toBe("step follow R0050")
		t.expect(act(facts({ where = "active", status = "active", raft = "R0050" })))
			.toBe("step follow R0050")
		t.expect(act(facts({ where = "done", status = "done" }))).toBe("stop 0")
	end)

	it("readies and runs a raft; the run's PR is always a human's to merge", function()
		local raft = { kind = "raft", id = "R0050" }
		local function with(over: { [string]: any }): dispatch.Facts
			local all = table.clone(raft) :: { [string]: any }
			for k, v in over do
				all[k] = v
			end
			return facts(all)
		end
		t.expect(act(with({ status = "prepared" }))).toBe("step z-ready R0050")
		t.expect(act(with({ status = "preparing" }))).toBe("stop 1")
		t.expect(act(with({ where = "active", status = "active" }))).toBe("step z-run R0050")
		t.expect(act(with({ where = "active", status = "active", pr = pr({ draft = true }) })))
			.toBe("step z-run R0050")
		-- green, mergeable and every gate auto-merged: still a stop at the run gate
		t.expect(
			act(
				with({ where = "active", status = "active", pr = pr(), autoMerge = { "prep", "raft", "run" } })
			)
		)
			.toBe("stop 4 run")
		local done = dispatch.next(with({ where = "done", status = "done" }))
		t.expect(done.kind).toBe("stop")
		t.expect(done.code).toBe(0)
		t.expect(done.step).toBe("flush")
	end)
end)
