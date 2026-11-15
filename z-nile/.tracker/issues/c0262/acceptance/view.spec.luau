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
	'- **Scope decision (user, 2026-11-14)**: "also a list".',
	"A compromise the reviewers reached in round two.",
	"",
	"## Solution",
	"- Compute alpha.",
	"",
	"## Design",
	"alpha returns a table.",
	"STATUS: prepared after design-review-003 (round 3).",
	"",
	"## Unknowns & experiments",
	"E1 refuted by design-review-002 F3.",
	"THE-UNKNOWN-NOTE",
	"",
	"## Acceptance criteria",
	"AC1: alpha exists.",
	"",
	"## Open to the human",
	"- F2: the finding text. Answer: the author's answer. Decision: pick a or b. Ruled (user, 2026-11-14): b.",
	"- F3: refuted by the author.",
	"",
	"## Verification log",
	"round 3 answered.",
}, "\n")

local function input(over: { [string]: any }?): finalview.Input
	local base: finalview.Input = {
		id = "c0010",
		captured = CAPTURED,
		base = CURRENT,
		tip = CURRENT,
		contract = { ["check.sh"] = "check", ["acceptance/a.spec.luau"] = "spec" },
		diff = "diff --git a/x b/x\n",
		patchId = "p1",
	}
	for k, v in over or {} do
		(base :: any)[k] = v
	end
	return base
