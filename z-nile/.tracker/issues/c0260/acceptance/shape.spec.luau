--!strict
-- c0260 AC2: the shape of an issue's capture/ folder (z-ticket skill, The capture folder), judged by capturecheck over
-- texts. One valid folder, then one case per rule with the plausible wrong folder that rule must refuse.
local capturecheck = require("@znile/engine/capturecheck")
local fs = require("@lune/fs")
local process = require("@lune/process")
local t = require("@tests/lib/t")

local ASK = [[
# Ask for c0900

## Verbatim ask
make the ghosts scarrier, thx

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
Confirmed (user, 2026-11-07) after idea-review-002: "yes, that is it"
]]

local REVIEW =
	"# Review 001: c0900 (idea mode)\nInputs: ask.md\n\n### F1 [high] a claim\nWhere: Problem\n\n### F2 [low] another\n"
local REFUTE = "- F1: fixed: the Problem now says sound\n- F2: refuted: the ask says all of them\n"

local function folder(): { [string]: string }
	return {
		["idea-review-001.md"] = REVIEW,
		["idea-refute-001.md"] = REFUTE,
		["idea-review-002.md"] = "# Review 002: c0900 (idea mode)\n\nVerdict: approve\n",
		["idea-refute-002.md"] = "",
	}
end

local ROOT = (string.gsub(process.exec("git", { "rev-parse", "--show-toplevel" }).stdout, "%s+$", ""))
local function skill(name: string): string
	return fs.readFile(`{ROOT}/z-nile/skills/{name}/SKILL.md`)
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
local function problems(ask: string, files: { [string]: string }?): string
	return table.concat(capturecheck.check(ask, files or folder()), "\n")
end
local function has(text: string, part: string): boolean
	return string.find(text, part, 1, true) ~= nil
end
local function sub(text: string, pattern: string, with: string): string
	return (string.gsub(text, pattern, with))
end
-- `ask` with `from` replaced by `to` once; errors when `from` is not in it, so a case cannot silently test nothing
local function swap(from: string, to: string): string
	local a, b = string.find(ASK, from, 1, true)
	if not a then
		error(`ASK has no {from}`, 0)
	end
	return string.sub(ASK, 1, a - 1) .. to .. string.sub(ASK, (b :: number) + 1)
end

