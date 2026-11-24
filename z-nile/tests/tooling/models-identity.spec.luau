--!strict
-- f0421 slice 3, S1a (AC30): `models.identity` over every id the three CLIs that list their models print (the fixtures
-- agent-models.txt, agy-models.txt and grok-models.txt, 315 ids). It removes a trailing `-fast`, then one effort word; what is
-- left is the family. The ids it cannot split (a family that still holds `fast`, `thinking`, `extra` or an effort word) are
-- pinned, so a table entry naming one must state its family; `sameModel` compares families, so `-fast` is the same model.
local fs = require("@lune/fs")
local models = require("@znile/engine/models")
local t = require("@tests/lib/t")

local FIXTURES = "tests/fixtures/models"

-- every id a listing prints, in its own format: agent `id - Name`, agy `id<TAB>Name`, grok `  - id` or `  * id (default)`
local function ids(): { [string]: { string } }
	local out: { [string]: { string } } = { agent = {}, agy = {}, grok = {} }
	local formats: { [string]: string } =
		{ agent = "^(%S+) %- ", agy = "^(%S+)\t", grok = "^%s+[%-%*] (%S+)" }
	for cli, pattern in formats do
		for line in string.gmatch(fs.readFile(`{FIXTURES}/{cli}-models.txt`), "[^\n]+") do
			local id = string.match(line, pattern)
			if id then
				table.insert(out[cli], id)
			end
		end
	end
	return out
end

-- the families of the listed ids the rule leaves holding a marker word (P1 of design-review-001): 58 ids
local UNSPLIT = {
	"claude-4-sonnet-thinking",
	"claude-4.5-opus-high-thinking",
	"claude-4.5-sonnet-thinking",
	"claude-4.6-opus-high-thinking",
	"claude-4.6-opus-max-thinking",
	"claude-4.6-sonnet-medium-thinking",
	"claude-fable-5-1-thinking",
	"claude-fable-5-thinking",
	"claude-haiku-5-5-thinking",
	"claude-opus-4-7-thinking",
	"claude-opus-4-8-thinking",
	"claude-opus-5-thinking",
	"claude-sonnet-5-thinking",
	"gpt-5.5-extra",
}

return t.spec("f0421 slice 3, S1a: a model's identity over every listed id", function(it)
	it("the three listings hold 315 ids: agent 284, agy 27, grok 4", function()
		local all = ids()
		t.expect(#all.agent).toBe(284)
		t.expect(#all.agy).toBe(27)
		t.expect(#all.grok).toBe(4)
	end)

	it("identity removes -fast, then one effort word; what is left is the family", function()
		local function shown(id: string): string
			local i = models.identity(id)
			return `{i.family} {i.effort or "-"} {tostring(i.fast)}`
		end
		t.expect(shown("claude-opus-5-5-high")).toBe("claude-opus-5-5 high false")
		t.expect(shown("grok-4.7-high-fast")).toBe("grok-4.7 high true")
		t.expect(shown("grok-4.7")).toBe("grok-4.7 - false")
		t.expect(shown("gpt-5.6-sol-none")).toBe("gpt-5.6-sol none false")
		t.expect(shown("muse-wonder-1.0-minimal")).toBe("muse-wonder-1.0 minimal false")
		t.expect(shown("Kimi-Code-K3.1-Pro")).toBe("kimi-code-k3.1-pro - false")
		-- the known edges, pinned as they come out
		t.expect(shown("grok-4.7-build-fast")).toBe("grok-4.7-build - true") -- grok's default: no id grok lists
		t.expect(shown("auto")).toBe("auto - false") -- agent's default: no model to name
		t.expect(shown("gemini-pro-orchestrator")).toBe("gemini-pro-orchestrator - false") -- one of three, not their family
		t.expect(shown("gpt-5.5-extra-high")).toBe("gpt-5.5-extra high false")
		t.expect(shown("claude-4.6-opus-high-thinking")).toBe("claude-4.6-opus-high-thinking - false")
		t.expect(shown("claude-opus-5-thinking-high-fast")).toBe("claude-opus-5-thinking high true")
	end)

	it("the ids the rule cannot split are exactly the pinned families (58 ids), and nothing else", function()
		local families: { string } = {}
		local count = 0
		for _, list in ids() do
			for _, id in list do
				local family = models.identity(id).family
				if models.unsplit(family) ~= nil then
					count += 1
					if not table.find(families, family) then
						table.insert(families, family)
					end
				end
			end
		end
		table.sort(families)
		t.expect(families).toEqual(UNSPLIT)
		t.expect(count).toBe(58)
		t.expect(models.unsplit("claude-4.6-opus-high-thinking")).toBe("high")
		t.expect(models.unsplit("gpt-5.5-extra")).toBe("extra")
		t.expect(models.unsplit("claude-opus-5-thinking")).toBe("thinking")
		t.expect(models.unsplit("claude-opus-5-5")).toBe(nil)
		t.expect(models.unsplit("kimi-code-k3.1-pro")).toBe(nil)
	end)

	it("sameModel compares families: -fast and every effort word are the same model", function()
		t.expect(models.sameModel("grok-4.7-high-fast", "grok-4.7")).toBe(true)
		t.expect(models.sameModel("gpt-5.6-sol-none", "gpt-5.6-sol-medium")).toBe(true)
		t.expect(models.sameModel("claude-opus-5-5-high", "claude-opus-5-5")).toBe(true)
		t.expect(models.sameModel("Claude-Opus-5-5-HIGH", "claude-opus-5-5-low")).toBe(true)
		t.expect(models.sameModel("claude-opus-5-5", "claude-sonnet-5-5")).toBe(false)
		t.expect(models.sameModel("claude-opus-5-5", nil)).toBe(false)
		-- the cross-CLI case: Opus at high on agy (one id) is claude's Opus at effort high (model and flag)
		t.expect(
			models.sameModel(
				"claude-opus-5-5-high",
				models.id({ model = "claude-opus-5-5", effort = "high" } :: any)
			)
		).toBe(true)
		-- a known edge: thinking is a family of its own until an entry states otherwise
		t.expect(models.sameModel("claude-opus-5-thinking-high", "claude-opus-5-high")).toBe(false)
	end)

	it("every entry the S1b seed's catalog places splits cleanly", function()
		local layers = { models.parse(fs.readFile(`{FIXTURES}/seed-s1b.models.toml`), ".models.toml") }
		local cat = models.config(layers).catalog :: { [string]: { models.Setting } }
		local n = 0
		for _, level in models.ALIASES do
			for _, entry in cat[level] do
				n += 1
				t.expect(models.unsplit(models.identity(entry.model :: string).family)).toBe(nil)
			end
		end
		t.expect(n).toBe(15)
	end)
end)
