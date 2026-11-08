--!strict
-- c0261 ("Commands refuse", the user, 2026-11-08): `./zn status <id> prepared` and `./zn done` refuse unless the last
-- design / code review round was recorded on a final-review model. Pure: engine/finalround over file names, spend rows
-- and the resolved final-review models; items whose first round predates the rule's landing are not held to it.
local finalround = require("@znile/engine/finalround")
local ledger = require("@znile/engine/ledger")
local models = require("@znile/engine/models")
local t = require("@tests/lib/t")

local function has(text: string, needle: string): boolean
	return string.find(text, needle, 1, true) ~= nil
end
local function row(subject: string, model: string?): ledger.Row
	return {
		when = "2026-11-08 10:00", subject = subject, added = 0, removed = 0, minutes = 1, how = "x",
		phase = "design-review", tokens = 5, model = model,
	}
end
local FINAL = { "claude-opus-5-5", "grok-4.7-xhigh", "claude-opus-5-5-high", "kimi-k3-high" }
local DESIGN = { "c0010.md", "design-review-001.md", "design-review-002.md", "design-refute-001.md", "harvest.md", "stream-review-c0010-009.md" }

return t.spec("c0261 the last round ran a final-review model", function(it)
	it("the last round is the highest numbered file of its kind, and nothing else counts as one (AC11)", function()
		local n, stem = finalround.lastRound(DESIGN, "design")
		t.expect(n).toBe(2)
		t.expect(stem).toBe("design-review-002")
		local c, cs = finalround.lastRound({ "review-001.md", "review-003.md", "design-review-007.md", "stream-review-c1-010.md" }, "code")
		t.expect(c).toBe(3)
		t.expect(cs).toBe("review-003")
		t.expect(finalround.lastRound({ "c0010.md" }, "design")).toBe(nil)
	end)

	it("a last round recorded on a final-review model passes, whichever of the ordered list it used (AC11)", function()
		for _, id in FINAL do
			t.expect(finalround.check("design", DESIGN, { row("design-review-002", id) }, FINAL, true)).toBe(nil)
		end
	end)

	it("a last round on any other model, with no model, or with no row is refused, naming the round and the list (AC11)", function()
		local cheap = finalround.check("design", DESIGN, { row("design-review-002", "claude-sonnet-5-5-high") }, FINAL, true) :: string
		t.expect(has(cheap, "design-review-002")).toBe(true)
		t.expect(has(cheap, "model claude-sonnet-5-5-high")).toBe(true)
		t.expect(has(cheap, "claude-opus-5-5, grok-4.7-xhigh, claude-opus-5-5-high, kimi-k3-high")).toBe(true)
		t.expect(has(cheap, "--final")).toBe(true)
		t.expect(has(finalround.check("design", DESIGN, { row("design-review-002", nil) }, FINAL, true) :: string, "no model")).toBe(true)
		t.expect(has(finalround.check("design", DESIGN, {}, FINAL, true) :: string, "no row")).toBe(true)
	end)

	it("only the last round is judged: an earlier cheap round does not matter, a missing last row does (AC11)", function()
		local rows = { row("design-review-001", "claude-sonnet-5-5-high"), row("design-review-002", "claude-opus-5-5") }
		t.expect(finalround.check("design", DESIGN, rows, FINAL, true)).toBe(nil)
		local only1 = { row("design-review-001", "claude-opus-5-5") }
		t.expect(finalround.check("design", DESIGN, only1, FINAL, true) ~= nil).toBe(true)
	end)

	it("a code review is judged the same way on review-NNN.md and the row naming it (AC11)", function()
		local files = { "R0010.md", "review-001.md", "review-002.md", "refute-001.md" }
		t.expect(finalround.check("code", files, { row("R0010: review-002", "kimi-k3-high") }, FINAL, true)).toBe(nil)
		t.expect(has(finalround.check("code", files, { row("R0010: review-002", "claude-sonnet-5-5-high") }, FINAL, true) :: string, "review-002")).toBe(true)
	end)

	it("an item whose first round predates the rule's landing is never locked out; one after it, or an uncommitted one, is held (AC11)", function()
		t.expect(finalround.enforced(100, 200)).toBe(false) -- reviewed before the rule landed
		t.expect(finalround.enforced(200, 200)).toBe(true)
		t.expect(finalround.enforced(300, 200)).toBe(true)
		t.expect(finalround.enforced(nil, 200)).toBe(true) -- the first round is not committed yet
		t.expect(finalround.enforced(300, nil)).toBe(false) -- the rule has not landed on the base
		t.expect(finalround.check("design", DESIGN, {}, FINAL, false)).toBe(nil)
	end)

	it("the allowed models are the zz-review tries of every CLI, fallbacks included, as a spend row records them (AC11)", function()
		local text = 'order = ["claude", "agent"]\n[zz-review.claude]\nmodel = "claude-opus-5-5"\nrank = 4\nruntime = "claude-cli"\nmax_tokens = 9\n[zz-review.agent]\nmodel = "claude-opus-5-5-high"\nfallback = ["kimi-k3-high", "grok-4.7-xhigh"]\nrank = 4\nruntime = "cursor-cli"\nmax_tokens = 9\nmax_calls = 9\nmax_minutes = 9\n'
		local r = models.resolve({ models.parse(text, ".models.toml") }, "zz-review")
		t.expect(finalround.finalModels(r)).toEqual({ "claude-opus-5-5", "claude-opus-5-5-high", "kimi-k3-high", "grok-4.7-xhigh" })
	end)
end)
