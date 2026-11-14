--!strict
-- c0250 AC2: the escalation note. Pure over engine/escalation: the reader, the checks, the writer of the header and the
-- resume commands, the resolution, and the table that maps each decision to the item's next state.
local escalation = require("@znile/engine/escalation")
local t = require("@tests/lib/t")

local function has(s: string, part: string): boolean
	return string.find(s, part, 1, true) ~= nil
end

local function lines(s: string): { string }
	local out: { string } = {}
	for line in string.gmatch(s .. "\n", "([^\n]*)\n") do
		table.insert(out, line)
	end
	return out
end

local GOOD = table.concat({
	"## Question",
	"Accept a new dependency on the json library, or write our own reader?",
	"",
	"## What was tried",
	"Two review rounds; the reviewer asked for a reader and the design has none.",
	"",
	"## Open findings or error",
	"F2: the design names no way to read the file.",
	"",
	"## Options",
	"- retry: one more review round",
	"- approve: accept the library (recommended)",
	"- amend-design: back to z-design",
	"",
}, "\n")

local function without(section: string): string
	local out: { string } = {}
	local skipping = false
	for _, line in lines(GOOD) do
		if string.match(line, "^## ") then
			skipping = line == `## {section}`
		end
		if not skipping then
			table.insert(out, line)
		end
	end
	return table.concat(out, "\n")
end

local HEADER: escalation.Header = {
	item = "R0120",
	reason = "red-gate",
	from = "active",
	layer = "c0230",
	actor = "agent:claude-opus-5-5 effort high",
	when = "2026-11-20 03:10",
}

