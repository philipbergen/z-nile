--!strict
-- f0417 AC4, AC12: `./zn work next` runs the idea stage of a new ticket (action `idea`, after `draft`), never guesses
-- the person's words, and walks a marked raft's code review as a loop of rounds. Facts built by hand, as f0399's
-- pick.spec builds them; a fact without the new fields behaves as before. Pure.
local t = require("@tests/lib/t")
local work = require("@znile/engine/work")

local ADA = "Ada <ada@example>"
local UNCHALLENGED = "no idea-review-001.md (the idea was not challenged): ./zn idea c0002"

local function has(text: string?, needle: string): boolean
	return string.find(text or "", needle, 1, true) ~= nil
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

local function layer(position: number, id: string): work.LayerFact
	return {
		position = position,
		issue = id,
		name = `R/{position}/{id}`,
		commits = 1,
		onlyStart = false,
		finished = true,
	}
end

-- an active raft whose every other gate has passed, its code review left to the loop
local function built(over: { [string]: any }?): work.RaftFact
	local r: work.RaftFact = {
		id = "R0010",
		title = "t",
		where = "active",
		status = "active",
		designReady = true,
		depsMet = true,
		questions = false,
		issues = { "c0010" },
		layers = { layer(1, "c0010") },
		holder = ADA,
		since = "",
		stacked = true,
		codeReview = "none",
		finalReview = "approved",
		trace = true,
		traceOk = true,
		root = "z-nile/.tracker",
		lands = true,
	}
	for k, v in (over or {}) :: { [string]: any } do
		(r :: any)[k] = v
	end
	return r
end

local function decide(rafts: { work.RaftFact }, issues: { work.IssueFact }?, asked: string?): work.Decision
	return work.decide({ asked = asked, author = ADA, session = "S1", rafts = rafts, issues = issues })
end

local function state(kind: string, over: { [string]: any }?): any
	local s = { kind = kind, count = 0, cap = 9, last = 0, human = {} }
	for k, v in (over or {}) :: { [string]: any } do
		(s :: any)[k] = v
	end
	return s
end

