--!strict
-- c0260 AC2: the capture record in the issue document (z-ticket skill, The capture record): its three sections, the
-- dated verbatim ask, the interview and the confirmation, judged by capturecheck over texts; and the record file
-- `./zn idea --record` appends. One valid document, then one case per rule with the
-- plausible wrong document that rule must refuse.
local capturecheck = require("@znile/engine/capturecheck")
local fs = require("@lune/fs")
local process = require("@lune/process")
local t = require("@tests/lib/t")

local DOC = [[
---
id: c0900
---

# c0900: ghosts

## Problem
Ghosts sound scarier.

## Solution
- sound

## Ask (verbatim)
### Message 2026-11-07
```
make the ghosts scarrier, thx
```

## Interview
### Q1
Question: Scarier how: look, sound or speed?
Options: look | sound | speed | free text
Answer: sound, mostly. Maybe look too

### Q2
Question: Which ghost?
Options: all | Blinky | free text
Answer: all of them

## Confirmation
Confirmed (user, 2026-11-07) after round 1: "yes, that is it"

## Design
]]
local function reviews(): { [string]: string }
	return { ["idea-review-001.md"] = "# Idea review 001\n\n## Findings\n\nnone\n\n## Verdict\n\napprove\n" }
end
local function problems(doc: string): string
	return table.concat(capturecheck.check(doc, reviews()), "\n")
end
local function has(text: string, part: string): boolean
	return string.find(text, part, 1, true) ~= nil
end
-- DOC with `from` replaced by `to` once; errors when `from` is not in it, so a case cannot silently test nothing
local function swap(from: string, to: string): string
	local a, b = string.find(DOC, from, 1, true)
	if not a then
		error(`DOC has no {from}`, 0)
	end
	return string.sub(DOC, 1, a - 1) .. to .. string.sub(DOC, (b :: number) + 1)
end
local function sub(text: string, pattern: string, with: string): string
	return (string.gsub(text, pattern, with))
end
-- `text` with every plain occurrence of `from` replaced by `to`.
local function replace(text: string, from: string, to: string): string
	local out, at = {}, 1
	while true do
		local i, j = string.find(text, from, at, true)
		if not i then
			table.insert(out, string.sub(text, at))
			return table.concat(out)
		end
		table.insert(out, string.sub(text, at, i - 1))
		table.insert(out, to)
		at = (j :: number) + 1
	end
end
local ROOT = (string.gsub(process.exec("git", { "rev-parse", "--show-toplevel" }).stdout, "%s+$", ""))

