--!strict
-- c0261 ("Commands refuse", the user, 2026-11-08): `./zn status <id> prepared` and `./zn done` refuse unless the last
-- design / code review round was recorded on a final-review model, judged by KIND of model (any Opus, any kimi-k3, any
-- grok model at xhigh), never by exact id. Pure: engine/finalround over file names, spend rows and times.
local finalround = require("@znile/engine/finalround")
local ledger = require("@znile/engine/ledger")
local models = require("@znile/engine/models")
local t = require("@tests/lib/t")

local fr = finalround :: any -- the API this issue adds, reached through `any` until the code exists (promote-check)
local m = models :: any

local function has(text: string, needle: string): boolean
	return string.find(text, needle, 1, true) ~= nil
end
local function row(subject: string, model: string?, phase: string?): ledger.Row
	return {
		when = "2026-11-08 10:00", subject = subject, added = 0, removed = 0, minutes = 1, how = "x",
		phase = phase or "design-review", tokens = 5, model = model,
	}
end
local DESIGN = { "c0010.md", "design-review-001.md", "design-review-002.md", "design-refute-001.md", "harvest.md", "stream-review-c0010-009.md" }
local function refusal(files: { string }, rows: { ledger.Row }, kind: string?): string?
	return fr.check(kind or "design", files, rows, true)
end

return t.spec("c0261 the last round ran a final-review model", function(it)
	it("the last round is the highest numbered file of its kind, and nothing else counts as one (AC11)", function()
		local n, stem = fr.lastRound(DESIGN, "design")
		t.expect(n).toBe(2)
		t.expect(stem).toBe("design-review-002")
		local c, cs = fr.lastRound({ "review-001.md", "review-003.md", "design-review-007.md", "stream-review-c1-010.md" }, "code")
		t.expect(c).toBe(3)
		t.expect(cs).toBe("review-003")
		t.expect(fr.lastRound({ "c0010.md" }, "design")).toBe(nil)
	end)

	it("the kinds of final-review model are defined once, per CLI family, and matched by shape (AC11)", function()
		for _, id in { "claude-opus-5-5", "claude-opus-5-5-high", "claude-opus-6-0", "claude-opus-9-9-max", "kimi-k3-high", "kimi-k3-max", "grok-4.7-xhigh", "grok-5-xhigh", "grok-4.9-xhigh" } do
			t.expect(`{id}={m.isFinalModel(id)}`).toBe(`{id}=true`) -- a new Opus id, kimi-k3 or grok at xhigh still passes
		end
		for _, id in { "claude-sonnet-5-5-high", "claude-haiku-5-5", "grok-4.7-high", "grok-4.7-low", "grok-4.6-high", "kimi-k2.7-code", "composer-2.5", "cursor-grok-4.6-high", "gpt-5.5-high", "opus" } do
			t.expect(`{id}={m.isFinalModel(id)}`).toBe(`{id}=false`)
		end
	end)

	it("a last round recorded on a model of a final-review kind passes, whichever id (AC11)", function()
		for _, id in { "claude-opus-5-5", "claude-opus-6-1-high", "kimi-k3-high", "grok-4.7-xhigh" } do
			t.expect(refusal(DESIGN, { row("design-review-002", id) })).toBe(nil)
		end
	end)

	it("a last round on a Sonnet, a non-xhigh grok, no model or no row is refused, naming the round and the kinds (AC11)", function()
		for _, id in { "claude-sonnet-5-5-high", "grok-4.7-high" } do
			local r = refusal(DESIGN, { row("design-review-002", id) }) :: string
			t.expect(has(r, "design-review-002")).toBe(true)
			t.expect(has(r, `model {id}`)).toBe(true)
			t.expect(has(r, "any Opus, any kimi-k3, any grok model at xhigh")).toBe(true)
			t.expect(has(r, "--final")).toBe(true)
		end
		t.expect(has(refusal(DESIGN, { row("design-review-002", nil) }) :: string, "no model")).toBe(true)
		t.expect(has(refusal(DESIGN, {}) :: string, "no row")).toBe(true)
	end)

	it("only the last round is judged: an earlier cheap round does not matter, a missing last row does (AC11)", function()
		t.expect(refusal(DESIGN, { row("design-review-001", "claude-sonnet-5-5-high"), row("design-review-002", "claude-opus-5-5") })).toBe(nil)
		t.expect(refusal(DESIGN, { row("design-review-001", "claude-opus-5-5") }) ~= nil).toBe(true)
	end)

	it("a round's row is matched exactly: its phase and its written subject, not a longer name that contains it (AC11)", function()
		local files = { "R0010.md", "review-001.md", "review-002.md" }
		local cheapCode = row("R0010: review-002", "claude-sonnet-5-5-high", "code-review")
		-- a member's design-review row, a stream review and a later fixes commit with the same number are not the round
		t.expect(refusal(files, { cheapCode, row("design-review-002", "claude-opus-5-5") }, "code") ~= nil).toBe(true)
		t.expect(refusal(files, { cheapCode, row("c0011: stream-review-002", "claude-opus-5-5", "code-review") }, "code") ~= nil).toBe(true)
		t.expect(refusal(files, { row("R0010: review-002", "claude-opus-5-5", "code-review"), row("R0010: review-002 fixes, refute-002", "claude-sonnet-5-5-high", "code-review") }, "code")).toBe(nil)
		-- a retry: any exact row on a final model is enough
		t.expect(refusal(files, { cheapCode, row("R0010: review-002", "kimi-k3-high", "code-review") }, "code")).toBe(nil)
		-- a code round's row has the code-review phase
		t.expect(refusal(files, { row("R0010: review-002", "claude-opus-5-5", "design-review") }, "code") ~= nil).toBe(true)
	end)

	it("the refusal names the line that records the model of its own kind of round (AC11)", function()
		t.expect(has(refusal(DESIGN, {}) :: string, "./zn spend <id> --phase design-review")).toBe(true)
		t.expect(has(refusal({ "review-001.md" }, {}, "code") :: string, "./zn commit -m \"<R-id>: review-001\" --phase code-review")).toBe(true)
	end)

	it("a spend.md that does not parse is a refusal of its own, never no rows (AC11)", function()
		local rows, why = fr.rowsOf({ "# Spend: c1 T\n\n| 1 | not a date | x |\n" })
		t.expect(rows).toBe(nil)
		t.expect(has(why :: string, "does not parse")).toBe(true)
		local ok = fr.rowsOf({ ledger.render("c1", "T", { row("design-review-001", "claude-opus-5-5") }) })
		t.expect(#(ok :: any)).toBe(1)
	end)

	it("an item whose first round predates the rule's landing is never locked out; one after it, or an uncommitted one, is held (AC11)", function()
		t.expect(fr.enforced(100, 200)).toBe(false)
		t.expect(fr.enforced(200, 200)).toBe(true)
		t.expect(fr.enforced(300, 200)).toBe(true)
		t.expect(fr.enforced(nil, 200)).toBe(true)
		t.expect(fr.enforced(300, nil)).toBe(false)
		t.expect(fr.check("design", DESIGN, {}, false)).toBe(nil)
	end)
end)
