--!strict
-- c0252 AC1 to AC4: the pure landing check (landcheck.luau) and the pull-request read (landread.parsePr). Every case
-- builds an Input from a clean one and breaks one thing; the exports are read through `any` because they do not exist
-- before c0252 (the spec type-checks without them).
local escalation = require("@znile/engine/escalation")
local t = require("@tests/lib/t")

local landcheck: any = require("@znile/engine/landcheck")
local landread: any = require("@znile/engine/landread")

local TIP = "aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa"

local function clean(): any
	return {
		raft = "R0010",
		layers = { { issue = "c0010" }, { issue = "c0020" } },
		through = nil,
		topIssue = "c0020",
		topTip = TIP,
		pr = {
			state = "OPEN",
			draft = true,
			head = TIP,
			mergeable = "UNKNOWN",
			checks = { { name = "deploy", state = "SKIPPED" } },
		},
		prError = nil,
		reviewProblem = nil,
		openHigh = {},
		traceProblems = {},
		approvalDrift = nil,
		verdictMissing = false,
		codeMoved = {},
		changedPaths = { "z-nile/engine/x.luau" },
		gameRoots = { "pickman", "snake" },
		cicd = true,
	}
end

local function codes(i: any): { string }
	local out: { string } = {}
	for _, p in landcheck.problems(i) do
		table.insert(out, p.code)
	end
	return out
end

local function kindOf(i: any, code: string): string?
	for _, p in landcheck.problems(i) do
		if p.code == code then
			return p.kind
		end
	end
	return nil
end

