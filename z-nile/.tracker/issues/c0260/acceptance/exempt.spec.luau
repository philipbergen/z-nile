--!strict
-- c0260 AC9: a ticket an agent filed from its own finding is exempt from the user's capture record, by a marker the
-- check reads (`## Filed by (agent)` with a Source line and a Scope decision line in the Problem); a ticket that has
-- a user ask cannot claim the exemption. capturecheck over texts.
local capturecheck = require("@znile/engine/capturecheck")
local capturecut = require("@znile/engine/capturecut")
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
-- the gate calls the checker with the idea reviews beside the document
local REVIEWS: { [string]: string } =
	{ ["idea-review-001.md"] = "# Idea review 001\n\n## Findings\n\nnone\n" }
local function satisfies(doc: string, reviews: { [string]: string }?): boolean
	return capturecheck.satisfies(doc, reviews or REVIEWS)
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
		t.expect(has(problems(agent("A lesson.\nScope decision: yes\n")), "exact Scope decision line"))
			.toBe(true)
	end)

	it(
		"AC9: a ticket that has a user ask (or any capture section) cannot also claim the exemption",
		function()
			for _, section in
				{
					"## Ask (verbatim)\n### Message 2026-11-07\n```\nhi\n```\n\n",
					"## Interview\nNone: x\n\n",
					"## Confirmation\nx\n\n",
				}
			do
				t.expect(has(problems(agent(nil, nil, section)), "cannot also carry a user's capture record"))
					.toBe(true)
			end
		end
	)

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
				"agent:c0260/graph-miss",
				"agent:R0090/gate-slow",
			}
		do
			t.expect(capturecheck.source(ok)).toBe(ok)
		end
		for _, bad in
			{
				"",
				"agent:c0260/Graph Miss",
				"agent:c0260/UPPER",
				"agent:c0260/",
				"agent:c0260/-lead",
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
			t.expect(has(problems(agent(nil, "Source: the user asked me to\n")), "needs a `Source:` line"))
				.toBe(true)
			t.expect(
				has(problems(agent(nil, "Source: lesson:z-ticket/split-designs-name-each-owner\n")), "Source")
			)
				.toBe(false)
			t.expect(problems(agent(nil, "Source: agent:c0260/graph-miss\n"))).toBe("")
			t.expect(
				has(
					problems(
						agent(
							"A lesson.\nScope decision (user, 2026-11-08): agents may file what they like\n"
						)
					),
					"exact Scope decision line"
				)
			).toBe(true)
		end
	)

	it(
		"AC10: the claim accepts an agent ticket only with a valid marker, and a user capture only with all three sections",
		function()
			t.expect(satisfies(agent())).toBe(true)
			t.expect(satisfies(agent(nil, "Source: free text\n"))).toBe(false)
			local onlyAsk =
				"---\nid: c0902\n---\n\n## Problem\nP\n\n## Ask (verbatim)\n### Message 2026-11-08\n```\nhi\n```\n"
			t.expect(satisfies(onlyAsk)).toBe(false)
			t.expect(satisfies("## Problem\nold\n")).toBe(false)
		end
	)

	it(
		"AC10: every section of a user record must be non-empty and of its kind: a headings-only record is not claimed",
		function()
			local full =
				'---\nid: c0903\n---\n\n## Problem\nP\n\n## Ask (verbatim)\n### Message 2026-11-08\n```\nhi\n```\n\n## Interview\n### Q1\nQuestion: q\nOptions: a\nAnswer: a\n\n## Confirmation\nConfirmed (user, 2026-11-08) after round 1: "y"\n\n## Design\n'
			t.expect(satisfies(full)).toBe(true)
			for _, section in { "Ask (verbatim)", "Interview", "Confirmation" } do
				local escaped = (string.gsub(section, "[%(%)]", "%%%0"))
				local emptied = (string.gsub(full, "(## " .. escaped .. "\n).-(\n## )", "%1%2", 1))
				t.expect(satisfies(emptied)).toBe(false)
			end
			t.expect(satisfies((string.gsub(full, "### Message 2026%-11%-08", "text", 1)))).toBe(false)
			-- text under a heading that is not that section's kind of text
			t.expect(
				satisfies(
					(
						string.gsub(
							full,
							'Confirmed %(user, 2026%-11%-08%) after round 1: "y"',
							"the user said yes",
							1
						)
					)
				)
			).toBe(false)
			t.expect(satisfies((string.gsub(full, "### Q1", "question one", 1)))).toBe(false)
		end
	)

	it(
		"AC10: the claim calls the record check: a record the check refuses is not claimed, however its sections look",
		function()
			local full =
				'---\nid: c0903\n---\n\n## Problem\nP\n\n## Ask (verbatim)\n### Message 2026-11-08\n```\nhi\n```\n\n## Interview\n### Q1\nQuestion: q\nOptions: a\nAnswer: a\n\n## Confirmation\nConfirmed (user, 2026-11-08) after round 1: "y"\n\n## Design\n'
			t.expect(satisfies(full)).toBe(true)
			local function without(from: string, to: string): string
				return (string.gsub(full, from, to, 1))
			end
			t.expect(
				satisfies(
					without('Confirmed %(user, 2026%-11%-08%) after round 1: "y"', "Pending (later, maybe)")
				)
			).toBe(false)
			t.expect(satisfies(without("Question: q\nOptions: a\nAnswer: a", "Question: q"))).toBe(false) -- Q1 with no Answer
			t.expect(satisfies(without("### Q1", "### Q2"))).toBe(false) -- a gap in the numbering
			t.expect(satisfies(without('"y"\n', '"y"\nanother line\n'))).toBe(false) -- a line after the Confirmed one
			t.expect(satisfies(full, {})).toBe(false) -- never reviewed: no raw review beside the document
		end
	)

	it(
		"AC9: a new ticket is `idea: unchallenged`; one filed by an agent carries the marker and the same idea key; the mark is added only when asked",
		function()
			local function setFront(doc: string, key: string, value: string): string
				return (string.gsub(doc, "\ndesign: draft\n", `\ndesign: draft\n{key}: {value}\n`, 1))
			end
			local stub = "---\nid: c0905\ndesign: draft\n---\n\n## Problem\n\n## Non-goals\n\n## Design\n"
			local user = capturecut.newDoc(stub, setFront, nil, false) :: string
			t.expect(has(user, "idea: unchallenged")).toBe(true)
			t.expect(has(user, "capture: required")).toBe(false)
			t.expect(has(capturecut.newDoc(stub, setFront, nil, true) :: string, "capture: required"))
				.toBe(true)
			local filed = capturecut.newDoc(stub, setFront, "agent:c0260/graph-miss", true) :: string
			t.expect(has(filed, "idea: unchallenged")).toBe(true) -- an agent ticket runs ./zn idea like any ticket
			t.expect(has(filed, "## Filed by (agent)\nSource: agent:c0260/graph-miss")).toBe(true)
			t.expect(has(filed, capturecheck.SCOPE_LINE)).toBe(true)
			t.expect(capturecheck.kind(filed)).toBe("agent")
			t.expect(#capturecheck.check(filed, {})).toBe(0)
			local bad, why = capturecut.newDoc(stub, setFront, "make it scarier", false)
			t.expect(bad).toBe(nil)
			t.expect(has(why or "", "--filed-by takes")).toBe(true)
		end
	)

	it(
		"AC11: a review or agent source must name something on origin: the item, the review file, its finding",
		function()
			local docs: { [string]: string } = { c0777 = "p/issues/c0777/c0777.md" }
			local files: { [string]: string } =
				{ ["p/issues/c0777/design-review-001.md"] = "# R\n\n### F4 [low] x\n\n### F5\n" }
			local function docOf(id: string): string?
				return docs[id]
			end
			local function read(path: string): string?
				return files[path]
			end
			local function why(source: string): string?
				return capturecut.sourceProblem(source, docOf, read)
			end
			t.expect(why("review:c0777/design-review-001 F4")).toBe(nil)
			t.expect(why("review:c0777/design-review-001 F5")).toBe(nil)
			t.expect(has(why("review:c0777/design-review-001 F9") or "", "has no finding F9")).toBe(true)
			t.expect(has(why("review:c0777/design-review-002 F4") or "", "is not on origin/main")).toBe(true)
			t.expect(has(why("review:c0999/design-review-001 F4") or "", "c0999 is not on origin/main"))
				.toBe(true)
			t.expect(why("agent:c0777/graph-miss")).toBe(nil)
			t.expect(has(why("agent:c0999/graph-miss") or "", "c0999 is not on origin/main")).toBe(true)
			t.expect(why("lesson:z-ticket/anything")).toBe(nil) -- written by the prep that takes the issue: nothing to look up
		end
	)
end)
