--!strict
-- c0261 AC9 to AC11: the committed root .models.toml defines the three tiers per CLI by real model names, every step's
-- table references one, and each step resolves to the right model: authoring and the way cheap, a final review
-- sharp, waiting on the wait tier. Reads the real file.
local fs = require("@lune/fs")
local models = require("@znile/engine/models")
local t = require("@tests/lib/t")

local m = models :: any -- the API this issue adds, reached through `any` until the code exists (promote-check)

local TOP = (
	string.gsub(require("@lune/process").exec("git", { "rev-parse", "--show-toplevel" }).stdout, "%s+$", "")
)
local function layers(): { models.Layer }
	return { models.parse(fs.readFile(`{TOP}/.models.toml`), ".models.toml") }
end
-- tier -> cli -> the id a spend row records (the capture: grok and agent cheap 4.6 high, sharp 4.7 xhigh; claude
-- Sonnet, Opus, Haiku; agent's wait Composer; grok's wait is the design's choice, grok-4.5 at low, for the user's veto)
local IDS = {
	cheap = { claude = "claude-sonnet-5", grok = "grok-4.6-high", agent = "cursor-grok-4.6-high" },
	sharp = { claude = "claude-opus-5-5", grok = "grok-4.7-xhigh", agent = "grok-4.7-xhigh" },
	wait = { claude = "claude-haiku-5-5", grok = "grok-4.5-low", agent = "composer-2.5" },
} :: { [string]: { [string]: string } }
local RANK = { cheap = 2, sharp = 4, wait = 1 } :: { [string]: number }
local STEPS = { ["z-ticket"] = "cheap", ["z-design"] = "cheap", ["z-raft"] = "cheap", ["z-run"] = "cheap", ["zz-review"] = "cheap", ["z-wait"] = "wait" } :: { [string]: string }

return t.spec("c0261 root .models.toml tiers", function(it)
	it("each CLI has a cheap, a sharp and a wait model with its rank (AC9)", function()
		for tier, byCli in IDS do
			for _, cli in models.CLIS do
				local r = m.resolve(layers(), "z-design", tier)
				t.expect(models.id(r.specs[cli])).toBe(byCli[cli])
				t.expect(r.specs[cli].rank).toBe(RANK[tier])
			end
		end
	end)

	it("every step's table references a tier and pins no model, and its default tier is the step's (AC10)", function()
		local file = layers()[1]
		for skill, tier in STEPS do
			local resolved = models.resolve(layers(), skill)
			for _, cli in models.CLIS do
				local fields: { [string]: any } = file.skills[skill][cli]
				t.expect(`{skill}.{cli} model pinned={fields.model ~= nil}`).toBe(`{skill}.{cli} model pinned=false`)
				t.expect(`{skill}.{cli} tier={tostring(fields.tier)}`).toBe(`{skill}.{cli} tier={tier}`)
				t.expect(models.id(resolved.specs[cli])).toBe(IDS[tier][cli])
			end
		end
	end)

	it("a final review resolves sharp and a middle round cheap, on every CLI (AC10)", function()
		local sharp = m.resolve(layers(), "zz-review", "sharp")
		local cheap = models.resolve(layers(), "zz-review")
		for _, cli in models.CLIS do
			t.expect(models.id(sharp.specs[cli])).toBe(IDS.sharp[cli])
			t.expect(models.id(cheap.specs[cli])).toBe(IDS.cheap[cli])
		end
	end)

	it("every tier model is a real name, never an alias (AC11)", function()
		for _, byCli in IDS do
			for _, cli in models.CLIS do
				local id = byCli[cli]
				local real = string.match(id, "^claude%-%a+%-%d[%w%-]*$") or string.match(id, "^[%a%-]*grok%-%d[%d%.]*[%w%-]*$")
					or string.match(id, "^composer%-%d[%d%.]*$")
				t.expect(`{id} real={real ~= nil}`).toBe(`{id} real=true`)
				for _, alias in { "latest", "default", "auto" } do
					t.expect((string.find(id, alias, 1, true))).toBe(nil)
				end
			end
		end
	end)

	it("the wait tier's agent step stops by calls and minutes like every agent table (AC10)", function()
		local r = models.resolve(layers(), "z-wait")
		t.expect(r.specs.agent.maxCalls ~= nil and r.specs.agent.maxMinutes ~= nil).toBe(true)
	end)
end)
