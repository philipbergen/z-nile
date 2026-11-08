--!strict
-- c0260 AC4: the idea review's record in the issue document: each raw review has its `### Round N` block with every
-- finding answered, and the Confirmation (or the unattended pair of lines) names the last round. judged by
-- capturecheck over texts.
local capturecheck = require("@znile/engine/capturecheck")
local t = require("@tests/lib/t")

local function doc(interview: string, confirmation: string, answers: string?): string
	return table.concat({
		"---\nid: c0900\n---\n\n## Problem\nP\n\n## Ask (verbatim)\n### Message 2026-11-07\n```\nmore ghosts\n```\n",
		"\n## Interview\n" .. interview .. "\n",
		"\n## Idea\nMore ghosts.\n\n## Idea review\n### Round 1\n" .. (answers or "- F1: fixed: x\n- F2: refuted: y\n"),
		"\n## Confirmation\n" .. confirmation .. "\n\n## Design\n",
	})
end
local Q = "### Q1\nQuestion: how many?\nOptions: 1 | 2\nAnswer: 2\n"
local NONE = ""
local CONFIRMED = 'Confirmed (user, 2026-11-07) after round 1: "yes"'
local UNCONFIRMED = "Unconfirmed (unattended, 2026-11-07) after round 1: the dispatch was started with this ask"
local REVIEWS = { ["idea-review-001.md"] = "# R\n\n### F1 [high] a\n\n### F2 [low] b\n" }
local function problems(d: string, reviews: { [string]: string }?): string
	return table.concat(capturecheck.check(d, reviews or REVIEWS), "\n")
end
local function has(text: string, part: string): boolean
	return string.find(text, part, 1, true) ~= nil
end

