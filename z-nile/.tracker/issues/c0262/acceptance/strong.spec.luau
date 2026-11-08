--!strict
-- c0262 AC5: "full force": the final review names concrete models by the existing review rule (models.reviewRule: Opus
-- through claude and agent, a grok model at xhigh through grok), with no alias and no tier of its own. A checked proxy:
-- the final mode resolves through the zz-review table, whose rule still refuses any weaker model.
local dispatch = require("@znile/engine/dispatch")
local models = require("@znile/engine/models")
local t = require("@tests/lib/t")

local function spec(cli: string, model: string, effort: string?): models.Spec
	return { cli = cli, model = model, effort = effort, rank = 4, runtime = "x", maxTokens = 1 } :: any
end

return t.spec("c0262 AC5 the final review runs on the review model of the CLI", function(it)
	it("AC5: the final mode takes its model from the zz-review table, like every review mode", function()
		for _, mode in { "design", "raft", "code", "stream", "final" } do
			t.expect((dispatch :: any).modelSkillOf("zz-review", mode)).toBe("zz-review")
		end
	end)

	it("AC5: the review rule the final mode is bound to: Opus or a grok model at xhigh, nothing weaker", function()
		t.expect(models.reviewRule("zz-review", spec("claude", "claude-opus-5-5"))).toBe(nil)
		t.expect(models.reviewRule("zz-review", spec("agent", "claude-opus-5-5-high"))).toBe(nil)
		t.expect(models.reviewRule("zz-review", spec("grok", "grok-4.7", "xhigh"))).toBe(nil)
		t.expect(models.reviewRule("zz-review", spec("claude", "claude-sonnet-5")) ~= nil).toBe(true)
		t.expect(models.reviewRule("zz-review", spec("grok", "grok-4.7", "high")) ~= nil).toBe(true)
	end)
end)
