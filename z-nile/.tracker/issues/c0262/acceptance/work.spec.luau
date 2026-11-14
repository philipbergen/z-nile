--!strict
-- c0262: the worker's next action honours the ticket's final review: a layer is complete when it is finished and on
-- course, and the next layer starts only then.
local t = require("@tests/lib/t")
local work = require("@znile/engine/work")

local function layer(pos: number, issue: string, state: string?): work.LayerFact
	return {
		position = pos,
		issue = issue,
		name = `R0010/{pos}/{issue}`,
		commits = 2,
		onlyStart = false,
		finished = true,
		finalState = state,
	}
end

local function raft(layers: { work.LayerFact }): work.RaftFact
	return {
		id = "R0010",
		title = "t",
		where = "active",
		status = "active",
		designReady = true,
		depsMet = true,
		questions = false,
		issues = { "c0010", "c0020" },
		layers = layers,
		holder = "Ada <ada@example>",
		since = "2026-11-13T00:00:00-08:00",
		stacked = false,
		codeReview = "none",
		finalReview = "none",
		trace = false,
		traceOk = false,
	}
end

local function step(r: work.RaftFact): work.Decision
	return work.decide({ asked = "R0010", held = nil, rafts = { r } })
end

return t.spec("c0262 a layer is complete after its final review", function(it)
	it("AC6: a finished layer with no final review asks for it, before the next layer starts", function()
		local d = step(raft({ layer(1, "c0010", "none") }))
		t.expect(d.action).toBe("final-review-ticket")
		t.expect(d.ticket).toBe("c0010")
		local again = step(raft({ layer(1, "c0010", "review-again") }))
		t.expect(again.action).toBe("final-review-ticket")
	end)

	it("AC6: an on-course layer lets the next layer start", function()
		local d = step(raft({ layer(1, "c0010", "on-course") }))
		t.expect(d.action).toBe("implement")
		t.expect(d.ticket).toBe("c0020")
	end)

	it("AC6: the last layer needs its review too, before the stack is restacked", function()
		local held = step(raft({ layer(1, "c0010", "on-course"), layer(2, "c0020", "none") }))
		t.expect(held.action).toBe("final-review-ticket")
		t.expect(held.ticket).toBe("c0020")
		local done = step(raft({ layer(1, "c0010", "on-course"), layer(2, "c0020", "on-course") }))
		t.expect(done.action).toBe("restack")
	end)

	it("AC7: off course by the implementation rebuilds the layer", function()
		local d = step(raft({ layer(1, "c0010", "redo-layer") }))
		t.expect(d.action).toBe("rebuild")
		t.expect(d.ticket).toBe("c0010")
	end)

	it("AC7: off course by the design sends the ticket back to z-design", function()
		local d = step(raft({ layer(1, "c0010", "redo-design") }))
		t.expect(d.action).toBe("redesign")
		t.expect(string.find(d.why, "z-design", 1, true) ~= nil).toBe(true)
	end)

	it(
		"AC8: a second off-course verdict, or a review nobody can read, blocks the ticket for the human",
		function()
			for _, state in { "blocked", "invalid" } do
				local d = step(raft({ layer(1, "c0010", state) }))
				t.expect(d.action).toBe("blocked")
				t.expect(string.find(d.why, "questions.md", 1, true) ~= nil).toBe(true)
			end
		end
	)

	it("AC9: a layer read without the fact is not held up", function()
		t.expect(step(raft({ layer(1, "c0010", nil) })).action).toBe("implement")
	end)
end)