return t.spec("f0417: work next runs the idea stage and the code loop", function(it)
	it("a new ticket whose idea can run is picked as idea, after draft", function()
		local runnable = issue("c0002", { draftBlock = UNCHALLENGED, idea = "run" })
		local draftable = issue("c0003")
		local first = decide({}, { runnable, draftable })
		t.expect(first.action).toBe("draft")
		t.expect(first.ticket).toBe("c0003")
		local only = decide({}, { runnable })
		t.expect(only.action).toBe("idea")
		t.expect(only.ticket).toBe("c0002")
		t.expect(work.say(only):sub(1, 14)).toBe("c0002: idea - ")
	end)

	it("the idea line runs ./zn idea in guess mode and never guesses a question for the person", function()
		local d = decide({}, { issue("c0002", { draftBlock = UNCHALLENGED, idea = "run" }) })
		t.expect(has(d.why, "./zn idea c0002 --guess")).toBe(true)
		t.expect(has(d.why, "guess mode")).toBe(true)
		t.expect(has(d.why, "up to 5 rounds")).toBe(true)
		t.expect(has(d.why, "never guess it")).toBe(true)
		t.expect(has(d.why, "pull request")).toBe(true)
	end)

	it("an idea waiting for the person is skipped, naming why", function()
		local waiting = issue("c0004", {
			draftBlock = "open to the human (F1)",
			ideaWhy = "F1 (idea-review-002 F1) waits for the person's answer",
		})
		local d = decide({}, { waiting })
		t.expect(d.action).toBe("none")
		t.expect(has(d.why, "c0004: its idea needs the person (F1 (idea-review-002 F1) waits")).toBe(true)
	end)

	it("an issue fact without idea is skipped as before", function()
		local d = decide({}, { issue("c0002", { draftBlock = UNCHALLENGED }) })
		t.expect(d.action).toBe("none")
		t.expect(has(d.why, "c0002: its idea needs the person (no idea-review-001.md")).toBe(true)
	end)

	it("a named new ticket gets the idea line", function()
		local d = decide({}, { issue("c0002", { draftBlock = UNCHALLENGED, idea = "run" }) }, "c0002")
		t.expect(d.action).toBe("idea")
		t.expect(has(d.why, "./zn idea c0002")).toBe(true)
	end)

	it("a marked raft's code review is a loop: round 1, answer, next round, the cap", function()
		local function with(st: any, gate: string?): work.RaftFact
			local l = layer(1, "c0010") :: any
			l.codeRounds = st
			l.codeGate = gate
			return built({ layers = { l } })
		end
		local one = decide({ with(state("none", { next = 1 })) }, {}, "R0010")
		t.expect(one.action).toBe("review")
		t.expect(has(one.why, "Run code review round 1 of 9 for c0010")).toBe(true)
		local answer = decide({ with(state("answer", { count = 2, last = 2 })) }, {}, "R0010")
		t.expect(answer.action).toBe("review")
		t.expect(has(answer.why, "Answer code review round 2 of c0010")).toBe(true)
		local nxt = decide({ with(state("next", { count = 2, last = 2, next = 3 })) }, {}, "R0010")
		t.expect(nxt.action).toBe("review")
		t.expect(has(nxt.why, "Run code review round 3 of 9 for c0010")).toBe(true)
		t.expect(has(nxt.why, "new clean reviewer")).toBe(true)
		t.expect(has(nxt.why, "fix delta")).toBe(true)
		local capped = decide({
			with(
				state("cap", { count = 9, last = 9, human = { "review-009 F1" } }),
				"review-009 F1 is not ruled"
			),
		}, {}, "R0010")
		t.expect(capped.action).toBe("review")
		t.expect(has(capped.why, "review-009 F1")).toBe(true)
		t.expect(has(capped.why, "./zn block R0010 review-exhausted --layer c0010")).toBe(true)
		t.expect(has(capped.why, "./zn guess c0010 --step build")).toBe(true)
		local settled = decide(
			{ with(state("cap", { count = 9, last = 9, human = { "review-009 F1" } }), "") },
			{},
			"R0010"
		)
		t.expect(settled.action).toBe("done")
		local ended = decide({ with(state("ended", { count = 3, last = 3 }), "") }, {}, "R0010")
		t.expect(ended.action).toBe("done")
	end)

	it("each layer has its own loop: the lowest layer whose loop has not ended is named", function()
		local l1, l2 = layer(1, "c0010") :: any, layer(2, "c0020") :: any
		l1.codeRounds = state("next", { count = 1, last = 1, next = 2 })
		l2.codeRounds = state("ended", { count = 2, last = 2 })
		l2.codeGate = ""
		local d = decide({ built({ issues = { "c0010", "c0020" }, layers = { l1, l2 } }) }, {}, "R0010")
		t.expect(d.action).toBe("review")
		t.expect(has(d.why, "for c0010")).toBe(true)
		t.expect(has(d.why, "c0020")).toBe(false)
		l1.codeRounds = state("ended", { count = 2, last = 2 })
		l1.codeGate = ""
		l2.codeRounds = state("answer", { count = 1, last = 1 })
		local d2 = decide({ built({ issues = { "c0010", "c0020" }, layers = { l1, l2 } }) }, {}, "R0010")
		t.expect(has(d2.why, "Answer code review round 1 of c0020")).toBe(true)
		-- two layers whose loops are both open: the lower one first
		l1.codeRounds = state("answer", { count = 1, last = 1 })
		l1.codeGate = "x"
		l2.codeRounds = state("next", { count = 1, last = 1, next = 2 })
		local d3 = decide({ built({ issues = { "c0010", "c0020" }, layers = { l1, l2 } }) }, {}, "R0010")
		t.expect(has(d3.why, "Answer code review round 1 of c0010")).toBe(true)
	end)

	it("a raft without codeRounds keeps the one review", function()
		local d = decide({ built() }, {}, "R0010")
		t.expect(d.action).toBe("review")
		t.expect(has(d.why, "of 9")).toBe(false) -- today's (or c0248's) one review, whatever its words
		t.expect(decide({ built({ codeReview = "resolved" }) }, {}, "R0010").action).toBe("done")
	end)
end)
