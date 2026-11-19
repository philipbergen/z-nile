--!strict
-- f0417 AC1, AC2, AC3, AC10: the round rule (z-nile/engine/rounds.luau), pure. A loop goes back and forth until a
-- round approves with no open finding, or its cap (idea 5, design 9, code 9) is reached; then what is open is the
-- human's. Reviews and refutes are written here as the skills write them.
local rounds = require("@znile/engine/rounds")
local t = require("@tests/lib/t")

local function has(text: string?, needle: string): boolean
	return string.find(text or "", needle, 1, true) ~= nil
end

-- a design or code review: findings as { id, severity, claim }, then the verdict
local function review(verdict: string, findings: { { string } }?): string
	local out = "# Review NNN: c0001 (design mode)\nInputs: x\n\n"
	for _, f in (findings or {}) :: { { string } } do
		out ..= `### {f[1]} [{f[2]}] {f[3] or "a claim"}\nWhere: x\nEvidence: y\nErred: z-design\nUpstream: none\n\n`
	end
	return out .. `Verdict: {verdict}\n`
end

-- a refute: { id, "fixed" | "refuted" | "deferred c0099" }
local function refute(answers: { { string } }): string
	local out = "# Refute NNN\n\n"
	for _, a in answers do
		if a[2] == "fixed" then
			out ..= `- {a[1]}: fixed: done; consequences: none\n`
		elseif a[2] == "refuted" then
			out ..= `- {a[1]}: refuted: the design says so\n`
		else
			out ..= `- {a[1]}: {a[2]}: later\n`
		end
	end
	return out
end

local function idea(verdict: string, findings: { string }?): string
	local out = "# Idea review NNN\n\n## Findings\n"
	if not findings or #findings == 0 then
		out ..= "- F1: none\n"
	else
		for i, f in findings do
			out ..= `- F{i}: {f}\n`
		end
	end
	return out .. `\n## Verdict\n{verdict}\n`
end

local NONE: rounds.Window = { from = 1, extra = 0 }

-- n rounds of design, each `changes` with one medium finding answered fixed
local function answeredDesign(n: number): { rounds.Round }
	local list: { rounds.Round } = {}
	for i = 1, n do
		table.insert(
			list,
			rounds.read("design", i, review("changes", { { "F1", "medium" } }), refute({ { "F1", "fixed" } }))
		)
	end
	return list
end