return t.spec("c0260 the capture record's shape", function(it)
	it(
		"AC2: a complete record has no problem, and a document with no capture section is not checked",
		function()
			t.expect(problems(DOC)).toBe("")
			t.expect(problems("---\nid: c0001\n---\n\n## Problem\nold\n")).toBe("")
			t.expect(capturecheck.kind(DOC)).toBe("user")
			t.expect(capturecheck.kind("## Problem\nold\n")).toBe("none")
		end
	)

	it("AC2: the three sections come once each, in order", function()
		local moved = sub(DOC, "(## Ask %(verbatim%).-)(## Interview.-)(## Confirmation)", "%2%1%3")
		t.expect(has(problems(moved), "capture sections must be")).toBe(true)
		local twice = swap("## Confirmation\n", "## Interview\n### Q3\n## Confirmation\n")
		t.expect(has(problems(twice), "capture sections must be")).toBe(true)
		-- a record still growing has the first sections only
		local growing = sub(DOC, "## Confirmation.-\n## Design", "## Design")
		t.expect(problems(growing)).toBe("")
		t.expect(capturecheck.satisfies(growing, reviews())).toBe(false)
		t.expect(capturecheck.satisfies(DOC, reviews())).toBe(true)
	end)

	it("AC2: every message of the ask is dated, in a block, and not empty", function()
		t.expect(has(problems(swap("### Message 2026-11-07", "### Message today")), "must read")).toBe(true)
		t.expect(has(problems(swap("make the ghosts scarrier, thx\n", "")), "is empty")).toBe(true)
		t.expect(
			has(
				problems(
					swap("### Message 2026-11-07\n```\nmake the ghosts scarrier, thx\n```\n", "just words\n")
				),
				"at least one"
			)
		).toBe(true)
	end)

	it(
		"AC2: a verbatim ask holding headings, code fences and Q lines is kept as written and passes",
		function()
			local nasty = "Here is my plan:\n\n## Goals\n- scarier ghosts\n### Q1\n```lua\nprint(1)\n```\n"
			t.expect(
				problems(swap("```\nmake the ghosts scarrier, thx\n```\n", "````\n" .. nasty .. "````\n"))
			)
				.toBe("")
			-- unfenced, the same words break the structure: that is what the fence is for
			t.expect(problems(swap("```\nmake the ghosts scarrier, thx\n```\n", nasty)) ~= "").toBe(true)
		end
	)

	it("AC2: an unclosed fence is an error, not 'everything after it is the ask'", function()
		t.expect(
			has(problems(swap("make the ghosts scarrier, thx\n```\n", "make it scarier\n")), "never closed")
		)
			.toBe(true)
	end)

	it(
		"AC2: every question keeps its question and answer, options may go; numbers run from 1 without gaps",
		function()
			t.expect(has(problems(swap("Answer: all of them", "Answer: ")), "Q2 has no Answer")).toBe(true)
			t.expect(has(problems(swap("Question: Which ghost?\n", "")), "Q2 has no Question")).toBe(true)
			t.expect(problems(swap("Options: all | Blinky | free text\n", ""))).toBe("")
			t.expect(has(problems(swap("### Q2", "### Q3")), "found Q3 where Q2 belongs")).toBe(true)
			t.expect(has(problems(swap("### Q1", "### Q2")), "found Q2 where Q1 belongs")).toBe(true)
		end
	)

	it("AC2: an answer of several lines goes in a fence after Answer:, and counts as given", function()
		t.expect(problems(swap("Answer: all of them", "Answer:\n```\nall of them\n## and more\n```")))
			.toBe("")
	end)

	it(
		"AC2: the interview is questions, with Q1 always there: `None:` and an empty interview are refused",
		function()
			local none = sub(DOC, "### Q1.-\n## Confirmation\n", "None: all clear\n\n## Confirmation\n")
			t.expect(has(problems(none), "not an interview")).toBe(true)
			local empty = sub(DOC, "### Q1.-\n## Confirmation\n", "\n## Confirmation\n")
			t.expect(has(problems(empty), "no ### Q1 block")).toBe(true)
		end
	)

	it("AC2: the confirmation names the last review round, in the exact form", function()
		t.expect(has(problems(swap("after round 1", "after round 2")), "last round is 1")).toBe(true)
		local two = { ["idea-review-001.md"] = "x", ["idea-review-002.md"] = "x" }
		t.expect(has(table.concat(capturecheck.check(DOC, two), "\n"), "last round is 2")).toBe(true)
		local gap = { ["idea-review-001.md"] = "x", ["idea-review-003.md"] = "x" }
		t.expect(has(table.concat(capturecheck.check(DOC, gap), "\n"), "idea-review-002.md is missing"))
			.toBe(true)
		t.expect(
			has(
				problems(swap('Confirmed (user, 2026-11-07) after round 1: "yes, that is it"', "OK")),
				"Confirmation lines read"
			)
		).toBe(true)
		t.expect(has(table.concat(capturecheck.check(DOC, {}), "\n"), "never reviewed")).toBe(true)
	end)

	it(
		"AC2: the template the skill shows is a record file capturecheck.appendRecord accepts once its placeholders are filled",
		function()
			local skill = fs.readFile(`{ROOT}/z-nile/skills/z-ticket/SKILL.md`)
			local template = string.match(skill, "````markdown\n(.-)````") :: string
			t.expect(template ~= nil).toBe(true)
			local filled = template
			for _, pair in
				{
					{ "YYYY-MM-DD", "2026-11-07" },
					{ "<the user's words, exactly>", "do it" },
					{ "<exactly as asked>", "which?" },
					{ '<the options offered, or "free text">', "a | b" },
					{ "<the user's words>", "a" },
					{ "### Q2\n...\n", "" },
				}
			do
				filled = replace(filled, pair[1], pair[2])
			end
			local base = "---\nid: c0900\n---\n\n## Problem\nx\n\n## Design\nd\n"
			local out, why = capturecheck.appendRecord(base, filled)
			t.expect(why).toBe(nil)
			t.expect(has(out :: string, "## Ask (verbatim)\n### Message 2026-11-07")).toBe(true)
			t.expect(table.concat(capturecheck.check(out :: string, {}), "\n")).toBe("")
			-- the sections sit before the Design
			local askAt = string.find(out :: string, "## Ask (verbatim)", 1, true) :: number
			t.expect(askAt < (string.find(out :: string, "## Design", 1, true) :: number)).toBe(true)
		end
	)

	it(
		"AC2: a record file only appends: messages join the Ask, questions continue the numbers, nothing else is accepted",
		function()
			local more =
				"## Ask (verbatim)\n### Message 2026-11-08\n```\nand sooner\n```\n\n## Interview\n### Q3\nQuestion: when?\nAnswer: now\n"
			local out, why = capturecheck.appendRecord(DOC, more)
			t.expect(why).toBe(nil)
			t.expect(capturecheck.askOnlyGrows(DOC, out :: string)).toBe(true)
			t.expect(has(out :: string, "make the ghosts scarrier, thx")).toBe(true)
			t.expect(has(out :: string, "and sooner")).toBe(true)
			t.expect(has(out :: string, "### Q3")).toBe(true)
			-- a question that skips or repeats a number, another section, an empty section, an undated message
			local _, skip = capturecheck.appendRecord(DOC, "## Interview\n### Q4\nQuestion: q\nAnswer: a\n")
			t.expect(has(skip or "", "next one is Q3")).toBe(true)
			local _, again = capturecheck.appendRecord(DOC, "## Interview\n### Q2\nQuestion: q\nAnswer: a\n")
			t.expect(has(again or "", "next one is Q3")).toBe(true)
			local _, other = capturecheck.appendRecord(DOC, "## Idea\nx\n")
			t.expect(has(other or "", "only ## Ask (verbatim) and ## Interview")).toBe(true)
			local _, empty = capturecheck.appendRecord(DOC, "## Ask (verbatim)\n\n")
			t.expect(has(empty or "", "is empty")).toBe(true)
			local _, undated =
				capturecheck.appendRecord(DOC, "## Ask (verbatim)\n### Message soon\n```\nx\n```\n")
			t.expect(has(undated or "", "must read")).toBe(true)
			local _, none = capturecheck.appendRecord(DOC, "nothing here")
			t.expect(has(none or "", "holds no ## Ask")).toBe(true)
		end
	)

	it("AC2: the Ask and the Interview only grow: a changed or dropped earlier word is refused", function()
		t.expect(capturecheck.askOnlyGrows(DOC, DOC)).toBe(true)
		t.expect(capturecheck.askOnlyGrows(DOC, swap("scarrier, thx", "scarier"))).toBe(false)
		t.expect(capturecheck.askOnlyGrows(DOC, swap("Answer: all of them", "Answer: Blinky"))).toBe(false)
		t.expect(
			capturecheck.askOnlyGrows(
				DOC,
				swap(
					"### Q2\nQuestion: Which ghost?\nOptions: all | Blinky | free text\nAnswer: all of them\n",
					""
				)
			)
		).toBe(false)
		t.expect(capturecheck.askOnlyGrows("## Problem\nold\n", DOC)).toBe(true)
	end)

	it(
		"AC2: a fence's info string may hold symbols (```bash title=x, ~~~ any text) and the record still parses",
		function()
			local ask = swap(
				"```\nmake the ghosts scarrier, thx\n```\n",
				"```bash title=x -- note\nmake the ghosts scarrier, thx\n```\n"
			)
			t.expect(problems(ask)).toBe("")
			local tilde =
				swap("```\nmake the ghosts scarrier, thx\n```\n", "~~~ any text ~~~\n## Goals\n~~~\n")
			t.expect(problems(tilde)).toBe("")
		end
	)

	it(
		"AC2: the user's sections are read and spliced outside fences: a pasted plan's headings are text",
		function()
			local nasty =
				'Here is my plan:\n\n## Goals\n- ALL of them\n## Open to the human\nnone\n## Interview\n### Q1\n## Confirmation\nConfirmed (x, 2026-01-01) after round 1: "y"\n'
			local doc = "---\nid: c0901\n---\n\n## Problem\nP\n\n## Design\nd\n"
			local file = "## Ask (verbatim)\n### Message 2026-11-07\n````\n" .. nasty .. "````\n"
			local one = capturecheck.appendRecord(doc, file) :: string
			t.expect(has(one, nasty)).toBe(true)
			-- the Interview is added after the Ask, not into the message; a Confirmation after it
			local two =
				capturecheck.appendRecord(one, "## Interview\n### Q1\nQuestion: q\nAnswer: a\n") :: string
			t.expect(has(two, nasty)).toBe(true)
			t.expect(
				(string.find(two, "## Interview\n### Q1\nQuestion: q", 1, true) :: number)
					> string.find(two, "````\n\n", 1, true) :: number
			).toBe(true)
			local three = capturecheck.addConfirmation(two, 'Confirmed (u, 2026-11-07) after round 1: "ok"')
			t.expect(has(three, nasty)).toBe(true)
			t.expect(capturecheck.confirmed(three)).toBe(true)
			local four = capturecheck.dropConfirmed(three)
			t.expect(has(four, nasty)).toBe(true)
			t.expect(capturecheck.confirmed(four)).toBe(false)
			t.expect(capturecheck.section(four, "Confirmation")).toBe(nil) -- the fenced copy is not the section
			local ask = capturecheck.section(four, "Ask (verbatim)") :: string
			t.expect(has(ask, "ALL of them")).toBe(true)
			t.expect(capturecheck.section(four, "Open to the human")).toBe(nil)
			-- replacing a section leaves the fenced copy alone
			local replaced = capturecheck.replace(four, "Open to the human", "- F1: x\n")
			t.expect(has(replaced, nasty)).toBe(true)
			t.expect(has(replaced, "## Open to the human\n- F1: x")).toBe(true)
			-- the same text read by the author prompt's source is whole
			t.expect(has(require("@znile/engine/idea").recordText(four) or "", "ALL of them")).toBe(true)
		end
	)

	it("AC2: a record's first file may hold the Interview only; the Ask then goes before it", function()
		local doc = "---\nid: c0901\n---\n\n## Problem\nP\n\n## Design\nd\n"
		local one = capturecheck.appendRecord(doc, "## Interview\n### Q1\nQuestion: q\nAnswer: a\n") :: string
		local two, why =
			capturecheck.appendRecord(one, "## Ask (verbatim)\n### Message 2026-11-07\n```\nhi\n```\n")
		t.expect(why).toBe(nil)
		t.expect(
			(string.find(two :: string, "## Ask (verbatim)", 1, true) :: number)
				< string.find(two :: string, "## Interview", 1, true) :: number
		).toBe(true)
		t.expect(table.concat(capturecheck.check(two :: string, {}), "\n")).toBe("")
	end)

	it("AC2: the Confirmation keeps its lines, and only a round drops a Confirmed one", function()
		local un = "Unconfirmed (unattended, 2026-11-07) after round 1: x"
		local co = 'Confirmed (u, 2026-11-07) after round 2: "ok"'
		local base = swap('Confirmed (user, 2026-11-07) after round 1: "yes, that is it"', un)
		local both = swap('Confirmed (user, 2026-11-07) after round 1: "yes, that is it"', un .. "\n" .. co)
		t.expect(capturecheck.recordGrows(base, both)).toBe(true) -- a Confirmed line is appended
		t.expect(capturecheck.recordGrows(both, base)).toBe(true) -- a round drops the Confirmed line
		t.expect(
			capturecheck.recordGrows(
				both,
				swap(
					'Confirmed (user, 2026-11-07) after round 1: "yes, that is it"',
					un .. "\n" .. 'Confirmed (u, 2026-11-07) after round 2: "different"'
				)
			)
		).toBe(false)
		t.expect(
			capturecheck.recordGrows(
				base,
				swap(
					'Confirmed (user, 2026-11-07) after round 1: "yes, that is it"',
					"Unconfirmed (unattended, 2026-11-08) after round 1: y"
				)
			)
		).toBe(false)
	end)

	it(
		"AC2: a round state is the counts of the record and a hash of the idea; the confirmation is bound to it while the ticket is unclaimed",
		function()
			local state = capturecheck.roundState(DOC)
			t.expect(has(state, "ask 1, interview 2, idea ")).toBe(true)
			t.expect(
				capturecheck.roundState(swap("Ghosts sound scarier.", "Ghosts sound different.")) ~= state
			)
				.toBe(true)
			t.expect(
				capturecheck.roundState(swap("### Q2", "### Q2\nQuestion: x\nAnswer: y\n### Q3")) ~= state
			)
				.toBe(true)
			local review = "# Idea review 001\n\nRound: " .. state .. "\n\n## Findings\n\nnone\n"
			local unclaimed = sub(DOC, "id: c0900\n", "id: c0900\nstatus: new-a-b-c\n")
			local bound = { ["idea-review-001.md"] = review }
			t.expect(table.concat(capturecheck.check(unclaimed, bound), "\n")).toBe("")
			local drifted = swap("Ghosts sound scarier.", "Ghosts sound different.")
			drifted = sub(drifted, "id: c0900\n", "id: c0900\nstatus: new-a-b-c\n")
			t.expect(has(table.concat(capturecheck.check(drifted, bound), "\n"), "changed since that round"))
				.toBe(true)
			-- claimed (z-design edits the Problem): not bound
			local claimed = sub(drifted, "status: new%-a%-b%-c", "status: preparing-a-b-c")
			t.expect(table.concat(capturecheck.check(claimed, bound), "\n")).toBe("")
			-- a review with no Round: line cannot bind an unclaimed Confirmed line
			local noLine = { ["idea-review-001.md"] = "# Idea review 001\n\n## Findings\n\nnone\n" }
			t.expect(has(table.concat(capturecheck.check(unclaimed, noLine), "\n"), "no Round: line"))
				.toBe(true)
		end
	)
end)
