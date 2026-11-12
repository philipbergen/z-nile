--!strict
-- The roles table: an unknown model fails when the file is loaded, and a challenge drops the author's model.
local models = require("@znile/engine/models")
local t = require("@tests/lib/t")

local function parse(text: string): (boolean, string)
	local ok, err = pcall(models.parse, text, ".models.toml")
	return ok, tostring(err)
end

local ROLES = [[
[fallback.kimi]
model = "kimi-code-k3.1-pro"
runtime = "kimi-cli"
rank = 2
max_tokens = 300000

[fallback.grok]
model = "grok-4.7"
runtime = "grok-cli"
effort = "high"
rank = 2
max_tokens = 300000

[roles.idea]
model = "claude-fable-5-2"
cli = "claude"
runtime = "claude-cli"
rank = 2
max_tokens = 300000
fallbacks = ["kimi", "grok"]

[roles.idea-challenge]
model = "claude-opus-5-5"
cli = "claude"
runtime = "claude-cli"
rank = 4
max_tokens = 300000
author = "idea"
fallbacks = ["kimi", "grok"]
]]

return t.spec("roles: the model table fails at load, and a challenge skips its author", function(it)
	it("an unknown model fails when the file is loaded", function()
		local ok, err = parse([[
[roles.idea]
model = "not-a-model"
cli = "claude"
runtime = "claude-cli"
rank = 2
max_tokens = 300000
]])
		t.expect(ok).toBe(false)
		t.expect(
			string.find(
				err,
				".models.toml: roles.idea.model is not-a-model, not a model of cli claude",
				1,
				true
			) ~= nil
		).toBe(true)
	end)

	it("an unknown CLI fails when the file is loaded", function()
		local ok, err = parse([[
[roles.idea]
model = "claude-fable-5-2"
cli = "nope"
runtime = "claude-cli"
rank = 2
max_tokens = 300000
]])
		t.expect(ok).toBe(false)
		t.expect(string.find(err, "not a supported CLI", 1, true) ~= nil).toBe(true)
	end)

	it("tries are the role, then its fallbacks, and the author's model is dropped", function()
		local layer = models.parse(ROLES, ".models.toml")
		local idea = models.resolve({ layer }, "idea")
		local ids = {}
		for _, spec in models.tries(idea) do
			table.insert(ids, models.id(spec))
		end
		t.expect(ids).toEqual({ "claude-fable-5-2", "kimi-code-k3.1-pro", "grok-4.7-high" })
		local challenge = models.resolve({ layer }, "idea-challenge")
		challenge.authorModel = "kimi-code-k3.1-pro"
		local left = {}
		for _, spec in models.tries(challenge) do
			table.insert(left, models.id(spec))
		end
		t.expect(left).toEqual({ "claude-opus-5-5", "grok-4.7-high" })
	end)

	it("stops when the only model left is the author's", function()
		local layer = models.parse(
			[[
[roles.idea]
model = "claude-fable-5-2"
cli = "claude"
runtime = "claude-cli"
rank = 2
max_tokens = 300000
fallbacks = []

[roles.idea-challenge]
model = "claude-fable-5-2"
cli = "claude"
runtime = "claude-cli"
rank = 4
max_tokens = 300000
author = "idea"
fallbacks = []
]],
			".models.toml"
		)
		local challenge = models.resolve({ layer }, "idea-challenge")
		local ok, err = pcall(models.tries, challenge)
		t.expect(ok).toBe(false)
		t.expect(
			string.find(
				tostring(err),
				"idea-challenge: the only model left is the author's (claude-fable-5-2); a challenge is never run by the model that wrote the text",
				1,
				true
			) ~= nil
		).toBe(true)
	end)
end)
