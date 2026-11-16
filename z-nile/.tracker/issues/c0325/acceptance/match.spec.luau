--!strict
-- c0325: a record of the model that wrote a text is cut to its bare model by every model the toml names, the two
-- sides of a match are normalised with the same function, and models.tries is unchanged.
local authorship = require("@znile/engine/authorship")
local models = require("@znile/engine/models")
local t = require("@tests/lib/t")

-- the new exports are read through `any`: promote-check on main then fails on missing keys, not on a type error
local M: any = models
local A: any = authorship

local TOML = [[
[fallback.kimi]
model = "kimi-code-k3.1-pro"
runtime = "kimi-cli"

[fallback.grok]
model = "grok-4.7"
runtime = "grok-cli"

[roles.implementation]
model = "claude-sonnet-5-5"
cli = "claude"
runtime = "claude-cli"
rank = 3
max_tokens = 12000000
effort = "high"
fallbacks = ["kimi", "grok"]

[roles.code-review]
model = "claude-opus-5-5"
cli = "claude"
runtime = "claude-cli"
rank = 4
max_tokens = 300000
effort = "low"
author = "implementation"
fallbacks = ["kimi", "grok"]

[roles.same-model-review]
model = "claude-sonnet-5-5"
cli = "claude"
runtime = "claude-cli"
rank = 3
max_tokens = 12000000
effort = "low"
author = "implementation"
fallbacks = ["kimi", "grok"]

[roles.small-kimi]
model = "kimi-code-k3.1"
cli = "kimi"
runtime = "kimi-cli"
rank = 2
max_tokens = 300000
fallbacks = []

[roles.final-review]
model = "claude-fable-5-2"
cli = "claude"
runtime = "claude-cli"
rank = 4
max_tokens = 300000
fallbacks = []
]]

local layer = models.parse(TOML, ".models.toml")
local KNOWN: { string } = M.knownModels({ layer })

local function spec(model: string): any
	return { cli = "claude", model = model, rank = 1, runtime = "claude-cli", maxTokens = 1 }
end

-- an Authorship written by hand: the writers are what a reader would have found
local function wrote(...: string): any
	local writers = {}
	for _, m in { ... } do
		table.insert(writers, { model = m, step = "build" })
	end
	return { writers = writers, provenance = "recorded", via = "row" }
end

local function ids(specs: { any }): { string }
	local out = {}
	for _, s in specs do
		table.insert(out, models.id(s))
	end
	return out
end

