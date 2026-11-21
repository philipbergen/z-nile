--!strict
-- f0420 step 1 (AC4-AC11): a named raft is walked with the open units it waits on. Pure: facts in, one Decision out.
local depgraph = require("@znile/engine/depgraph")
local t = require("@tests/lib/t")
local work = require("@znile/engine/work")

local function has(text: string?, needle: string): boolean
	return string.find(text or "", needle, 1, true) ~= nil
end

local function raft(id: string, over: { [string]: any }?): work.RaftFact
	local r: work.RaftFact = {
		id = id,
		title = id,
		where = "backlog",
		status = "prepared",
		designReady = true,
		depsMet = true,
		questions = false,
		issues = {},
		layers = {},
		holder = "",
		since = "",
		stacked = false,
		codeReview = "none",
		finalReview = "none",
		trace = false,
		traceOk = false,
		root = "z-nile/.tracker",
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
		status = "new",
		raft = "",
		designReady = false,
		sized = false,
		deps = {},
		draftBlock = "",
	}
	for k, v in (over or {}) :: { [string]: any } do
		(i :: any)[k] = v
	end
	return i
end

local function prepared(id: string, over: { [string]: any }?): work.IssueFact
	local i = issue(id, { status = "prepared", designReady = true, sized = true })
	for k, v in (over or {}) :: { [string]: any } do
		(i :: any)[k] = v
	end
	return i
end

local function layer(position: number, id: string, finished: boolean): work.LayerFact
	return {
		position = position,
		issue = id,
		name = `x/{position}/{id}`,
		commits = 2,
		onlyStart = false,
		finished = finished,
	}
end

-- A raft built, reviewed and traced, whose members await the person (every layer finished).
local function awaiting(id: string, member: string): work.RaftFact
	return raft(id, {
		where = "active",
		issues = { member },
		layers = { layer(1, member, true) },
		stacked = true,
		codeReview = "resolved",
		finalReview = "approved",
		trace = true,
		traceOk = true,
		lands = true,
		unapproved = { `{member} (no approval)` },
	})
end

local function decide(
	rafts: { work.RaftFact },
	issues: { work.IssueFact },
	asked: string,
	one: boolean?
): work.Decision
	return work.decide({ asked = asked, rafts = rafts, issues = issues, one = one })
end

-- R0100 (member c0100) waits on c0090, which is in no raft.
local function waitingOnIssue(dep: work.IssueFact): ({ work.RaftFact }, { work.IssueFact })
	local r = raft("R0100", { issues = { "c0100" }, outside = { "c0090" }, depsMet = false })
	return { r }, { prepared("c0100", { raft = "R0100", deps = { "c0090" } }), dep }
end