return t.spec("c0260 the capture folder's shape", function(it)
	it("AC2: a complete folder has no problem, and an unattended confirmation and `None:` are accepted", function()
		t.expect(problems(ASK)).toBe("")
		local unattended =
			sub(ASK, "### Q1.-\n## Confirmation", "None: unattended, nobody could be asked\n\n## Confirmation")
		unattended = sub(
			unattended,
			'Confirmed %(user, 2026%-11%-07%) after idea%-review%-002: "yes, that is it"',
			"Confirmed (unattended, 2026-11-07) after idea-review-002: the user started this dispatch with this ask"
		)
		t.expect(problems(unattended)).toBe("")
	end)

	it("AC2: the verbatim ask must be there and not empty", function()
		t.expect(has(problems(swap("make the ghosts scarrier, thx\n", "\n")), "Verbatim ask is empty")).toBe(true)
	end)

	it("AC2: the sections are exactly Verbatim ask, Interview, Confirmation, in that order", function()
		t.expect(has(problems(swap("## Interview", "## Questions")), "sections must be")).toBe(true)
		local swapped = sub(ASK, "(## Verbatim ask.-)(## Interview.-)(## Confirmation)", "%2%1%3")
		t.expect(has(problems(swapped), "sections must be")).toBe(true)
	end)

	it("AC2: every question keeps its question, options and answer; numbers run from 1 without gaps", function()
		t.expect(has(problems(swap("Answer: all of them", "Answer: ")), "Q2 has no Answer")).toBe(true)
		t.expect(has(problems(swap("Options: all | Blinky | free text\n", "")), "Q2 has no Options")).toBe(true)
		t.expect(has(problems(swap("### Q2", "### Q3")), "found Q3 where Q2 belongs")).toBe(true)
		t.expect(has(problems(swap("### Q1", "### Q2")), "found Q2 where Q1 belongs")).toBe(true)
	end)

	it("AC2: an interview is questions or `None: <why>`, never neither and never `None:` bare", function()
		local none = sub(ASK, "### Q1.-\n## Confirmation", "None:\n\n## Confirmation")
		t.expect(has(problems(none), "needs the reason")).toBe(true)
		local empty = sub(ASK, "### Q1.-\n## Confirmation", "\n## Confirmation")
		t.expect(has(problems(empty), "no ### Q1 block")).toBe(true)
	end)

	it("AC2: `None: <why>` is the whole interview: questions after it are refused", function()
		local both = sub(ASK, "### Q1", "None: nobody asked\n### Q1")
		t.expect(has(problems(both), "must be the only line")).toBe(true)
	end)

	it(
		"AC2: the ask.md template z-ticket shows is accepted by capturecheck once its placeholders are filled",
		function()
			local template = string.match(skill("z-ticket"), "````markdown\n(.-)````") :: string
			t.expect(template ~= nil).toBe(true)
			local filled = template
			for _, pair in
				{
					{ "<id>", "c0900" },
					{ "<the user's words, exactly>", "do it" },
					{ "<exactly as asked>", "which?" },
					{ '<the options offered, or "free text">', "a | b" },
					{ "<the user's words>", "yes" },
					{ "YYYY-MM-DD", "2026-11-07" },
					{ "NNN", "001" },
					{ "## Part\n<only in a batch: the sibling ids, and this issue's part quoted>\n\n", "" },
					{ "### Q2\n...\n", "" },
				}
			do
				filled = replace(filled, pair[1], pair[2])
			end
			local files = {
				["idea-review-001.md"] = "# Review\n",
				["idea-refute-001.md"] = "",
			}
			t.expect(table.concat(capturecheck.check(filled, files), "\n")).toBe("")
		end
	)

	it("AC2: a verbatim ask holding headings, code fences and Q lines is kept as written and passes", function()
		local nasty = "Here is my plan:\n\n## Goals\n- scarier ghosts\n### Q1\n```lua\nprint(1)\n```\n"
		local ask = swap("make the ghosts scarrier, thx\n", "````\n" .. nasty .. "````\n")
		t.expect(problems(ask)).toBe("")
		-- unfenced, the same words break the structure: that is what the fence is for
		t.expect(has(problems(swap("make the ghosts scarrier, thx\n", nasty)), "sections must be")).toBe(true)
	end)

	it("AC2: an unclosed fence is an error, not 'everything after it is the ask'", function()
		t.expect(has(problems(swap("make the ghosts scarrier, thx\n", "```\nmake it scarier\n")), "never closed"))
			.toBe(true)
	end)

	it("AC2: an answer of several lines goes in a fence after Answer:, and counts as given", function()
		local ask = swap("Answer: all of them", "Answer:\n```\nall of them\n## and more\n```")
		t.expect(problems(ask)).toBe("")
	end)

	it(
		"AC2: a batch capture adds a non-empty Part between the Verbatim ask and the Interview, and nowhere else",
		function()
			local withPart = swap("## Interview", "## Part\nc0901, c0902; this is part (a): ghosts\n\n## Interview")
			t.expect(problems(withPart)).toBe("")
			t.expect(has(problems(swap("## Interview", "## Part\n\n## Interview")), "Part is empty")).toBe(true)
			t.expect(has(problems(swap("## Confirmation", "## Part\nlate\n\n## Confirmation")), "sections must be"))
				.toBe(true)
		end
	)

	it("AC2: an unattended confirmation needs an Interview that is `None:`", function()
		local unattended = swap(
			'Confirmed (user, 2026-11-07) after idea-review-002: "yes, that is it"',
			"Confirmed (unattended, 2026-11-07) after idea-review-002: started by the user"
		)
		t.expect(has(problems(unattended), "needs the Interview to be `None")).toBe(true)
	end)

	it("AC6: ask.md only grows: the verbatim ask, the part and the questions already there may not change", function()
		local more = swap("## Confirmation", "### Q3\nQuestion: more?\nOptions: no\nAnswer: no\n\n## Confirmation")
		t.expect(capturecheck.appendOnly(ASK, more)).toBe(nil)
		t.expect(capturecheck.appendOnly(ASK, ASK)).toBe(nil)
		t.expect(capturecheck.appendOnly(ASK, swap("make the ghosts scarrier, thx", "make the ghosts scary")))
			.toBe("Verbatim ask changed")
		t.expect(capturecheck.appendOnly(ASK, swap("Answer: all of them", "Answer: some")) ~= nil).toBe(true)
		t.expect(
			capturecheck.appendOnly(
				ASK,
				swap("### Q2\nQuestion: Which ghost?\nOptions: all | Blinky | free text\nAnswer: all of them\n\n", "")
			) ~= nil
		).toBe(true)
		-- an unattended capture later gets the questions z-design put to the user in place of `None:`
		local none = sub(ASK, "### Q1.-\n## Confirmation", "None: unattended\n\n## Confirmation")
		t.expect(capturecheck.appendOnly(none, ASK)).toBe(nil)
	end)
end)
