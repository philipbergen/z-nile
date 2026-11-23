--!strict
-- f0420 step 9 (AC18): an unnamed `work next` takes the unit that unblocks the most, then the lowest id; one function
-- (`work.order`) holds the rule. Pure: facts in, one Decision out.
local fs = require("@lune/fs")
local process = require("@lune/process")
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

return t.spec("f0420: a named ticket is taken with what it depends on", function(it)
	it("a new dependency is designed first, and the answer says it is for the ticket", function()
		local d = work.decide({
			asked = "c0100",
			rafts = {},
			issues = { prepared("c0100", { deps = { "c0090" } }), issue("c0090") },
		})
		t.expect(d.action).toBe("draft")
		t.expect(d.ticket).toBe("c0090")
		t.expect(string.sub(d.why, 1, 13)).toBe("For c0100: De")
	end)

	it("the ticket itself is designed when it is new", function()
		local d = work.decide({ asked = "c0100", rafts = {}, issues = { issue("c0100") } })
		t.expect(d.action).toBe("draft")
		t.expect(d.ticket).toBe("c0100")
	end)

	it("designed tickets are rafted from the bottom: the dependency first", function()
		local d = work.decide({
			asked = "c0100",
			rafts = {},
			issues = { prepared("c0100", { deps = { "c0090" } }), prepared("c0090") },
		})
		t.expect(d.action).toBe("rafting")
		t.expect(d.ticket).toBe("c0090")
	end)

	it("with --one a named ticket is answered alone, as before", function()
		local d = work.decide({
			asked = "c0100",
			one = true,
			rafts = {},
			issues = { prepared("c0100", { deps = { "c0090" } }), issue("c0090") },
		})
		t.expect(d.action).toBe("none")
		t.expect(has(d.why, "c0090")).toBe(true)
	end)

	it("a ticket already in a raft is that raft's walk", function()
		local rafts = { raft("R0100", { issues = { "c0100" }, outside = { "c0090" }, depsMet = false }) }
		local issues = { prepared("c0100", { raft = "R0100", deps = { "c0090" } }), issue("c0090") }
		local viaTicket = work.decide({ asked = "c0100", rafts = rafts, issues = issues })
		local viaRaft = work.decide({ asked = "R0100", rafts = rafts, issues = issues })
		t.expect(viaTicket.action).toBe("draft")
		t.expect(viaTicket.ticket).toBe("c0090")
		t.expect(viaTicket.why).toBe(viaRaft.why)
	end)

	it("a ticket whose raft is not in the tracker is told to unfold it", function()
		local d =
			work.decide({ asked = "c0100", rafts = {}, issues = { prepared("c0100", { raft = "R0100" }) } })
		t.expect(d.action).toBe("fix")
		t.expect(has(d.why, "./zn unfold R0100 c0100")).toBe(true)
	end)

	it("nothing workable: the Stops message names the ticket and what the person owes", function()
		local d = work.decide({
			asked = "c0100",
			rafts = {},
			issues = { issue("c0100", { draftBlock = "no idea-review-001.md" }) },
		})
		t.expect(d.action).toBe("wait")
		t.expect(has(d.why, `c0100 {work.STOPS}`)).toBe(true)
		t.expect(has(d.why, "./zn idea c0100 # no idea-review-001.md")).toBe(true)
		t.expect(has(d.why, "Then run ./zn work c0100 again.")).toBe(true)
	end)

	it("a ticket held by another worker is a plain wait naming the holder", function()
		local d = work.decide({
			asked = "c0100",
			claims = { c0100 = "w1" },
			rafts = {},
			issues = { prepared("c0100") },
		})
		t.expect(d.action).toBe("wait")
		t.expect(has(d.why, "c0100 is held by w1")).toBe(true)
		t.expect(has(d.why, work.STOPS)).toBe(false)
	end)

	it("a ticket whose design this checkout is resuming is resumed first", function()
		local d = work.decide({
			asked = "c0100",
			rafts = {},
			issues = { issue("c0100", { status = "preparing" }), issue("c0090") },
		})
		t.expect(d.action).toBe("draft")
		t.expect(has(d.why, "c0100 is being designed: resume its prep worktree")).toBe(true)
	end)

	it("a ticket a raft lists is no unit of its own: the answer says who is grouping it", function()
		local d = work.decide({
			asked = "c0100",
			rafts = { raft("R0007", { issues = { "c0100" } }) },
			issues = { prepared("c0100", { groupedBy = "R0007" }) },
		})
		t.expect(has(d.why, "is being grouped by R0007 (z-raft)")).toBe(true)
	end)

	it("the Stops mark is one constant and the skill quotes it", function()
		local top = (string.gsub(process.exec("git", { "rev-parse", "--show-toplevel" }).stdout, "%s+$", ""))
		local skill = fs.readFile(`{top}/z-nile/skills/z-work/SKILL.md`)
		t.expect(work.STOPS).toBe("is not landed yet:")
		t.expect(has(skill, work.STOPS)).toBe(true)
		t.expect(has(skill, "ticket")).toBe(true)
	end)
end)
