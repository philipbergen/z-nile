--!strict
-- c0260 AC9: a ticket an agent filed from its own finding is exempt from the user's capture record, by a marker the
-- check reads (`## Filed by (agent)` with a Source line and a Scope decision line in the Problem); a ticket that has
-- a user ask cannot claim the exemption. capturecheck over texts.
local capturecheck = require("@znile/engine/capturecheck")
local t = require("@tests/lib/t")

local SCOPE =
	"Scope decision (user, 2026-11-08): agent-filed tickets are exempt from the ask, interview, idea review and confirmation (c0260)\n"
local function agent(problem: string?, filed: string?, extra: string?): string
	return table.concat({
		"---\nid: c0901\n---\n\n## Problem\n" .. (problem or ("A lesson.\n" .. SCOPE)) .. "\n",
		"## Filed by (agent)\n" .. (filed or "Source: review:c0260/design-review-002 F4\n") .. "\n",
		extra or "",
		"## Design\n",
	})
end
local function problems(d: string): string
	return table.concat(capturecheck.check(d, {}), "\n")
end
local function has(text: string, part: string): boolean
	return string.find(text, part, 1, true) ~= nil
end

return t.spec("c0260 an agent-filed ticket is exempt, and only that", function(it)
	it(
		"AC9: a ticket filed by an agent with a source and a scope decision passes, and is recognised as agent",
		function()
			t.expect(problems(agent())).toBe("")
			t.expect(capturecheck.kind(agent())).toBe("agent")
		end
	)

	it("AC9: the marker needs a Source line and the Scope decision line", function()
		t.expect(has(problems(agent(nil, "no source here\n")), "needs a `Source:")).toBe(true)
		t.expect(has(problems(agent("A lesson.\n")), "exact Scope decision line")).toBe(true)
		t.expect(has(problems(agent("A lesson.\nScope decision: yes\n")), "exact Scope decision line")).toBe(true)
	end)

	it("AC9: a ticket that has a user ask (or any capture section) cannot also claim the exemption", function()
		for _, section in
			{
				"## Ask (verbatim)\n### Message 2026-11-07\n```\nhi\n```\n\n",
				"## Interview\nNone: x\n\n",
				"## Idea\nx\n\n",
				"## Confirmation\nx\n\n",
			}
		do
			t.expect(has(problems(agent(nil, nil, section)), "cannot also carry a user's capture record")).toBe(true)
		end
	end)

	it("AC9: free text in the Problem is not the marker", function()
		local text = "---\nid: c0902\n---\n\n## Problem\nFiled by an agent from a review. " .. SCOPE .. "\n"
		t.expect(capturecheck.kind(text)).toBe("none")
	end)

	it("AC9: --filed-by accepts a lesson id or a review finding and refuses everything else", function()
		for _, ok in
			{
				"lesson:z-ticket/split-designs-name-each-owner",
				"review:c0260/design-review-003 F4",
				"review:R0090/review-001 F12",
			}
		do
			t.expect(capturecheck.source(ok)).toBe(ok)
		end
		for _, bad in
			{
				"",
				"make the ghosts scarier",
				"review:c0260/design-review-003",
				"review:c0260/design-review-003 F",
				"lesson:",
				"lesson:z-ticket",
				"lesson:Z/x",
				"review:x/y F1",
			}
		do
			t.expect(capturecheck.source(bad)).toBe(nil)
		end
	end)

	it(
		"AC9: the Source must be a lesson, a review finding or an agent finding, and the Scope line the exact one",
		function()
			t.expect(has(problems(agent(nil, "Source: the user asked me to\n")), "needs a `Source:` line")).toBe(true)
			t.expect(has(problems(agent(nil, "Source: lesson:z-ticket/split-designs-name-each-owner\n")), "Source"))
				.toBe(false)
			t.expect(problems(agent(nil, "Source: agent:c0260/graph-miss\n"))).toBe("")
			t.expect(
				has(
					problems(agent("A lesson.\nScope decision (user, 2026-11-08): agents may file what they like\n")),
					"exact Scope decision line"
				)
			).toBe(true)
		end
	)

	it(
		"AC10: the claim accepts an agent ticket only with a valid marker, and a user capture only with all five sections",
		function()
			t.expect(capturecheck.satisfies(agent())).toBe(true)
			t.expect(capturecheck.satisfies(agent(nil, "Source: free text\n"))).toBe(false)
			local onlyAsk =
				"---\nid: c0902\n---\n\n## Problem\nP\n\n## Ask (verbatim)\n### Message 2026-11-08\n```\nhi\n```\n"
			t.expect(capturecheck.satisfies(onlyAsk)).toBe(false)
			t.expect(capturecheck.satisfies("## Problem\nold\n")).toBe(false)
		end
	)
end)
