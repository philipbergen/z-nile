--!strict
-- c0248 AC16: `./zn work next` (work.forRaft, pure) carries a raft with `layers: reviewed` one complete layer at a time:
-- a finished layer is reviewed in its own issue folder before the next `./zn start`, a landed layer is skipped, there
-- is no raft-level code review, and the trace and final review are this landing's. A raft without the marker keeps
-- today's order. Pure: facts in, one decision out; nothing is read or written.
local t = require("@tests/lib/t")
local work = require("@znile/engine/work")

local function layer(pos: number, issue: string, over: { [string]: any }?): work.LayerFact
	local l: work.LayerFact = {
		position = pos,
		issue = issue,
		name = `R0010/{pos}/{issue}`,
		commits = 2,
		onlyStart = false,
		finished = true,
	}
	local given: { [string]: any } = over or {}
	for k, v in given do
		(l :: any)[k] = v
	end
	return l
end

local function raft(over: { [string]: any }): work.RaftFact
	local r: work.RaftFact = {
		id = "R0010",
		title = "t",
		where = "active",
		status = "active",
		designReady = true,
		depsMet = true,
		questions = false,
		issues = { "c0010", "c0020", "c0030" },
		layers = {},
		holder = "Ada <ada@example.invalid>",
		since = "2026-11-19T00:00:00-08:00",
		stacked = true,
		codeReview = "none",
		finalReview = "none",
		trace = false,
		traceOk = false,
		root = "",
	}
	for k, v in over do
		(r :: any)[k] = v
	end
	return r
end

local function has(s: string, part: string): boolean
	return string.find(s, part, 1, true) ~= nil
end

return t.spec("c0248 work next carries one complete layer at a time", function(it)
	it(
		"AC16: on a raft with layers: reviewed, work next reviews a finished layer before the next start, and starts the next once it is complete",
		function()
			local notYet = raft({
				marked = true,
				traceName = "trace-001.md",
				stacked = false,
				layers = { layer(1, "c0010", { reviewReason = "no review-001.md in c0010's folder" }) },
			})
			local d = work.forRaft(notYet)
			t.expect(d.action).toBe("review")
			t.expect(d.ticket).toBe("c0010")
			t.expect(has(d.why, "c0010's folder")).toBe(true)
			t.expect(has(d.why, "no review-001.md in c0010's folder")).toBe(true)
			-- complete: the next layer is started, not reviewed again
			local complete = raft({
				marked = true,
				traceName = "trace-001.md",
				stacked = false,
				layers = { layer(1, "c0010", { reviewReason = "" }) },
			})
			local next = work.forRaft(complete)
			t.expect(next.action).toBe("implement")
			t.expect(next.ticket).toBe("c0020")
			t.expect(has(next.why, "./zn start R0010")).toBe(true)
		end
	)

	it(
		"AC16: a landed layer is skipped, a marked raft has no raft-level code review, and the trace and final review are this landing's",
		function()
			local r = raft({
				marked = true,
				traceName = "trace-002.md",
				codeReview = "none", -- the raft folder has no review-NNN.md: the layers' reviews are in their issue folders
				layers = {
					layer(1, "c0010", { landed = true, commits = 0 }),
					layer(2, "c0020", { landed = true, commits = 0 }),
					layer(3, "c0030", { reviewReason = "" }),
				},
			})
			local d = work.forRaft(r)
			t.expect(d.action).toBe("trace")
			t.expect(has(d.why, "trace-002.md")).toBe(true)
			r.trace = true
			local f = work.forRaft(r)
			t.expect(f.action).toBe("final-review")
			t.expect(has(f.why, "trace-002.md")).toBe(true)
			-- a landed layer is skipped whatever its fact says: one whose branch is gone may read as unfinished, and it
			-- is never sent back to implement, finish or review
			local landedOnly = raft({
				marked = true,
				traceName = "trace-002.md",
				layers = {
					layer(1, "c0010", { landed = true, commits = 0, finished = false }),
					layer(2, "c0020", { landed = true, commits = 0, finished = false }),
					layer(3, "c0030", { reviewReason = "c0030 is not complete: no review-001.md" }),
				},
			})
			local back = work.forRaft(landedOnly)
			t.expect(back.action).toBe("review")
			t.expect(back.ticket).toBe("c0030")
		end
	)

	it(
		"AC16: a raft without the marker keeps today's order: every layer, one code review, then trace.md",
		function()
			local r = raft({
				layers = { layer(1, "c0010"), layer(2, "c0020"), layer(3, "c0030") },
			})
			local d = work.forRaft(r)
			t.expect(d.action).toBe("review")
			t.expect(d.ticket).toBe("")
			t.expect(has(d.why, "Run the code review once")).toBe(true)
			r.codeReview = "resolved"
			local tr = work.forRaft(r)
			t.expect(tr.action).toBe("trace")
			t.expect(has(tr.why, "as trace.md in R0010's folder")).toBe(true)
		end
	)
end)
