--!strict
-- f0420 a theme at a time, review fixes: membership through rafts, the Stops message, a held bottom unit and
-- the report. Pure: facts in, one Decision out.
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

local function workerIssue(id: string, over: { [string]: any }?): work.IssueFact
	return issueIn("worker", issue(id, over))
end

local function workerPrepared(id: string, over: { [string]: any }?): work.IssueFact
	return issueIn("worker", prepared(id, over))
end

return t.spec(
	"f0420: a theme keeps its tickets through rafting, and never answers none while one is open",
	function(it)
		it("a raft with no line belongs to every tributary its members name", function()
			local d = work.decide({
				tributary = "worker",
				rafts = { raft("R0200", { issues = { "c0030" } }) },
				issues = { workerPrepared("c0030", { raft = "R0200" }) },
			})
			t.expect(d.raft).toBe("R0200")
			t.expect(d.action).toBe("ready")
		end)

		it("a raft with a line also belongs to its members' tributaries", function()
			local input: any = {
				tributary = "worker",
				rafts = { inTr("board", raft("R0200", { issues = { "c0030" } })) },
				issues = { workerPrepared("c0030", { raft = "R0200" }) },
			}
			t.expect(work.decide(input).raft).toBe("R0200")
			input.tributary = "board"
			t.expect(work.decide(input).raft).toBe("R0200")
		end)

		it("a raft none of whose members names a tributary is unsorted", function()
			local d = work.decide({
				tributary = "unsorted",
				rafts = { raft("R0200", { issues = { "c0030" } }) },
				issues = { prepared("c0030", { raft = "R0200" }) },
			})
			t.expect(d.raft).toBe("R0200")
		end)

		it(
			"the journey: rafting, ready, building, then approval, and never none while the theme has an open unit",
			function()
				local theme = "worker"
				-- 1 the ticket is rafted
				local one =
					work.decide({ tributary = theme, rafts = {}, issues = { workerPrepared("c0030") } })
				t.expect(one.action).toBe("rafting")
				-- 2 it is in a raft with no tributary line: the raft is readied
				local two = work.decide({
					tributary = theme,
					rafts = { raft("R0200", { issues = { "c0030" } }) },
					issues = { workerPrepared("c0030", { raft = "R0200" }) },
				})
				t.expect(two.action).toBe("ready")
				-- 3 it is active and nobody of this person holds it: the theme still answers its next action
				local active = raft("R0200", {
					where = "active",
					status = "active",
					issues = { "c0030" },
					layers = { layer(1, "c0030", false) },
				})
				local three = work.decide({
					tributary = theme,
					rafts = { active },
					issues = { workerPrepared("c0030", { raft = "R0200", status = "active" }) },
				})
				t.expect(three.raft).toBe("R0200")
				t.expect(three.action).toBe("finish")
				-- 4 built and reviewed, awaiting the person: the Stops message, not none
				local waiting = raft("R0200", {
					where = "active",
					status = "active",
					issues = { "c0030" },
					layers = { layer(1, "c0030", true) },
					stacked = true,
					codeReview = "resolved",
					finalReview = "approved",
					trace = true,
					traceOk = true,
					lands = true,
					unapproved = { "c0030 (no approval)" },
				})
				local four = work.decide({
					tributary = theme,
					rafts = { waiting },
					issues = { workerPrepared("c0030", { raft = "R0200", status = "active" }) },
				})
				t.expect(four.action).toBe("wait")
				t.expect(has(four.why, work.STOPS)).toBe(true)
				t.expect(has(four.why, "./zn approve c0030")).toBe(true)
				-- 5 landed: nothing is open in the theme
				local five = work.decide({
					tributary = theme,
					rafts = { raft("R0200", { where = "done" }) },
					issues = {},
				})
				t.expect(five.action).toBe("none")
				t.expect(has(five.why, "nothing open in tributary worker")).toBe(true)
			end
		)

		it("a theme whose units all wait for the owner answers the Stops message", function()
			local d = work.decide({
				tributary = "worker",
				rafts = {},
				issues = {
					workerIssue("c0030", { draftBlock = "open to the human (F1)" }),
					workerIssue("c0031", { deps = { "c0030" } }),
				},
			})
			t.expect(d.action).toBe("wait")
			t.expect(has(d.why, work.STOPS)).toBe(true)
			t.expect(has(d.why, "open to the human (F1)")).toBe(true)
			t.expect(d.owed ~= nil and #(d.owed :: any) > 0).toBe(true)
		end)

		it("a chain that leaves the theme and returns is the Stops message too", function()
			local d = work.decide({
				tributary = "worker",
				rafts = {},
				issues = {
					workerIssue("c0030", { draftBlock = "open to the human (F1)" }),
					issueIn("board", issue("c0040", { deps = { "c0030" } })),
					workerIssue("c0050", { deps = { "c0040" } }),
				},
			})
			t.expect(d.action).toBe("wait")
			t.expect(has(d.why, work.STOPS)).toBe(true)
		end)

		it("a dependency cycle inside a theme is owed, not none", function()
			local d = work.decide({
				tributary = "worker",
				rafts = {},
				issues = {
					workerIssue("c0060", { deps = { "c0061" } }),
					workerIssue("c0061", { deps = { "c0060" } }),
				},
			})
			t.expect(d.action).toBe("wait")
			t.expect(has(d.why, "dependency cycle")).toBe(true)
		end)

		it("another worker holding a shared bottom dependency is a plain wait naming the holder", function()
			local input: any = {
				tributary = "approval",
				claims = { c0010 = "w1" },
				rafts = {},
				issues = {
					issueIn("board", issue("c0010")),
					workerIssue("c0020", { deps = { "c0010" } }),
					issueIn("approval", issue("c0021", { deps = { "c0010" } })),
				},
			}
			local d = work.decide(input)
			t.expect(d.action).toBe("wait")
			t.expect(has(d.why, "c0010 is held by w1")).toBe(true)
			t.expect(has(d.why, work.STOPS)).toBe(false)
		end)

		it("the report prints the theme's own answer and lists only the theme's skips", function()
			local input: any = {
				tributary = "worker",
				rafts = {},
				issues = { issueIn("board", issue("c0010", { draftBlock = "open to the human (F1)" })) },
			}
			local text = work.report(input, work.decide(input))
			t.expect(has(text, "nothing open in tributary worker")).toBe(true)
			t.expect(has(text, "c0010")).toBe(false)
			-- a pick lists no other theme's skip either
			local picked: any = {
				tributary = "worker",
				rafts = { raft("R0200", { issues = { "c0030" } }) },
				issues = {
					workerPrepared("c0030", { raft = "R0200" }),
					issueIn("board", issue("c0010", { draftBlock = "open to the human (F1)" })),
				},
			}
			local text2 = work.report(picked, work.decide(picked))
			t.expect(has(text2, "R0200")).toBe(true)
			t.expect(has(text2, "c0010")).toBe(false)
		end)
	end
)
