--!strict
-- f0464 AC4, AC3: what `./zn work next` answers for a prepared ticket in no raft. It is `ready` (./zn ready <id>, which
-- makes its single raft) whatever its level or size, never `rafting`; with an unmet dependency that one finished,
-- unlanded raft delivers, it is `ready` with `./zn ready <id> --on <R>` (the base work.baseFor picks); a ticket ready
-- refuses for a repairable reason is `fix`; one whose approved contract changed is not picked. Pure: work.decide and
-- work.forIssue over facts.
local t = require("@tests/lib/t")
local work = require("@znile/engine/work")

local function has(text: string?, needle: string): boolean
	return string.find(text or "", needle, 1, true) ~= nil
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

-- an active raft holding `issues`, one finished layer each (or unfinished when `finished` is false)
local function raft(id: string, issues: { string }, finished: boolean?): work.RaftFact
	local layers: { any } = {}
	for n, iid in issues do
		table.insert(layers, {
			position = n,
			issue = iid,
			name = `{id}/{n}/{iid}`,
			commits = 3,
			onlyStart = false,
			finished = finished ~= false,
		})
	end
	local r = {
		id = id,
		title = id,
		where = "active",
		status = "active",
		designReady = true,
		depsMet = true,
		questions = false,
		issues = issues,
		layers = layers,
		holder = "someone",
		since = "",
		stacked = true,
		finalReview = "none",
		trace = false,
		traceOk = false,
		root = "z-nile/.tracker",
		codeMax = 2,
		finalMax = 2,
	}
	return (r :: any) :: work.RaftFact
end

local function decide(rafts: { work.RaftFact }, issues: { work.IssueFact }): work.Decision
	return work.decide({ rafts = rafts, issues = issues })
end

local function named(rafts: { work.RaftFact }, issues: { work.IssueFact }, id: string): work.Decision
	for _, i in issues do
		if i.id == id then
			return work.forIssue(i, { rafts = rafts, issues = issues })
		end
	end
	error(`no {id}`)
end