return t.spec("f0417: the round rule", function(it)
	it("the caps are the owner's: 5, 9, 9", function()
		t.expect(rounds.CAP.idea).toBe(5)
		t.expect(rounds.CAP.design).toBe(9)
		t.expect(rounds.CAP.code).toBe(9)
		t.expect(rounds.PREFIX.design[1]).toBe("design-review-")
		t.expect(rounds.PREFIX.code[1]).toBe("review-")
		t.expect(rounds.PREFIX.idea[2]).toBe("idea-refute-")
	end)

	it("no round: none, the next file one past the folder's highest", function()
		local s = rounds.state("design", {}, NONE)
		t.expect(s.kind).toBe("none")
		t.expect(s.next).toBe(1)
		t.expect(s.count).toBe(0)
		-- an older item's rounds below the window still number the folder
		local old = answeredDesign(3)
		local fresh = rounds.state("design", old, { from = 4, extra = 0 })
		t.expect(fresh.kind).toBe("none")
		t.expect(fresh.next).toBe(4)
	end)

	it("an approving round with no finding ends the loop", function()
		local list = answeredDesign(2)
		table.insert(list, rounds.read("design", 3, review("approve"), nil))
		local s = rounds.state("design", list, NONE)
		t.expect(s.kind).toBe("ended")
		t.expect(s.last).toBe(3)
		t.expect(#s.human).toBe(0)
	end)

	it(
		"an approving round's low finding answered by an edit needs another round; by a refute it ends",
		function()
			local low = review("approve", { { "F1", "low" } })
			local edited =
				rounds.state("design", { rounds.read("design", 1, low, refute({ { "F1", "fixed" } })) }, NONE)
			t.expect(edited.kind).toBe("next")
			t.expect(edited.next).toBe(2)
			local kept = rounds.state(
				"design",
				{ rounds.read("design", 1, low, refute({ { "F1", "refuted" } })) },
				NONE
			)
			t.expect(kept.kind).toBe("ended")
			-- unanswered, it waits
			t.expect(rounds.state("design", { rounds.read("design", 1, low, nil) }, NONE).kind).toBe("answer")
		end
	)

	it("a round with an unanswered finding waits for the answer", function()
		local r = review("changes", { { "F1", "high" }, { "F2", "low" } })
		t.expect(rounds.state("code", { rounds.read("code", 1, r, nil) }, NONE).kind).toBe("answer")
		local half = rounds.read("code", 1, r, refute({ { "F1", "fixed" } }))
		t.expect(rounds.state("code", { half }, NONE).kind).toBe("answer")
	end)

	it("an answered round under the cap is followed by the next", function()
		local s = rounds.state("design", answeredDesign(4), NONE)
		t.expect(s.kind).toBe("next")
		t.expect(s.next).toBe(5)
		t.expect(s.count).toBe(4)
		t.expect(s.cap).toBe(9)
		-- a disapproval with no finding is answered by the next reviewer
		local bare = rounds.state("design", { rounds.read("design", 1, review("changes"), nil) }, NONE)
		t.expect(bare.kind).toBe("next")
	end)

	it("the design loop stops at the ninth round, not the eighth or the tenth", function()
		t.expect(rounds.state("design", answeredDesign(8), NONE).kind).toBe("next")
		t.expect(rounds.state("design", answeredDesign(9), NONE).kind).toBe("cap")
		t.expect(rounds.state("code", answeredDesign(9), NONE).kind).toBe("cap")
		-- the ninth round still gets its one answer before the cap applies
		local nine = answeredDesign(8)
		table.insert(nine, rounds.read("design", 9, review("changes", { { "F1", "medium" } }), nil))
		t.expect(rounds.state("design", nine, NONE).kind).toBe("answer")
	end)

	it("at the cap the human gets every high, refuted and unanswered finding of the last round", function()
		local list = answeredDesign(8)
		local last = review("changes", {
			{ "F1", "high" },
			{ "F2", "medium" },
			{ "F3", "medium" },
			{ "F4", "low" },
			{ "F5", "low" },
		})
		table.insert(
			list,
			rounds.read(
				"design",
				9,
				last,
				refute({
					{ "F1", "fixed" },
					{ "F2", "fixed" },
					{ "F3", "refuted" },
					{ "F4", "deferred c0099" },
					{ "F5", "fixed" },
				})
			)
		)
		local s = rounds.state("design", list, NONE)
		t.expect(s.kind).toBe("cap")
		table.sort(s.human)
		t.expect(s.human).toEqual({ "design-review-009 F1", "design-review-009 F3", "design-review-009 F4" })
	end)

	it("a repeat refuted again goes to the human before the cap", function()
		local one = rounds.read(
			"design",
			1,
			review("changes", { { "F1", "medium", "the cap is wrong" } }),
			refute({ { "F1", "refuted" } })
		)
		local two = rounds.read(
			"design",
			2,
			review(
				"changes",
				{ { "F1", "low" }, { "F2", "medium", "the cap is wrong (repeat of design-review-001 F1)" } }
			),
			refute({ { "F1", "fixed" }, { "F2", "refuted" } })
		)
		t.expect(two.findings[2].repeatOf).toBe("design-review-001 F1")
		local s = rounds.state("design", { one, two }, NONE)
		t.expect(s.kind).toBe("next")
		t.expect(s.human).toEqual({ "design-review-002 F2" })
		-- a repeat the author then fixes is not the human's
		local fixedTwo = rounds.read(
			"design",
			2,
			review("changes", { { "F1", "medium", "the cap is wrong (repeat of design-review-001 F1)" } }),
			refute({ { "F1", "fixed" } })
		)
		t.expect(#rounds.state("design", { one, fixedTwo }, NONE).human).toBe(0)
	end)

	it(
		"the idea loop stops at the fifth challenge, which is never answered, and all it found is the human's",
		function()
			local list: { rounds.Round } = {}
			for i = 1, 4 do
				table.insert(
					list,
					rounds.read("idea", i, idea("revise", { "too big." }), "# Idea refute\n\n- F1: revised\n")
				)
			end
			t.expect(rounds.state("idea", list, NONE).kind).toBe("next")
			table.insert(
				list,
				rounds.read("idea", 5, idea("revise", { "still big.", "ask: which board?" }), nil)
			)
			local s = rounds.state("idea", list, NONE)
			t.expect(s.kind).toBe("cap")
			t.expect(s.cap).toBe(5)
			table.sort(s.human)
			t.expect(s.human).toEqual({ "idea-review-005 F1", "idea-review-005 F2" })
			-- the third challenge, c0260's old cap, is not the end
			local three = { list[1], list[2], rounds.read("idea", 3, idea("revise", { "x." }), nil) }
			t.expect(rounds.state("idea", three, NONE).kind).toBe("answer")
		end
	)

	it("an idea approval that still lists a finding does not end the loop", function()
		local listed = rounds.read("idea", 1, idea("approve", { "one more thing." }), nil)
		t.expect(rounds.state("idea", { listed }, NONE).kind).toBe("answer")
		local clean = rounds.read("idea", 1, idea("approve"), nil)
		t.expect(rounds.state("idea", { clean }, NONE).kind).toBe("ended")
	end)

	it("the window: a new loop from a file, and one more round past a file", function()
		local doc = table.concat({
			"## Problem",
			"- x.",
			"Decided with the user (2026-11-20): a new design loop from design-review-009", -- not a Loops line: ignored
			"",
			"## Loops",
			"- Loop (tool, 2026-11-20): a new design loop from design-review-004",
			"- Loop (Ada, 2026-11-21): one more design round past design-review-002",
			"- Loop (Ada, 2026-11-22): one more design round past design-review-004",
			"- Loop (Ada, 2026-11-23): one more design round past design-review-013",
			"- Loop (Ada, 2026-11-23): one more code round past review-013",
			"- Loop (tool, 2026-11-19): a new design loop from design-review-002",
			"",
		}, "\n")
		local w = rounds.window(doc, "design")
		t.expect(w.from).toBe(4)
		t.expect(w.extra).toBe(2) -- past 004 counts (at from), past 002 lies below the window
		t.expect(rounds.window(doc, "code").extra).toBe(1)
		t.expect(rounds.window(doc, "idea").from).toBe(1)
		t.expect(
			rounds.window(
				"## Problem\nDecided with the user (2026-11-20): a new design loop from design-review-009\n",
				"design"
			).from
		).toBe(1)
		-- rounds 4..12 are nine; with two extra the loop goes on to 14
		local list = answeredDesign(12)
		local s = rounds.state("design", list, w)
		t.expect(s.count).toBe(9)
		t.expect(s.cap).toBe(11)
		t.expect(s.kind).toBe("next")
		t.expect(s.next).toBe(13)
	end)

	it(
		"an ask waits for the person until the Interview answers it; the idea gate asks every open line ruled",
		function()
			local function withRound(text: string, q: number): string
				return (
					string.gsub(
						text,
						"\n\n## Findings",
						`\nRound: ask 1, interview {q}, idea abc123\n\n## Findings`,
						1
					)
				)
			end
			local askOnly = rounds.read("idea", 1, withRound(idea("revise", { "ask: which board?" }), 1), nil)
			t.expect(askOnly.findings[1].ask).toBe(true)
			t.expect(askOnly.interview).toBe(1)
			local oneQ =
				"## Interview\n### Q1\nwhat?\nA: this.\n\n## Open to the human\n- F1: ask: which board?\n"
			local waits = rounds.state("idea", { askOnly }, NONE, oneQ)
			t.expect(waits.kind).toBe("person")
			t.expect(has(rounds.filing("idea", { askOnly }, NONE, oneQ).refusal, "asks the person"))
				.toBe(true)
			local twoQ =
				"## Interview\n### Q1\nwhat?\nA: this.\n### Q2\nwhich board?\nA: the main one.\n\n## Open to the human\n- F1: ask: which board?\n"
			local goes = rounds.state("idea", { askOnly }, NONE, twoQ)
			t.expect(goes.kind).toBe("next")
			t.expect(goes.next).toBe(2)
			-- a mixed round answered for its other finding goes on
			local mixed = rounds.read(
				"idea",
				1,
				withRound(idea("revise", { "too big.", "ask: which board?" }), 1),
				"# Idea refute\n\n- F1: revised\n"
			)
			t.expect(rounds.state("idea", { mixed }, NONE, oneQ).kind).toBe("next")
			-- an ended loop passes the gate only once c0260's open list is ruled; a Guessed line is not enough
			local clean = rounds.read("idea", 2, idea("approve"), nil)
			t.expect(rounds.state("idea", { mixed, clean }, NONE, oneQ).kind).toBe("ended")
			t.expect(has(rounds.gate("idea", { mixed, clean }, NONE, oneQ), "F1")).toBe(true)
			t.expect(
				rounds.gate("idea", { mixed, clean }, NONE, oneQ .. "  Guessed (agent, 2026-11-20): G1\n")
					~= nil
			).toBe(true)
			t.expect(
				rounds.gate("idea", { mixed, clean }, NONE, oneQ .. "  Ruled (user, 2026-11-20): main.\n")
			)
				.toBe(nil)
		end
	)

	it("a stale round at the cap waits for the person", function()
		local list = answeredDesign(8)
		local last = rounds.read("code", 9, review("approve"), nil)
		last.current = false
		table.insert(list, last)
		local s = rounds.state("code", list, NONE)
		t.expect(s.kind).toBe("cap")
		t.expect(s.human).toEqual({ "review-009 stale" })
		t.expect(rounds.gate("code", list, NONE, "## Open to the human\nnone\n") ~= nil).toBe(true)
	end)

	it("a Loops line counts only when origin holds it, or it is the new ask's new idea loop", function()
		local base =
			"---\nid: c0001\nrounds: on\n---\n\n## Ask (verbatim)\n### Message 2026-11-18\nx\n\n## Loops\n- Loop (Ada, 2026-11-19): one more design round past design-review-009\n- Loop (tool, 2026-11-19): a new design loop from design-review-010\n"
		local highest = { idea = 2, design = 9, code = 0 }
		t.expect(rounds.loopsProblem(base, base, highest, false)).toBe(nil) -- the claim published its own line with the claim
		local granted = base .. "- Loop (agent, 2026-11-20): one more design round past design-review-010\n"
		t.expect(
			has(
				rounds.loopsProblem(base, granted, highest, false),
				"one more design round past design-review-010"
			)
		).toBe(true)
		local moved = base .. "- Loop (tool, 2026-11-20): a new design loop from design-review-011\n"
		t.expect(
			has(rounds.loopsProblem(base, moved, highest, false), "a new design loop from design-review-011")
		)
			.toBe(true)
		local newIdea = base .. "- Loop (Ada, 2026-11-20): a new idea loop from idea-review-003\n"
		t.expect(rounds.loopsProblem(base, newIdea, highest, true)).toBe(nil)
		t.expect(rounds.loopsProblem(base, newIdea, highest, false) ~= nil).toBe(true)
		local oldIdea = base .. "- Loop (Ada, 2026-11-20): a new idea loop from idea-review-002\n"
		t.expect(rounds.loopsProblem(base, oldIdea, highest, true) ~= nil).toBe(true) -- only from the next number
		t.expect(rounds.loopsProblem(nil, granted, highest, false) ~= nil).toBe(true)
		-- a line origin holds that the branch's copy dropped (or never synced) is refused too: sync first
		local dropped = (
			string.gsub(
				base,
				"%- Loop %(tool, 2026%-11%-19%): a new design loop from design%-review%-010\n",
				""
			)
		)
		local why = rounds.loopsProblem(base, dropped, highest, false)
		t.expect(has(why, "a new design loop from design-review-010")).toBe(true)
		t.expect(has(why, "./zn sync")).toBe(true)
	end)

	it(
		"a loop may restart exactly when its gate passes (ended, or a cap ruled or guessed), or the claim adopts an older reviewed issue",
		function()
			local doc = "## Open to the human\nnone\n"
			local ended = answeredDesign(1)
			table.insert(ended, rounds.read("design", 2, review("approve"), nil))
			t.expect(rounds.restartable(ended, NONE, doc, false)).toBe(true)
			t.expect(rounds.restartable(answeredDesign(3), NONE, doc, false)).toBe(false) -- mid-loop
			local capped = answeredDesign(8)
			table.insert(
				capped,
				rounds.read(
					"design",
					9,
					review("changes", { { "F1", "high" } }),
					"- F1: fixed: x; consequences: none\n"
				)
			)
			local bullet =
				"## Open to the human\n- F1: (design-review-009 F1) a high. Answer: fixed. Decision: accept?\n"
			t.expect(rounds.restartable(capped, NONE, bullet, false)).toBe(false) -- an unruled cap is the person's
			-- a cap closed by Guessed lines passes the gate, so a redesign of it must start a new loop too
			t.expect(rounds.restartable(capped, NONE, bullet .. "  Guessed (agent, 2026-11-20): G4\n", false))
				.toBe(true)
			t.expect(
				rounds.restartable(capped, NONE, bullet .. "  Ruled (user, 2026-11-20): accepted.\n", false)
			)
				.toBe(true)
			-- an older issue adopted by this claim, with one-round-era reviews in its folder
			t.expect(rounds.restartable(answeredDesign(7), NONE, doc, true)).toBe(true)
			t.expect(rounds.restartable({}, NONE, doc, true)).toBe(false) -- nothing to restart
		end
	)

	it(
		"an idea approval whose only findings are asks waits for the answer, then takes the next round",
		function()
			local function withRound(text: string, q: number): string
				return (
					string.gsub(
						text,
						"\n\n## Findings",
						`\nRound: ask 1, interview {q}, idea abc123\n\n## Findings`,
						1
					)
				)
			end
			local r = rounds.read("idea", 1, withRound(idea("approve", { "ask: which board?" }), 1), nil)
			local oneQ = "## Interview\n### Q1\nwhat?\n"
			t.expect(rounds.state("idea", { r }, NONE, oneQ).kind).toBe("person")
			local twoQ = "## Interview\n### Q1\nwhat?\n### Q2\nwhich board?\nA: main.\n"
			t.expect(rounds.state("idea", { r }, NONE, twoQ).kind).toBe("next") -- the answer is challenged, never taken as ended
		end
	)

	it("a ruled stale bullet answers the stale entry at the cap", function()
		local list = answeredDesign(8)
		local last = rounds.read("code", 9, review("approve"), nil)
		last.current = false
		table.insert(list, last)
		local bullet =
			"## Open to the human\n- F1: (review-009 stale) round 9 reviewed an older patch. Answer: rebuilt. Decision: review again?\n"
		t.expect(rounds.gate("code", list, NONE, bullet) ~= nil).toBe(true)
		t.expect(
			rounds.gate(
				"code",
				list,
				NONE,
				bullet .. "  Ruled (user, 2026-11-20): the rebuild only renamed a helper.\n"
			)
		).toBe(nil)
	end)

	it("a code round that reviewed an older patch is followed by the next, even when it approved", function()
		local old = rounds.read("code", 1, review("approve"), nil)
		old.current = false
		local s = rounds.state("code", { old }, NONE)
		t.expect(s.kind).toBe("next")
		t.expect(s.next).toBe(2)
		local now = rounds.read("code", 1, review("approve"), nil)
		t.expect(rounds.state("code", { now }, NONE).kind).toBe("ended")
	end)

	it("the mark is read from the frontmatter only", function()
		t.expect(rounds.marked("---\nid: c0001\nrounds: on\nstatus: new\n---\n\n# c0001\n")).toBe(true)
		t.expect(rounds.marked("---\nid: c0001\nstatus: new\n---\n\n# c0001\n")).toBe(false)
		t.expect(rounds.marked("---\nid: c0001\nrounds: off\n---\n")).toBe(false)
		t.expect(rounds.marked("---\nid: c0001\n---\n\nrounds: on\n")).toBe(false) -- body text is not the mark
	end)

	it("filing numbers the next round and refuses an ended, unanswered or capped loop, naming why", function()
		t.expect(rounds.filing("design", {}, NONE).number).toBe(1)
		t.expect(rounds.filing("design", answeredDesign(3), NONE).number).toBe(4)
		local ended = answeredDesign(1)
		table.insert(ended, rounds.read("design", 2, review("approve"), nil))
		local e = rounds.filing("design", ended, NONE)
		t.expect(e.number).toBe(nil)
		t.expect(has(e.refusal, "design-review-002")).toBe(true)
		t.expect(has(e.refusal, "the loop ended")).toBe(true)
		local open = { rounds.read("code", 1, review("changes", { { "F1", "high" } }), nil) }
		local a = rounds.filing("code", open, NONE)
		t.expect(a.number).toBe(nil)
		t.expect(has(a.refusal, "answer review-001 first")).toBe(true)
		local c = rounds.filing("design", answeredDesign(9), NONE)
		t.expect(c.number).toBe(nil)
		t.expect(has(c.refusal, "cap of 9 rounds")).toBe(true)
		t.expect(has(c.refusal, "./zn block")).toBe(true)
		t.expect(has(c.refusal, "./zn resolve")).toBe(true)
		t.expect(has(c.refusal, "one more design round past")).toBe(false) -- an agent is never told to grant itself a round
		t.expect(rounds.filing("design", answeredDesign(9), { from = 1, extra = 1 }).number).toBe(10)
	end)

	it(
		"the gate: ended or capped with every human entry ruled; guessed passes for design, never for the idea",
		function()
			local ended = { rounds.read("design", 1, review("approve"), nil) }
			t.expect(rounds.gate("design", ended, NONE, "## Problem\n- x.\n")).toBe(nil)
			t.expect(rounds.gate("design", answeredDesign(2), NONE, "## Problem\n- x.\n") ~= nil).toBe(true)
			local capped = answeredDesign(8)
			table.insert(
				capped,
				rounds.read(
					"design",
					9,
					review("changes", { { "F1", "high" } }),
					refute({ { "F1", "fixed" } })
				)
			)
			local unruled =
				"## Open to the human\n- F1: (design-review-009 F1) a high. Answer: fixed. Decision: accept?\n"
			local refusal = rounds.gate("design", capped, NONE, unruled)
			t.expect(has(refusal, "design-review-009 F1")).toBe(true)
			local missing = rounds.gate("design", capped, NONE, "## Open to the human\nnone\n")
			t.expect(has(missing, "design-review-009 F1")).toBe(true)
			local ruled = unruled .. "  Ruled (user, 2026-11-20): accepted.\n"
			t.expect(rounds.gate("design", capped, NONE, ruled)).toBe(nil)
			local guessed = unruled .. "  Guessed (agent, 2026-11-20): G4\n"
			t.expect(rounds.gate("design", capped, NONE, guessed)).toBe(nil)
			local ideas: { rounds.Round } = {}
			for i = 1, 5 do
				table.insert(
					ideas,
					rounds.read("idea", i, idea("revise", { "x." }), if i < 5 then "- F1: revised\n" else nil)
				)
			end
			local ideaOpen =
				"## Open to the human\n- F1: (idea-review-005 F1) x. Answer: none. Decision: which?\n"
			t.expect(
				rounds.gate("idea", ideas, NONE, ideaOpen .. "  Guessed (agent, 2026-11-20): G1\n") ~= nil
			)
				.toBe(true)
			t.expect(rounds.gate("idea", ideas, NONE, ideaOpen .. "  Ruled (user, 2026-11-20): this one.\n"))
				.toBe(nil)
		end
	)
end)
