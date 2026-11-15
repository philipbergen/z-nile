--!strict
-- c0325: models.isAuthor says whether a challenger try runs the model that wrote the text (effort ignored),
-- models.modelOf reads a record, resolveRole keeps the author role, and models.tries is unchanged.
local models = require("@znile/engine/models")
local t = require("@tests/lib/t")

-- the new exports are read through `any`: promote-check on main then fails on missing keys, not on a type error
local M: any = models

-- the author role "implementation" has an effort; the challenger roles share its fallbacks
local function toml(effort: string): string
	local text = [[[fallback.kimi]
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
effort = "EFFORT"
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
]]
	return (string.gsub(text, "EFFORT", effort))
end

local function resolve(effort: string, role: string): any
	return models.resolveRole({ models.parse(toml(effort), ".models.toml") }, role)
end

-- a challenger try: a copy of the role's spec for `cli`, with the model and effort asked for
local function try(r: any, cli: string, model: string?, effort: string?): any
	local spec: any = table.clone(r.specs[cli])
	if model then
		spec.model = model
	end
	spec.effort = effort
	return spec
end

local function ids(specs: { any }): { string }
	local out = {}
	for _, s in specs do
		table.insert(out, models.id(s))
	end
	return out
end

return t.spec("c0325: the model that wrote the text is matched without its effort", function(it)
	local review = resolve("high", "code-review")

	it("AC1: a spend row of the author's primary try matches the same model at any effort", function()
		local rec = "claude-sonnet-5-5-high"
		t.expect(M.isAuthor(try(review, "claude", "claude-sonnet-5-5", "low"), review, rec)).toBe(true)
		t.expect(M.isAuthor(try(review, "claude", "claude-sonnet-5-5", "high"), review, rec)).toBe(true)
		t.expect(M.isAuthor(try(review, "claude", "claude-sonnet-5-5", nil), review, rec)).toBe(true)
		t.expect(M.isAuthor(try(review, "claude", "claude-opus-5-5", "high"), review, rec)).toBe(false)
		t.expect(M.isAuthor(try(review, "kimi", nil, "high"), review, rec)).toBe(false)
	end)

	it("AC1: a spend row of a fallback try matches that fallback's model at any effort", function()
		local rec = "kimi-code-k3.1-pro-high"
		t.expect(M.isAuthor(try(review, "kimi", nil, "high"), review, rec)).toBe(true)
		t.expect(M.isAuthor(try(review, "kimi", nil, "low"), review, rec)).toBe(true)
		t.expect(M.isAuthor(try(review, "kimi", nil, nil), review, rec)).toBe(true)
		t.expect(M.isAuthor(try(review, "grok", nil, "high"), review, rec)).toBe(false)
		t.expect(M.isAuthor(try(review, "claude", nil, "high"), review, rec)).toBe(false)
	end)

	it(
		"AC1: a spend row whose effort has a hyphen is cut by the author's tries, not at the last hyphen",
		function()
			local hy = resolve("extra-high", "code-review")
			local rec = "claude-sonnet-5-5-extra-high"
			t.expect(M.isAuthor(try(hy, "claude", "claude-sonnet-5-5", "low"), hy, rec)).toBe(true)
			t.expect(M.isAuthor(try(hy, "claude", "claude-sonnet-5-5-extra", "low"), hy, rec)).toBe(false)
		end
	)

	it("AC1: a bare typed id matches the same model at another effort", function()
		t.expect(M.isAuthor(try(review, "claude", "claude-sonnet-5-5", "xhigh"), review, "claude-sonnet-5-5"))
			.toBe(true)
		t.expect(M.isAuthor(try(review, "claude", "claude-sonnet-5-5", nil), review, "claude-sonnet-5-5"))
			.toBe(true)
		t.expect(M.isAuthor(try(review, "claude", "claude-opus-5-5", "high"), review, "claude-sonnet-5-5"))
			.toBe(false)
		-- a bare id of a fallback's model carries no effort, so it is no author try's id: it is the model itself
		t.expect(M.isAuthor(try(review, "kimi", nil, "high"), review, "kimi-code-k3.1-pro")).toBe(true)
		t.expect(M.isAuthor(try(review, "claude", "claude-opus-5-5", "low"), review, "claude-opus-5-5"))
			.toBe(true)
	end)

	it("AC1: a model whose id only starts with the author's model is not the author's", function()
		local rec = "kimi-code-k3.1-pro-high"
		t.expect(M.isAuthor(try(review, "kimi", "kimi-code-k3.1", "high"), review, rec)).toBe(false)
		t.expect(M.isAuthor(try(review, "kimi", "kimi-code-k3.1", nil), review, "kimi-code-k3.1-pro"))
			.toBe(false)
		t.expect(M.isAuthor(try(review, "kimi", "kimi-code-k3.1-pro", "high"), review, "kimi-code-k3.1"))
			.toBe(false)
		t.expect(M.isAuthor(try(review, "claude", "claude-sonnet-5", "high"), review, "claude-sonnet-5-5"))
			.toBe(false)
	end)

	it("AC2: with no record the first choice of the author role is compared, effort ignored", function()
		for _, none in { "nil", "empty" } do
			local rec: string? = if none == "nil" then nil else ""
			t.expect(M.isAuthor(try(review, "claude", "claude-sonnet-5-5", "low"), review, rec)).toBe(true)
			t.expect(M.isAuthor(try(review, "claude", "claude-sonnet-5-5", nil), review, rec)).toBe(true)
			t.expect(M.isAuthor(try(review, "claude", "claude-opus-5-5", "high"), review, rec)).toBe(false)
			-- a fallback is not the first choice, so with no record it is not matched
			t.expect(M.isAuthor(try(review, "kimi", nil, "high"), review, rec)).toBe(false)
		end
	end)

	it("AC2: a role with no author never matches, with a record or without", function()
		local impl = resolve("high", "implementation")
		t.expect(M.isAuthor(try(impl, "claude", nil, "high"), impl, "claude-sonnet-5-5-high")).toBe(false)
		t.expect(M.isAuthor(try(impl, "claude", nil, "high"), impl, "claude-sonnet-5-5")).toBe(false)
		t.expect(M.isAuthor(try(impl, "claude", nil, "high"), impl, nil)).toBe(false)
		t.expect(M.isAuthor(try(impl, "claude", nil, "high"), impl, "")).toBe(false)
		t.expect(M.isAuthor(try(impl, "kimi", nil, "high"), impl, "kimi-code-k3.1-pro")).toBe(false)
	end)

	it("AC2: Resolved.author is set exactly where authorModel is, which keeps its value", function()
		t.expect(review.authorModel).toBe("claude-sonnet-5-5-high")
		local author: any = review.author
		t.expect(author ~= nil).toBe(true)
		t.expect(author.skill).toBe("implementation")
		t.expect(author.order).toEqual({ "claude", "kimi", "grok" })
		t.expect(author.specs.kimi.model).toBe("kimi-code-k3.1-pro")
		t.expect(models.id(author.specs.claude)).toBe("claude-sonnet-5-5-high")
		local impl = resolve("high", "implementation")
		t.expect(impl.authorModel).toBe(nil)
		t.expect(impl.author).toBe(nil)
	end)

	it("AC3: a bare record loses one trailing context marker", function()
		t.expect(M.modelOf("claude-opus-5-5[1m]", nil)).toBe("claude-opus-5-5")
		t.expect(M.modelOf("claude-opus-5-5", nil)).toBe("claude-opus-5-5")
		t.expect(M.modelOf("claude-opus-5-5[1m][2m]", nil)).toBe("claude-opus-5-5[1m]")
		t.expect(M.modelOf("claude-opus-5-5[1m]", review.author)).toBe("claude-opus-5-5")
		t.expect(M.isAuthor(try(review, "claude", "claude-opus-5-5", "low"), review, "claude-opus-5-5[1m]"))
			.toBe(true)
	end)

	it("AC3: a record that is an author try's id is cut to that try's model and keeps its marker", function()
		local marked = resolve("high", "code-review")
		marked.author.specs.claude.model = "claude-opus-5-5[1m]"
		t.expect(M.modelOf("claude-opus-5-5[1m]-high", marked.author)).toBe("claude-opus-5-5[1m]")
		t.expect(M.modelOf("kimi-code-k3.1-pro-high", marked.author)).toBe("kimi-code-k3.1-pro")
		t.expect(M.modelOf("kimi-code-k3.1-pro-high", nil)).toBe("kimi-code-k3.1-pro-high")
		-- the marker is not removed from a recognised record, nor widened on the toml side
		t.expect(
			M.isAuthor(try(marked, "claude", "claude-opus-5-5", "low"), marked, "claude-opus-5-5[1m]-high")
		)
			.toBe(false)
		t.expect(
			M.isAuthor(
				try(marked, "claude", "claude-opus-5-5[1m]", "low"),
				marked,
				"claude-opus-5-5[1m]-high"
			)
		)
			.toBe(true)
		t.expect(
			M.isAuthor(try(marked, "claude", "claude-opus-5-5[1m]", "low"), marked, "claude-opus-5-5[1m]")
		)
			.toBe(false)
	end)

	it("AC4: tries keeps a fallback author, and keeps the same model at another effort", function()
		-- today's drop: the author role's first choice, effort and all
		t.expect(ids(models.tries(review)))
			.toEqual({ "claude-opus-5-5-low", "kimi-code-k3.1-pro-low", "grok-4.7-low" })
		local same = resolve("high", "same-model-review")
		t.expect(ids(models.tries(same))).toEqual({
			"claude-sonnet-5-5-low",
			"kimi-code-k3.1-pro-low",
			"grok-4.7-low",
		})
		-- a fallback wrote the text: its try at another effort is still kept
		local fb = resolve("high", "code-review")
		fb.authorModel = "kimi-code-k3.1-pro-high"
		t.expect(ids(models.tries(fb)))
			.toEqual({ "claude-opus-5-5-low", "kimi-code-k3.1-pro-low", "grok-4.7-low" })
		-- and an exact id is dropped as today
		fb.authorModel = "kimi-code-k3.1-pro-low"
		t.expect(ids(models.tries(fb))).toEqual({ "claude-opus-5-5-low", "grok-4.7-low" })
	end)

	it(
		"AC4: tries still stops when the only model left is the author's, and not at another effort",
		function()
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

[roles.low-review]
model = "claude-sonnet-5-5"
cli = "claude"
runtime = "claude-cli"
rank = 3
max_tokens = 12000000
effort = "low"
author = "implementation"
fallbacks = []
]],
				".models.toml"
			)
			local ok, err = pcall(models.tries, models.resolveRole({ solo }, "code-review"))
			t.expect(ok).toBe(false)
			t.expect(
				string.find(
					tostring(err),
					"code-review: the only model left is the author's (claude-sonnet-5-5-high); a challenge is never run by the model that wrote the text",
					1,
					true
				) ~= nil
			).toBe(true)
			t.expect(ids(models.tries(models.resolveRole({ solo }, "low-review"))))
				.toEqual({ "claude-sonnet-5-5-low" })
		end
	)
end)
