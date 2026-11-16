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
		codePaths = { "z-nile/engine/x.luau" },
		unreadable = {},
		gate = nil,
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
				code = "self-gating",
				kind = "wait",
				mutate = function(i: any)
					i.codePaths = { "z-nile/engine/x.luau", "z-nile/check.sh" }
				end,
			},
			{
				code = "cicd-missing",
				kind = "wait",
				mutate = function(i: any)
					i.codePaths = { "pickman/src/server/Game.luau" }
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
				kind = "redo",
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
					i.pr.draft = false
					i.pr.mergeable = "CONFLICTING"
				end,
			},
			{
				code = "pr-mergeable-unknown",
				kind = "wait",
				mutate = function(i: any)
					i.pr.draft = false
					i.pr.mergeable = "UNKNOWN"
				end,
			},
			{
				code = "pr-state-unknown",
				kind = "wait",
				mutate = function(i: any)
					i.pr.state = ""
				end,
			},
			{
				code = "ci-none",
				kind = "wait",
				mutate = function(i: any)
					i.pr.checks = {}
				end,
			},
			{
				code = "git-unreadable",
				kind = "wait",
				mutate = function(i: any)
					i.unreadable = { { code = "git-unreadable", text = "git diff-tree failed" } }
				end,
			},
			{
				code = "registry-unreadable",
				kind = "wait",
				mutate = function(i: any)
					i.unreadable =
						{ { code = "registry-unreadable", text = "projects.toml could not be read" } }
				end,
			},
			{
				code = "full-gate-red",
				kind = "redo",
				mutate = function(i: any)
					i.gate = { red = "the clean-clone full gate is red" }
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

	it(
		"AC1: a draft layer's UNKNOWN mergeable is not a wait, a merged pull request is closed, and a tracker-only stack needs nothing",
		function()
			local i = clean()
			t.expect(i.pr.draft).toBe(true)
			t.expect(codes(i)).toEqual({})
			i.pr.state = "MERGED"
			t.expect(codes(i)).toEqual({ "pr-closed" })
			t.expect(landcheck.touchesGame({ "snake/src/a.luau" }, { "pickman", "snake" })).toBe(true)
			t.expect(landcheck.touchesGame({ "snakeish/src/a.luau" }, { "pickman", "snake" })).toBe(false)
			-- a game path with cicd present needs nothing of landcheck: the clean-clone gate is `./zn land-gate`'s
			local g = clean()
			g.codePaths = { "pickman/src/server/Game.luau" }
			t.expect(codes(g)).toEqual({})
			g.cicd = false
			g.codePaths = {}
			t.expect(codes(g)).toEqual({})
			t.expect(landcheck.selfGating({ "z-nile/engine/x.luau" })).toBe(nil)
			t.expect(landcheck.selfGating({ "z-nile/lib/par.sh" })).toBe("z-nile/lib/par.sh")
			t.expect(landcheck.selfGating({ "zn" })).toBe("zn")
			t.expect(landcheck.selfGating({ "znx" })).toBe(nil)
		end
	)

	it(
		"AC1: tracker state is judged by trackerstate, the one definition: a file moved out of an item folder, or under an unregistered .tracker, is code",
		function()
			local trackerstate = require("@znile/engine/trackerstate")
			local roots = { "pickman/.tracker", "z-nile/.tracker" }
			local function entry(status: string, path: string): any
				local old = if status == "A" then "000000" else "100644"
				local new = if status == "D" then "000000" else "100644"
				return {
					oldMode = old,
					newMode = new,
					oldBlob = "a",
					newBlob = "b",
					status = status,
					path = path,
				}
			end
			local code: { string } = landread.codePaths({
				entry("M", "pickman/.tracker/issues/c0010/c0010.md"),
				entry("D", "z-nile/.tracker/issues/c0010/notes.md"),
				entry("A", "z-nile/engine/notes.luau"),
				entry("A", "foo/.tracker/x"),
				entry("M", "z-nile/.tracker/rafts/R0010/R0010.md"),
			}, roots)
			t.expect(code).toEqual({ "z-nile/engine/notes.luau", "foo/.tracker/x" })
			local entries = trackerstate.parseRaw(":100644 100644 aaa bbb M\tz-nile/engine/main.luau\n")
			t.expect(landread.codePaths(entries :: any, roots)).toEqual({ "z-nile/engine/main.luau" })
		end
	)

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

	it("AC2: a problem of a kind the module does not know is a wait, never a landing", function()
		local odd = { { code = "new-check", kind = "maybe", text = "x", reason = "red-gate" } }
		t.expect(landcheck.classify(odd, 0, 2).action).toBe("wait")
		t.expect(landcheck.knownKind("maybe")).toBe(false)
		t.expect(landcheck.knownKind(nil)).toBe(false)
		t.expect(landcheck.knownKind("redo")).toBe(true)
		-- and a wait among redo problems still lets the redo through
		local mixed =
			{ odd[1], { code = "trace-stale", kind = "redo", text = "y", reason = "review-exhausted" } }
		t.expect(landcheck.classify(mixed, 0, 2).action).toBe("redo")
	end)

	it("AC2: a redo problem runs the worker again until the cap, then blocks under its own reason", function()
		local i = clean()
		i.traceProblems = { "stale" }
		t.expect(landcheck.classify(landcheck.problems(i), 0, 2).action).toBe("redo")
		t.expect(landcheck.classify(landcheck.problems(i), 1, 2).action).toBe("redo")
		local capped = landcheck.classify(landcheck.problems(i), 2, 2)
		t.expect(capped.action).toBe("block")
		t.expect(capped.reason).toBe("review-exhausted")
		-- a red check is a redo too (c0250: blocked is a human decision, or the same check failed after a real second attempt)
		local red = clean()
		red.pr.checks = { { name = "static", state = "FAILURE" } }
		t.expect(landcheck.classify(landcheck.problems(red), 0, 2).action).toBe("redo")
		t.expect(landcheck.classify(landcheck.problems(red), 2, 2).reason).toBe("red-gate")
		-- a redo outranks a wait: waiting on CI for a stack the worker must change is pointless
		i.pr.checks = { { name = "static", state = "" } }
		t.expect(landcheck.classify(landcheck.problems(i), 0, 2).action).toBe("redo")
	end)

	it(
		"AC2: only a repeat of the same failure is counted: a worker that moves the codes or the tip starts the count again",
		function()
			local ps = landcheck.problems((function()
				local i = clean()
				i.traceProblems = { "stale" }
				return i
			end)())
			local sig: string = landcheck.signature(ps, TIP)
			t.expect(sig).toBe(`trace-stale@{TIP}`)
			t.expect(landcheck.repeats(sig, 2, sig)).toBe(2)
			t.expect(landcheck.repeats(nil, 2, sig)).toBe(0)
			t.expect(landcheck.repeats(sig, 2, landcheck.signature(ps, "bbbb"))).toBe(0) -- the tip moved: progress
			t.expect(landcheck.repeats(sig, 2, landcheck.signature({}, TIP))).toBe(0) -- the codes changed
			-- the codes are sorted: the order the checks ran in is not a different failure
			local two = {
				{ code = "b", kind = "redo", text = "", reason = "red-gate" },
				{ code = "a", kind = "redo", text = "", reason = "red-gate" },
			}
			t.expect(landcheck.signature(two, "t")).toBe("a,b@t")
		end
	)

	it(
		"AC3: the escalation the dispatcher files parses and names every problem; each code recommends one pinned option, never amend-design",
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
			t.expect(string.find(text2, "after 2 repeat(s)", 1, true) ~= nil).toBe(true)
			-- the option each problem recommends: a person's ruling is `approve`; every capped redo is `retry`
			local table_: { [string]: string } = {
				["open-high"] = "approve",
				["approval-drift"] = "approve",
				["ci-failed"] = "retry",
				["layer-incomplete"] = "retry",
				["trace-stale"] = "retry",
				["pr-closed"] = "retry",
				["full-gate-red"] = "retry",
			}
			for code, option in table_ do
				local p = { { code = code, kind = "redo", text = "x", reason = "red-gate" } }
				t.expect(landcheck.recommended(p)).toBe(option)
				local body: string = landcheck.escalation(p, "R0010", nil, 2)
				local parsed = escalation.parse(body)
				t.expect(escalation.check(parsed :: any)).toBe(nil)
				for _, o in (parsed :: any).options do
					t.expect(o.recommended).toBe(o.decision == option)
				end
			end
		end
	)

	it(
		"AC3: the bind is found on main's first-parent line even with tracker commits above it, and a block request round-trips",
		function()
			-- newest first: two tracker commits above the bind, then a commit below it
			local chain = { { "t2", "t1" }, { "t1", "bind" }, { "bind", "below", TIP }, { "below", "older" } }
			local at, why = landcheck.findBind(chain, TIP)
			t.expect(at).toBe(3)
			t.expect(why).toBe(nil)
			local none, nowhy = landcheck.findBind({ { "t1", "below" } }, TIP)
			t.expect(none).toBe(nil)
			t.expect(nowhy ~= nil).toBe(true)
			local twice, twicewhy = landcheck.findBind({ { "a", "b", TIP }, { "c", "d", TIP } }, TIP)
			t.expect(twice).toBe(nil)
			t.expect(twicewhy ~= nil).toBe(true)
			t.expect(landcheck.findBind({ { "a", "b", "" } }, "")).toBe(nil)
			local text: string = landcheck.requestText("R0010", "design-gap", "c0020", "abc123")
			local r = landcheck.parseRequest(text)
			t.expect(r.item).toBe("R0010")
			t.expect(r.reason).toBe("design-gap")
			t.expect(r.layer).toBe("c0020")
			t.expect(r.tip).toBe("abc123")
			local bare = landcheck.parseRequest(landcheck.requestText("R0010", "quota", nil, nil))
			t.expect(bare.layer).toBe(nil)
			t.expect(bare.tip).toBe(nil)
			t.expect(landcheck.parseRequest("item: R0010\nreason: nonsense\nlayer: \ntip: \n")).toBe(nil)
			t.expect(landcheck.parseRequest("garbage")).toBe(nil)
		end
	)

	it(
		"AC4: green is read from the rollup: SKIPPED, NEUTRAL and SUCCESS pass; failed, cancelled and still-running checks are named",
		function()
			local failed, pending = landcheck.checks({
				{ name = "a", state = "SUCCESS" },
				{ name = "b", state = "SKIPPED" },
				{ name = "c", state = "NEUTRAL" },
				{ name = "d", state = "FAILURE" },
				{ name = "e", state = "TIMED_OUT" },
				{ name = "f", state = "" },
				{ name = "g", state = "IN_PROGRESS" },
				{ name = "h", state = "CANCELLED" },
				{ name = "i", state = "STARTUP_FAILURE" },
				{ name = "j", state = "STALE" },
				{ name = "k", state = "SOMETHING_NEW" },
			})
			t.expect(failed).toEqual({ "d", "e", "h", "i" })
			t.expect(pending).toEqual({ "f", "g", "j", "k" })
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
			-- an empty rollup reads as no check, which landcheck calls `ci-none` (a wait), never green
			local empty = landread.parsePr(
				'{"state":"OPEN","isDraft":false,"headRefOid":"abc","mergeable":"MERGEABLE","statusCheckRollup":[]}'
			)
			t.expect(#empty.checks).toBe(0)
			-- a missing state or mergeable reads as unknown, which landcheck calls a wait
			local nostate = landread.parsePr(
				'{"headRefOid":"abc","statusCheckRollup":[{"name":"a","conclusion":"SUCCESS"}]}'
			)
			t.expect(nostate.state).toBe("")
			t.expect(nostate.mergeable).toBe("UNKNOWN")
		end
	)
end)
