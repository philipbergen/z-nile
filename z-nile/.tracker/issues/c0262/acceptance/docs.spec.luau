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
		t.expect(has(text, "`./zn block <R> review-exhausted --layer <issue>`")).toBe(true)
		t.expect(has(text, "its confirmed idea (the approved document's Problem, Solution and Non-goals)"))
			.toBe(true)
		t.expect(has(text, "`Measured against:`")).toBe(true)
		t.expect(has(text, "`design-changes.patch`")).toBe(true)
	end)

	it(
		"AC12: zz-execute puts the ticket's final review between finishing a layer and starting the next",
		function()
			local text = skill("zz-execute")
			t.expect(
				has(
					text,
					"**The ticket's final review** (before the next layer starts, and after the layer's own code review)"
				)
			).toBe(true)
			t.expect(has(text, "`final-review-ticket`")).toBe(true)
			t.expect(has(text, "`rebuild`")).toBe(true)
			t.expect(has(text, "`redesign`")).toBe(true)
			t.expect(has(text, "A second off-course verdict blocks the ticket for the human")).toBe(true)
			t.expect(has(text, "run `./zn block <R> review-exhausted --layer <issue>`")).toBe(true)
			t.expect(has(text, "a raft without `layers: reviewed` lands whole, so nothing lands first"))
				.toBe(true)
			t.expect(has(text, "questions.md, `./zn stop`")).toBe(false)
			t.expect(has(text, "An agent never starts that reviewer itself")).toBe(true)
			t.expect(has(text, "After `approve` or `retry` the raft is `prepared`: it is readied again"))
				.toBe(true)
			t.expect(
				has(text, "after `amend-design` the ticket has left the raft and is re-prepped as a redesign")
			)
				.toBe(true)
		end
	)

	it("AC12: zz-rules lists ./zn final, the file, and what done refuses", function()
		local text = skill("zz-rules")
		t.expect(has(text, "`./zn final <issue-id> [--view]`")).toBe(true)
		t.expect(has(text, "<issue>/final-review-NNN.md")).toBe(true)
		t.expect(
			has(
				text,
				"`redo-design`, `redo-layer`, `blocked` or `invalid`, or `review-again` after an off-course verdict (a ticket with no final review is not refused by this rule"
			)
		).toBe(true)
		t.expect(has(text, "only edits the local documents (and marks the issue `final: ticket`")).toBe(true)
	end)

	it(
		"AC12: z-design keeps review citations out of the Design and sends a redone ticket its reviews",
		function()
			local text = skill("z-design")
			t.expect(
				has(
					text,
					"names no design review, refute or round in the Design and Acceptance criteria sections"
				)
			).toBe(true)
			t.expect(has(text, "off-course `final-review-NNN.md` files copied from its old layer branch"))
				.toBe(true)
			t.expect(has(text, "it edits the local document and marks the issue `final: ticket`")).toBe(true)
			t.expect(
				has(text, "The ticket's `check.sh` and acceptance specs cite none of its own reviews either")
			)
				.toBe(true)
		end
	)
end)
