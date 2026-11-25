--!strict
-- f0421 slice 3, S1b, AC32 (design-review-002 F4): what each CLI delivers on the seed of S1b's step one
-- (tests/fixtures/models/seed-s1b.models.toml, variant (b) of design-review-002 F6), written by hand from C6 and R2, not
-- captured from a build. claude, grok, agent and kimi answer exactly as on today's root; agy's sessions on Claude Opus and
-- Sonnet work; the waiting lines name several models as `one of a|b`. The live root file only has to load with a deliverer
-- for every activity at every level. Sequestered: red until S1b is built.
local fs = require("@lune/fs")
local models = require("@znile/engine/models")
local process = require("@lune/process")
local t = require("@tests/lib/t")

local FIXTURES = "tests/fixtures/models"
local TOP = (string.gsub(process.exec("git", { "rev-parse", "--show-toplevel" }).stdout, "%s+$", ""))

local function walk(name: string): { models.Layer }
	return { models.parse(fs.readFile(`{FIXTURES}/{name}`), ".models.toml") }
end

local function joined(list: { string }): string
	return table.concat(list, ",")
end

-- agy: what a session on each model of its lists delivers (by hand: C6 takes the review list for a review, else the plain
-- list; a session delivers the levels whose list holds its exact id)
local AGY = {
	["gemini-4-neon-low"] = "design/easy,raft/easy,code/easy",
	["gemini-4-neon-medium"] = "design/normal,raft/normal,code/normal",
	["gemini-4-neon-high"] = "idea/easy,idea/normal,idea/risky,design/risky,raft/risky,code/risky,approve/easy,approve/normal,approve/risky",
	["gemini-4-argon-medium"] = "design-review/easy,raft-review/easy,code-review/easy",
	["gemini-4-argon-high"] = "design-review/normal,raft-review/normal,code-review/normal",
	["claude-sonnet-5-5-medium"] = "design/normal,design-review/easy,raft/normal,raft-review/easy,code/normal,code-review/easy",
	["claude-sonnet-5-5-high"] = "design/normal,design-review/easy,raft/normal,raft-review/easy,code/normal,code-review/easy",
	["claude-opus-5-5-high"] = "idea/easy,idea/normal,idea/risky,design/risky,design-review/normal,raft/risky,raft-review/normal,code/risky,code-review/normal,approve/easy,approve/normal,approve/risky",
	["claude-opus-5-5-medium"] = "idea/easy,idea/normal,idea/risky,design/risky,design-review/normal,raft/risky,raft-review/normal,code/risky,code-review/normal,approve/easy,approve/normal,approve/risky",
}

return t.spec("f0421 S1b AC32: the step-one seed's answers, by hand", function(it)
	it(
		"claude, grok, agent and kimi deliver on the seed exactly what they deliver on today's root",
		function()
			local seed = walk("seed-s1b.models.toml")
			local today = walk("root-5e8f5eaa4.models.toml")
			for _, cli in { "claude", "grok", "agent", "kimi" } do
				t.expect(joined(models.canList(seed, cli))).toBe(joined(models.canList(today, cli)))
				t.expect(models.modelsOf(seed, cli)).toEqual(models.modelsOf(today, cli))
			end
			t.expect(#models.canList(seed, "claude")).toBe(30)
			t.expect(#models.canList(seed, "grok")).toBe(6)
			t.expect(#models.canList(seed, "agent")).toBe(12)
			t.expect(#models.canList(seed, "kimi")).toBe(12)
			-- agent names no offers, so the catalog does not reach it: its one model, no ZN_MODEL needed
			t.expect(models.needsSession(seed, "agent")).toBe(false)
		end
	)

	it("agy holds nine models, and a session on each delivers what its lists give that exact id", function()
		local seed = walk("seed-s1b.models.toml")
		t.expect(models.modelsOf(seed, "agy")).toEqual({
			"claude-opus-5-5-high",
			"claude-opus-5-5-medium",
			"claude-sonnet-5-5-high",
			"claude-sonnet-5-5-medium",
			"gemini-4-argon-high",
			"gemini-4-argon-medium",
			"gemini-4-neon-high",
			"gemini-4-neon-low",
			"gemini-4-neon-medium",
		})
		for model, want in AGY do
			t.expect(`{model}: {joined(models.canList(seed, "agy", model))}`).toBe(`{model}: {want}`)
		end
		-- Neon never reviews and Argon never writes; Opus and Sonnet do both (G9)
		t.expect(models.can(seed, "agy", "code-review", "normal", "gemini-4-neon-high")).toBe(false)
		t.expect(models.can(seed, "agy", "code", "risky", "gemini-4-argon-high")).toBe(false)
		-- nothing reaches agy at ultra: its offers hold no Fable
		t.expect(models.can(seed, "agy", "final-review", "normal", "claude-opus-5-5-high")).toBe(false)
	end)

	it("the waiting line names one model as today and several as one of a|b", function()
		local seed = walk("seed-s1b.models.toml")
		t.expect(models.waiting(seed, "code-review", "normal")).toBe(
			"code-review/normal (heavy: claude, agent, kimi, agy running one of gemini-4-argon-high|claude-opus-5-5-high|claude-opus-5-5-medium)"
		)
		t.expect(models.waiting(seed, "code", "normal")).toBe(
			"code/normal (light: claude, grok, agy running one of gemini-4-neon-medium|claude-sonnet-5-5-medium|claude-sonnet-5-5-high)"
		)
		t.expect(models.waiting(seed, "design", "easy"))
			.toBe("design/easy (xlight: claude, agy running gemini-4-neon-low)")
		t.expect(models.waiting(seed, "final-review", "normal")).toBe("final-review/normal (ultra: claude)")
		t.expect(models.waiting(seed, "code-review", "risky")).toBe("code-review/risky (ultra: claude)")
	end)

	it(
		"on this seed no session of agent, agy or kimi resolves the final review or any ultra activity: the hold-back cannot act",
		function()
			local seed = walk("seed-s1b.models.toml")
			-- the pairs whose root setting is ultra: idea-challenge and final-review at every level, the reviews of risky work
			local ultra = {
				"idea-challenge/",
				"final-review/",
				"design-review/risky",
				"raft-review/risky",
				"code-review/risky",
			}
			for _, cli in { "agent", "agy", "kimi" } do
				local sessions: { string? } = { nil }
				for _, m in models.modelsOf(seed, cli) do
					table.insert(sessions, m)
				end
				for i = 1, #models.modelsOf(seed, cli) + 1 do
					local can = joined(models.canList(seed, cli, sessions[i]))
					for _, pair in ultra do
						t.expect(`{cli} {tostring(sessions[i])}: {string.find(can, pair, 1, true) ~= nil}`)
							.toBe(`{cli} {tostring(sessions[i])}: false`)
					end
				end
			end
		end
	)

	it("the live root file loads, and every activity at every level has a deliverer", function()
		local root = { models.parse(fs.readFile(`{TOP}/.models.toml`), ".models.toml") }
		for _, act in models.ACTIVITIES do
			for _, lvl in { "easy", "normal", "risky" } do
				t.expect(`{act}/{lvl}: {#models.deliverers(root, act, lvl :: any) > 0}`)
					.toBe(`{act}/{lvl}: true`)
			end
		end
	end)
end)