return t.spec("f0420: a named raft is walked", function(it)
	it("AC4: a new raftless dependency is designed first, and the answer says it is for the raft", function()
		local rafts, issues = waitingOnIssue(issue("c0090"))
		local d = decide(rafts, issues, "R0100")
		t.expect(d.action).toBe("draft")
		t.expect(d.ticket).toBe("c0090")
		t.expect(string.sub(d.why, 1, 12)).toBe("For R0100: D")
		t.expect(has(work.say(d), "c0090: draft - For R0100: ")).toBe(true)
		-- a design that is not yet ready and whose idea the person must answer is owed, not a draft
		local blocked = issue("c0090", { draftBlock = "no idea-review-001.md" })
		local r2, i2 = waitingOnIssue(blocked)
		local owed = decide(r2, i2, "R0100")
		t.expect(owed.action).toBe("wait")
		t.expect(has(owed.why, "c0090: no idea-review-001.md")).toBe(true)
	end)

	it("AC5: a prepared dependency is rafted, an unsized one is sized first", function()
		local rafts, issues = waitingOnIssue(prepared("c0090"))
		local d = decide(rafts, issues, "R0100")
		t.expect(d.action).toBe("rafting")
		t.expect(d.ticket).toBe("c0090")
		local r2, i2 = waitingOnIssue(prepared("c0090", { sized = false }))
		local fix = decide(r2, i2, "R0100")
		t.expect(fix.action).toBe("fix")
		t.expect(fix.ticket).toBe("c0090")
		-- an easy ticket's `ready <issue>` is f0420 step 3 (the light path): nothing here names it yet
	end)

	it("AC6: a claimable backlog dependency raft is readied, a part-built active one is worked", function()
		local dep = raft("R0090", { issues = { "c0090" } })
		local top = raft("R0100", { issues = { "c0100" }, outside = { "c0090" }, depsMet = false })
		local issues = {
			prepared("c0090", { raft = "R0090" }),
			prepared("c0100", { raft = "R0100", deps = { "c0090" } }),
		}
		local d = decide({ top, dep }, issues, "R0100")
		t.expect(d.raft).toBe("R0090")
		t.expect(d.action).toBe("ready")
		local active = raft("R0090", { where = "active", status = "active", issues = { "c0090" } })
		local built = decide({ top, active }, issues, "R0100")
		t.expect(built.raft).toBe("R0090")
		t.expect(built.action).toBe("implement")
		t.expect(has(built.why, "For R0100: ")).toBe(true)
		local one = decide({ top, active }, issues, "R0100", true)
		t.expect(one.raft).toBe("R0100")
		t.expect(one.action).toBe("none")
	end)

	it("AC7: dependencies in two active rafts with every layer finished give ready --on for both", function()
		local a, d = awaiting("R0090", "c0090"), awaiting("R0091", "c0091")
		local top = raft("R0100", { issues = { "c0100" }, outside = { "c0090", "c0091" }, depsMet = false })
		local issues = {
			prepared("c0090", { raft = "R0090" }),
			prepared("c0091", { raft = "R0091" }),
			prepared("c0100", { raft = "R0100", deps = { "c0090", "c0091" } }),
		}
		local got = decide({ top, a, d }, issues, "R0100")
		t.expect(got.raft).toBe("R0100")
		t.expect(got.action).toBe("ready")
		t.expect(has(got.why, "./zn ready R0100 --on R0090 --on R0091")).toBe(true)
		t.expect(has(got.why, "For R0100")).toBe(false)
		-- one base keeps the unnamed pick's words
		local single = decide(
			{ raft("R0100", { issues = { "c0100" }, outside = { "c0090" }, depsMet = false }), a },
			{
				prepared("c0090", { raft = "R0090" }),
				prepared("c0100", { raft = "R0100", deps = { "c0090" } }),
			},
			"R0100"
		)
		t.expect(has(single.why, "./zn ready R0100 --on R0090, then ask again.")).toBe(true)
	end)

	it("AC8: of two workable units the one with more dependents first, and on a tie the lower id", function()
		-- c0070 holds up R0090 and R0100; c0071 only R0100
		local mid = raft("R0090", { issues = { "c0090" }, outside = { "c0070" }, depsMet = false })
		local top = raft("R0100", { issues = { "c0100" }, outside = { "c0090", "c0071" }, depsMet = false })
		local issues = {
			issue("c0070"),
			issue("c0071"),
			prepared("c0090", { raft = "R0090", deps = { "c0070" } }),
			prepared("c0100", { raft = "R0100", deps = { "c0090", "c0071" } }),
		}
		t.expect(decide({ top, mid }, issues, "R0100").ticket).toBe("c0070")
		-- a tie: both hold up one unit
		local flat = raft("R0100", { issues = { "c0100" }, outside = { "c0072", "c0071" }, depsMet = false })
		local tie = {
			issue("c0071"),
			issue("c0072"),
			prepared("c0100", { raft = "R0100", deps = { "c0072", "c0071" } }),
		}
		t.expect(decide({ flat }, tie, "R0100").ticket).toBe("c0071")
		t.expect(depgraph.order({ "c0072", "c0071" }, { c0071 = 1, c0072 = 1 })[1]).toBe("c0071")
	end)

	it("AC9: workable before owed; nothing workable lists each approval the closure owes", function()
		local base = awaiting("R0090", "c0090")
		local top = awaiting("R0100", "c0100")
		top.on = "R0090"
		top.onLanded = false
		local issues = {
			prepared("c0090", { raft = "R0090", status = "active" }),
			prepared("c0100", { raft = "R0100", status = "active", deps = { "c0090" } }),
		}
		top.outside = { "c0090" }
		local stop = decide({ top, base }, issues, "R0100")
		t.expect(stop.action).toBe("wait")
		t.expect(stop.raft).toBe("R0100")
		t.expect(stop.why)
			.toBe("R0100 waits for the person: ./zn approve c0090 (R0090); ./zn approve c0100 (R0100).")
		-- a design that can be done is answered before the approvals
		local more = table.clone(issues)
		table.insert(more, issue("c0050"))
		table.insert(more, prepared("c0095", { raft = "R0100" }))
		more[2].deps = { "c0090", "c0050" }
		top.outside = { "c0090", "c0050" }
		local first = decide({ top, base }, more, "R0100")
		t.expect(first.action).toBe("draft")
		t.expect(first.ticket).toBe("c0050")
	end)

	it("AC10: questions.md with nothing else workable or owed is end, and a done raft is end", function()
		local q = raft("R0100", { questions = true, issues = { "c0100" } })
		local d = decide({ q }, { prepared("c0100", { raft = "R0100" }) }, "R0100")
		t.expect(d.action).toBe("end")
		t.expect(has(d.why, "needs a human (questions.md)")).toBe(true)
		local done = raft("R0100", { where = "done" })
		t.expect(decide({ done }, {}, "R0100").action).toBe("end")
		-- another unit's work first while there is any
		local waits =
			raft("R0100", { questions = true, issues = { "c0100" }, outside = { "c0090" }, depsMet = false })
		local got = decide(
			{ waits },
			{ prepared("c0100", { raft = "R0100", deps = { "c0090" } }), issue("c0090") },
			"R0100"
		)
		t.expect(got.action).toBe("draft")
		t.expect(got.ticket).toBe("c0090")
		-- a dependency raft with questions.md is owed, and the questions name the file
		local depQ = raft("R0090", { questions = true, issues = { "c0090" } })
		local top = raft("R0100", { issues = { "c0100" }, outside = { "c0090" }, depsMet = false })
		local owed = decide({ top, depQ }, {
			prepared("c0090", { raft = "R0090" }),
			prepared("c0100", { raft = "R0100", deps = { "c0090" } }),
		}, "R0100")
		t.expect(owed.action).toBe("wait")
		t.expect(has(owed.why, "answer z-nile/.tracker/rafts/R0090/questions.md")).toBe(true)
	end)

	it("AC11: --one answers the raft's own next action, as before", function()
		local rafts, issues = waitingOnIssue(issue("c0090"))
		local one = decide(rafts, issues, "R0100", true)
		t.expect(one.action).toBe("none")
		t.expect(one.raft).toBe("R0100")
		local waiting = awaiting("R0100", "c0100")
		local alone = work.decide({ asked = "R0100", rafts = { waiting }, issues = {}, one = true })
		local forRaft = work.forRaft(waiting)
		t.expect(alone.action).toBe(forRaft.action)
		t.expect(alone.why).toBe(forRaft.why)
	end)

	it("the closure is the raft and what it waits on, and no other raft", function()
		local top = raft("R0100", { issues = { "c0100" }, outside = { "c0090" }, depsMet = false })
		local stranger = raft("R0050", { issues = { "c0050" } })
		local rafts = { top, stranger }
		local issues = {
			issue("c0090"),
			issue("c0040"),
			prepared("c0050", { raft = "R0050" }),
			prepared("c0100", { raft = "R0100", deps = { "c0090" } }),
		}
		local w = work.walk({ asked = "R0100", rafts = rafts, issues = issues }, "R0100")
		t.expect(w.closure).toEqual({ "R0100", "c0090" })
		t.expect(w.workable).toEqual({ "c0090" })
	end)

	it("a unit nobody can move, or a dependency cycle, is not a pick", function()
		local a = raft("R0090", { issues = { "c0090" }, outside = { "c0100" }, depsMet = false })
		local b = raft("R0100", { issues = { "c0100" }, outside = { "c0090" }, depsMet = false })
		local issues = {
			prepared("c0090", { raft = "R0090", deps = { "c0100" } }),
			prepared("c0100", { raft = "R0100", deps = { "c0090" } }),
		}
		local d = decide({ a, b }, issues, "R0100")
		t.expect(d.action).toBe("wait")
		t.expect(has(d.why, "break the dependency cycle among R0090, R0100")).toBe(true)
	end)

	it(
		"depgraph.units: a raft waits on the open raft of a dependency, or the dependency itself when raftless",
		function()
			local units = depgraph.units({
				{ id = "R0001", done = true, issues = { "c0001" }, dependsOn = {} },
				{ id = "R0002", done = false, issues = { "c0002" }, dependsOn = { "c0001" } },
				{
					id = "R0003",
					done = false,
					issues = { "c0003" },
					dependsOn = { "c0002", "c0009", "c0003" },
				},
			}, {
				{ id = "c0001", raft = "R0001", done = false, dependsOn = {} },
				{ id = "c0002", raft = "R0002", done = false, dependsOn = { "c0001" } },
				{ id = "c0003", raft = "R0003", done = false, dependsOn = { "c0002", "c0009" } },
				{ id = "c0009", done = false, dependsOn = {} },
				{ id = "c0010", done = false, dependsOn = { "c0003", "c0009", "c0010" } },
			})
			t.expect(units).toEqual({
				{ id = "R0002", waitsOn = {} },
				{ id = "R0003", waitsOn = { "R0002", "c0009" } },
				{ id = "c0009", waitsOn = {} },
				{ id = "c0010", waitsOn = { "R0003", "c0009" } },
			})
			t.expect(depgraph.closure(units, "c0010")).toEqual({ "R0002", "R0003", "c0009", "c0010" })
			t.expect(depgraph.closure(units, "R0002")).toEqual({ "R0002" })
			t.expect(depgraph.closure(units, "R0001")).toEqual({})
		end
	)
end)
