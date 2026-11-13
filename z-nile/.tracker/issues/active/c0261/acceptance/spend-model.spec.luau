--!strict
-- c0261: `./zn spend --model <id>` records the typed model: it wins over the model the transcripts of the span measured
-- (spend.chooseModel, pure), which fills in only when nothing was typed.
local spend = require("@znile/engine/spend")
local t = require("@tests/lib/t")

local s = spend :: any -- the API this issue adds, reached through `any` until the code exists (promote-check)

return t.spec("c0261 a typed --model wins over the measured session model", function(it)
	it("the typed model wins over the measured one", function()
		t.expect(s.chooseModel("claude-opus-5-5", "claude-sonnet-5-5-high")).toBe("claude-opus-5-5")
		t.expect(s.chooseModel("claude-opus-5-5", nil)).toBe("claude-opus-5-5")
	end)

	it("the measured model fills in only when none was typed", function()
		t.expect(s.chooseModel(nil, "claude-sonnet-5-5-high")).toBe("claude-sonnet-5-5-high")
		t.expect(s.chooseModel(nil, nil)).toBe(nil)
	end)
end)
