--!strict
-- c0260 AC4: the review record of an issue's capture/ folder, judged by capturecheck over
-- texts. One valid folder, then one case per rule with the plausible wrong folder that rule must refuse.
local capturecheck = require("@znile/engine/capturecheck")
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

local function problems(ask: string, files: { [string]: string }?): string
	return table.concat(capturecheck.check(ask, files or folder()), "\n")
end
local function has(text: string, part: string): boolean
	return string.find(text, part, 1, true) ~= nil
end
-- `ask` with `from` replaced by `to` once; errors when `from` is not in it, so a case cannot silently test nothing
local function swap(from: string, to: string): string
	local a, b = string.find(ASK, from, 1, true)
	if not a then
		error(`ASK has no {from}`, 0)
	end
	return string.sub(ASK, 1, a - 1) .. to .. string.sub(ASK, (b :: number) + 1)
end

return t.spec("c0260 the capture folder's review record", function(it)
	it("AC4: every review round has its refute file and every finding an answer of the three kinds", function()
		local files = folder()
		files["idea-refute-001.md"] = "- F1: fixed: the Problem now says sound\n"
		t.expect(has(problems(ASK, files), "finding F2 of idea-review-001.md has no answer line")).toBe(true)
		files = folder()
		files["idea-refute-001.md"] = nil
		t.expect(has(problems(ASK, files), "idea-refute-001.md is missing")).toBe(true)
		files = folder()
		files["idea-refute-001.md"] = "- F1: fixed: x\n- F2: maybe: y\n"
		t.expect(has(problems(ASK, files), 'answered "maybe"')).toBe(true)
		files = folder()
		files["idea-refute-001.md"] = "- F1: fixed: x\n- F2: refuted: y\n- F3: fixed: z\n"
		t.expect(has(problems(ASK, files), "answers F3, which idea-review-001.md does not have")).toBe(true)
		files = folder()
		files["idea-refute-001.md"] = "- F1: fixed:\n- F2: ask: which sound?\n"
		t.expect(has(problems(ASK, files), "F1 has an empty answer")).toBe(true)
		t.expect(has(problems(ASK, files), "F2")).toBe(false)
	end)

	it("AC4: a capture with no idea review, or a gap in the rounds, is refused", function()
		t.expect(has(problems(ASK, {}), "the idea was never reviewed")).toBe(true)
		local files = folder()
		files["idea-review-001.md"] = nil
		files["idea-refute-001.md"] = nil
		t.expect(has(problems(ASK, files), "idea-review-001.md is missing")).toBe(true)
	end)

	it("AC4: the confirmation is one line of the exact form that names the last review round", function()
		t.expect(
			has(
				problems(swap("after idea-review-002", "after idea-review-001")),
				"but the last round is idea-review-002"
			)
		)
			.toBe(true)
		t.expect(has(problems(swap("Confirmed (user,", "Confirmed (bot,")), "Confirmation must read")).toBe(true)
		t.expect(has(problems(swap('"yes, that is it"', "")), "Confirmation must read")).toBe(true)
		t.expect(has(problems(swap("2026-11-07", "7 Nov")), "Confirmation must read")).toBe(true)
		t.expect(
			has(problems(swap("\n## Confirmation\n", "\n## Confirmation\nthe user said yes\n")), "must be one line")
		)
			.toBe(true)
		t.expect(has(problems(swap("\n## Confirmation\n", "\n## Confirmation\n\n")), "must be one line")).toBe(false) -- blank lines are fine
	end)

	it(
		"AC4: an `ask:` answer is kept only while the confirmation is unattended; once the user answered it, it is rewritten",
		function()
			local files = folder()
			files["idea-refute-001.md"] = "- F1: ask: which sound?\n- F2: refuted: y\n"
			t.expect(has(problems(ASK, files), "answer is open")).toBe(true)
			local unattended = string.gsub(ASK, "### Q1.-\n## Confirmation", "None: unattended\n\n## Confirmation")
			unattended = string.gsub(
				unattended,
				'Confirmed %(user, 2026%-11%-07%) after idea%-review%-002: "yes, that is it"',
				"Confirmed (unattended, 2026-11-07) after idea-review-002: started by the user"
			)
			t.expect(problems(unattended, files)).toBe("")
			files["idea-refute-001.md"] = "- F1: fixed: asked as Q1\n- F2: refuted: y\n"
			t.expect(problems(ASK, files)).toBe("")
		end
	)

	it("AC4: a refute that answers a finding the review lacks, or leaves an answer empty, is refused", function()
		local files = folder()
		files["idea-refute-001.md"] = "- F1: fixed: x\n- F2: refuted: y\n- F3: fixed: z\n"
		t.expect(has(problems(ASK, files), "answers F3")).toBe(true)
		files["idea-refute-001.md"] = "- F1: fixed:\n- F2: refuted: y\n"
		t.expect(has(problems(ASK, files), "F1 has an empty answer")).toBe(true)
	end)
end)