return t.spec("c0260 the idea review's record", function(it)
	it("AC4: a reviewed idea confirmed by the user passes", function()
		t.expect(problems(doc(Q, CONFIRMED))).toBe("")
	end)

	it("AC4: every raw review has its Round block and every finding an answer of the three kinds", function()
		t.expect(
			has(problems(doc(Q, CONFIRMED, "- F1: fixed: x\n")), "finding F2 of idea-review-001.md has no answer line")
		)
			.toBe(true)
		t.expect(has(problems(doc(Q, CONFIRMED, "- F1: fixed: x\n- F2: maybe: y\n")), 'answered "maybe"')).toBe(true)
		t.expect(has(problems(doc(Q, CONFIRMED, "- F1: fixed: x\n- F2: refuted: y\n- F3: fixed: z\n")), "answers F3"))
			.toBe(true)
		t.expect(has(problems(doc(Q, CONFIRMED, "- F1: fixed:\n- F2: refuted: y\n")), "F1 has an empty answer"))
			.toBe(true)
		local two = { ["idea-review-001.md"] = REVIEWS["idea-review-001.md"], ["idea-review-002.md"] = "# R2\n" }
		t.expect(has(problems(doc(Q, CONFIRMED), two), 'no "### Round 2" block')).toBe(true)
	end)

	it("AC4: an idea that was never reviewed, or a gap in the rounds, is refused", function()
		t.expect(has(problems(doc(Q, CONFIRMED), {}), "the idea was never reviewed")).toBe(true)
		t.expect(
			has(problems(doc(Q, CONFIRMED), { ["idea-review-002.md"] = "# R\n" }), "idea-review-001.md is missing")
		)
			.toBe(true)
	end)

	it("AC4: the confirmation names the last review round, and is in the exact form", function()
		t.expect(has(problems(doc(Q, 'Confirmed (user, 2026-11-07) after round 2: "yes"')), "but the last round is 1"))
			.toBe(true)
		t.expect(has(problems(doc(Q, 'Confirmed (user, 7 Nov) after round 1: "yes"')), "Confirmation lines read"))
			.toBe(true)
		t.expect(has(problems(doc(Q, "the user said yes")), "Confirmation lines read")).toBe(true)
		t.expect(has(problems(doc(Q, "")), "holds one line")).toBe(true)
	end)

	it(
		"AC4: a dispatched capture ends Unconfirmed (unattended) and may be confirmed later by a distinct line",
		function()
			t.expect(problems(doc(Q, UNCONFIRMED))).toBe("")
			t.expect(problems(doc(NONE .. Q, UNCONFIRMED .. "\n" .. CONFIRMED))).toBe("")
			t.expect(capturecheck.unconfirmed(doc(Q, UNCONFIRMED))).toBe(true)
			t.expect(capturecheck.unconfirmed(doc(NONE .. Q, UNCONFIRMED .. "\n" .. CONFIRMED))).toBe(false)
		end
	)

	it("AC4: the unattended and user forms cannot be mixed; an Unconfirmed line follows any interview", function()
		t.expect(problems(doc(Q, UNCONFIRMED))).toBe("") -- a dispatched capture holds at least Q1, the restatement
		t.expect(has(problems(doc(Q, "Confirmed (unattended, 2026-11-07) after round 1: ok")), "cannot be unattended"))
			.toBe(true)
		t.expect(has(problems(doc(NONE .. Q, CONFIRMED .. "\n" .. UNCONFIRMED)), "comes first")).toBe(true)
		t.expect(has(problems(doc(NONE .. Q, UNCONFIRMED .. "\n" .. UNCONFIRMED)), "Confirmed")).toBe(true)
		t.expect(has(problems(doc(Q, "Unconfirmed (user, 2026-11-07) after round 1: x")), "only ever `(unattended"))
			.toBe(true)
	end)

	it("AC4: an interview that is only `None: <why>` (a dropped Q1) is refused", function()
		t.expect(has(problems(doc("None: the ask was complete\n", CONFIRMED)), "not an interview")).toBe(true)
		t.expect(has(problems(doc("", CONFIRMED)), "no ### Q1 block")).toBe(true)
	end)

	it("AC4: the confirmer is any text without a comma or parenthesis (a git identity with spaces passes)", function()
		t.expect(problems(doc(Q, 'Confirmed (Philip Bergen <p@example.invalid>, 2026-11-08) after round 1: "yes"')))
			.toBe("")
		t.expect(has(problems(doc(Q, 'Confirmed (A, B, 2026-11-08) after round 1: "yes"')), "Confirmation lines read"))
			.toBe(true)
	end)

	it("AC4: a document with no capture section is never parsed, whatever fences it holds", function()
		t.expect(table.concat(capturecheck.check("## Problem\n```bash title=x\nunclosed\n", {}), "")).toBe("")
		t.expect(capturecheck.kind("## Problem\n```\nunclosed\n")).toBe("none")
		t.expect(capturecheck.confirmed("## Problem\n```\nunclosed\n")).toBe(false)
	end)

	it("AC4: a dispatched run never confirms: the helper land uses sees a Confirmed line and only that", function()
		t.expect(capturecheck.confirmed(doc(Q, CONFIRMED))).toBe(true)
		t.expect(capturecheck.confirmed(doc(Q, UNCONFIRMED))).toBe(false)
	end)

	it("AC4: the record comes before the Design", function()
		local late = doc(Q, CONFIRMED)
		local body = string.gsub(late, "\n## Design\n$", "\n")
		t.expect(has(problems(body .. "\n## Design\nD\n"), "comes before")).toBe(false)
		local before = string.gsub(late, "## Ask %(verbatim%)", "## Design\nD\n\n## Ask (verbatim)", 1)
		t.expect(has(problems(before), "the capture record comes before ## Design")).toBe(true)
	end)

	it(
		"AC4: an `ask:` answer stays only while Unconfirmed; once confirmed it is rewritten as asked-as-Qn of an existing Q",
		function()
			local ask = "- F1: ask: which sound?\n- F2: refuted: y\n"
			t.expect(problems(doc(Q, UNCONFIRMED, ask))).toBe("")
			t.expect(has(problems(doc(NONE .. Q, UNCONFIRMED .. "\n" .. CONFIRMED, ask)), "answer is open")).toBe(true)
			local fixed = "- F1: fixed: asked as Q1\n- F2: refuted: y\n"
			t.expect(problems(doc(NONE .. Q, UNCONFIRMED .. "\n" .. CONFIRMED, fixed))).toBe("")
			local missing = "- F1: fixed: asked as Q9\n- F2: refuted: y\n"
			t.expect(has(problems(doc(NONE .. Q, UNCONFIRMED .. "\n" .. CONFIRMED, missing)), "no Q9")).toBe(true)
		end
	)

	it("AC4: the verbatim ask only grows: messages may be appended, nothing already there may change", function()
		local old = doc(Q, CONFIRMED)
		local appended =
			string.gsub(old, "more ghosts\n```\n", "more ghosts\n```\n### Message 2026-11-08\n```\nand a map\n```\n", 1)
		t.expect(capturecheck.askOnlyGrows(old, appended)).toBe(true)
		t.expect(capturecheck.askOnlyGrows(old, old)).toBe(true)
		t.expect(capturecheck.askOnlyGrows(old, (string.gsub(old, "more ghosts", "fewer ghosts")))).toBe(false)
		t.expect(capturecheck.askOnlyGrows("## Problem\nold\n", old)).toBe(true) -- no ask before: any is fine
	end)
end)
