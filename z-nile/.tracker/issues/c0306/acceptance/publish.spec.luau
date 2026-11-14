--!strict
-- c0306 AC3 (the publish half): publish.markProblem accepts the `reviews: judged` line in an issue's claim (status
-- preparing-...) and in a new raft's document, and refuses it in any other commit: another status move, a changed or
-- removed line, a new issue or any other document. Pure: path, the document on origin (nil when new), the document.
local publish = require("@znile/engine/publish")
local reviewmodel = require("@znile/engine/reviewmodel")
local store = require("@znile/engine/store")
local t = require("@tests/lib/t")

local ISSUE = "pickman/.tracker/issues/c0010/c0010.md"
local RAFT = "pickman/.tracker/rafts/R0010/R0010.md"

local function doc(status: string, reviews: string?): string
	return `---\nid: c0010\ntype: chore\ntitle: t\nslug: t\nraft: \ndepends_on: []\nemergent: false\ndesign: draft\n{if reviews
		then `reviews: {reviews}\n`
		else ""}created: 2026-11-14\nstatus: {status}\n---\n\n# c0010\n`
end

-- read through any: the prep type-checks with none of the issue's code present
local function mark(path: string, existing: string?, content: string): string?
	return (publish :: any).markProblem(path, existing, content)
end

local function has(s: string?, part: string): boolean
	return s ~= nil and string.find(s, part, 1, true) ~= nil
end

return t.spec("c0306 publish accepts the mark only where the tool writes it", function(it)
	it("AC3: a claim (status preparing) may add reviews: judged to an existing issue", function()
		t.expect(mark(ISSUE, doc("new-quiet-copper-falcon"), doc("preparing-quiet-copper-falcon", "judged")))
			.toBe(nil)
	end)

	it("AC3: a new raft's document may carry the line, and a document without it is untouched", function()
		t.expect(mark(RAFT, nil, doc("preparing-quiet-copper-falcon", "judged"))).toBe(nil)
		-- a raft made by the local form lands by pull request with the line; its later published changes carry it
		t.expect(mark(RAFT, doc("prepared-a-b-c", "judged"), doc("preparing-d-e-f", "judged"))).toBe(nil)
		t.expect(mark(ISSUE, doc("new-quiet-copper-falcon"), doc("preparing-quiet-copper-falcon"))).toBe(nil)
		t.expect(mark(ISSUE, nil, doc("new-quiet-copper-falcon"))).toBe(nil)
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
			local why = mark(ISSUE, doc("preparing-quiet-copper-falcon"), doc(to, "judged"))
			t.expect(has(why, "reviews: judged")).toBe(true)
			t.expect(has(why, ISSUE)).toBe(true)
		end
	end)

	it("AC3: the line is refused on a document that is not an issue's, or whose claim is a raft's", function()
		t.expect(mark(RAFT, doc("preparing-a-b-c"), doc("preparing-a-b-c", "judged")) ~= nil).toBe(true)
		t.expect(mark("pickman/.tracker/issues/c0010/provenance.md", nil, doc("new-a-b-c", "judged")) ~= nil)
			.toBe(true)
	end)

	it("AC3: the line is refused in a new issue's stub", function()
		t.expect(has(mark(ISSUE, nil, doc("new-quiet-copper-falcon", "judged")), "reviews: judged"))
			.toBe(true)
	end)

	it("AC3: the line is never removed or changed, in a claim or out of it", function()
		t.expect(mark(ISSUE, doc("preparing-a-b-c", "judged"), doc("preparing-d-e-f")) ~= nil).toBe(true)
		t.expect(mark(ISSUE, doc("new-a-b-c", "judged"), doc("new-d-e-f")) ~= nil).toBe(true)
		t.expect(mark(ISSUE, doc("new-a-b-c", "judged"), doc("preparing-d-e-f", "all")) ~= nil).toBe(true)
		-- already marked and kept: a re-claim carries it
		t.expect(mark(ISSUE, doc("new-a-b-c", "judged"), doc("preparing-d-e-f", "judged"))).toBe(nil)
		t.expect(mark(ISSUE, doc("preparing-a-b-c", "judged"), doc("prepared-d-e-f", "judged"))).toBe(nil)
	end)

	it(
		"AC3: a status line in the body is not a claim, and a mark line in the body is not the mark",
		function()
			local body = "\nstatus: preparing-x-y-z\n"
			local moved = doc("prepared-a-b-c", "judged") .. body
			t.expect(has(mark(ISSUE, doc("new-a-b-c") .. body, moved), "reviews: judged")).toBe(true)
			local fake = doc("new-a-b-c") .. "\nreviews: judged\n"
			t.expect(mark(ISSUE, doc("new-a-b-c"), fake)).toBe(nil)
		end
	)

	it(
		"AC3: publish and the commands read the mark the same way: a trailing space is a mark in both",
		function()
			-- the one reader: store.parseFront, then reviewmodel.judged (read through any: the prep has none of the code)
			local function judged(text: string): boolean
				return reviewmodel.judged((store :: any).parseFront(text))
			end
			local spaced = (
				string.gsub(doc("preparing-a-b-c", "judged"), "reviews: judged\n", "reviews: judged \n", 1)
			)
			t.expect(judged(spaced)).toBe(true)
			-- publish sees it as the mark: a claim may add it, any other status move may not
			t.expect(mark(ISSUE, doc("new-a-b-c"), spaced)).toBe(nil)
			t.expect(
				has(
					mark(ISSUE, doc("new-a-b-c"), (string.gsub(spaced, "preparing", "prepared", 1))),
					"reviews: judged"
				)
			).toBe(true)
			-- and a kept mark with a trailing space is not a change
			t.expect(mark(ISSUE, spaced, spaced)).toBe(nil)
			t.expect(has(mark(ISSUE, spaced, doc("preparing-a-b-c")), "reviews: judged")).toBe(true)
			-- a value that is not the mark is neither a mark nor refused
			local other = (
				string.gsub(doc("preparing-a-b-c", "judged"), "reviews: judged", "reviews: judgedx", 1)
			)
			t.expect(judged(other)).toBe(false)
			t.expect(mark(ISSUE, doc("new-a-b-c"), other)).toBe(nil)
		end
	)
end)
