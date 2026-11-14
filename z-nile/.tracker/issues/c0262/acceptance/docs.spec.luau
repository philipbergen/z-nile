--!strict
-- c0262: the skills that restate the ticket's final review say it the same way. Reads skill files as text, never writes.
local fs = require("@lune/fs")
local process = require("@lune/process")
local t = require("@tests/lib/t")

local ROOT = (string.gsub(process.exec("git", { "rev-parse", "--show-toplevel" }).stdout, "%s+$", ""))

local function skill(name: string): string
	return fs.readFile(`{ROOT}/z-nile/skills/{name}/SKILL.md`)
end

local function has(text: string, needle: string): boolean
	return string.find(text, needle, 1, true) ~= nil
end

return t.spec("c0262 the skills say the ticket's final review", function(it)
	it("AC12: zz-review names the last review, its view, its one question and its two verdicts", function()
		local text = skill("zz-review")
		t.expect(has(text, "## Final mode on a ticket (the last review)")).toBe(true)
		t.expect(has(text, "does the diff deliver the original ask")).toBe(true)
		t.expect(has(text, "`Gap: design`")).toBe(true)
		t.expect(has(text, "`Gap: implementation`")).toBe(true)
		t.expect(has(text, "`Verdict: on-course | off-course`")).toBe(true)
		t.expect(has(text, "never design reviews, refutes, harvests, pull request comments or worker notes"))
			.toBe(true)
		t.expect(has(text, "Off course twice: the ticket is blocked for the human")).toBe(true)
	end)

	it(
		"AC12: zz-execute puts the ticket's final review between finishing a layer and starting the next",
		function()
			local text = skill("zz-execute")
			t.expect(has(text, "**The ticket's final review** (before the next layer starts)")).toBe(true)
			t.expect(has(text, "`final-review-ticket`")).toBe(true)
			t.expect(has(text, "`rebuild`")).toBe(true)
			t.expect(has(text, "`redesign`")).toBe(true)
			t.expect(has(text, "A second off-course verdict blocks the ticket for the human")).toBe(true)
		end
	)

	it("AC12: zz-rules lists ./zn final, the file, and what done refuses", function()
		local text = skill("zz-rules")
		t.expect(has(text, "`./zn final <issue-id> [--view]`")).toBe(true)
		t.expect(has(text, "<issue>/final-review-NNN.md")).toBe(true)
		t.expect(
			has(
				text,
				"`redo-design`, `redo-layer`, `blocked` or `invalid` (a ticket with no final review is not refused)"
			)
		).toBe(true)
	end)
end)
