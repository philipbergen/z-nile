--!strict
-- c0251 AC15: `models.tries` keeps the author's model (its own role's, or the one `authorModel` names) and no longer stops when
-- it is the only one left: the picker orders the tries, it is not a filter. The role-then-fallbacks order and the stack stay.
-- (The edited tests/tooling/roles.spec pins the same two cases; this is the acceptance copy.)
local models = require("@znile/engine/models")
local t = require("@tests/lib/t")

local ROLES = [[
[fallback.kimi]
model = "kimi-code-k3.1-pro"
runtime = "kimi-cli"

[fallback.grok]
model = "grok-4.7"
runtime = "grok-cli"

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

local ONLY = [[
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
]]

local function ids(r: models.Resolved): { string }
	local out = {}
	for _, spec in models.tries(r) do
		table.insert(out, models.id(spec))
	end
	return out
end

return t.spec("c0251 models.tries keeps the author's model", function(it)
	it("AC15: tries are the role, then its fallbacks, and the author's model stays in the list", function()
		local layer = models.parse(ROLES, ".models.toml")
		t.expect(ids(models.resolve({ layer }, "idea")))
			.toEqual({ "claude-fable-5-2", "kimi-code-k3.1-pro", "grok-4.7" })
		local challenge = models.resolve({ layer }, "idea-challenge")
		challenge.authorModel = "kimi-code-k3.1-pro"
		t.expect(ids(challenge)).toEqual({ "claude-opus-5-5", "kimi-code-k3.1-pro", "grok-4.7" })
	end)

	it("AC15: the author's model is not dropped by its recorded id, with or without an effort", function()
		local layer = models.parse(ROLES, ".models.toml")
		local challenge = models.resolve({ layer }, "idea-challenge")
		for _, author in { "claude-opus-5-5", "claude-opus-5-5-xhigh", "grok-4.7", "grok-4.7-high" } do
			challenge.authorModel = author
			t.expect(#models.tries(challenge)).toBe(3)
		end
	end)

	it("AC15: it does not stop when the only model left is the author's", function()
		local layer = models.parse(ONLY, ".models.toml")
		local challenge = models.resolve({ layer }, "idea-challenge")
		challenge.authorModel = models.id(models.resolve({ layer }, "idea").specs.claude)
		local ok, tries = pcall(models.tries, challenge)
		t.expect(ok).toBe(true)
		t.expect(#(tries :: { models.Spec })).toBe(1)
		t.expect((tries :: { models.Spec })[1].model).toBe("claude-fable-5-2")
	end)

	it("AC15: a role with no CLI that has a spec still fails, naming the role", function()
		local layer = models.parse(ROLES, ".models.toml")
		local r = models.resolve({ layer }, "idea")
		r.pool = {}
		local ok, err = pcall(models.tries, r)
		t.expect(ok).toBe(false)
		t.expect(string.find(tostring(err), "idea: no CLI in the order", 1, true) ~= nil).toBe(true)
	end)
end)
