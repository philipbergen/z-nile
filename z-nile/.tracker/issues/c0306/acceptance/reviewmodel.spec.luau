--!strict
-- c0306 AC1, AC2 and the isModel half of AC8: the review models (one fixed list in code) and the record of a review's
-- model and effort, two stamped lines in the review file. Pure: texts in, texts or a refusal out.
local ledger = require("@znile/engine/ledger")
local reviewmodel = require("@znile/engine/reviewmodel")
local t = require("@tests/lib/t")

local function has(s: string?, part: string): boolean
	return s ~= nil and string.find(s, part, 1, true) ~= nil
end

local REVIEW =
	"# Review 001: c0306 (design mode)\nInputs: the design\n\n### F1 [high] a finding\n\nVerdict: changes\n"

return t.spec("c0306 review models and the record", function(it)
	it("AC1: ok passes claude-opus-, claude-fable- and kimi-code-k3 ids at any effort", function()
		for _, id in
			{
				"claude-opus-4-1",
				"claude-opus-5-5",
				"claude-opus-5-5[1m]",
				"claude-fable-5-2",
				"kimi-code-k3",
				"kimi-code-k3.2",
			}
		do
			t.expect(reviewmodel.ok(id, nil)).toBe(true)
			t.expect(reviewmodel.ok(id, "low")).toBe(true)
			t.expect(reviewmodel.ok(id, "xhigh")).toBe(true)
		end
	end)

	it("AC1: ok passes a grok- id only at effort xhigh and refuses it with no effort", function()
		t.expect(reviewmodel.ok("grok-4.7", "xhigh")).toBe(true)
		t.expect(reviewmodel.ok("grok-4.7", "high")).toBe(false)
		t.expect(reviewmodel.ok("grok-4.7", "max")).toBe(false)
		t.expect(reviewmodel.ok("grok-4.7", "")).toBe(false)
		t.expect(reviewmodel.ok("grok-4.7", nil)).toBe(false)
		t.expect(reviewmodel.ok("grok-4.7", "XHIGH")).toBe(false)
	end)

	it(
		"AC1: ok refuses every other id, the aliases opus and claude-opus included, and judges the prefix plainly",
		function()
			for _, id in
				{
					"claude-sonnet-5-5",
					"claude-haiku-4-5",
					"opus",
					"claude-opus",
					"claude-fable",
					"fable-5-2",
					"kimi-k3",
					"kimi-code-k2",
					"gpt-5",
					"",
					"x-claude-opus-5-5",
					"claude.opus-5",
					"claude%-opus-5",
				}
			do
				t.expect(reviewmodel.ok(id, "xhigh")).toBe(false)
			end
		end
	)

	it("AC1: describe names the four kinds", function()
		local d = reviewmodel.describe()
		t.expect(has(d, "claude-opus-")).toBe(true)
		t.expect(has(d, "claude-fable-")).toBe(true)
		t.expect(has(d, "kimi-code-k3")).toBe(true)
		t.expect(has(d, "grok-")).toBe(true)
		t.expect(has(d, "xhigh")).toBe(true)
		t.expect(#reviewmodel.KINDS).toBe(4)
	end)

	it("AC2: stamp prepends Model: and Effort: to a review that records none", function()
		local out, why = reviewmodel.stamp(REVIEW, "claude-opus-5-5", "xhigh")
		t.expect(why).toBe(nil)
		t.expect(out).toBe("Model: claude-opus-5-5\nEffort: xhigh\n" .. REVIEW)
	end)

	it("AC2: stamp leaves out Effort: when none is given", function()
		local out = reviewmodel.stamp(REVIEW, "claude-fable-5-2", nil)
		t.expect(out).toBe("Model: claude-fable-5-2\n" .. REVIEW)
		local empty = reviewmodel.stamp(REVIEW, "claude-fable-5-2", "")
		t.expect(empty).toBe("Model: claude-fable-5-2\n" .. REVIEW)
	end)

	it(
		"AC2: stamp refuses a review that already records a model, whether the new value differs or not",
		function()
			local once = reviewmodel.stamp(REVIEW, "claude-opus-5-5", "high") :: string
			local agains: { { model: string, effort: string? } } = {
				{ model = "claude-opus-5-5", effort = "high" },
				{ model = "claude-sonnet-5-5", effort = "low" },
				{ model = "claude-opus-5-5", effort = nil },
			}
			for _, again in agains do
				local out, why = reviewmodel.stamp(once, again.model, again.effort)
				t.expect(out).toBe(nil)
				t.expect(has(why, "already records claude-opus-5-5")).toBe(true)
				t.expect(has(why, "recorded once")).toBe(true)
			end
			-- a Model: line with no id is a record too
			local out, why = reviewmodel.stamp("Model:\n" .. REVIEW, "claude-opus-5-5", nil)
			t.expect(out).toBe(nil)
			t.expect(why ~= nil).toBe(true)
		end
	)

	it("AC2: read finds both lines within the first 12 lines, beside c0248's Commit: and Patch:", function()
		local text = "Commit: abc1234\nPatch: p-77\nModel: grok-4.7\nEffort: xhigh\n# Review 001\n"
		local model, effort = reviewmodel.read(text)
		t.expect(model).toBe("grok-4.7")
		t.expect(effort).toBe("xhigh")
		-- the twelfth line counts, the thirteenth does not
		local lines: { string } = {}
		for i = 1, 11 do
			table.insert(lines, `filler {i}`)
		end
		table.insert(lines, "Model: claude-opus-5-5")
		local m12 = reviewmodel.read(table.concat(lines, "\n") .. "\n")
		t.expect(m12).toBe("claude-opus-5-5")
		table.insert(lines, 12, "filler 12")
		local m13 = reviewmodel.read(table.concat(lines, "\n") .. "\n")
		t.expect(m13).toBe(nil)
		-- a record in the body of a review, far below the head, is not a record
		local body = reviewmodel.read(REVIEW .. string.rep("text\n", 20) .. "Model: claude-opus-5-5\n")
		t.expect(body).toBe(nil)
	end)

	it(
		"AC2: read gives nil for a review with no record, and an empty string for a Model: line with no id",
		function()
			local none, noneEffort = reviewmodel.read(REVIEW)
			t.expect(none).toBe(nil)
			t.expect(noneEffort).toBe(nil)
			t.expect((reviewmodel.read("Model:\n" .. REVIEW))).toBe("")
			local m, e = reviewmodel.read("Model: claude-opus-5-5\n" .. REVIEW)
			t.expect(m).toBe("claude-opus-5-5")
			t.expect(e).toBe(nil)
		end
	)

	it("AC2: a stamped review reads back what was stamped", function()
		local m, e = reviewmodel.read(reviewmodel.stamp(REVIEW, "kimi-code-k3.2", "high") :: string)
		t.expect(m).toBe("kimi-code-k3.2")
		t.expect(e).toBe("high")
	end)

	it(
		"AC8: ledger.isModel accepts claude-opus-5-5[1m] and still refuses a space and a cell separator",
		function()
			t.expect(ledger.isModel("claude-opus-5-5[1m]")).toBe(true)
			t.expect(ledger.isModel("claude-opus-5-5")).toBe(true)
			t.expect(ledger.isModel("grok-4.7")).toBe(true)
			t.expect(ledger.isModel("a b")).toBe(false)
			t.expect(ledger.isModel("a|b")).toBe(false)
			t.expect(ledger.isModel("[1m]")).toBe(false)
			t.expect(ledger.isModel("")).toBe(false)
		end
	)
end)
