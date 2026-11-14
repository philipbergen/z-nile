--!strict
-- c0262: the limited view. What the reviewer is shown is built from a fixed list of files, so the limit is the
-- tool's and not the reviewer's restraint. Pure: texts in, texts out.
local finalview = require("@znile/engine/finalview")
local t = require("@tests/lib/t")

local function has(text: string, needle: string): boolean
	return string.find(text, needle, 1, true) ~= nil
end

local CAPTURED = table.concat({
	"---",
	"id: c0010",
	"title: Alpha thing",
	"---",
	"",
	"# c0010: Alpha thing",
	"",
	"## Problem",
	"User: the alpha value is wrong.",
	"",
	"## Solution",
	"- Compute alpha.",
	"",
	"## Non-goals",
	"- No beta.",
	"",
	"## Design",
	"captured design text",
}, "\n")

local CURRENT = table.concat({
	"---",
	"id: c0010",
	"title: Alpha thing",
	"---",
	"",
	"# c0010: Alpha thing",
	"",
	"## Problem",
	"User: the alpha value is wrong.",
	'Decided with the user (2026-11-13): "alpha is a table".',
	"A compromise the reviewers reached in round two.",
	"",
	"## Solution",
	"- Compute alpha.",
	"",
	"## Design",
	"alpha returns a table.",
	"",
	"## Unknowns & experiments",
	"E1 refuted by design-review-002 F3.",
	"",
	"## Acceptance criteria",
	"AC1: alpha exists.",
	"",
	"## Open to the human",
	"- F2: refuted.",
	"",
	"## Verification log",
	"round 3 answered.",
}, "\n")

return t.spec("c0262 the limited view", function(it)
	it(
		"AC1: the ask of an older ticket is its capture plus the user's later decisions, and nothing else",
		function()
			local ask = finalview.ask(CAPTURED, CURRENT)
			t.expect(has(ask, "the alpha value is wrong")).toBe(true)
			t.expect(has(ask, "No beta")).toBe(true)
			t.expect(has(ask, "alpha is a table")).toBe(true)
			t.expect(has(ask, "A compromise the reviewers reached")).toBe(false)
			t.expect(has(ask, "captured design text")).toBe(false)
		end
	)

	it("AC1: a ticket captured with the interview is asked by Ask, Interview and Idea", function()
		local doc =
			"# c\n\n## Ask (verbatim)\nfix alpha\n\n## Interview\nQ1 which?\n\n## Idea\nalpha is a table\n\n## Problem\nrestated\n"
		local ask = finalview.ask(doc, doc)
		t.expect(has(ask, "fix alpha")).toBe(true)
		t.expect(has(ask, "Q1 which?")).toBe(true)
		t.expect(has(ask, "restated")).toBe(false)
	end)

	it("AC1: the design is the Design and Acceptance criteria sections, none of the trail", function()
		local d = finalview.design(CURRENT)
		t.expect(has(d, "alpha returns a table")).toBe(true)
		t.expect(has(d, "AC1: alpha exists")).toBe(true)
		t.expect(has(d, "design-review-002")).toBe(false)
		t.expect(has(d, "refuted")).toBe(false)
		t.expect(has(d, "round 3 answered")).toBe(false)
	end)

	it(
		"AC1: tracker bookkeeping of tickets and rafts is not in the diff, a project's own tracker documents are",
		function()
			for _, bad in
				{
					"z-nile/.tracker/issues/active/c0010/design-review-001.md",
					"z-nile/.tracker/issues/c0010/harvest.md",
					"pickman/.tracker/rafts/active/R0010/R0010.md",
					"z-nile/.tracker/issues/active/c0010/spend.d/x.tsv",
					".cache/final/c0010/diff.patch",
				}
			do
				t.expect(finalview.keepPath(bad)).toBe(false)
			end
			for _, good in
				{
					"z-nile/engine/finalview.luau",
					"pickman/.tracker/architecture.md",
					"pickman/.tracker/game-design.md",
					"z-nile/skills/zz-review/SKILL.md",
				}
			do
				t.expect(finalview.keepPath(good)).toBe(true)
			end
		end
	)

	it("AC1: the view holds only the fixed files", function()
		local files = finalview.assemble({
			id = "c0010",
			captured = CAPTURED,
			current = CURRENT,
			contract = { ["check.sh"] = "check", ["acceptance/a.spec.luau"] = "spec" },
			diff = "diff --git a/x b/x\n",
		})
		for path in files do
			t.expect(finalview.allowed(path)).toBe(true)
		end
		t.expect(files["ask.md"] ~= nil and files["design.md"] ~= nil and files["diff.patch"] ~= nil)
			.toBe(true)
		t.expect(files["contract/acceptance/a.spec.luau"]).toBe("spec")
		t.expect(finalview.allowed("design-review-001.md")).toBe(false)
		t.expect(finalview.allowed("contract/../design-review-001.md")).toBe(false)
		t.expect(finalview.allowed("harvest.md")).toBe(false)
	end)

	it("AC2: the view's id follows what is judged, not the README", function()
		local base = {
			id = "c0010",
			captured = CAPTURED,
			current = CURRENT,
			contract = { ["check.sh"] = "check" },
			diff = "d1",
		}
		local a = finalview.assemble(base)
		local same = finalview.assemble(base)
		t.expect(finalview.viewId(a)).toBe(finalview.viewId(same))
		t.expect(has(a["README.md"] :: string, finalview.viewId(a))).toBe(true)
		local moved = table.clone(base)
		moved.diff = "d2"
		t.expect(finalview.viewId(finalview.assemble(moved)) ~= finalview.viewId(a)).toBe(true)
		local redesigned = table.clone(base)
		redesigned.current = (string.gsub(CURRENT, "alpha returns a table%.", "alpha returns a list."))
		t.expect(finalview.viewId(finalview.assemble(redesigned)) ~= finalview.viewId(a)).toBe(true)
	end)

	it("AC3: the README sets the one question: does the diff deliver the original ask", function()
		local readme = finalview.readme("c0010", "abc123")
		t.expect(has(readme, "does the diff deliver the original ask")).toBe(true)
		t.expect(has(readme, "Gap: design")).toBe(true)
		t.expect(has(readme, "Gap: implementation")).toBe(true)
		t.expect(has(readme, "Verdict: on-course | off-course")).toBe(true)
		t.expect(has(readme, "View: abc123")).toBe(true)
		t.expect(has(readme, "reviews, refutes, harvests, pull request comments or worker notes")).toBe(true)
	end)
end)
