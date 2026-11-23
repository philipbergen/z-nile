--!strict
-- f0420 a theme at a time: scope and depth, each case written to fail under a named mutant. Pure: facts in, one Decision out.
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
local function inTr(name: string, r: work.RaftFact): work.RaftFact
	(r :: any).tributary = name
	return r
end

local function issueIn(name: string, i: work.IssueFact): work.IssueFact
	(i :: any).tributary = name
	return i
end

local PICKMAN = "pickman/.tracker"

return t.spec("f0420: a theme's scope and depth", function(it)
	it("an unsorted unit does not leak into a named theme", function()
		local d = work.decide({
			tributary = "worker",
			rafts = {},
			issues = { issue("c0010"), issueIn("worker", issue("c0020")) },
		})
		t.expect(d.ticket).toBe("c0020")
	end)

	it("a unit that depends on the theme's unit is not pulled into the theme", function()
		-- R0200 (worker) is built and nobody of this person holds it; c0010 (board, lower id) waits on its ticket and
		-- could be designed from its document: it is not the theme's to take
		local active = raft("R0200", {
			where = "active",
			status = "active",
			issues = { "c0300" },
			layers = { layer(1, "c0300", false) },
		})
		local d = work.decide({
			tributary = "worker",
			rafts = { inTr("worker", active) },
			issues = {
				issueIn("worker", prepared("c0300", { raft = "R0200", status = "active" })),
				issueIn("board", issue("c0010", { deps = { "c0300" } })),
			},
		})
		t.expect(d.raft).toBe("R0200")
		t.expect(d.action).toBe("finish")
	end)

	it("outside dependencies are taken all the way down, not one level", function()
		local d = work.decide({
			tributary = "worker",
			rafts = {},
			issues = {
				issueIn("worker", issue("c0030", { deps = { "c0020" } })),
				issueIn("board", issue("c0020", { deps = { "c0010" } })),
				issueIn("board", issue("c0010")),
			},
		})
		t.expect(d.action).toBe("draft")
		t.expect(d.ticket).toBe("c0010")
	end)

	it(
		"two projects sharing a tributary name: a folder's theme names only its own project's units",
		function()
			local d = work.decide({
				tributary = "worker",
				scope = PICKMAN,
				rafts = {},
				issues = {
					issueIn("worker", issue("c0010", { root = "z-nile/.tracker" })),
					issueIn("worker", issue("c0020", { root = PICKMAN })),
				},
			})
			t.expect(d.ticket).toBe("c0020")
		end
	)

	it("a theme's dependency in another project is still worked from a project folder", function()
		local d = work.decide({
			tributary = "worker",
			scope = PICKMAN,
			rafts = {},
			issues = {
				issueIn("worker", issue("c0020", { root = PICKMAN, deps = { "c0010" } })),
				issueIn("board", issue("c0010", { root = "z-nile/.tracker" })),
			},
		})
		t.expect(d.action).toBe("draft")
		t.expect(d.ticket).toBe("c0010")
	end)

	it("inside a theme the unit that unblocks the most comes before a lower id", function()
		local d = work.decide({
			tributary = "worker",
			rafts = {},
			issues = {
				issueIn("worker", issue("c0010")),
				issueIn("worker", issue("c0020")),
				issueIn("worker", issue("c0030", { deps = { "c0020" } })),
			},
		})
		t.expect(d.ticket).toBe("c0020")
	end)
end)