end

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

	it("AC1: a decision is found in a bulleted or bold line, and in any section", function()
		local ask = finalview.ask(CAPTURED, CURRENT)
		t.expect(has(ask, "Scope decision (user, 2026-11-14)")).toBe(true)
		t.expect(has(ask, "also a list")).toBe(true)
		local elsewhere = CURRENT
			.. '\n## Verification log\nDecided with the user (2026-11-15): "in the log".\n'
		t.expect(has(finalview.ask(CAPTURED, elsewhere), "in the log")).toBe(true)
		local solution = (
			string.gsub(
				CURRENT,
				"%- Compute alpha%.",
				'- Compute alpha.\n- Decided with the user (2026-11-16): "in the solution".'
			)
		)
		t.expect(has(finalview.ask(CAPTURED, solution), "in the solution")).toBe(true)
	end)

	it(
		"AC1: a ruling shows its Decision and the user's word, never the finding or the author's answer",
		function()
			local ask = finalview.ask(CAPTURED, CURRENT)
			t.expect(has(ask, "Ruled (user, 2026-11-14): b.")).toBe(true)
			t.expect(has(ask, "pick a or b")).toBe(true)
			t.expect(has(ask, "the finding text")).toBe(false)
			t.expect(has(ask, "the author's answer")).toBe(false)
			t.expect(has(ask, "refuted by the author")).toBe(false)
		end
	)

	it(
		"AC1: a ticket captured with the interview is asked by Ask, Interview, Idea and Confirmation, as the base has them",
		function()
			local captured =
				"# c\n\n## Ask (verbatim)\nfix alpha\n\n## Interview\nQ1 which?\n\n## Idea\nalpha is a table\n"
			local base = captured .. "\n## Idea\n"
			base =
				"# c\n\n## Ask (verbatim)\nfix alpha\n\n## Interview\nQ1 which?\nQ2 asked later\n\n## Idea\nalpha is a table, updated after capture\n\n## Confirmation\nConfirmed (Ada, 2026-11-13): looks good\n\n## Problem\nrestated\n"
			local ask = finalview.ask(captured, base)
			t.expect(has(ask, "fix alpha")).toBe(true)
			t.expect(has(ask, "Q2 asked later")).toBe(true)
			t.expect(has(ask, "updated after capture")).toBe(true)
			t.expect(has(ask, "Confirmed (Ada, 2026-11-13)")).toBe(true)
			t.expect(has(ask, "restated")).toBe(false)
		end
	)

	it("AC1: the design is the Design and Acceptance criteria sections, none of the trail", function()
		local d = finalview.design(CURRENT)
		t.expect(has(d, "alpha returns a table")).toBe(true)
		t.expect(has(d, "AC1: alpha exists")).toBe(true)
		t.expect(has(d, "design-review-002")).toBe(false)
		t.expect(has(d, "refuted")).toBe(false)
		t.expect(has(d, "round 3 answered")).toBe(false)
		t.expect(has(d, "THE-UNKNOWN-NOTE")).toBe(false)
		-- a line of the Design that cites a review or a round is dropped
		t.expect(has(d, "STATUS: prepared after design-review-003")).toBe(false)
	end)

	it(
		"AC1: what the layer changed in the design is shown apart, as claims, and never in design.md",
		function()
			local tip = (
				string.gsub(
					CURRENT,
					"alpha returns a table%.",
					'alpha returns a list.\nDecided with the user (2026-11-20): "added on the layer".'
				)
			)
			tip ..= "\n## Verification log\nthe worker's note\n"
			local files = finalview.assemble(input({ tip = tip }))
			local changes = files["design-changes.patch"] :: string
			t.expect(has(changes, "+ alpha returns a list.")).toBe(true)
			t.expect(has(changes, "- alpha returns a table.")).toBe(true)
			t.expect(has(changes, "added on the layer")).toBe(true)
			t.expect(has(changes, "claims to check")).toBe(true)
			t.expect(has(changes, "the worker's note")).toBe(false)
			t.expect(has(files["design.md"] :: string, "alpha returns a list")).toBe(false)
			t.expect(has(files["ask.md"] :: string, "added on the layer")).toBe(false)
			t.expect(files["design-changes.patch"] ~= nil).toBe(true)
			t.expect(finalview.assemble(input())["design-changes.patch"]).toBe(nil)
		end
	)

	it("AC1: this ticket's and its raft's bookkeeping is not in the diff; deliverables are", function()
		for _, bad in
			{
				"z-nile/.tracker/issues/active/c0010/design-review-001.md",
				"z-nile/.tracker/issues/c0010/harvest.md",
				"pickman/.tracker/rafts/active/R0010/R0010.md",
				"z-nile/.tracker/issues/active/c0010/spend.d/x.tsv",
				"z-nile/.tracker/issues/c0099/spend.d/x.tsv",
				".cache/final/c0010/diff.patch",
			}
		do
			t.expect(finalview.keepPath(bad, "c0010", "R0010")).toBe(false)
		end
		for _, good in
			{
				"z-nile/engine/finalview.luau",
				"pickman/.tracker/architecture.md",
				"pickman/.tracker/game-design.md",
				"z-nile/skills/zz-review/SKILL.md",
				"z-nile/.tracker/issues/c0099/c0099.md",
				"z-nile/.tracker/rafts/R0020/R0020.md",
				"z-nile/next",
			}
		do
			t.expect(finalview.keepPath(good, "c0010", "R0010")).toBe(true)
		end
	end)

	it("AC1: the view holds only the fixed files", function()
		local files = finalview.assemble(input())
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

	it(
		"AC2: the view's id follows the design, the contract and the patch id, not the README or the diff text",
		function()
			local a = finalview.assemble(input())
			t.expect(finalview.viewId(a, "p1")).toBe(finalview.viewId(finalview.assemble(input()), "p1"))
			t.expect(has(a["README.md"] :: string, finalview.viewId(a, "p1"))).toBe(true)
			-- the same patch with other index lines and offsets (a restack, main moving) is the same view
			local restacked =
				finalview.assemble(input({ diff = "diff --git a/x b/x\nindex 111..222\n@@ -9 +9 @@\n" }))
			t.expect(finalview.viewId(restacked, "p1")).toBe(finalview.viewId(a, "p1"))
			-- another patch, design or contract is another view
			t.expect(finalview.viewId(a, "p2") ~= finalview.viewId(a, "p1")).toBe(true)
			local redesigned = finalview.assemble(
				input({ base = (string.gsub(CURRENT, "alpha returns a table%.", "alpha returns a list.")) })
			)
			t.expect(finalview.viewId(redesigned, "p1") ~= finalview.viewId(a, "p1")).toBe(true)
			local newcheck = finalview.assemble(input({ contract = { ["check.sh"] = "other check" } }))
			t.expect(finalview.viewId(newcheck, "p1") ~= finalview.viewId(a, "p1")).toBe(true)
		end
	)

	it("AC3: the README sets the one question: does the diff deliver the original ask", function()
		local readme = finalview.readme("c0010", "abc123")
		t.expect(has(readme, "does the diff deliver the original ask")).toBe(true)
		t.expect(has(readme, "Gap: <design or implementation>")).toBe(true)
		t.expect(has(readme, "Verdict: <on-course or off-course>")).toBe(true)
		t.expect(has(readme, "View: abc123")).toBe(true)
		t.expect(has(readme, "reviews, refutes, harvests, pull request comments or worker notes")).toBe(true)
		t.expect(has(readme, "design-changes.patch")).toBe(true)
	end)
end)