return t.spec("c0252 landcheck: the checks before a landing", function(it)
	it(
		"AC1: a clean input has no problem, and a draft layer pull request whose only check is SKIPPED is green",
		function()
			t.expect(codes(clean())).toEqual({})
		end
	)

	it("AC1: each failed check is one named problem of its kind", function()
		local cases: { { code: string, kind: string, mutate: (any) -> () } } = {
			{
				code = "layer-incomplete",
				kind = "redo",
				mutate = function(i: any)
					i.layers[1].incomplete = "c0010 is not complete: its review names another commit"
				end,
			},
			{
				code = "no-verdict",
				kind = "redo",
				mutate = function(i: any)
					i.verdictMissing = true
				end,
			},
			{
				code = "open-high",
				kind = "block",
				mutate = function(i: any)
					i.openHigh = { "F2" }
				end,
			},
			{
				code = "review-open",
				kind = "redo",
				mutate = function(i: any)
					i.reviewProblem = "findings not answered"
				end,
			},
			{
				code = "trace-stale",
				kind = "redo",
				mutate = function(i: any)
					i.traceProblems = { "trace line 3 names a commit that came after the table" }
				end,
			},
			{
				code = "approval-drift",
				kind = "block",
				mutate = function(i: any)
					i.approvalDrift = "c0010: contract changed since approval"
				end,
			},
			{
				code = "main-moved",
				kind = "redo",
				mutate = function(i: any)
					i.codeMoved = { "z-nile/engine/other.luau" }
				end,
			},
			{
				code = "cicd-missing",
				kind = "wait",
				mutate = function(i: any)
					i.changedPaths = { "pickman/src/server/Game.luau" }
					i.cicd = false
				end,
			},
			{
				code = "pr-unreadable",
				kind = "wait",
				mutate = function(i: any)
					i.pr = nil
					i.prError = "gh pr view R0010/2/c0020 failed"
				end,
			},
			{
				code = "pr-closed",
				kind = "block",
				mutate = function(i: any)
					i.pr.state = "CLOSED"
				end,
			},
			{
				code = "pr-head-moved",
				kind = "redo",
				mutate = function(i: any)
					i.pr.head = "bbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbb"
				end,
			},
			{
				code = "ci-failed",
				kind = "block",
				mutate = function(i: any)
					i.pr.checks = { { name = "static", state = "FAILURE" } }
				end,
			},
			{
				code = "ci-pending",
				kind = "wait",
				mutate = function(i: any)
					i.pr.checks = { { name = "static", state = "" } }
				end,
			},
			{
				code = "pr-conflicting",
				kind = "redo",
				mutate = function(i: any)
					i.pr.mergeable = "CONFLICTING"
				end,
			},
		}
		for _, c in cases do
			local i = clean()
			c.mutate(i)
			t.expect(codes(i)).toEqual({ c.code })
			t.expect(kindOf(i, c.code)).toBe(c.kind)
		end
	end)

	it("AC1: a game path with cicd present, and a tracker path in a game home, need nothing", function()
		local i = clean()
		i.changedPaths = { "pickman/src/server/Game.luau" }
		t.expect(codes(i)).toEqual({})
		i.cicd = false
		i.changedPaths = { "pickman/.tracker/issues/c0010/c0010.md", "z-nile/engine/x.luau" }
		t.expect(codes(i)).toEqual({})
		t.expect(landcheck.touchesGame({ "snake/src/a.luau" }, { "pickman", "snake" })).toBe(true)
		t.expect(landcheck.touchesGame({ "snakeish/src/a.luau" }, { "pickman", "snake" })).toBe(false)
	end)

	it("AC1: only code main gained is a problem; tracker state main gained is not (c0152)", function()
		t.expect(landcheck.isTracker("pickman/.tracker/issues/c0010/c0010.md")).toBe(true)
		t.expect(landcheck.isTracker("z-nile/.tracker/rafts/R0010/R0010.md")).toBe(true)
		t.expect(landcheck.isTracker("z-nile/engine/main.luau")).toBe(false)
		t.expect(landcheck.isTracker("z-nile/tests/.tracker/x")).toBe(false)
		t.expect(
			landcheck.codeOf({ "pickman/.tracker/issues/c0010/c0010.md", "z-nile/engine/main.luau", "" })
		)
			.toEqual({ "z-nile/engine/main.luau" })
	end)

	it("AC2: classify lands a clean input, blocks a block problem at once, and lets a wait wait", function()
		local ok = landcheck.classify(landcheck.problems(clean()), 0, 2)
		t.expect(ok.action).toBe("land")
		local i = clean()
		i.openHigh = { "F2" }
		i.pr.checks = { { name = "static", state = "" } }
		local v = landcheck.classify(landcheck.problems(i), 0, 2)
		t.expect(v.action).toBe("block")
		t.expect(v.reason).toBe("review-exhausted")
		local w = clean()
		w.pr.checks = { { name = "static", state = "" } }
		for tries = 0, 9 do
			t.expect(landcheck.classify(landcheck.problems(w), tries, 2).action).toBe("wait")
		end
	end)

	it("AC2: a redo problem runs the worker again until the cap, then blocks under its own reason", function()
		local i = clean()
		i.traceProblems = { "stale" }
		t.expect(landcheck.classify(landcheck.problems(i), 0, 2).action).toBe("redo")
		t.expect(landcheck.classify(landcheck.problems(i), 1, 2).action).toBe("redo")
		local capped = landcheck.classify(landcheck.problems(i), 2, 2)
		t.expect(capped.action).toBe("block")
		t.expect(capped.reason).toBe("review-exhausted")
		-- a redo outranks a wait: waiting on CI for a stack the worker must change is pointless
		i.pr.checks = { { name = "static", state = "" } }
		t.expect(landcheck.classify(landcheck.problems(i), 0, 2).action).toBe("redo")
	end)

	it(
		"AC3: the escalation the dispatcher files parses, has one recommended option and names every problem",
		function()
			local i = clean()
			i.pr.checks = { { name = "static", state = "FAILURE" } }
			i.openHigh = { "F2" }
			local ps = landcheck.problems(i)
			local text: string = landcheck.escalation(ps, "R0010", "c0020", 0)
			local note, why = escalation.parse(text)
			t.expect(why).toBe(nil)
			t.expect(note ~= nil).toBe(true)
			t.expect(escalation.check(note :: any)).toBe(nil)
			t.expect(string.find(text, "ci-failed", 1, true) ~= nil).toBe(true)
			t.expect(string.find(text, "open-high", 1, true) ~= nil).toBe(true)
			local capped = clean()
			capped.traceProblems = { "stale" }
			local text2: string = landcheck.escalation(landcheck.problems(capped), "R0010", nil, 2)
			local note2 = escalation.parse(text2)
			t.expect(escalation.check(note2 :: any)).toBe(nil)
			t.expect(string.find(text2, "after 2 tries", 1, true) ~= nil).toBe(true)
		end
	)

	it(
		"AC3: the dispatcher's own bind is a merge whose second parent is the layer tip, and a block request round-trips",
		function()
			t.expect(landcheck.ownBind({ "p1", TIP }, TIP)).toBe(true)
			t.expect(landcheck.ownBind({ "p1", "other" }, TIP)).toBe(false)
			t.expect(landcheck.ownBind({ TIP }, TIP)).toBe(false)
			t.expect(landcheck.ownBind({ "p1", TIP, "p3" }, TIP)).toBe(false)
			t.expect(landcheck.ownBind({ "p1", "" }, "")).toBe(false)
			local text: string = landcheck.requestText("R0010", "design-gap", "c0020")
			local r = landcheck.parseRequest(text)
			t.expect(r.item).toBe("R0010")
			t.expect(r.reason).toBe("design-gap")
			t.expect(r.layer).toBe("c0020")
			t.expect(landcheck.parseRequest(landcheck.requestText("R0010", "quota", nil)).layer).toBe(nil)
			t.expect(landcheck.parseRequest("item: R0010\nreason: nonsense\nlayer: \n")).toBe(nil)
			t.expect(landcheck.parseRequest("garbage")).toBe(nil)
		end
	)

	it(
		"AC4: green is read from the rollup: SKIPPED, NEUTRAL and SUCCESS pass; failed and still-running checks are named",
		function()
			local failed, pending = landcheck.checks({
				{ name = "a", state = "SUCCESS" },
				{ name = "b", state = "SKIPPED" },
				{ name = "c", state = "NEUTRAL" },
				{ name = "d", state = "FAILURE" },
				{ name = "e", state = "TIMED_OUT" },
				{ name = "f", state = "" },
				{ name = "g", state = "IN_PROGRESS" },
			})
			t.expect(failed).toEqual({ "d", "e" })
			t.expect(pending).toEqual({ "f", "g" })
		end
	)

	it(
		"AC4: landread.parsePr reads gh's JSON, and a text it cannot read is a named failure, never a green PR",
		function()
			local json =
				'{"state":"OPEN","isDraft":true,"headRefOid":"abc123","mergeable":"UNKNOWN","statusCheckRollup":[{"name":"deploy","conclusion":"SKIPPED"},{"name":"static","status":"IN_PROGRESS","conclusion":""},{"context":"ci","state":"success"}]}'
			local pr, why = landread.parsePr(json)
			t.expect(why).toBe(nil)
			t.expect(pr.head).toBe("abc123")
			t.expect(pr.draft).toBe(true)
			t.expect(pr.mergeable).toBe("UNKNOWN")
			t.expect(pr.checks[1]).toEqual({ name = "deploy", state = "SKIPPED" })
			t.expect(pr.checks[2]).toEqual({ name = "static", state = "" })
			t.expect(pr.checks[3]).toEqual({ name = "ci", state = "SUCCESS" })
			local none, bad = landread.parsePr("not json")
			t.expect(none).toBe(nil)
			t.expect(bad ~= nil).toBe(true)
			local nohead, bad2 = landread.parsePr('{"state":"OPEN"}')
			t.expect(nohead).toBe(nil)
			t.expect(bad2 ~= nil).toBe(true)
			-- an empty rollup is not "all green" by itself: no check, no failure, the head decides (landcheck)
			local empty = landread.parsePr(
				'{"state":"OPEN","isDraft":false,"headRefOid":"abc","mergeable":"MERGEABLE","statusCheckRollup":[]}'
			)
			t.expect(#empty.checks).toBe(0)
		end
	)
end)
