--!strict
-- c0261 AC1 to AC4: `.models.toml` gets `[tiers.<cli>.<tier>]` tables (model, effort, rank) that the existing per-skill
-- tables reference with `tier = "..."`; a per-skill table that sets its own model keeps it; the sharp tier obeys the
-- review rule; the resolved spec records its tier. Pure: models.parse and models.resolve over layers built from text.
local models = require("@znile/engine/models")
local t = require("@tests/lib/t")

-- the API this issue adds, reached through `any` so the spec type-checks before the code exists (promote-check)
local m = models :: any

local ORDER = 'order = ["claude", "grok", "agent"]\n'
local CHEAP_WAIT = ORDER .. [[
[tiers.claude.cheap]
model = "claude-sonnet-5"
rank = 2
[tiers.claude.wait]
model = "claude-haiku-5-5"
rank = 1
[tiers.grok.cheap]
model = "grok-4.6"
effort = "high"
rank = 2
[tiers.grok.wait]
model = "grok-4.5"
effort = "low"
rank = 1
[tiers.agent.cheap]
model = "cursor-grok-4.6-high"
rank = 2
[tiers.agent.wait]
model = "composer-2.5"
rank = 1
]]
local SHARP = [[
[tiers.claude.sharp]
model = "claude-opus-5-5"
rank = 4
[tiers.grok.sharp]
model = "grok-4.7"
effort = "xhigh"
rank = 4
[tiers.agent.sharp]
model = "grok-4.7-xhigh"
rank = 4
]]
local TIERS = CHEAP_WAIT .. SHARP
local SKILLS = [[
[z-design.claude]
tier = "cheap"
runtime = "claude-cli"
max_tokens = 300000
[z-design.grok]
tier = "cheap"
runtime = "grok-cli"
max_tokens = 300000
[z-design.agent]
tier = "cheap"
runtime = "cursor-cli"
max_tokens = 300000
max_calls = 9
max_minutes = 9
[zz-review.claude]
tier = "cheap"
runtime = "claude-cli"
max_tokens = 100
[zz-review.grok]
tier = "cheap"
runtime = "grok-cli"
max_tokens = 100
[zz-review.agent]
tier = "cheap"
runtime = "cursor-cli"
max_tokens = 100
max_calls = 9
max_minutes = 9
]]
local function layer(text: string, path: string?): models.Layer
	return models.parse(text, path or ".models.toml")
end
local function errorOf(f: () -> ()): string
	local ok: boolean, e: any = pcall(f)
	if ok then
		error("expected an error", 2)
	end
	return tostring(e)
end
local function has(text: string, needle: string): boolean
	return string.find(text, needle, 1, true) ~= nil
end

