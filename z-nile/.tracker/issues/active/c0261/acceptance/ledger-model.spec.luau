--!strict
-- c0261: the cost per model shows: spend rows already carry the model that spent them; `ledger.byModel` sums tokens,
-- minutes and rows per model id (rows without one under "none"), which `./zn metrics` prints as its "by model" table.
-- Pure: engine/ledger.
local ledger = require("@znile/engine/ledger")
local t = require("@tests/lib/t")

local l = ledger :: any -- the API this issue adds, reached through `any` until the code exists (promote-check)

local function row(model: string?, tokens: number?, minutes: number, phase: string): ledger.Row
	return {
		when = "2026-11-07 10:00",
		subject = "s",
		added = 1,
		removed = 0,
		minutes = minutes,
		how = "x",
		phase = phase,
		tokens = tokens,
		model = model,
	}
end

return t.spec("c0261 cost per model", function(it)
	it(
		"sums tokens, minutes and rows per model, rows with no model under none, biggest spender first (AC6)",
		function()
			local rows = {
				row("claude-sonnet-5", 100, 1, "prep"),
				row("claude-opus-5-5", 50, 2, "design-review"),
				row("claude-sonnet-5", 20, 1.5, "build"),
				row(nil, nil, 3, "build"),
			}
			local out = l.byModel(rows)
			t.expect(#out).toBe(3)
			t.expect(out[1].model).toBe("claude-sonnet-5")
			t.expect(out[1].tokens).toBe(120)
			t.expect(out[1].records).toBe(2)
			t.expect(out[1].minutes).toBe(2.5)
			t.expect(out[2].model).toBe("claude-opus-5-5")
			t.expect(out[3].model).toBe("none")
			t.expect(out[3].tokens).toBe(0)
		end
	)

	it(
		"a row's phase and model tell the activity: a final review's model is not a middle round's (AC6)",
		function()
			local mid = row("claude-sonnet-5", 10, 1, "design-review")
			local fin = row("claude-opus-5-5", 10, 1, "design-review")
			local out = l.byModel({ mid, fin })
			t.expect(#out).toBe(2) -- two lines, so the cost of the final round shows apart from the rounds on the way
		end
	)

	it("the metrics table is printed by ./zn metrics under a 'by model' heading (AC6)", function()
		local text: string = l.renderByModel(l.byModel({ row("claude-opus-5-5", 50, 2, "design-review") }))
		t.expect(string.find(text, "by model", 1, true) ~= nil).toBe(true)
		t.expect(string.find(text, "claude-opus-5-5", 1, true) ~= nil).toBe(true)
		t.expect(string.find(text, "50", 1, true) ~= nil).toBe(true)
	end)
end)