return t.spec("c0325: a record is cut to its model, and the match normalises both sides", function(it)
	it(
		"AC1: a record is cut by the longest known model of any role or fallback, at any effort word",
		function()
			t.expect(KNOWN).toEqual({
				"claude-fable-5-2",
				"claude-opus-5-5",
				"claude-sonnet-5-5",
				"grok-4.7",
				"kimi-code-k3.1",
				"kimi-code-k3.1-pro",
			})
			t.expect(M.modelOf("claude-sonnet-5-5-high", KNOWN)).toBe("claude-sonnet-5-5")
			t.expect(M.modelOf("claude-sonnet-5-5", KNOWN)).toBe("claude-sonnet-5-5")
			t.expect(M.modelOf("grok-4.7-xhigh", KNOWN)).toBe("grok-4.7")
			-- the longest known model wins: kimi-code-k3.1-pro is not kimi-code-k3.1 at effort "pro"
			t.expect(M.modelOf("kimi-code-k3.1-pro-high", KNOWN)).toBe("kimi-code-k3.1-pro")
			t.expect(M.modelOf("kimi-code-k3.1-pro", KNOWN)).toBe("kimi-code-k3.1-pro")
			t.expect(M.modelOf("kimi-code-k3.1-high", KNOWN)).toBe("kimi-code-k3.1")
			t.expect(M.modelOf("kimi-code-k3.1", KNOWN)).toBe("kimi-code-k3.1")
			-- a marker, then an effort
			t.expect(M.modelOf("claude-opus-5-5[1m]-high", KNOWN)).toBe("claude-opus-5-5")
			t.expect(M.modelOf("claude-opus-5-5[1m]", KNOWN)).toBe("claude-opus-5-5")
		end
	)

	it(
		"AC1: a hyphenated effort word, an effort no role uses, a typed `<model>-<effort>` id and a record of a model at the author's effort that is no author try",
		function()
			t.expect(M.modelOf("claude-sonnet-5-5-extra-high", KNOWN)).toBe("claude-sonnet-5-5")
			t.expect(M.modelOf("claude-sonnet-5-5-ultra", KNOWN)).toBe("claude-sonnet-5-5")
			t.expect(M.modelOf("claude-opus-5-5-xhigh", KNOWN)).toBe("claude-opus-5-5")
			-- final-review's fable is no try of the implementation role, but the toml names it
			t.expect(M.modelOf("claude-fable-5-2-high", KNOWN)).toBe("claude-fable-5-2")
			-- a record no known model fits is a bare model itself, marker removed, and a bare hyphen is no effort word
			t.expect(M.modelOf("mystery-model-high", KNOWN)).toBe("mystery-model-high")
			t.expect(M.modelOf("mystery[1m]", KNOWN)).toBe("mystery")
			t.expect(M.modelOf("claude-sonnet-5-5-", KNOWN)).toBe("claude-sonnet-5-5-")
			t.expect(M.modelOf("claude-sonnet-5-50", KNOWN)).toBe("claude-sonnet-5-50")
		end
	)

	it(
		"AC2: identical bracketed strings match; `[1m]` against plain matches both ways; `[1m][2m]` keeps `[1m]`",
		function()
			t.expect(M.bareModel("claude-opus-5-5[1m]")).toBe("claude-opus-5-5")
			t.expect(M.bareModel("claude-opus-5-5")).toBe("claude-opus-5-5")
			t.expect(M.bareModel("claude-opus-5-5[1m][2m]")).toBe("claude-opus-5-5[1m]")
			t.expect(A.isAuthor(spec("claude-opus-5-5[1m]"), wrote("claude-opus-5-5[1m]"))).toBe(true)
			t.expect(A.isAuthor(spec("claude-opus-5-5[1m]"), wrote("claude-opus-5-5"))).toBe(true)
			t.expect(A.isAuthor(spec("claude-opus-5-5"), wrote("claude-opus-5-5[1m]"))).toBe(true)
			t.expect(A.isAuthor(spec("claude-opus-5-5[1m][2m]"), wrote("claude-opus-5-5[1m][2m]"))).toBe(true)
			t.expect(A.isAuthor(spec("claude-opus-5-5"), wrote("claude-opus-5-5[1m][2m]"))).toBe(false)
			t.expect(A.isAuthor(spec("claude-opus-5-5[1m][2m]"), wrote("claude-opus-5-5"))).toBe(false)
			t.expect(A.isAuthor(spec("claude-opus-5-5[1m]"), wrote("claude-opus-5-5[1m][2m]"))).toBe(false)
		end
	)

	it("AC2: a model that only starts with another model's name does not match", function()
		t.expect(A.isAuthor(spec("kimi-code-k3.1"), wrote("kimi-code-k3.1-pro"))).toBe(false)
		t.expect(A.isAuthor(spec("kimi-code-k3.1-pro"), wrote("kimi-code-k3.1"))).toBe(false)
		t.expect(A.isAuthor(spec("claude-sonnet-5"), wrote("claude-sonnet-5-5"))).toBe(false)
		t.expect(A.isAuthor(spec("claude-sonnet-5-5"), wrote("claude-sonnet-5"))).toBe(false)
		t.expect(A.isAuthor(spec("grok-4.7"), wrote("claude-sonnet-5-5", "kimi-code-k3.1-pro"))).toBe(false)
		t.expect(A.isAuthor(spec("grok-4.7"), wrote("claude-sonnet-5-5", "grok-4.7"))).toBe(true)
		t.expect(A.isAuthor(spec("grok-4.7"), wrote())).toBe(false)
	end)

	it(
		"AC8: `models.tries` returns the same tries for every input, including a fallback author (c0251: the author is never dropped)",
		function()
			local review = models.resolveRole({ layer }, "code-review")
			t.expect(review.authorModel).toBe("claude-sonnet-5-5-high")
			-- the author role's first choice, effort and all, is today's drop; a different model is not dropped
			t.expect(ids(models.tries(review)))
				.toEqual({ "claude-opus-5-5-low", "kimi-code-k3.1-pro-low", "grok-4.7-low" })
			-- the same model at another effort is kept
			local same = models.resolveRole({ layer }, "same-model-review")
			t.expect(ids(models.tries(same))).toEqual({
				"claude-sonnet-5-5-low",
				"kimi-code-k3.1-pro-low",
				"grok-4.7-low",
			})
			-- a fallback wrote the text: its try at another effort is still kept; an exact id is dropped as today
			local fb = models.resolveRole({ layer }, "code-review")
			fb.authorModel = "kimi-code-k3.1-pro-high"
			t.expect(ids(models.tries(fb)))
				.toEqual({ "claude-opus-5-5-low", "kimi-code-k3.1-pro-low", "grok-4.7-low" })
			fb.authorModel = "kimi-code-k3.1-pro-low"
			t.expect(ids(models.tries(fb)))
				.toEqual({ "claude-opus-5-5-low", "kimi-code-k3.1-pro-low", "grok-4.7-low" })
			-- the only model left is the author's: the error, word for word
			local solo = models.parse(
				[[
[roles.implementation]
model = "claude-sonnet-5-5"
cli = "claude"
runtime = "claude-cli"
rank = 3
max_tokens = 12000000
effort = "high"
fallbacks = []

[roles.code-review]
model = "claude-sonnet-5-5"
cli = "claude"
runtime = "claude-cli"
rank = 3
max_tokens = 12000000
effort = "high"
author = "implementation"
fallbacks = []
]],
				".models.toml"
			)
			-- c0251: the only model left is the author's: it still runs (the picker flags it), the chain never stops
			local ok, only = pcall(models.tries, models.resolveRole({ solo }, "code-review"))
			t.expect(ok).toBe(true)
			t.expect(ids(only :: { models.Spec })).toEqual({ "claude-sonnet-5-5-high" })
		end
	)
end)
