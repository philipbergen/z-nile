--!strict
-- c0306 AC3 (the publish half): publish.markProblem accepts the `reviews: judged` line in an issue's claim (status
-- preparing-...) and in a new raft's document, and refuses it in any other commit: another status move, a changed or
-- removed line, a new issue or any other document. Pure: path, the document on origin (nil when new), the document.
local publish = require("@znile/engine/publish")
local t = require("@tests/lib/t")

local ISSUE = "pickman/.tracker/issues/c0010/c0010.md"
local RAFT = "pickman/.tracker/rafts/R0010/R0010.md"

local function doc(status: string, reviews: string?): string
	return `---\nid: c0010\ntype: chore\ntitle: t\nslug: t\nraft: \ndepends_on: []\nemergent: false\ndesign: draft\n{if reviews
		then `reviews: {reviews}\n`
		else ""}created: 2026-11-14\nstatus: {status}\n---\n\n# c0010\n`
end

local function has(s: string?, part: string): boolean
	return s ~= nil and string.find(s, part, 1, true) ~= nil
end

return t.spec("c0306 publish accepts the mark only where the tool writes it", function(it)
	it("AC3: a claim (status preparing) may add reviews: judged to an existing issue", function()
		t.expect(
			publish.markProblem(
				ISSUE,
				doc("new-quiet-copper-falcon"),
				doc("preparing-quiet-copper-falcon", "judged")
			)
		).toBe(nil)
	end)

	it("AC3: a new raft's document may carry the line, and a document without it is untouched", function()
		t.expect(publish.markProblem(RAFT, nil, doc("preparing-quiet-copper-falcon", "judged"))).toBe(nil)
		t.expect(
			publish.markProblem(ISSUE, doc("new-quiet-copper-falcon"), doc("preparing-quiet-copper-falcon"))
		)
			.toBe(nil)
		t.expect(publish.markProblem(ISSUE, nil, doc("new-quiet-copper-falcon"))).toBe(nil)
	end)

	it("AC3: the line is refused on any other status move of an existing document", function()
		for _, to in
			{
				"new-quiet-copper-falcon",
				"prepared-quiet-copper-falcon",
				"active-quiet-copper-falcon",
				"blocked-quiet-copper-falcon",
			}
		do
			local why = publish.markProblem(ISSUE, doc("preparing-quiet-copper-falcon"), doc(to, "judged"))
			t.expect(has(why, "reviews: judged")).toBe(true)
			t.expect(has(why, ISSUE)).toBe(true)
		end
	end)

	it("AC3: the line is refused on a document that is not an issue's, or whose claim is a raft's", function()
		t.expect(publish.markProblem(RAFT, doc("preparing-a-b-c"), doc("preparing-a-b-c", "judged")) ~= nil)
			.toBe(true)
		t.expect(
			publish.markProblem(
				"pickman/.tracker/issues/c0010/provenance.md",
				nil,
				doc("new-a-b-c", "judged")
			) ~= nil
		).toBe(true)
	end)

	it("AC3: the line is refused in a new issue's stub", function()
		t.expect(
			has(publish.markProblem(ISSUE, nil, doc("new-quiet-copper-falcon", "judged")), "reviews: judged")
		)
			.toBe(true)
	end)

	it("AC3: the line is never removed or changed, in a claim or out of it", function()
		t.expect(publish.markProblem(ISSUE, doc("preparing-a-b-c", "judged"), doc("preparing-d-e-f")) ~= nil)
			.toBe(true)
		t.expect(publish.markProblem(ISSUE, doc("new-a-b-c", "judged"), doc("new-d-e-f")) ~= nil).toBe(true)
		t.expect(publish.markProblem(ISSUE, doc("new-a-b-c", "judged"), doc("preparing-d-e-f", "all")) ~= nil)
			.toBe(true)
		-- already marked and kept: a re-claim carries it
		t.expect(publish.markProblem(ISSUE, doc("new-a-b-c", "judged"), doc("preparing-d-e-f", "judged")))
			.toBe(nil)
		t.expect(
			publish.markProblem(ISSUE, doc("preparing-a-b-c", "judged"), doc("prepared-d-e-f", "judged"))
		)
			.toBe(nil)
	end)

	it(
		"AC3: a status line in the body is not a claim, and a mark line in the body is not the mark",
		function()
			local body = "\nstatus: preparing-x-y-z\n"
			local moved = doc("prepared-a-b-c", "judged") .. body
			t.expect(has(publish.markProblem(ISSUE, doc("new-a-b-c") .. body, moved), "reviews: judged"))
				.toBe(true)
			local fake = doc("new-a-b-c") .. "\nreviews: judged\n"
			t.expect(publish.markProblem(ISSUE, doc("new-a-b-c"), fake)).toBe(nil)
		end
	)
end)
