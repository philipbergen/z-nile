--!strict
-- c0251 AC3: `reviewpool.order` is a stable partition of a role's tries into tier 1 (differs from the author and the previous
-- round), tier 2 (differs from the author), tier 3 (the author's family, its exact model last); it never drops a try, and an
-- unknown family is never "different". Pure: fixed ids and a fixed family table.
local models = require("@znile/engine/models")
local t = require("@tests/lib/t")

local pool: any = require("@znile/engine/reviewpool")

local FAMILIES = {
	opus = { "claude-opus-" },
	fable = { "claude-fable-" },
	sonnet = { "claude-sonnet-" },
	kimi = { "kimi-" },
	grok = { "grok-" },
}

local function spec(cli: string, model: string): models.Spec
	return { cli = cli, model = model, effort = "high", rank = 4, runtime = `{cli}-rt`, maxTokens = 1000 }
end

local OPUS = spec("claude", "claude-opus-5-5")
local FABLE = spec("claude", "claude-fable-5-2")
local KIMI = spec("kimi", "kimi-code-k3.1-pro")
local GROK = spec("grok", "grok-4.7")
local AGENT = spec("agent", "claude-opus-5-5") -- Opus through the Cursor CLI

-- the role's try order: primary, pool members, then the CLI fallbacks
local TRIES = { OPUS, FABLE, KIMI, GROK, AGENT }

local function names(picks: any): { string }
	local out = {}
	for _, p in picks do
		table.insert(out, `{p.spec.cli}:{p.spec.model}`)
	end
	return out
end
local ROLE_ORDER = {
	"claude:claude-opus-5-5",
	"claude:claude-fable-5-2",
	"kimi:kimi-code-k3.1-pro",
	"grok:grok-4.7",
	"agent:claude-opus-5-5",
}
local function tiers(picks: any): { number }
	local out = {}
	for _, p in picks do
		table.insert(out, p.tier)
	end
	return out
end

return t.spec("c0251 the review pool picker", function(it)
	it(
		"AC3: an Opus author sends the review to the other lines first and keeps Opus last, the exact model after",
		function()
			local picks = pool.order(TRIES, FAMILIES, { "claude-opus-5-5" }, {})
			t.expect(names(picks)).toEqual({
				"claude:claude-fable-5-2",
				"kimi:kimi-code-k3.1-pro",
				"grok:grok-4.7",
				"claude:claude-opus-5-5",
				"agent:claude-opus-5-5",
			})
			t.expect(tiers(picks)).toEqual({ 1, 1, 1, 3, 3 })
			t.expect(picks[1].exact).toBe(false)
			t.expect(picks[4].exact).toBe(true)
			t.expect(picks[1].family).toBe("fable")
			t.expect(picks[4].family).toBe("opus")
		end
	)

	it("AC3: the author's exact model goes after the other models of its line", function()
		-- the author wrote on claude-opus-5-4: an Opus 5.5 try is the same line, the 5.4 try is the exact model
		local older = spec("agent", "claude-opus-5-4")
		local picks = pool.order({ older, OPUS, FABLE }, FAMILIES, { "claude-opus-5-4" }, {})
		t.expect(names(picks)).toEqual({
			"claude:claude-fable-5-2",
			"claude:claude-opus-5-5",
			"agent:claude-opus-5-4",
		})
		t.expect(tiers(picks)).toEqual({ 1, 3, 3 })
		t.expect(picks[2].exact).toBe(false)
		t.expect(picks[3].exact).toBe(true)
	end)

	it("AC3: the previous round's line goes to tier 2, after tier 1 and before the author's own", function()
		local picks = pool.order(TRIES, FAMILIES, { "claude-sonnet-5-5" }, { "claude-opus-5-5" })
		t.expect(names(picks)).toEqual({
			"claude:claude-fable-5-2",
			"kimi:kimi-code-k3.1-pro",
			"grok:grok-4.7",
			"claude:claude-opus-5-5",
			"agent:claude-opus-5-5",
		})
		t.expect(tiers(picks)).toEqual({ 1, 1, 1, 2, 2 })
		-- with no previous round the Sonnet author leaves every line at tier 1, in the role's order
		local first = pool.order(TRIES, FAMILIES, { "claude-sonnet-5-5" }, {})
		t.expect(names(first)).toEqual(ROLE_ORDER)
		t.expect(tiers(first)).toEqual({ 1, 1, 1, 1, 1 })
	end)

	it("AC3: tier 1 needs both a different line from the author and from the previous round", function()
		-- author Opus, previous reviewer Fable: Fable is tier 2 (differs from the author only), kimi and grok tier 1
		local picks = pool.order(TRIES, FAMILIES, { "claude-opus-5-5" }, { "claude-fable-5-2" })
		t.expect(names(picks)).toEqual({
			"kimi:kimi-code-k3.1-pro",
			"grok:grok-4.7",
			"claude:claude-fable-5-2",
			"claude:claude-opus-5-5",
			"agent:claude-opus-5-5",
		})
		t.expect(tiers(picks)).toEqual({ 1, 1, 2, 3, 3 })
		-- author Sonnet, previous reviewer Opus and Fable: only kimi and grok are tier 1
		local two = pool.order(
			TRIES,
			FAMILIES,
			{ "claude-sonnet-5-5" },
			{ "claude-opus-5-5", "claude-fable-5-2" }
		)
		t.expect(tiers(two)).toEqual({ 1, 1, 2, 2, 2 })
		t.expect(names(two)).toEqual({
			"kimi:kimi-code-k3.1-pro",
			"grok:grok-4.7",
			"claude:claude-opus-5-5",
			"claude:claude-fable-5-2",
			"agent:claude-opus-5-5",
		})
	end)

	it("AC3: the order inside a tier is the role's order, not the model ids' order", function()
		-- kimi is listed before grok; sorted by id grok would come first
		local picks = pool.order({ KIMI, GROK }, FAMILIES, { "claude-opus-5-5" }, {})
		t.expect(names(picks)).toEqual({ "kimi:kimi-code-k3.1-pro", "grok:grok-4.7" })
		local reversed = pool.order({ GROK, KIMI }, FAMILIES, { "claude-opus-5-5" }, {})
		t.expect(names(reversed)).toEqual({ "grok:grok-4.7", "kimi:kimi-code-k3.1-pro" })
	end)

	it("AC3: no try is ever dropped, so the list is empty only when the tries are", function()
		-- only the author's own model is left: it is tier 3, exact, and still there
		local only = pool.order({ OPUS }, FAMILIES, { "claude-opus-5-5" }, {})
		t.expect(#only).toBe(1)
		t.expect(only[1].tier).toBe(3)
		t.expect(only[1].exact).toBe(true)
		for _, authors in { {}, { "claude-opus-5-5" }, { "claude-fable-5-2" }, { "mystery-1" } } do
			for _, priors in { {}, { "claude-opus-5-5" }, { "kimi-code-k3.1-pro" } } do
				t.expect(#pool.order(TRIES, FAMILIES, authors, priors)).toBe(#TRIES)
			end
		end
		t.expect(#pool.order({}, FAMILIES, { "claude-opus-5-5" }, {})).toBe(0)
	end)

	it("AC3: a context marker on the author's id changes nothing", function()
		local plain = pool.order(TRIES, FAMILIES, { "claude-opus-5-5" }, {})
		local marked = pool.order(TRIES, FAMILIES, { "claude-opus-5-5[1m]" }, {})
		t.expect(names(marked)).toEqual(names(plain))
		t.expect(tiers(marked)).toEqual(tiers(plain))
		t.expect(marked[4].exact).toBe(true)
	end)

	it("AC3: an unknown family is never tier 1 against a known author", function()
		local mystery = spec("grok", "mystery-9")
		local picks = pool.order({ mystery, FABLE, OPUS }, FAMILIES, { "claude-opus-5-5" }, {})
		t.expect(names(picks))
			.toEqual({ "claude:claude-fable-5-2", "grok:mystery-9", "claude:claude-opus-5-5" })
		t.expect(tiers(picks)).toEqual({ 1, 2, 3 })
		t.expect(picks[2].family).toBe(nil)
	end)

	it("AC3: an unknown author gives every try tier 1 and no reason, and the order is the role's", function()
		for _, authors in { {}, { "mystery-1" } } do
			local picks = pool.order(TRIES, FAMILIES, authors, {})
			t.expect(names(picks)).toEqual(ROLE_ORDER)
			t.expect(tiers(picks)).toEqual({ 1, 1, 1, 1, 1 })
			for _, p in picks do
				t.expect(pool.fallbackReason(p, "unknown", "none")).toBe(nil)
			end
		end
		-- an unknown try with an unknown author is tier 1 too (nothing to differ from)
		local mystery = spec("grok", "mystery-9")
		t.expect(pool.order({ mystery }, FAMILIES, {}, {})[1].tier).toBe(1)
		-- but a previous round's line still moves a try to tier 2 when the author is unknown
		local prior = pool.order({ OPUS, KIMI }, FAMILIES, {}, { "claude-opus-5-5" })
		t.expect(names(prior)).toEqual({ "kimi:kimi-code-k3.1-pro", "claude:claude-opus-5-5" })
		t.expect(tiers(prior)).toEqual({ 1, 2 })
	end)
end)
