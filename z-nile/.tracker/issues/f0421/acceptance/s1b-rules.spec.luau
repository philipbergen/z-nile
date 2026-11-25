--!strict
-- f0421 slice 3, S1b, AC34 (design-review-002 F4, F5, F7): S1b's resolution rules, one case each: which list an activity
-- takes (C6), exclusive lists (C5), a session matched by exact id (R2), the catalog reaching a CLI only through the offers it
-- states and in its own spelling (C3, F7), a lowered entry (C2), the bare level and the Agent tool's word (R1), a review's
-- non-writer entry and the recorded id (R1, R3), and the words of the four refusals of a session model (F4). Sequestered:
-- red until S1b's step one is built. (The Agent tool's version list moved to step two: s1b-agentword.)
local fs = require("@lune/fs")
local modelcmd = require("@znile/engine/modelcmd")
local models = require("@znile/engine/models")
local t = require("@tests/lib/t")

local FIXTURES = "tests/fixtures/models"
local SEED = fs.readFile(`{FIXTURES}/seed-s1b.models.toml`)

local function walk(text: string): { models.Layer }
	return { models.parse(text, ".models.toml") }
end
local function swap(old: string, new: string): string
	local a = string.find(SEED, old, 1, true)
	assert(a ~= nil, `the seed has no {old}`)
	return string.sub(SEED, 1, (a :: number) - 1) .. new .. string.sub(SEED, (a :: number) + #old)
end
local function model(l: { models.Layer }, cli: string, act: string, lvl: string, session: string?): string
	local s = models.resolveActivity(l, cli, act, lvl :: any, nil, session)
	return if s then s.model .. (if s.effort then `@{s.effort}` else "") else "-"
end

local AGY_HELD =
	"claude-opus-5-5-high, claude-opus-5-5-medium, claude-sonnet-5-5-high, claude-sonnet-5-5-medium, gemini-4-argon-high, gemini-4-argon-medium, gemini-4-neon-high, gemini-4-neon-low, gemini-4-neon-medium"

return t.spec("f0421 S1b AC34: the resolution rules", function(it)
	it(
		"C6: a review takes the review list, else the plain list; a level with no list takes the catalog through the offers, in catalog order",
		function()
			local seed = walk(SEED)
			-- agy has a review list at heavy and none at xlight: a review at xlight falls to the plain list
			t.expect(model(seed, "agy", "code-review", "normal")).toBe("gemini-4-argon-high")
			t.expect(model(seed, "agy", "code-review", "normal", "claude-opus-5-5-medium"))
				.toBe("claude-opus-5-5-medium")
			-- agy with no plain heavy list: the catalog's heavy entries agy offers, in catalog order
			local noHeavy = walk(
				swap('heavy = ["gemini-4-neon-high", "claude-opus-5-5-high", "claude-opus-5-5-medium"]\n', "")
			)
			t.expect(model(noHeavy, "agy", "code", "risky")).toBe("claude-opus-5-5-high")
			t.expect(model(noHeavy, "agy", "code", "risky", "gemini-4-argon-high"))
				.toBe("gemini-4-argon-high")
			t.expect(model(noHeavy, "agy", "code", "risky", "gemini-4-neon-high")).toBe("gemini-4-neon-high")
			-- the catalog is filtered by the offers: agy offering no Opus at medium is not given it at heavy
			local narrowed = string.gsub(
				string.gsub(
					SEED,
					'heavy = %["gemini%-4%-neon%-high", "claude%-opus%-5%-5%-high", "claude%-opus%-5%-5%-medium"%]\n',
					""
				),
				'"claude%-opus%-5%-5%-medium", "claude%-opus%-5%-5%-high", ',
				'"claude-opus-5-5-high", '
			)
			local l = walk((string.gsub(narrowed, ', "claude%-opus%-5%-5%-medium"%]', "]")))
			t.expect(model(l, "agy", "code", "risky", "claude-opus-5-5-high")).toBe("claude-opus-5-5-high")
			t.expect(model(l, "agy", "code", "risky", "claude-opus-5-5-medium")).toBe("-")
		end
	)

	it("C5: a list is exclusive: what the catalog holds at the level does not join it", function()
		local seed = walk(SEED)
		-- Argon is placed at heavy and agy offers it, but agy's plain heavy list leaves it out: an Argon session writes nothing
		t.expect(model(seed, "agy", "code", "risky", "gemini-4-argon-high")).toBe("-")
		t.expect(model(seed, "agy", "code-review", "normal", "gemini-4-neon-high")).toBe("-")
	end)

	it("R2: a session delivers the entry that is its exact id, never another effort of its family", function()
		local seed = walk(SEED)
		t.expect(model(seed, "agy", "code", "risky", "claude-opus-5-5-high")).toBe("claude-opus-5-5-high")
		t.expect(model(seed, "agy", "code", "risky", "claude-opus-5-5-low")).toBe("-")
		t.expect(models.can(seed, "agy", "code", "risky", "claude-opus-5-5-low")).toBe(false)
	end)

	it(
		"C3 and F7: the catalog reaches a CLI only through offers it states, and in the CLI's own spelling",
		function()
			local seed = walk(SEED)
			-- agent states no offers: its one table, today's answer
			t.expect(models.modelsOf(seed, "agent")).toEqual({ "claude-opus-5-5" })
			t.expect(model(seed, "agent", "code", "normal")).toBe("-")
			-- grok with no light table: the catalog's grok-4.7-high, which grok lists as grok-4.7 with a flag
			local noLight = walk(
				swap(
					'[clis.grok]\noffers = ["grok-4.7", "grok-4.7-build-fast", "grok-4.6", "grok-4.5"]\nlight = { model = "grok-4.7", effort = "high" }\n',
					'[clis.grok]\noffers = ["grok-4.7", "grok-4.7-build-fast", "grok-4.6", "grok-4.5"]\n'
				)
			)
			t.expect(model(noLight, "grok", "code", "normal")).toBe("grok-4.7@high")
		end
	)

	it(
		"C2: an entry listed below its catalog level delivers there, and alias= stays the level the activity needs",
		function()
			local lowered = walk(
				swap(
					'xlight = ["gemini-4-neon-low"]\n',
					'xlight = ["gemini-4-neon-low", "gemini-4-neon-medium"]\n'
				)
			)
			local spec = models.resolveActivity(lowered, "agy", "design", "easy", nil, "gemini-4-neon-medium")
			t.expect(spec ~= nil and spec.model).toBe("gemini-4-neon-medium")
			t.expect(spec ~= nil and spec.alias).toBe("xlight")
		end
	)

	it(
		"R1 and d3-F6: ./zn model <level> is the first entry for a CLI that starts each step, and a session's own entry for a session",
		function()
			local seed = walk(SEED)
			t.expect((models.resolveAlias(seed, "claude", "heavy") :: models.Spec).model)
				.toBe("claude-opus-5-5")
			-- an agy session on Opus at high: its own entry of the heavy list, not the list's first
			local own = models.resolveAlias(seed, "agy", "heavy", "claude-opus-5-5-high") :: models.Spec
			t.expect(own.model).toBe("claude-opus-5-5-high")
			-- a session whose model the level's plain list does not hold: nil, naming the list
			local none, why = models.resolveAlias(seed, "agy", "heavy", "gemini-4-argon-high")
			t.expect(none).toBe(nil)
			t.expect(why).toBe(
				"this session runs gemini-4-argon-high, and heavy on agy is one of gemini-4-neon-high|claude-opus-5-5-high|claude-opus-5-5-medium"
			)
		end
	)

	it(
		"R1 and R3: a review takes the first entry that is no writer's, and that entry's id is what is recorded",
		function()
			local text = swap(
				'ultra = { model = "claude-fable-5-2", effort = "xhigh", context = 1000000 }',
				'ultra = [{ model = "claude-fable-5-2", effort = "xhigh", context = 1000000 }, { model = "claude-opus-5-5", effort = "xhigh" }]'
			)
			text = (
				string.gsub(
					text,
					'ultra = %[{ id = "claude%-fable%-5%-2%-xhigh", context = 1000000 }%]',
					'ultra = [{ id = "claude-fable-5-2-xhigh", context = 1000000 }, "claude-opus-5-5-xhigh"]'
				)
			)
			local l = walk(text)
			local fableWrote = models.resolveReview(
				l,
				"claude",
				"code-review",
				"risky",
				{ "claude-fable-5-2-high" },
				nil,
				true
			) :: models.Spec
			t.expect(models.id(fableWrote)).toBe("claude-opus-5-5-xhigh")
			t.expect(fableWrote.sameAsAuthor).toBe(nil)
			local sonnetWrote = models.resolveReview(
				l,
				"claude",
				"code-review",
				"risky",
				{ "claude-sonnet-5-5-medium" },
				nil,
				true
			) :: models.Spec
			t.expect(models.id(sonnetWrote)).toBe("claude-fable-5-2-xhigh")
			local both = models.resolveReview(
				l,
				"claude",
				"code-review",
				"risky",
				{ "claude-fable-5-2-high", "claude-opus-5-5-high" },
				nil,
				true
			) :: models.Spec
			t.expect(models.id(both)).toBe("claude-fable-5-2-xhigh")
			t.expect(both.sameAsAuthor).toBe(true)
		end
	)

	it(
		"F4: each cause of a refused session model has its own words, naming the file and the key that would change it",
		function()
			local function refusal(text: string, id: string): string?
				local _, why = modelcmd.sessionModel({ ZN_MODEL = id }, walk(text), "agy")
				return why
			end
			local tail =
				`; until then ask the person to start agy on one of {AGY_HELD} (an agent never sets or changes ZN_MODEL)`
			t.expect(refusal(SEED, "claude-fable-5-2-xhigh")).toBe(
				`ZN_MODEL claude-fable-5-2-xhigh is not a model agy runs (agy's id rule, in the engine): ask the person to start agy on one of {AGY_HELD} (an agent never sets or changes ZN_MODEL)`
			)
			t.expect(refusal(SEED, "claude-opus-5-5-low")).toBe(
				`ZN_MODEL claude-opus-5-5-low is not placed in [catalog] (.models.toml): ask the owner to place it{tail}`
			)
			-- placed and offered, and no list holds it
			local held = string.gsub(AGY_HELD, "claude%-sonnet%-5%-5%-high, ", "")
			local unlisted = string.gsub(SEED, ', "claude%-sonnet%-5%-5%-high"%]', "]")
			local _, why3 =
				modelcmd.sessionModel({ ZN_MODEL = "claude-sonnet-5-5-high" }, walk(unlisted), "agy")
			t.expect(why3).toBe(
				`ZN_MODEL claude-sonnet-5-5-high is placed at light, and no list of clis.agy in .models.toml holds it: ask the owner to add it to one; until then ask the person to start agy on one of {held} (an agent never sets or changes ZN_MODEL)`
			)
			-- placed, and agy's offers do not hold it: the offers are checked before the catalog (d3-F9), so the id is not a
			-- model agy runs; only agy's offers lose it (the catalog keeps it at light)
			local unoffered = string.gsub(unlisted, '"claude%-sonnet%-5%-5%-high", "gpt%-oss', '"gpt-oss')
			local _, why4 =
				modelcmd.sessionModel({ ZN_MODEL = "claude-sonnet-5-5-high" }, walk(unoffered), "agy")
			t.expect(why4).toBe(
				`ZN_MODEL claude-sonnet-5-5-high is not a model agy runs (clis.agy.offers in .models.toml does not hold it): ask the person to start agy on one of {held} (an agent never sets or changes ZN_MODEL)`
			)
		end
	)
end)