return t.spec("c0250 the escalation note", function(it)
	it(
		"AC2: parse and check refuse a note missing a section, an option naming no decision, or not exactly one recommendation",
		function()
			local note, why = escalation.parse(GOOD)
			t.expect(why).toBe(nil)
			t.expect(note ~= nil).toBe(true)
			local n = note :: escalation.Note
			t.expect(n.question).toBe("Accept a new dependency on the json library, or write our own reader?")
			t.expect(#n.options).toBe(3)
			t.expect(n.options[1].decision).toBe("retry")
			t.expect(n.options[2].decision).toBe("approve")
			t.expect(n.options[2].recommended).toBe(true)
			t.expect(n.options[1].recommended).toBe(false)
			t.expect(escalation.check(n)).toBe(nil)
			-- every section is required, and named in the refusal
			for _, name in { "Question", "What was tried", "Open findings or error", "Options" } do
				local missing, missingWhy = escalation.parse(without(name))
				t.expect(missing).toBe(nil)
				t.expect(has(missingWhy or "", `"## {name}"`)).toBe(true)
			end
			-- an empty section is a missing one
			local empty, emptyWhy = escalation.parse((string.gsub(GOOD, "Two review rounds[^\n]*", "")))
			t.expect(empty).toBe(nil)
			t.expect(has(emptyWhy or "", "What was tried")).toBe(true)
			-- an option naming no decision
			local odd = string.gsub(GOOD, "%- retry:", "- maybe:")
			local oddNote = escalation.parse(odd) :: escalation.Note
			local oddWhy = escalation.check(oddNote)
			t.expect(oddWhy ~= nil).toBe(true)
			t.expect(has(oddWhy or "", "maybe")).toBe(true)
			-- no recommendation, and two
			local none = escalation.parse((string.gsub(GOOD, " %(recommended%)", ""))) :: escalation.Note
			t.expect(has(escalation.check(none) or "", "exactly one")).toBe(true)
			local two = escalation.parse(
				(string.gsub(GOOD, "one more review round", "one more review round (recommended)"))
			) :: escalation.Note
			t.expect(has(escalation.check(two) or "", "exactly one")).toBe(true)
			-- no option at all
			local bare =
				escalation.parse((string.gsub(GOOD, "%- [^\n]*\n", "Whatever you think.\n"))) :: escalation.Note
			t.expect(escalation.check(bare) ~= nil).toBe(true)
		end
	)

	it(
		"AC2: stamp writes the header and one resume command per option, and the reason list is closed",
		function()
			t.expect(escalation.REASONS).toEqual({
				"review-exhausted",
				"design-gap",
				"needs-decision",
				"red-gate",
				"quota",
				"tripwire",
			})
			t.expect(escalation.DECISIONS).toEqual({ "amend-design", "approve", "split", "retry", "abort" })
			local text = escalation.stamp(GOOD, HEADER)
			local all = lines(text)
			t.expect(all[1]).toBe("# Escalation: R0120")
			t.expect(all[2]).toBe("Item: R0120")
			t.expect(all[3]).toBe("Reason: red-gate")
			t.expect(all[4]).toBe("From: active")
			t.expect(all[5]).toBe("Layer: c0230")
			t.expect(all[6]).toBe("Actor: agent:claude-opus-5-5 effort high")
			t.expect(all[7]).toBe("When: 2026-11-20 03:10")
			-- the worker's four sections follow, in order, as written
			local at = 0
			for _, name in { "Question", "What was tried", "Open findings or error", "Options", "Resume" } do
				local found = string.find(text, `\n## {name}\n`, at + 1, true)
				t.expect(found ~= nil).toBe(true)
				at = found :: number
			end
			t.expect(has(text, "- approve: accept the library (recommended)")).toBe(true)
			-- one resume command per option, in the option order, and none for a decision the note does not offer
			local resume =
				string.sub(text, (string.find(text, "\n## Resume\n", 1, true) :: number) + #"\n## Resume\n")
			t.expect(resume).toBe(
				'./zn resolve R0120 retry --answer "<your answer>"\n'
					.. './zn resolve R0120 approve --answer "<your answer>"\n'
					.. './zn resolve R0120 amend-design --answer "<your answer>"\n'
			)
			t.expect(has(text, "resolve R0120 split")).toBe(false)
			t.expect(has(text, "resolve R0120 abort")).toBe(false)
			-- an issue's note has no Layer line
			local issueText = escalation.stamp(GOOD, {
				item = "c0250",
				reason = "needs-decision",
				from = "preparing",
				layer = nil,
				actor = "human:Philip Bergen",
				when = "2026-11-20 03:10",
			})
			t.expect(has(issueText, "\nLayer:")).toBe(false)
			-- the stamped note reads back with its header
			local back = escalation.parse(text) :: escalation.Note
			t.expect(back.item).toBe("R0120")
			t.expect(back.reason).toBe("red-gate")
			t.expect(back.from).toBe("active")
			t.expect(back.layer).toBe("c0230")
			t.expect(back.actor).toBe("agent:claude-opus-5-5 effort high")
			t.expect(back.when).toBe("2026-11-20 03:10")
			t.expect(#back.resume).toBe(3)
			t.expect(escalation.check(back)).toBe(nil)
			-- the reason list is closed
			t.expect(function()
				escalation.stamp(GOOD, {
					item = "R0120",
					reason = "bored",
					from = "active",
					layer = nil,
					actor = HEADER.actor,
					when = HEADER.when,
				})
			end).toThrow("bored")
			-- a stamped note with a reason outside the list does not check
			local bad =
				escalation.parse((string.gsub(text, "Reason: red%-gate", "Reason: bored"))) :: escalation.Note
			t.expect(has(escalation.check(bad) or "", "bored")).toBe(true)
			-- a title or header the worker wrote is replaced, not doubled
			local twice = escalation.stamp(text, HEADER)
			t.expect(twice).toBe(text)
		end
	)

	it("AC2: plan maps each decision from preparing and from active to its status and edits", function()
		type Row = {
			decision: string,
			status: string,
			design: string?,
			decided: boolean,
			unfold: boolean,
			split: boolean,
		}
		local function expectPlan(from: "preparing" | "active", isRaft: boolean, want: Row)
			local got = escalation.plan(from, isRaft, want.decision)
			local label = `{from} {if isRaft then "raft" else "issue"} {want.decision}`
			t.expect(`{label} status {got.status}`).toBe(`{label} status {want.status}`)
			t.expect(`{label} design {got.design or "-"}`).toBe(`{label} design {want.design or "-"}`)
			t.expect(`{label} decided {got.decided}`).toBe(`{label} decided {want.decided}`)
			t.expect(`{label} unfold {got.unfold}`).toBe(`{label} unfold {want.unfold}`)
			t.expect(`{label} split {got.split}`).toBe(`{label} split {want.split}`)
			t.expect(`{label} copy {got.copyNote}`).toBe(`{label} copy {want.unfold}`)
		end
		for _, isRaft in { false, true } do
			expectPlan("preparing", isRaft, {
				decision = "retry",
				status = "new",
				design = nil,
				decided = false,
				unfold = false,
				split = false,
			})
			expectPlan("preparing", isRaft, {
				decision = "approve",
				status = "new",
				design = nil,
				decided = true,
				unfold = false,
				split = false,
			})
			expectPlan("preparing", isRaft, {
				decision = "amend-design",
				status = "new",
				design = "draft",
				decided = false,
				unfold = false,
				split = false,
			})
			expectPlan("preparing", isRaft, {
				decision = "split",
				status = "new",
				design = "draft",
				decided = false,
				unfold = false,
				split = true,
			})
			expectPlan("preparing", isRaft, {
				decision = "abort",
				status = "new",
				design = nil,
				decided = false,
				unfold = false,
				split = false,
			})
		end
		-- a raft that was running goes back prepared, and the Layer member is the one that changes
		expectPlan("active", true, {
			decision = "retry",
			status = "prepared",
			design = nil,
			decided = false,
			unfold = false,
			split = false,
		})
		expectPlan("active", true, {
			decision = "approve",
			status = "prepared",
			design = nil,
			decided = true,
			unfold = false,
			split = false,
		})
		expectPlan("active", true, {
			decision = "amend-design",
			status = "prepared",
			design = nil,
			decided = false,
			unfold = true,
			split = false,
		})
		expectPlan("active", true, {
			decision = "split",
			status = "prepared",
			design = nil,
			decided = false,
			unfold = true,
			split = true,
		})
		expectPlan("active", true, {
			decision = "abort",
			status = "prepared",
			design = nil,
			decided = false,
			unfold = false,
			split = false,
		})
		-- a sixth decision is not one
		t.expect(function()
			escalation.plan("preparing", false, "shrug")
		end).toThrow("shrug")
	end)

	it(
		"AC2: resolution appends the decision, the answer, the actor, the quoted words and the time; nextArchive and question",
		function()
			local stamped = escalation.stamp(GOOD, HEADER)
			local done = escalation.resolution(stamped, {
				decision = "approve",
				answer = "use the library",
				by = "agent:claude-opus-5-5 effort high",
				said = "yes, take the library",
				when = "2026-11-20 09:00",
			})
			t.expect(string.sub(done, 1, #stamped)).toBe(stamped)
			t.expect(
				has(
					done,
					"\n## Resolution\nDecision: approve\nAnswer: use the library\nBy: agent:claude-opus-5-5 effort high\n"
				)
			).toBe(true)
			t.expect(has(done, 'Said: "yes, take the library"\n')).toBe(true)
			t.expect(has(done, "When: 2026-11-20 09:00\n")).toBe(true)
			local read = escalation.parse(done) :: escalation.Note
			t.expect((read.resolution :: escalation.Resolution).decision).toBe("approve")
			t.expect((read.resolution :: escalation.Resolution).answer).toBe("use the library")
			t.expect((read.resolution :: escalation.Resolution).said).toBe("yes, take the library")
			-- a terminal resolution has no Said line, and no answer reads as none
			local human = escalation.resolution(stamped, {
				decision = "retry",
				answer = nil,
				by = "human:Philip Bergen",
				said = nil,
				when = "2026-11-20 09:00",
			})
			t.expect(has(human, "Said:")).toBe(false)
			t.expect(has(human, "Answer: none\n")).toBe(true)
			t.expect(
				((escalation.parse(human) :: escalation.Note).resolution :: escalation.Resolution).answer
			)
				.toBe(nil)
			t.expect(escalation.question(read))
				.toBe("Accept a new dependency on the json library, or write our own reader?")
			-- the next free archive name
			t.expect(escalation.nextArchive({ "R0120.md", "escalation.md" })).toBe("escalation-001.md")
			t.expect(escalation.nextArchive({ "escalation.md", "escalation-001.md", "escalation-004.md" }))
				.toBe("escalation-005.md")
			t.expect(escalation.nextArchive({ "escalation-12.md", "notes-009.md" })).toBe("escalation-001.md")
		end
	)
end)
