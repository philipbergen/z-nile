--!strict
-- c0261 AC8: spend records the tier with the model: an eleventh `tier` column appears only when some row records one,
-- as the model column did (c0117); older ledgers parse, and render, as they did. Pure: engine/ledger.
local ledger = require("@znile/engine/ledger")
local t = require("@tests/lib/t")

local l = ledger :: any -- the API this issue adds, reached through `any` until the code exists (promote-check)

local function row(model: string?, tier: string?): ledger.Row
	return {
		when = "2026-11-07 10:00",
		subject = "s",
		added = 1,
		removed = 0,
		minutes = 1,
		how = "x",
		phase = "design-review",
		tokens = 5,
		model = model,
		tier = tier,
	} :: any
end

return t.spec("c0261 spend tier", function(it)
	it("a row with a tier round-trips with the model, under an eleven-column header (AC8)", function()
		local text = ledger.render("c1", "T", { row("claude-opus-5-5", "sharp") })
		t.expect(string.find(text, "| tokens | model | tier |", 1, true) ~= nil).toBe(true)
		local back = ledger.parse(text) :: ledger.Ledger
		t.expect(back.rows[1].model).toBe("claude-opus-5-5")
		t.expect((back.rows[1] :: any).tier).toBe("sharp")
	end)

	it("a ledger with no tier keeps the ten-column header, and a model-less one the nine (AC8)", function()
		local ten = ledger.render("c1", "T", { row("claude-opus-5-5", nil) })
		t.expect(string.find(ten, "| tier |", 1, true) == nil).toBe(true)
		t.expect(string.find(ten, "| model |", 1, true) ~= nil).toBe(true)
		local nine = ledger.render("c1", "T", { row(nil, nil) })
		t.expect(string.find(nine, "| model |", 1, true) == nil).toBe(true)
		local old = ledger.parse(ten) :: ledger.Ledger
		t.expect((old.rows[1] :: any).tier).toBe(nil)
	end)

	it("old rows stay as they are when a tiered row is appended after them (AC8)", function()
		local ten = ledger.render("c1", "T", { row("claude-opus-5-5", nil) })
		local more = l.append(ten, "c1", "T", row("claude-haiku-5-5", "wait")) :: string
		local back = ledger.parse(more) :: ledger.Ledger
		t.expect(#back.rows).toBe(2)
		t.expect((back.rows[1] :: any).tier).toBe(nil)
		t.expect((back.rows[2] :: any).tier).toBe("wait")
		t.expect(ledger.render("c1", "T", back.rows)).toBe(more)
	end)

	it("a tier is one of cheap, sharp, wait; a row cannot record a tier without a model (AC8)", function()
		t.expect(l.isTier("sharp")).toBe(true)
		t.expect(l.isTier("fast")).toBe(false)
		local ok = pcall(function()
			ledger.render("c1", "T", { row(nil, "sharp") })
		end)
		t.expect(ok).toBe(false)
		local bad = pcall(function()
			l.append(nil, "c1", "T", row("claude-opus-5-5", "fast"))
		end)
		t.expect(bad).toBe(false)
	end)
end)
