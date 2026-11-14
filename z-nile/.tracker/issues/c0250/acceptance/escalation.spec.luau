--!strict
-- c0250 AC2: the escalation note. Pure over engine/escalation: the reader, the checks, the writer of the header and the
-- resume commands, the resolution, and the table that maps each decision to the item's next state.
local escalation = require("@znile/engine/escalation")
local t = require("@tests/lib/t")

-- the module's types, read through any: the spec stays loadable by a type check of the tree that has no module yet
type Note = any
type Header = any
type Resolution = any

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

local HEADER: Header = {
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
			local n = note :: Note
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
			local oddNote = escalation.parse(odd) :: Note
			local oddWhy = escalation.check(oddNote)
			t.expect(oddWhy ~= nil).toBe(true)
			t.expect(has(oddWhy or "", "maybe")).toBe(true)
			-- no recommendation, and two
			local none = escalation.parse((string.gsub(GOOD, " %(recommended%)", ""))) :: Note
			t.expect(has(escalation.check(none) or "", "exactly one")).toBe(true)
			local two = escalation.parse(
				(string.gsub(GOOD, "one more review round", "one more review round (recommended)"))
			) :: Note
			t.expect(has(escalation.check(two) or "", "exactly one")).toBe(true)
			-- no option at all
			local bare = escalation.parse((string.gsub(GOOD, "%- [^\n]*\n", "Whatever you think.\n"))) :: Note
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
					.. 'An agent adds --said "<the user\'s message>" to each command.\n'
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
			local back = escalation.parse(text) :: Note
			t.expect(back.item).toBe("R0120")
			t.expect(back.reason).toBe("red-gate")
			t.expect(back.from).toBe("active")
			t.expect(back.layer).toBe("c0230")
			t.expect(back.actor).toBe("agent:claude-opus-5-5 effort high")
			t.expect(back.when).toBe("2026-11-20 03:10")
			t.expect(#back.resume).toBe(4) -- three commands and the closing line
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
			local bad = escalation.parse((string.gsub(text, "Reason: red%-gate", "Reason: bored"))) :: Note
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
			-- a draft raft has no design to amend or split: its approve and amend-design act as retry (F13)
			local draft = isRaft
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
				decided = not draft,
				unfold = false,
				split = false,
			})
			expectPlan("preparing", isRaft, {
				decision = "amend-design",
				status = "new",
				design = if draft then nil else "draft",
				decided = false,
				unfold = false,
				split = false,
			})
			if draft then
				t.expect(escalation.plan("preparing", true, "split").refuse).toBe(
					"a draft raft has no design to split: resolve it amend-design, then split the issue in z-design"
				)
			else
				t.expect(escalation.plan("preparing", false, "split").refuse).toBe(nil)
				expectPlan("preparing", false, {
					decision = "split",
					status = "new",
					design = "draft",
					decided = false,
					unfold = false,
					split = true,
				})
			end
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
		-- only an approve on a raft that was running re-records its Layer member (F4)
		t.expect(escalation.plan("active", true, "approve").regroup).toBe(true)
		t.expect(escalation.plan("active", true, "retry").regroup).toBe(false)
		t.expect(escalation.plan("preparing", false, "approve").regroup).toBe(false)
		t.expect(escalation.plan("preparing", true, "approve").regroup).toBe(false)
		-- an issue is never blocked from active: its raft is (F2)
		for _, decision in escalation.DECISIONS do
			t.expect(function()
				escalation.plan("active", false, decision)
			end).toThrow("its raft is")
		end
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
			local read = escalation.parse(done) :: Note
			t.expect((read.resolution :: Resolution).decision).toBe("approve")
			t.expect((read.resolution :: Resolution).answer).toBe("use the library")
			t.expect((read.resolution :: Resolution).said).toBe("yes, take the library")
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
			t.expect(((escalation.parse(human) :: Note).resolution :: Resolution).answer).toBe(nil)
			t.expect(escalation.question(read))
				.toBe("Accept a new dependency on the json library, or write our own reader?")
			-- the next free archive name
			t.expect(escalation.nextArchive({ "R0120.md", "escalation.md" })).toBe("escalation-001.md")
			t.expect(escalation.nextArchive({ "escalation.md", "escalation-001.md", "escalation-004.md" }))
				.toBe("escalation-005.md")
			t.expect(escalation.nextArchive({ "escalation-12.md", "notes-009.md" })).toBe("escalation-001.md")
		end
	)
	it(
		"AC2: stamp writes Session and Open, and the resume lines carry --title for split and one --rule per open id",
		function()
			local all = escalation.stamp(GOOD .. "- split: carve it out\n- abort: stop\n", {
				item = "c0230",
				reason = "review-exhausted",
				from = "preparing",
				layer = nil,
				actor = HEADER.actor,
				session = "6f1c-aaaa",
				open = { "F2", "F5" },
				when = HEADER.when,
			})
			local head = lines(all)
			t.expect(head[6]).toBe("Session: 6f1c-aaaa")
			t.expect(head[7]).toBe("Open: F2, F5")
			t.expect(head[8]).toBe("When: 2026-11-20 03:10")
			local resume =
				string.sub(all, (string.find(all, "\n## Resume\n", 1, true) :: number) + #"\n## Resume\n")
			t.expect(
				has(
					resume,
					'./zn resolve c0230 split --answer "<your answer>" --title "<the new issue\'s title>" --rule F2="<your ruling>" --rule F5="<your ruling>"\n'
				)
			).toBe(true)
			t.expect(
				has(
					resume,
					'./zn resolve c0230 retry --answer "<your answer>" --rule F2="<your ruling>" --rule F5="<your ruling>"\n'
				)
			).toBe(true)
			t.expect(has(resume, 'An agent adds --said "<the user\'s message>" to each command.\n'))
				.toBe(true)
			-- a reason other than review-exhausted carries no --rule, and no Open line when none is open
			local plain = escalation.stamp(GOOD, {
				item = "c0230",
				reason = "red-gate",
				from = "preparing",
				layer = nil,
				actor = HEADER.actor,
				session = nil,
				open = { "F2" },
				when = HEADER.when,
			})
			t.expect(has(plain, "--rule")).toBe(false)
			t.expect(has(plain, "\nSession:")).toBe(false)
			-- the header reads back
			local back = escalation.parse(all) :: Note
			t.expect(back.session).toBe("6f1c-aaaa")
			t.expect(back.open).toEqual({ "F2", "F5" })
			t.expect((escalation.parse(plain) :: Note).open).toEqual({ "F2" })
		end
	)

	it("AC2: check refuses a note that already holds a resolution", function()
		local stamped = escalation.stamp(GOOD, HEADER)
		t.expect(escalation.check(escalation.parse(stamped) :: Note)).toBe(nil)
		local resolved = escalation.resolution(stamped, {
			decision = "retry",
			answer = nil,
			by = "human:Ann",
			said = nil,
			when = "2026-11-20 09:00",
		})
		t.expect(escalation.check(escalation.parse(resolved) :: Note))
			.toBe("this is the last block's note: write the new one")
	end)

	it(
		"AC6: the resolution records rulings, the Decided and Scope lines quote the user, and rulings apply",
		function()
			local stamped = escalation.stamp(GOOD, {
				item = "c0230",
				reason = "review-exhausted",
				from = "preparing",
				layer = nil,
				actor = HEADER.actor,
				session = nil,
				open = { "F2", "F5" },
				when = HEADER.when,
			})
			local done = escalation.resolution(stamped, {
				decision = "retry",
				answer = "go on",
				by = "human:Ann",
				said = nil,
				ruled = { { id = "F2", words = "keep the reader" }, { id = "F5", words = "defer it" } },
				when = "2026-11-20 09:00",
			})
			t.expect(
				has(
					done,
					'Answer: go on\nBy: human:Ann\nRuled F2: "keep the reader"\nRuled F5: "defer it"\nWhen: '
				)
			).toBe(true)
			local note = escalation.parse(done) :: Note
			t.expect(escalation.rulings(note)).toEqual({ F2 = "keep the reader", F5 = "defer it" })
			-- an unresolved note has none
			t.expect(escalation.rulings(escalation.parse(stamped) :: Note)).toEqual({})
			-- the Decided line: a terminal quotes the answer, an agent session the user's words and the option
			t.expect(escalation.decidedLine("2026-11-20", "approve", "use json", nil))
				.toBe('Decided with the user (2026-11-20), resolve approve: "use json"')
			t.expect(escalation.decidedLine("2026-11-20", "approve", "use json", "yes, take json"))
				.toBe(
					'Decided with the user (2026-11-20), resolve approve: "yes, take json" (the option: use json)'
				)
			t.expect(escalation.scopeLine("2026-11-20", "split it", "c0301"))
				.toBe('Scope decision (user, 2026-11-20): "split it" (split into c0301)')
			-- rulings go under each unruled bullet of the open list, and an already ruled bullet is left as it is
			local doc = table.concat({
				"# c0230",
				"",
				"## Open to the human",
				"- F2: the reader is missing. Answer: refuted. Decision: keep it or not?",
				"- F5: the cache. Answer: refuted. Decision: defer?",
				"- F7: old. Answer: refuted. Decision: x",
				"  Ruled (user, 2026-11-01): fine",
				"",
				"## Notes",
				"x",
				"",
			}, "\n")
			local out, why = escalation.applyRulings(doc, note, "2026-11-20")
			t.expect(why).toBe(nil)
			t.expect(out).toBe(table.concat({
				"# c0230",
				"",
				"## Open to the human",
				"- F2: the reader is missing. Answer: refuted. Decision: keep it or not?",
				"  Ruled (user, 2026-11-20): keep the reader",
				"- F5: the cache. Answer: refuted. Decision: defer?",
				"  Ruled (user, 2026-11-20): defer it",
				"- F7: old. Answer: refuted. Decision: x",
				"  Ruled (user, 2026-11-01): fine",
				"",
				"## Notes",
				"x",
				"",
			}, "\n"))
			-- a bullet with no recorded ruling is refused, naming it; an unresolved note applies nothing
			local partial = escalation.resolution(stamped, {
				decision = "retry",
				answer = nil,
				by = "human:Ann",
				said = nil,
				ruled = { { id = "F2", words = "keep" } },
				when = "2026-11-20 09:00",
			})
			local none, noneWhy =
				escalation.applyRulings(doc, escalation.parse(partial) :: Note, "2026-11-20")
			t.expect(none).toBe(nil)
			t.expect(has(noneWhy or "", "F5 has no recorded ruling")).toBe(true)
			local unresolved, unresolvedWhy =
				escalation.applyRulings(doc, escalation.parse(stamped) :: Note, "2026-11-20")
			t.expect(unresolved).toBe(nil)
			t.expect(has(unresolvedWhy or "", "no resolution")).toBe(true)
		end
	)
end)
