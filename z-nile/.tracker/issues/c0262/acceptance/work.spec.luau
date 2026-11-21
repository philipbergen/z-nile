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
		root = "z-nile/.tracker",
	}
end

local function has(text: string, needle: string): boolean
	return string.find(text, needle, 1, true) ~= nil
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

	it(
		"AC6: the worker runs the review through the dispatcher and never starts the reviewer itself",
		function()
			local d = step(raft({ layer(1, "c0010", "none") }))
			t.expect(has(d.why, "./zn dispatch zz-review c0010 --mode final")).toBe(true)
			t.expect(has(d.why, "An agent never starts the reviewer itself")).toBe(true)
		end
	)

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
		"AC8: a second off-course verdict, or a review nobody can read, blocks the ticket for the human through ./zn block on its raft",
		function()
			local twice = step(raft({ layer(1, "c0010", "blocked") }))
			t.expect(twice.action).toBe("blocked")
			t.expect(has(twice.why, "./zn block R0010 review-exhausted --layer c0010")).toBe(true)
			t.expect(has(twice.why, "escalation.md")).toBe(true)
			t.expect(has(twice.why, "./zn resolve")).toBe(true)
			t.expect(has(twice.why, "questions.md")).toBe(false)
			t.expect(has(twice.why, "the latest final-review-NNN.md, the one ./zn final c0010 names"))
				.toBe(true)
			t.expect(has(twice.why, "After approve or retry, R0010 is prepared: it is readied again"))
				.toBe(true)
			t.expect(has(twice.why, "After amend-design, c0010 has left R0010")).toBe(true)
			t.expect(has(twice.why, "After abort, nothing is readied")).toBe(true)
			t.expect(
				has(
					twice.why,
					"After split, the same (./zn resolve has already captured the new issue: capture nothing)"
				)
			).toBe(true)
			t.expect(has(twice.why, "unless no member is left to land")).toBe(true)
			local unreadable = step(raft({ layer(1, "c0010", "invalid") }))
			t.expect(unreadable.action).toBe("blocked")
			t.expect(has(unreadable.why, "./zn block R0010 needs-decision --layer c0010")).toBe(true)
			t.expect(has(unreadable.why, "questions.md")).toBe(false)
		end
	)

	it("AC9: a layer read without the fact is not held up", function()
		t.expect(step(raft({ layer(1, "c0010", nil) })).action).toBe("implement")
	end)

	it("AC7: the redo and the block tell the worker to harvest the review's findings first", function()
		for _, state in { "redo-layer", "redo-design", "blocked" } do
			local d = step(raft({ layer(1, "c0010", state) }))
			t.expect(string.find(d.why, "harvest.md", 1, true) ~= nil).toBe(true)
		end
	end)

	it(
		"AC8: on a raft with layers: reviewed, a block or a redesign above a complete layer lands the layers below first",
		function()
			local marked = raft({ layer(1, "c0010", "on-course"), layer(2, "c0020", "blocked") })
			marked.marked = true
			local d = step(marked)
			t.expect(d.action).toBe("blocked")
			t.expect(has(d.why, "./zn done R0010 --through c0010")).toBe(true)
			local redo = raft({ layer(1, "c0010", "on-course"), layer(2, "c0020", "redo-design") })
			redo.marked = true
			t.expect(has(step(redo).why, "./zn done R0010 --through c0010")).toBe(true)
			-- the layer below is not complete while its own code review is not settled
			local unsettled = layer(1, "c0010", "on-course")
			unsettled.reviewReason = "review-001.md is not current"
			local open = raft({ unsettled, layer(2, "c0020", "blocked") })
			open.marked = true
			t.expect(has(open.layers[2].issue, "c0020")).toBe(true)
			t.expect(has(work.finalStep(open, "c0020", open.layers[2], "blocked").why, "--through"))
				.toBe(false)
			local first = raft({ layer(1, "c0010", "blocked") })
			first.marked = true
			t.expect(has(step(first).why, "--through")).toBe(false)
			-- a landed layer below is landed already: nothing to land first
			local landedBelow = layer(1, "c0010", "on-course")
			landedBelow.landed = true
			local afterLanding = raft({ landedBelow, layer(2, "c0020", "blocked") })
			afterLanding.marked = true
			t.expect(
				has(work.finalStep(afterLanding, "c0020", afterLanding.layers[2], "blocked").why, "--through")
			)
				.toBe(false)
		end
	)

	it(
		"AC8: a raft without layers: reviewed lands whole: a block or a redesign is never told to land layers with --through",
		function()
			for _, state in { "blocked", "redo-design", "invalid" } do
				local d = step(raft({ layer(1, "c0010", "on-course"), layer(2, "c0020", state) }))
				t.expect(has(d.why, "--through")).toBe(false)
				t.expect(has(d.why, "lands whole")).toBe(true)
			end
		end
	)

	it("AC6: the layer's code review comes before the ticket's final review", function()
		local unsettled = layer(1, "c0010", "none")
		unsettled.reviewReason = "review-001.md is not current"
		local d = step(raft({ unsettled }))
		t.expect(d.action).toBe("review")
		t.expect(string.find(d.why, "review-001.md is not current", 1, true) ~= nil).toBe(true)
		local settled = layer(1, "c0010", "none")
		settled.reviewReason = ""
		t.expect(step(raft({ settled })).action).toBe("final-review-ticket")
	end)
end)
