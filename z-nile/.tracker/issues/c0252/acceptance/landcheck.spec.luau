--!strict
-- c0252 AC1 to AC4: the pure landing check (landcheck.luau) and the pull-request read (landread.parsePr). Every case
-- builds an Input from a clean one and breaks one thing; the exports are read through `any` because they do not exist
-- before c0252 (the spec type-checks without them).
local escalation = require("@znile/engine/escalation")
local t = require("@tests/lib/t")

local frontier: any = require("@znile/engine/frontier")
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
		frontier = { met = true, listed = {} },
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

	it(
		"AC20: a land request round-trips with the raft, the tip, --through and the worktree, a malformed one is refused, and only the same tip is fresh",
		function()
			local text: string = landcheck.landRequestText("R0010", TIP, "c0010", "/w/R0010")
			t.expect(text).toBe(`item: R0010\ntip: {TIP}\nthrough: c0010\nworktree: /w/R0010\n`)
			local r = landcheck.parseLandRequest(text)
			t.expect(r.item).toBe("R0010")
			t.expect(r.tip).toBe(TIP)
			t.expect(r.through).toBe("c0010")
			t.expect(r.worktree).toBe("/w/R0010")
			t.expect(landcheck.parseLandRequest(landcheck.landRequestText("R0010", TIP, nil, "/w")).through)
				.toBe(nil)
			for _, bad in
				{
					"garbage",
					"item: c0010\ntip: " .. TIP .. "\nthrough: \nworktree: /w\n",
					"item: R0010\ntip: zz\nthrough: \nworktree: /w\n",
					"item: R0010\ntip: abc\nthrough: \nworktree: /w\n",
					"item: R0010\ntip: " .. TIP .. "\nworktree: /w\n",
					"item: R0010\ntip: " .. TIP .. "\nthrough: \n",
				}
			do
				t.expect(landcheck.parseLandRequest(bad)).toBe(nil)
			end
			t.expect(landcheck.landRequestFresh(r, TIP)).toBe(true)
			t.expect(landcheck.landRequestFresh(r, "b" .. string.sub(TIP, 2))).toBe(false)
			t.expect(landcheck.landRequestFresh(r, "")).toBe(false)
		end
	)
	-- c0251's frontier floor (user, 2026-11-16): the problem is c0251's code on c0251's verdict, with a kind of its own
	local UNMET = {
		met = false,
		code = "no-frontier-review",
		problem = "no-frontier-review: no review of the landed code ran on a frontier model (frontier: claude-fable-5-2); found final-review-001.md on claude-sonnet-5-5",
		listed = { "claude-fable-5-2" },
	}
	local function unmet(): any
		local i = clean()
		i.frontier = UNMET
		return i
	end

	it(
		"AC22: an unmet frontier floor is the one problem no-frontier-review, c0251's own code, of kind review and not a block or a redo",
		function()
			t.expect(landcheck.knownKind("review")).toBe(true)
			t.expect(frontier.CODE).toBe("no-frontier-review")
			t.expect(codes(unmet())).toEqual({ "no-frontier-review" })
			t.expect(kindOf(unmet(), "no-frontier-review")).toBe("review")
			local p = landcheck.problems(unmet())[1]
			-- the code is printed once (by `lines`), and the text names the command the dispatcher runs
			t.expect(string.find(p.text, "no-frontier-review", 1, true)).toBe(nil)
			t.expect(string.find(p.text, "found final-review-001.md on claude-sonnet-5-5", 1, true) ~= nil)
				.toBe(true)
			t.expect(
				string.find(p.text, "./zn dispatch zz-review R0010 --mode final --frontier)", 1, true) ~= nil
			)
				.toBe(true)
			-- for a prefix landing the command carries --through
			local prefix = unmet()
			prefix.through = "c0010"
			t.expect(
				string.find(
					landcheck.problems(prefix)[1].text,
					"zz-review R0010 --mode final --frontier --through c0010)",
					1,
					true
				) ~= nil
			).toBe(true)
			t.expect(landcheck.lines(landcheck.problems(unmet()))[1]:sub(1, 33))
				.toBe("no-frontier-review (review): no r")
			-- a met floor, and no list at all (frontier.check: an empty list sets no floor), give none
			local met = clean()
			met.frontier = frontier.check({}, {})
			t.expect(codes(met)).toEqual({})
			t.expect(codes((function()
				local i = clean()
				i.frontier = frontier.check(
					{ { file = "final-review-001.md", model = "claude-fable-5-2" } },
					{ "claude-fable-5-2" }
				)
				return i
			end)())).toEqual({})
		end
	)

	it(
		"AC22: classify runs the extra round for a review problem: a block and a redo outrank it, it outranks a wait, and it never blocks by itself",
		function()
			local v = landcheck.classify(landcheck.problems(unmet()), 0, 2)
			t.expect(v.action).toBe("review")
			t.expect(v.reason).toBe(nil)
			-- however often the worker has already rerun, the verdict is the same round (the cap is for redo)
			t.expect(landcheck.classify(landcheck.problems(unmet()), 9, 2).action).toBe("review")
			-- a wait (CI running) is outranked: the round pushes a review, which moves the head and restarts CI
			local w = unmet()
			w.pr.checks = { { name = "static", state = "" } }
			t.expect(landcheck.classify(landcheck.problems(w), 0, 2).action).toBe("review")
			-- a redo outranks the round (the worker is about to change the code), a block outranks everything
			local r = unmet()
			r.traceProblems = { "stale" }
			t.expect(landcheck.classify(landcheck.problems(r), 0, 2).action).toBe("redo")
			local b = unmet()
			b.openHigh = { "F2" }
			t.expect(landcheck.classify(landcheck.problems(b), 0, 2).action).toBe("block")
			-- the round is not a failure to repeat: it adds a code, so a worker's signature moves with it, nothing more
			t.expect(landcheck.signature(landcheck.problems(unmet()), TIP)).toBe(`no-frontier-review@{TIP}`)
		end
	)

	it(
		"AC22: afterRound: once the round ran at this tip a review problem still open is a block under needs-decision, never a second round",
		function()
			local ps = landcheck.problems(unmet())
			t.expect(landcheck.afterRound(ps, false)[1].kind).toBe("review")
			local after = landcheck.afterRound(ps, true)
			t.expect(#after).toBe(1)
			t.expect(after[1].code).toBe("no-frontier-review")
			t.expect(after[1].kind).toBe("block")
			t.expect(after[1].reason).toBe("needs-decision")
			t.expect(
				string.find(after[1].text, "the extra round ran and the floor is still unmet", 1, true) ~= nil
			)
				.toBe(true)
			local v = landcheck.classify(after, 0, 2)
			t.expect(v.action).toBe("block")
			t.expect(v.reason).toBe("needs-decision")
			-- other problems pass through untouched
			local mixed = unmet()
			mixed.pr.checks = { { name = "static", state = "" } }
			local out = landcheck.afterRound(landcheck.problems(mixed), true)
			t.expect(#out).toBe(2)
			local kinds: { string } = {}
			for _, p in out do
				table.insert(kinds, p.code .. ":" .. p.kind)
			end
			table.sort(kinds)
			t.expect(kinds).toEqual({ "ci-pending:wait", "no-frontier-review:block" })
		end
	)

	it(
		"AC22: the note filed when the round did not clear the floor parses, names the round it ran, and recommends retry (a retry runs the round again after the list or the model is fixed)",
		function()
			local ps = landcheck.afterRound(landcheck.problems(unmet()), true)
			local body: string = landcheck.escalation(ps, "R0010", nil, 0)
			local note, why = escalation.parse(body)
			t.expect(why).toBe(nil)
			t.expect(note ~= nil).toBe(true)
			t.expect(escalation.check(note :: any)).toBe(nil)
			t.expect(
				string.find(
					body,
					"the frontier floor is still unmet after the one extra review round",
					1,
					true
				) ~= nil
			).toBe(true)
			t.expect(string.find(body, "--mode final --frontier once for this tip", 1, true) ~= nil)
				.toBe(true)
			t.expect(string.find(body, "- no-frontier-review: the extra round ran", 1, true) ~= nil)
				.toBe(true)
			t.expect(landcheck.recommended(ps)).toBe("retry")
			t.expect(
				string.find(
					body,
					"amend-design: the design has to change to make the check pass (recommended)",
					1,
					true
				)
			).toBe(nil)
			-- a note for any other block does not talk of the round
			local other = clean()
			other.openHigh = { "F2" }
			local plain: string = landcheck.escalation(landcheck.problems(other), "R0010", nil, 0)
			t.expect(string.find(plain, "frontier", 1, true)).toBe(nil)
		end
	)
end)