return t.spec("c0261 tiers in .models.toml", function(it)
	it("a per-skill table takes its model, effort and rank from the tier it names (AC1)", function()
		local r = models.resolve({ layer(TIERS .. SKILLS) }, "z-design")
		t.expect(models.id(r.specs.claude)).toBe("claude-sonnet-5")
		t.expect(models.id(r.specs.grok)).toBe("grok-4.6-high")
		t.expect(models.id(r.specs.agent)).toBe("cursor-grok-4.6-high")
		t.expect(r.specs.claude.rank).toBe(2)
		t.expect(r.specs.claude.maxTokens).toBe(300000) -- the budget stays the skill's
		t.expect((r.specs.claude :: any).tier).toBe("cheap")
	end)

	it("a call can name the tier: the final review round runs sharp, the wait step waits (AC1)", function()
		local layers = { layer(TIERS .. SKILLS) }
		local r = m.resolve(layers, "zz-review", "sharp")
		t.expect(models.id(r.specs.claude)).toBe("claude-opus-5-5")
		t.expect(models.id(r.specs.grok)).toBe("grok-4.7-xhigh")
		t.expect(models.id(r.specs.agent)).toBe("grok-4.7-xhigh")
		t.expect(r.specs.grok.rank).toBe(4)
		local w = m.resolve(layers, "zz-review", "wait")
		t.expect(models.id(w.specs.claude)).toBe("claude-haiku-5-5")
		t.expect(models.id(w.specs.grok)).toBe("grok-4.5-low")
		t.expect(models.id(w.specs.agent)).toBe("composer-2.5")
	end)

	it("a table that sets its own model keeps it: nothing is refactored (AC2)", function()
		local pinned = SKILLS .. '[z-raft.claude]\ntier = "cheap"\nmodel = "claude-opus-5-5"\nrank = 3\nruntime = "claude-cli"\nmax_tokens = 5\n'
		local r = models.resolve({ layer(TIERS .. pinned) }, "z-raft")
		t.expect(models.id(r.specs.claude)).toBe("claude-opus-5-5")
		t.expect(r.specs.claude.rank).toBe(3)
		-- and the old file without any tiers table still resolves as c0117 had it
		local old = 'order = ["claude"]\n[z-raft.claude]\nmodel = "claude-sonnet-5"\nrank = 2\nruntime = "claude-cli"\nmax_tokens = 5\n'
		t.expect(models.id(models.resolve({ layer(old) }, "z-raft").specs.claude)).toBe("claude-sonnet-5")
	end)

	it("a closer file replaces only the keys it sets, tiers included (AC2)", function()
		local closer = layer('[tiers.claude.cheap]\nmodel = "claude-sonnet-5-1"\n', "pickman/.models.toml")
		local r = models.resolve({ layer(TIERS .. SKILLS), closer }, "z-design")
		t.expect(r.specs.claude.model).toBe("claude-sonnet-5-1")
		t.expect(r.specs.claude.rank).toBe(2)
	end)

	it("errors name the file and the key: unknown tier, CLI or field, a missing tier, a tier nobody defines (AC3)", function()
		t.expect(has(errorOf(function()
			layer("[tiers.claude.fast]\nmodel = \"claude-sonnet-5\"\n")
		end), "fast")).toBe(true)
		t.expect(has(errorOf(function()
			layer("[tiers.kimi.cheap]\nmodel = \"x\"\n")
		end), "kimi")).toBe(true)
		t.expect(has(errorOf(function()
			layer("[tiers.claude.cheap]\nruntime = \"claude-cli\"\n")
		end), "tiers.claude.cheap.runtime")).toBe(true)
		t.expect(has(errorOf(function()
			models.resolve({ layer(ORDER .. SKILLS) }, "z-design")
		end), "tiers.claude.cheap")).toBe(true)
		t.expect(has(errorOf(function()
			m.resolve({ layer(TIERS .. SKILLS) }, "z-design", "fast")
		end), "fast")).toBe(true)
		t.expect(has(errorOf(function()
			layer(TIERS .. (string.gsub(SKILLS, 'tier = "cheap"', 'tier = "fast"', 1)))
		end), "tier")).toBe(true)
	end)

	it("a tier entry spells a real model name: no alias (AC3)", function()
		for _, alias in { "opus", "sonnet", "haiku", "claude-opus-latest", "auto" } do
			local e = errorOf(function()
				layer(`[tiers.claude.cheap]\nmodel = "{alias}"\nrank = 2\n`)
			end)
			t.expect(has(e, "alias") or has(e, "real")).toBe(true)
		end
		layer('[tiers.claude.cheap]\nmodel = "claude-haiku-5-5"\nrank = 1\n') -- a real name parses
	end)

	it("the sharp tier is the review model of the CLI: Opus on claude, grok at xhigh on grok and agent (AC4)", function()
		local GOOD = {
			claude = '[tiers.claude.sharp]\nmodel = "claude-opus-5-5"\nrank = 4\n',
			grok = '[tiers.grok.sharp]\nmodel = "grok-4.7"\neffort = "xhigh"\nrank = 4\n',
			agent = '[tiers.agent.sharp]\nmodel = "grok-4.7-xhigh"\nrank = 4\n',
		} :: { [string]: string }
		-- the sharp tables of all three CLIs, `cli`'s replaced by `text`
		local function sharpWith(cli: string, text: string): string
			local out = ""
			for _, c in models.CLIS do
				out ..= if c == cli then text else GOOD[c]
			end
			return out
		end
		local function resolveSharp(text: string): any
			return m.resolve({ layer(CHEAP_WAIT .. text .. SKILLS) }, "zz-review", "sharp")
		end
		local function bad(cli: string, text: string): string
			return errorOf(function()
				resolveSharp(sharpWith(cli, text))
			end)
		end
		t.expect(resolveSharp(sharpWith("claude", GOOD.claude)) ~= nil).toBe(true)
		t.expect(has(bad("claude", '[tiers.claude.sharp]\nmodel = "claude-sonnet-5"\nrank = 4\n'), "sharp")).toBe(true)
		t.expect(has(bad("grok", '[tiers.grok.sharp]\nmodel = "grok-4.7"\neffort = "high"\nrank = 4\n'), "xhigh")).toBe(true)
		t.expect(has(bad("agent", '[tiers.agent.sharp]\nmodel = "claude-opus-5-5-high"\nrank = 4\n'), "xhigh")).toBe(true)
	end)

	it("the old pin rule still holds for a zz-review table that names its own model (AC4)", function()
		local pin = 'order = ["claude"]\n[zz-review.claude]\nmodel = "claude-sonnet-5"\nrank = 4\nruntime = "claude-cli"\nmax_tokens = 5\n'
		t.expect(has(errorOf(function()
			models.resolve({ layer(pin) }, "zz-review")
		end), "runs on Opus")).toBe(true)
	end)
end)
