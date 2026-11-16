--!strict
-- c0251 AC6 (the pure half): `reviewmodel.stamp` writes `Fallback: <reason>` in the same call as `Model:`, `reviewmodel.fallbackOf`
-- reads it within 12 lines beside c0248's `Commit:` and `Patch:`, and the reason exists only for a tier 3 pick, names the exact
-- model, and says `assumed` when the author's provenance is not recorded. (The dispatcher's stamping is dispatch-pool.spec's.)
local models = require("@znile/engine/models")
local reviewmodel = require("@znile/engine/reviewmodel")
local t = require("@tests/lib/t")

local RM: any = reviewmodel
local pool: any = require("@znile/engine/reviewpool")

local FAMILIES = { opus = { "claude-opus-" }, fable = { "claude-fable-" }, kimi = { "kimi-" } }

local function spec(cli: string, model: string): models.Spec
	return { cli = cli, model = model, effort = "high", rank = 4, runtime = `{cli}-rt`, maxTokens = 1000 }
end

local function has(text: string, needle: string): boolean
	return string.find(text, needle, 1, true) ~= nil
end

local BODY = "# Review\n\nVerdict: approve\n"

return t.spec("c0251 the Fallback: stamp and its reason", function(it)
	it("AC6: stamp prepends Fallback: after Model: and Effort:, in the same call", function()
		local stamped, why =
			RM.stamp(BODY, "claude-opus-5-5", "xhigh", "the model that wrote the text ran the review")
		t.expect(why).toBe(nil)
		t.expect(stamped).toBe(
			"Model: claude-opus-5-5\nEffort: xhigh\nFallback: the model that wrote the text ran the review\n"
				.. BODY
		)
		-- no effort: the Fallback: line follows Model: directly
		local bare = RM.stamp(BODY, "claude-fable-5-2", nil, "same line")
		t.expect(bare).toBe("Model: claude-fable-5-2\nFallback: same line\n" .. BODY)
		-- no fallback: nothing is added, as before
		t.expect(RM.stamp(BODY, "claude-opus-5-5", "xhigh"))
			.toBe("Model: claude-opus-5-5\nEffort: xhigh\n" .. BODY)
		t.expect(RM.stamp(BODY, "claude-opus-5-5", "xhigh", nil))
			.toBe("Model: claude-opus-5-5\nEffort: xhigh\n" .. BODY)
	end)

	it(
		"AC6: a stamped review reads back its model, effort and fallback, and a file that records a model is never stamped again",
		function()
			local stamped = RM.stamp(BODY, "claude-opus-5-5", "xhigh", "why not") :: string
			local model, effort = reviewmodel.read(stamped)
			t.expect(model).toBe("claude-opus-5-5")
			t.expect(effort).toBe("xhigh")
			t.expect(RM.fallbackOf(stamped)).toBe("why not")
			local again, refusal = RM.stamp(stamped, "claude-fable-5-2", nil, "other")
			t.expect(again).toBe(nil)
			t.expect(has(refusal :: string, "already records claude-opus-5-5")).toBe(true)
			-- an unflagged review reads no fallback
			t.expect(RM.fallbackOf(RM.stamp(BODY, "claude-fable-5-2", "high") :: string)).toBe(nil)
		end
	)

	it("AC6: a reason that is not one short line is refused", function()
		for _, bad in { "two\nlines", string.rep("x", 121), "" } do
			local out, refusal = RM.stamp(BODY, "claude-opus-5-5", "high", bad)
			t.expect(out).toBe(nil)
			t.expect(has(refusal :: string, "120")).toBe(true)
		end
		t.expect(RM.stamp(BODY, "claude-opus-5-5", "high", string.rep("x", 120)) ~= nil).toBe(true)
	end)

	it("AC6: fallbackOf reads the line within 12 lines, beside Commit: and Patch:", function()
		local head =
			"Model: claude-opus-5-5\nEffort: xhigh\nFallback: exact model\nCommit: 0123456789ab\nPatch: abcdef012345\n# Review\n"
		t.expect(RM.fallbackOf(head)).toBe("exact model")
		local m, e = reviewmodel.read(head)
		t.expect(m).toBe("claude-opus-5-5")
		t.expect(e).toBe("xhigh")
		-- the twelfth line counts, the thirteenth does not
		local pad = string.rep("x\n", 11)
		t.expect(RM.fallbackOf(pad .. "Fallback: twelfth\n")).toBe("twelfth")
		t.expect(RM.fallbackOf(pad .. "y\nFallback: thirteenth\n")).toBe(nil)
		-- none, and an empty reason, read as none
		t.expect(RM.fallbackOf("Model: claude-opus-5-5\n# Review\n")).toBe(nil)
		t.expect(RM.fallbackOf("Model: claude-opus-5-5\nFallback:\n# Review\n")).toBe(nil)
		t.expect(RM.fallbackOf("")).toBe(nil)
	end)

	it("AC6: only a tier 3 pick has a reason, and it names the exact model", function()
		local tries = {
			spec("claude", "claude-fable-5-2"),
			spec("kimi", "kimi-code-k3.1-pro"),
			spec("claude", "claude-opus-5-5"),
		}
		-- the previous round was Fable: Fable is tier 2, kimi tier 1, Opus the author's own, tier 3 and exact
		local picks = pool.order(tries, FAMILIES, { "claude-opus-5-5" }, { "claude-fable-5-2" })
		t.expect(picks[1].tier).toBe(1)
		t.expect(picks[2].tier).toBe(2)
		t.expect(picks[3].tier).toBe(3)
		t.expect(pool.fallbackReason(picks[1], "recorded", "row")).toBe(nil)
		t.expect(pool.fallbackReason(picks[2], "recorded", "row")).toBe(nil)
		local reason = pool.fallbackReason(picks[3], "recorded", "row") :: string
		t.expect(has(reason, "claude-opus-5-5")).toBe(true)
		t.expect(has(reason, "assumed")).toBe(false)
		t.expect(#reason <= 120).toBe(true)
		t.expect(string.find(reason, "\n", 1, true)).toBe(nil)
	end)

	it("AC6: a same-line model that is not the exact one names the line", function()
		local picks = pool.order({ spec("claude", "claude-opus-5-6") }, FAMILIES, { "claude-opus-5-5" }, {})
		t.expect(picks[1].tier).toBe(3)
		t.expect(picks[1].exact).toBe(false)
		local reason = pool.fallbackReason(picks[1], "recorded", "row") :: string
		t.expect(has(reason, "opus")).toBe(true)
		t.expect(has(reason, "claude-opus-5-6")).toBe(true)
	end)

	it(
		"AC6: the reason says assumed or unknown when the author is not recorded, and stays one short line",
		function()
			local picks = pool.order(
				{ spec("claude", "claude-opus-5-5") },
				FAMILIES,
				{ "claude-opus-5-5" },
				{}
			)
			local assumed = pool.fallbackReason(picks[1], "assumed", "role") :: string
			t.expect(has(assumed, "assumed")).toBe(true)
			t.expect(has(assumed, "role")).toBe(true)
			t.expect(has(pool.fallbackReason(picks[1], "unknown", "none") :: string, "unknown")).toBe(true)
			t.expect(has(pool.fallbackReason(picks[1], "recorded", "row") :: string, "assumed")).toBe(false)
			-- a very long via cannot push the reason past the limit
			t.expect(#(pool.fallbackReason(picks[1], "assumed", string.rep("v", 400)) :: string) <= 120)
				.toBe(true)
		end
	)
end)
