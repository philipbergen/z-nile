--!strict
-- c0260 AC2: the capture record in the issue document (z-ticket skill, The capture record): its sections, the dated
-- verbatim ask, the interview, judged by capturecheck over texts. One valid document, then one case per rule with the
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

## Idea
Every ghost gets a scarier sound.

## Idea review
### Round 1
- F1: fixed: the idea now says sound
- F2: refuted: the ask says all of them

## Confirmation
Confirmed (user, 2026-11-07) after round 1: "yes, that is it"

## Design
]]
local REVIEW = "# Review 001: c0900 (idea mode)\n\n### F1 [high] a claim\nWhere: Idea\n\n### F2 [low] another\n"
local function reviews(): { [string]: string }
	return { ["idea-review-001.md"] = REVIEW }
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
	it("AC2: a complete record has no problem, and a document with no capture section is not checked", function()
		t.expect(problems(DOC)).toBe("")
		t.expect(problems("---\nid: c0001\n---\n\n## Problem\nold\n")).toBe("")
		t.expect(capturecheck.kind(DOC)).toBe("user")
		t.expect(capturecheck.kind("## Problem\nold\n")).toBe("none")
	end)

	it("AC2: the five sections come once each, in order", function()
		t.expect(has(problems(swap("## Idea\n", "## Notes\n")), "capture sections must be")).toBe(true)
		local moved = sub(DOC, "(## Interview.-)(## Idea\n.-)(## Idea review)", "%2%1%3")
		t.expect(has(problems(moved), "capture sections must be")).toBe(true)
	end)

	it("AC2: every message of the ask is dated, in a block, and not empty", function()
		t.expect(has(problems(swap("### Message 2026-11-07", "### Message today")), "must read")).toBe(true)
		t.expect(has(problems(swap("make the ghosts scarrier, thx\n", "")), "is empty")).toBe(true)
		t.expect(
			has(
				problems(swap("### Message 2026-11-07\n```\nmake the ghosts scarrier, thx\n```\n", "just words\n")),
				"at least one"
			)
		).toBe(true)
	end)

	it("AC2: a verbatim ask holding headings, code fences and Q lines is kept as written and passes", function()
		local nasty = "Here is my plan:\n\n## Goals\n- scarier ghosts\n### Q1\n```lua\nprint(1)\n```\n"
		t.expect(problems(swap("```\nmake the ghosts scarrier, thx\n```\n", "````\n" .. nasty .. "````\n"))).toBe("")
		-- unfenced, the same words break the structure: that is what the fence is for
		t.expect(problems(swap("```\nmake the ghosts scarrier, thx\n```\n", nasty)) ~= "").toBe(true)
	end)

	it("AC2: an unclosed fence is an error, not 'everything after it is the ask'", function()
		t.expect(has(problems(swap("make the ghosts scarrier, thx\n```\n", "make it scarier\n")), "never closed"))
			.toBe(true)
	end)

	it("AC2: every question keeps its question, options and answer; numbers run from 1 without gaps", function()
		t.expect(has(problems(swap("Answer: all of them", "Answer: ")), "Q2 has no Answer")).toBe(true)
		t.expect(has(problems(swap("Options: all | Blinky | free text\n", "")), "Q2 has no Options")).toBe(true)
		t.expect(has(problems(swap("### Q2", "### Q3")), "found Q3 where Q2 belongs")).toBe(true)
		t.expect(has(problems(swap("### Q1", "### Q2")), "found Q2 where Q1 belongs")).toBe(true)
	end)

	it("AC2: an answer of several lines goes in a fence after Answer:, and counts as given", function()
		t.expect(problems(swap("Answer: all of them", "Answer:\n```\nall of them\n## and more\n```"))).toBe("")
	end)

	it("AC2: the interview is questions, with Q1 always there: `None:` and an empty interview are refused", function()
		local none = sub(DOC, "### Q1.-\n## Idea\n", "None: all clear\n\n## Idea\n")
		t.expect(has(problems(none), "not an interview")).toBe(true)
		local empty = sub(DOC, "### Q1.-\n## Idea\n", "\n## Idea\n")
		t.expect(has(problems(empty), "no ### Q1 block")).toBe(true)
	end)

	it("AC2: the idea must not be empty", function()
		t.expect(has(problems(swap("Every ghost gets a scarier sound.\n", "")), "Idea is empty")).toBe(true)
	end)

	it("AC2: the template the skill shows is accepted by capturecheck once its placeholders are filled", function()
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
				{ "### Q2\n...\n", "" },
				{ "<the clean, fully formed idea>", "Do it." },
				{ "- F1: fixed|refuted|ask: <text>", "- F1: fixed: done" },
				{ "<who>", "user" },
				{ "<the user's words>", "yes" },
				{ "round N", "round 1" },
			}
		do
			filled = replace(filled, pair[1], pair[2])
		end
		filled = filled .. "\n## Design\n"
		local one = { ["idea-review-001.md"] = "# Review 001\n\n### F1 [low] x\n" }
		t.expect(table.concat(capturecheck.check(filled, one), "\n")).toBe("")
	end)

	it(
		"AC2: a fence's info string may hold symbols (```bash title=x, ~~~ any text) and the record still parses",
		function()
			local ask = swap(
				"```\nmake the ghosts scarrier, thx\n```\n",
				"```bash title=x -- note\nmake the ghosts scarrier, thx\n```\n"
			)
			t.expect(problems(ask)).toBe("")
			local tilde = swap("```\nmake the ghosts scarrier, thx\n```\n", "~~~ any text ~~~\n## Goals\n~~~\n")
			t.expect(problems(tilde)).toBe("")
		end
	)
end)
