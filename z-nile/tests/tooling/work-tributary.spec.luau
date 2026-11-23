--!strict
-- f0420 step 9 (AC18): an unnamed `work next` takes the unit that unblocks the most, then the lowest id; one function
-- (`work.order`) holds the rule. Pure: facts in, one Decision out.
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

local function inTr(name: string, r: work.RaftFact): work.RaftFact
	(r :: any).tributary = name
	return r
end

local function issueIn(name: string, i: work.IssueFact): work.IssueFact
	(i :: any).tributary = name
	return i
end

return t.spec("f0420: a theme at a time", function(it)
	it("only the named tributary's units are picked, though another's has a lower id", function()
		local input: any = {
			tributary = "worker",
			rafts = {
				inTr("board", raft("R0010", { issues = { "c0010" } })),
				inTr("worker", raft("R0020", { issues = { "c0020" } })),
			},
			issues = { prepared("c0010", { raft = "R0010" }), prepared("c0020", { raft = "R0020" }) },
		}
		t.expect(work.decide(input).raft).toBe("R0020")
		input.tributary = "board"
		t.expect(work.decide(input).raft).toBe("R0010")
	end)

	it("a unit outside it that the tributary depends on is worked, from the bottom", function()
		local d = work.decide({
			tributary = "worker",
			rafts = {
				inTr(
					"worker",
					raft("R0030", { issues = { "c0030" }, outside = { "c0050" }, depsMet = false })
				),
				inTr("board", raft("R0010", { issues = { "c0010" } })),
			},
			issues = {
				prepared("c0030", { raft = "R0030", deps = { "c0050" } }),
				prepared("c0010", { raft = "R0010" }),
				issueIn("board", issue("c0050")),
			},
		})
		t.expect(d.action).toBe("draft")
		t.expect(d.ticket).toBe("c0050")
	end)

	it("a unit outside that nothing in the tributary needs is left alone", function()
		local d = work.decide({
			tributary = "worker",
			rafts = {},
			issues = { issueIn("board", issue("c0010")), issueIn("worker", issue("c0020")) },
		})
		t.expect(d.ticket).toBe("c0020")
	end)

	it("a unit with no tributary line is in unsorted", function()
		local d = work.decide({
			tributary = "unsorted",
			rafts = {},
			issues = { issueIn("worker", issue("c0010")), issue("c0020") },
		})
		t.expect(d.ticket).toBe("c0020")
	end)

	it("nothing open in the tributary answers none, naming it", function()
		local d = work.decide({
			tributary = "worker",
			rafts = {},
			issues = { issueIn("board", issue("c0010")) },
		})
		t.expect(d.action).toBe("none")
		t.expect(has(d.why, "worker")).toBe(true)
	end)

	it("a unit another worker holds stays a fact: its dependent is still not ready", function()
		local d = work.decide({
			tributary = "worker",
			claims = { R0040 = "w1" },
			rafts = {
				inTr(
					"board",
					raft(
						"R0040",
						{
							where = "active",
							status = "active",
							issues = { "c0040" },
							layers = { layer(1, "c0040", false) },
						}
					)
				),
				inTr(
					"worker",
					raft("R0050", { issues = { "c0050" }, outside = { "c0040" }, depsMet = false })
				),
			},
			issues = {
				prepared("c0040", { raft = "R0040" }),
				prepared("c0050", { raft = "R0050", deps = { "c0040" } }),
			},
		})
		t.expect(d.action).toBe("none")
	end)

	it("no tributary is every unit, as before", function()
		local d = work.decide({
			rafts = { inTr("board", raft("R0010", { issues = { "c0010" } })) },
			issues = { prepared("c0010", { raft = "R0010" }) },
		})
		t.expect(d.raft).toBe("R0010")
	end)

	it("work.inTributary lists the open units a theme needs", function()
		local ids = (work :: any).inTributary({
			tributary = "worker",
			rafts = {
				inTr(
					"worker",
					raft("R0030", { issues = { "c0030" }, outside = { "c0050" }, depsMet = false })
				),
			},
			issues = { prepared("c0030", { raft = "R0030", deps = { "c0050" } }), issue("c0050") },
		}, "worker")
		t.expect(table.concat(ids, ",")).toBe("R0030,c0050")
	end)
end)