return t.spec("f0464 work next readies a raftless ticket alone", function(it)
	it("AC3: a prepared ticket in no raft is answered ready <issue> at every level, never rafting", function()
		for _, level in { "easy", "normal", "risky" } do
			local i = issue("c0010", { level = level, light = false, lightWhy = "not easy" })
			local d = decide({}, { i })
			t.expect(d.action).toBe("ready")
			t.expect(d.ticket).toBe("c0010")
			t.expect(has(d.why, "./zn ready c0010")).toBe(true)
			t.expect(has(d.why, "--on")).toBe(false)
			t.expect(has(d.why, "raft-plan")).toBe(false)
			t.expect(has(d.why, "z-raft")).toBe(false)
			local n = named({}, { i }, "c0010")
			t.expect(n.action).toBe("ready")
			t.expect(has(n.why, "./zn ready c0010")).toBe(true)
		end
		-- no size: no longer holds it back (size was z-raft's input)
		local unsized = decide({}, { issue("c0011", { sized = false }) })
		t.expect(unsized.action).toBe("ready")
		t.expect(unsized.ticket).toBe("c0011")
		-- a light one keeps the light path's words
		local lit = decide({}, { issue("c0012", { level = "easy", light = true }) })
		t.expect(lit.action).toBe("ready")
		t.expect(has(lit.why, "light path")).toBe(true)
		-- the action is built next: its activity is code
		local activity =
			work.activityOf({ rafts = {}, issues = { issue("c0010") } }, decide({}, { issue("c0010") }))
		t.expect(activity).toBe("code")
	end)

	it("AC3: the lowest id among the tickets to ready goes first, and none is answered rafting", function()
		local d = decide(
			{},
			{ issue("c0031"), issue("c0030", { level = "risky" }), issue("c0032", { sized = false }) }
		)
		t.expect(d.action).toBe("ready")
		t.expect(d.ticket).toBe("c0030")
		for _, id in { "c0030", "c0031", "c0032" } do
			t.expect(named({}, { issue("c0030"), issue("c0031"), issue("c0032") }, id).action ~= "rafting")
				.toBe(true)
		end
	end)

	it(
		"AC3: a ticket ready refuses is fix with the refusal, or not picked when its approval changed",
		function()
			local bad =
				issue("c0040", { readyWhy = "c0040 has no check: its check.sh needs at least one line" })
			local d = decide({}, { bad })
			t.expect(d.action).toBe("fix")
			t.expect(d.ticket).toBe("c0040")
			t.expect(has(d.why, "ready refuses c0040: c0040 has no check")).toBe(true)
			local changed = issue("c0041", {
				readyWhy = "c0041's contract changed since approval: design. Run ./zn approve c0041 again.",
			})
			local none = decide({}, { changed })
			t.expect(none.action ~= "ready" and none.action ~= "fix").toBe(true)
			t.expect(named({}, { changed }, "c0041").action ~= "ready").toBe(true)
			-- a ticket z-raft is grouping (listed by a raft that is not done) is left alone
			local grouped = issue("c0042", { groupedBy = "R0042", readyWhy = "c0042 is listed by R0042" })
			t.expect(decide({}, { grouped }).action ~= "ready").toBe(true)
		end
	)

	it("AC3: a dependency delivered by a finished, unlanded raft is readied with --on that raft", function()
		local dep = issue("c0050", { status = "active", raft = "R0050" })
		local mine = issue("c0051", { deps = { "c0050" }, level = "normal" })
		local base = raft("R0050", { "c0050" })
		local d = decide({ base }, { dep, mine })
		t.expect(d.action).toBe("ready")
		t.expect(d.ticket).toBe("c0051")
		t.expect(has(d.why, "./zn ready c0051 --on R0050")).toBe(true)
		local n = named({ base }, { dep, mine }, "c0051")
		t.expect(n.action).toBe("ready")
		t.expect(has(n.why, "./zn ready c0051 --on R0050")).toBe(true)
		-- a ticket with nothing unmet comes first (tier 1 before tier 2)
		local free = issue("c0052")
		t.expect(decide({ base }, { dep, mine, free }).ticket).toBe("c0052")
	end)

	it("AC3: no --on while the base is unfinished or two rafts hold the dependencies", function()
		local dep = issue("c0060", { status = "active", raft = "R0060" })
		local mine = issue("c0061", { deps = { "c0060" } })
		local open = raft("R0060", { "c0060" }, false)
		local d = named({ open }, { dep, mine }, "c0061")
		t.expect(d.action ~= "ready").toBe(true)
		t.expect(
			decide({ open }, { dep, mine }).ticket ~= "c0061"
				or decide({ open }, { dep, mine }).action ~= "ready"
		).toBe(true)
		local dep2 = issue("c0062", { status = "active", raft = "R0062" })
		local two = issue("c0063", { deps = { "c0060", "c0062" } })
		local r1, r2 = raft("R0060", { "c0060" }), raft("R0062", { "c0062" })
		t.expect(named({ r1, r2 }, { dep, dep2, two }, "c0063").action ~= "ready").toBe(true)
		-- a dependency that is only prepared (no raft) is readied first, never built on
		local prep = issue("c0064")
		local after = issue("c0065", { deps = { "c0064" } })
		local first = decide({}, { prep, after })
		t.expect(first.ticket).toBe("c0064")
		t.expect(first.action).toBe("ready")
		t.expect(has(first.why, "--on")).toBe(false)
	end)

	it("AC3: baseForDeps is work.baseFor's pick for a list of ids", function()
		local dep = issue("c0070", { status = "active", raft = "R0070" })
		local base = raft("R0070", { "c0070" })
		local all = { dep }
		t.expect((work.baseForDeps({ "c0070" }, { base }, all))).toBe("R0070")
		local outside = (raft("R0071", { "c0071" }) :: any) :: { [string]: any }
		outside.where = "backlog"
		outside.outside = { "c0070" }
		t.expect((work.baseFor((outside :: any) :: work.RaftFact, { base }, all))).toBe("R0070")
		local none, why = work.baseForDeps({}, { base }, all)
		t.expect(none).toBe(nil)
		t.expect(why).toBe("has no unmet dependency")
	end)
end)
