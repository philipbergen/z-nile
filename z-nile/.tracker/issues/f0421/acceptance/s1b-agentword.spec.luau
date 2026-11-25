--!strict
-- f0421 slice 3, step two (design-review-003; moved from S1b's step one by the coordinator's ruling, G28): the Agent tool's
-- word is printed only for the version it runs (`modelcmd.CURRENT`; E10 first). On today's claude table every version is
-- current, so step one changes no answer here. Sequestered with no check line until step two.
local modelcmd = require("@znile/engine/modelcmd")
local t = require("@tests/lib/t")

return t.spec("f0421 step two: the Agent tool's word", function(it)
	it("the word is printed only for the version it runs", function()
		t.expect(modelcmd.subagentWord("claude", "claude-opus-5-5")).toBe("opus")
		t.expect(modelcmd.subagentWord("claude", "claude-opus-4-8")).toBe("-")
		t.expect(modelcmd.subagentWord("claude", "claude-fable-5-1")).toBe("-")
	end)
end)
