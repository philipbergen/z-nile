--!strict
-- c0175 AC8, AC9 and AC10: the root `.models.toml` as the new CLIs change it. AC8: any model may run any review (c0251), so no agy,
-- kimi or opencode id is refused; the floor is the frontier list (gemini-4-argon is on it, hydrogen, flash and opencode are not),
-- and opencode is in no review role but the stream review (the user, 2026-11-16). AC9: every id any CLI reaches is placed by
-- `family.of`, an opencode model in the family of its own model line. AC10: where agy and opencode sit in the roles' tries, and
-- what each try is recorded as. Pure: reads the repository's file.
local family = require("@znile/engine/family")
local frontier = require("@znile/engine/frontier")
local fs = require("@lune/fs")
local models = require("@znile/engine/models")
local process = require("@lune/process")
local reviewmodel = require("@znile/engine/reviewmodel")
local reviewpool = require("@znile/engine/reviewpool")
local t = require("@tests/lib/t")

local M: any = models
local R: any = reviewmodel
local F: any = family
local FR: any = frontier
local RP: any = reviewpool

local TOP = (string.gsub(process.exec("git", { "rev-parse", "--show-toplevel" }).stdout, "%s+$", ""))
local function layers(): { any }
	return { M.parse(fs.readFile(`{TOP}/.models.toml`), ".models.toml") }
end
local function tryIds(skill: string, mode: string?): { string }
	local out = {}
	for _, s in M.tries(M.resolve(layers(), skill, mode)) do
		table.insert(out, `{s.cli}:{M.id(s)}`)
	end
	return out
end

-- `agy models`, 2026-11-15, by the bare names agy takes (the effort goes beside the name)
local AGY_MODELS = {
	"gemini-4-argon",
	"gemini-4-hydrogen",
	"gemini-pro-orchestrator-g1-pro",
	"gemini-3.8-flash",
	"claude-opus-5-5",
	"claude-sonnet-5-5",
	"gpt-oss-120b",
}
-- `opencode models` on this machine, 2026-11-15, as ledger ids
local OPENCODE_MODELS = {
	"opencode-opencode-big-pickle",
	"opencode-opencode-deepseek-v4.1-flash-free",
	"opencode-opencode-glm-5.3-flash-free",
	"opencode-deepseek-deepseek-flash",
	"opencode-deepseek-deepseek-v4-pro",
	"opencode-xai-grok-4.3",
	"opencode-xai-grok-4.7",
	"opencode-xai-grok-build-0.1",
}

return t.spec("c0175 the root .models.toml, the frontier list and the families", function(it)
	it(
		"AC8: any agy, kimi or opencode model may run a review: the record accepts every id the CLIs reach",
		function()
			for _, id in AGY_MODELS do
				t.expect(R.ok(id, "high")).toBe(true)
			end
			for _, id in OPENCODE_MODELS do
				for _, effort in { "low", "high", "xhigh", "max" } do
					t.expect(R.ok(id, effort)).toBe(true)
				end
			end
			t.expect(R.ok("kimi-code-kimi-for-coding", "high")).toBe(true)
			t.expect(R.ok("", "high")).toBe(false) -- the record rule is the one that stays: an empty id is no record
		end
	)

	it(
		"AC8: gemini-4-argon is on the frontier list at any effort; hydrogen, flash and the opencode models are not",
		function()
			local list = M.frontier(layers())
			t.expect(table.find(list, "gemini-4-argon") ~= nil).toBe(true)
			for _, effort in { "low", "high" } do
				t.expect(FR.listed("gemini-4-argon", effort, list)).toBe(true)
			end
			for _, id in
				{
					"gemini-4-hydrogen",
					"gemini-3.8-flash",
					"gemini-pro-orchestrator-g1-pro",
					"gpt-oss-120b",
					"opencode-deepseek-deepseek-v4-pro",
					"opencode-xai-grok-4.7",
				}
			do
				t.expect(FR.listed(id, "high", list)).toBe(false)
			end
			-- an opencode-carried grok is not "grok-4.7@xhigh": the list names a model id, and this is another id
			t.expect(FR.listed("opencode-xai-grok-4.7", "xhigh", list)).toBe(false)
		end
	)

	it(
		"AC8: opencode is in the writing roles and the stream review only; agy is in every role, with argon on all but implementation",
		function()
			local l: any = layers()[1]
			for _, role in { "idea", "design", "raft", "implementation" } do
				t.expect(table.find(l.roles[role].fallbacks, "opencode") ~= nil).toBe(true)
			end
			for _, role in
				{ "idea-challenge", "design-challenge", "raft-review", "code-review", "final-review" }
			do
				t.expect(table.find(l.roles[role].fallbacks, "opencode")).toBe(nil)
			end
			for _, mode in { "design", "raft", "code", "final" } do
				for _, id in tryIds("zz-review", mode) do
					t.expect((string.find(id, "opencode", 1, true))).toBe(nil)
				end
			end
			t.expect(
				string.find(table.concat(tryIds("zz-review", "stream"), " "), "opencode", 1, true) ~= nil
			)
				.toBe(true)
			-- raft (writing) has opencode, raft-review does not (c0251's split)
			t.expect(string.find(table.concat(tryIds("z-raft"), " "), "opencode", 1, true) ~= nil).toBe(true)
			-- every agy try of a review mode is argon (the frontier model), so a fallen-back review still meets the floor
			for _, mode in { "design", "raft", "code", "final" } do
				for _, s in M.tries(M.resolve(layers(), "zz-review", mode)) do
					if s.cli == "agy" then
						t.expect(s.model).toBe("gemini-4-argon")
					end
				end
			end
		end
	)

	it(
		"AC9: every model line a CLI reaches is placed: agy's Gemini, Claude and GPT-OSS ids, and an opencode id by its own model line",
		function()
			local families = M.families(layers())
			t.expect(families.gemini).toEqual({ "gemini-" })
			t.expect(families.gpt).toEqual({ "gpt-" })
			for _, id in AGY_MODELS do
				t.expect(F.of(id, families) ~= nil).toBe(true)
			end
			t.expect(F.of("gemini-3.8-flash", families)).toBe("gemini")
			t.expect(F.of("gemini-pro-orchestrator-g1-pro", families)).toBe("gemini")
			t.expect(F.of("claude-opus-5-5", families)).toBe("opus")
			t.expect(F.of("claude-sonnet-5-5", families)).toBe("sonnet")
			t.expect(F.of("gpt-oss-120b", families)).toBe("gpt")
			t.expect(F.of("kimi-code-kimi-for-coding", families)).toBe("kimi")
			-- the user's ruling (2026-11-16): an opencode model's family is its own model line's, whoever carries it
			t.expect(F.of("opencode-deepseek-deepseek-v4-pro", families)).toBe("deepseek")
			t.expect(F.of("opencode-deepseek-deepseek-flash", families)).toBe("deepseek")
			t.expect(F.of("opencode-opencode-deepseek-v4.1-flash-free", families)).toBe("deepseek")
			t.expect(F.of("opencode-xai-grok-4.7", families)).toBe("grok")
			t.expect(F.of("opencode-xai-grok-build-0.1", families)).toBe("grok")
			-- a Claude served by opencode's Zen is in Claude's family; a gateway's vendor part is stripped too
			t.expect(F.of("opencode-opencode-claude-opus-5-5", families)).toBe("opus")
			t.expect(F.of("opencode-openrouter-anthropic_sclaude-opus-5-5", families)).toBe("opus")
			t.expect(F.of("opencode-openrouter-moonshotai_skimi-k3.1-pro", families)).toBe("kimi")
			-- the old per-provider lines are gone
			for _, name in { "opencode-deepseek", "opencode-xai", "opencode-opencode" } do
				t.expect(families[name]).toBe(nil)
			end
			-- a model the table cannot place has no family (never "different", c0251)
			t.expect(F.of("opencode-opencode-big-pickle", families)).toBe(nil)
			t.expect(F.of("opencode-opencode-glm-5.3-flash-free", families)).toBe(nil)
			t.expect(F.of("opencode-openrouter-meta-llama_sllama-4", families)).toBe(nil)
		end
	)

	it("AC9: an opencode model is in the family of the same model reached another way", function()
		local families = M.families(layers())
		t.expect(F.same(F.of("opencode-xai-grok-4.7", families), F.of("grok-4.7", families))).toBe(true)
		t.expect(
			F.same(F.of("opencode-deepseek-deepseek-v4-pro", families), F.of("deepseek-v4-pro", families))
		)
			.toBe(true)
		t.expect(
			F.same(F.of("opencode-opencode-claude-opus-5-5", families), F.of("claude-opus-5-5", families))
		)
			.toBe(true)
		t.expect(F.same(F.of("opencode-xai-grok-4.7", families), F.of("claude-opus-5-5", families)))
			.toBe(false)
		-- an unplaced model is the same as nothing, itself included
		t.expect(
			F.same(
				F.of("opencode-opencode-big-pickle", families),
				F.of("opencode-opencode-big-pickle", families)
			)
		).toBe(false)
		-- a longer prefix the user adds for the whole id still wins over the model line's shorter one
		local custom = { grok = { "grok-" }, mine = { "opencode-xai-grok-build-" } }
		t.expect(F.of("opencode-xai-grok-build-0.1", custom)).toBe("mine")
		t.expect(F.of("opencode-xai-grok-4.7", custom)).toBe("grok")
		-- family.opencodeModel is the one place the id is cut
		t.expect(F.opencodeModel("opencode-xai-grok-4.7")).toBe("grok-4.7")
		t.expect(F.opencodeModel("opencode-openrouter-anthropic_sclaude-3.5-sonnet_cbeta"))
			.toBe("claude-3.5-sonnet_cbeta")
		t.expect(F.opencodeModel("grok-4.7")).toBe(nil)
	end)

	it(
		"AC9: a grok review through opencode of a grok text is the author's line, not a different one",
		function()
			local families = M.families(layers())
			local function spec(cli: string, model: string): any
				return {
					cli = cli,
					model = model,
					effort = "high",
					rank = 4,
					runtime = `{cli}-rt`,
					maxTokens = 1000,
				}
			end
			local viaOpencode = spec("opencode", "opencode-xai-grok-4.7")
			local sonnet = spec("claude", "claude-sonnet-5-5")
			local picks = RP.order({ viaOpencode, sonnet }, families, { "grok-4.7" }, {})
			t.expect(picks[1].spec.model).toBe("claude-sonnet-5-5") -- tier 1
			t.expect(picks[1].tier).toBe(1)
			t.expect(picks[2].spec.model).toBe("opencode-xai-grok-4.7")
			t.expect(picks[2].tier).toBe(3) -- the author's own line, last
		end
	)

	it(
		"AC9: every model any role, fallback or member of the file names has a model line, so no rotating role fails to resolve",
		function()
			local families = M.families(layers())
			for _, model in M.knownModels(layers()) do
				t.expect(F.of(model, families) ~= nil).toBe(true)
			end
			for _, mode in { "design", "raft", "code", "final", "stream" } do
				M.resolve(layers(), "zz-review", mode)
			end
			M.resolve(layers(), "idea-challenge")
		end
	)

	it("AC10: agy and opencode end the roles' CLIs as the user placed them, in the file's order", function()
		local l: any = layers()[1]
		for _, role in { "idea", "design", "raft" } do
			t.expect(l.roles[role].fallbacks).toEqual({ "kimi", "grok", "agent", "agy", "opencode" })
		end
		t.expect(l.roles.implementation.fallbacks)
			.toEqual({ "kimi", "grok", "agent", "agy-hydrogen", "opencode" })
		for _, role in { "idea-challenge", "design-challenge", "raft-review", "code-review", "final-review" } do
			t.expect(l.roles[role].fallbacks).toEqual({ "kimi", "grok", "agent", "agy" })
		end
		-- the stream-review list, the user's order: Haiku (the role), Sonnet, grok 4.6, Kimi K2.8 Preview, composer, Gemini
		-- flash (agy), DeepSeek flash (opencode)
		t.expect(l.roles["stream-review"].fallbacks).toEqual({})
		t.expect(l.roles["stream-review"].pool)
			.toEqual({ "sonnet", "grok46", "kimi-k28", "composer", "gemini-flash", "deepseek-flash" })
		t.expect(l.fallbacks.agy).toEqual({ model = "gemini-4-argon", runtime = "agy-cli" })
		t.expect(l.fallbacks.opencode)
			.toEqual({ model = "opencode-deepseek-deepseek-v4-pro", runtime = "opencode-cli" })
		t.expect(l.members["agy-hydrogen"])
			.toEqual({ cli = "agy", model = "gemini-4-hydrogen", runtime = "agy-cli" })
		t.expect(l.members["kimi-k28"])
			.toEqual({ cli = "kimi", model = "kimi-code-kimi-for-coding", runtime = "kimi-cli" })
		t.expect(l.members["gemini-flash"])
			.toEqual({ cli = "agy", model = "gemini-3.8-flash", runtime = "agy-cli" })
		t.expect(l.members["deepseek-flash"]).toEqual({
			cli = "opencode",
			model = "opencode-deepseek-deepseek-flash",
			runtime = "opencode-cli",
		})
		-- Orchestrator and GPT-OSS are named by no role
		for _, group in { l.roles, l.fallbacks, l.members } do
			for _, v in group do
				t.expect(string.find(tostring(v.model), "orchestrator", 1, true)).toBe(nil)
				t.expect(string.find(tostring(v.model), "gpt-oss", 1, true)).toBe(nil)
			end
		end
	end)

	it(
		"AC10: each try is recorded as the model and effort that ran: agy's argon at high where the stage asks xhigh, hydrogen at xhigh",
		function()
			-- design-challenge asks xhigh: claude takes it, agy's argon cannot
			t.expect(tryIds("zz-review", "design")).toEqual({
				"claude:claude-opus-5-5-xhigh",
				"claude:claude-fable-5-2-xhigh",
				"kimi:kimi-code-k3.1-pro-xhigh",
				"grok:grok-4.7-xhigh",
				"agent:claude-opus-5-5-xhigh",
				"agy:gemini-4-argon-high",
			})
			t.expect(tryIds("z-run")).toEqual({
				"claude:claude-sonnet-5-5-high",
				"kimi:kimi-code-k3.1-pro-high",
				"grok:grok-4.7-high",
				"agent:claude-opus-5-5-high",
				"agy:gemini-4-hydrogen-high",
				"opencode:opencode-deepseek-deepseek-v4-pro-high",
			})
			t.expect(tryIds("zz-review", "stream")).toEqual({
				"claude:claude-haiku-5-5-medium",
				"claude:claude-sonnet-5-5-medium",
				"grok:grok-4.6-medium",
				"kimi:kimi-code-kimi-for-coding-medium",
				"agent:composer-2.5-medium",
				"agy:gemini-3.8-flash-medium",
				"opencode:opencode-deepseek-deepseek-flash-medium",
			})
		end
	)

	it("AC10: the new tries carry their role's rank and cap, and no cap of their own", function()
		local run = M.resolve(layers(), "z-run")
		for _, cli in { "agy", "opencode" } do
			t.expect(run.specs[cli].rank).toBe(3)
			t.expect(run.specs[cli].maxTokens).toBe(12000000)
			t.expect(run.specs[cli].maxCalls).toBe(nil)
			t.expect(run.specs[cli].maxMinutes).toBe(nil)
		end
		t.expect(M.CALL_CAPPED.agy).toBe(nil)
		t.expect(M.CALL_CAPPED.opencode).toBe(nil)
	end)

	it("AC10: the author record matches each new id to its own model", function()
		local known = M.knownModels(layers())
		t.expect(M.modelOf("gemini-4-argon-high", known)).toBe("gemini-4-argon")
		t.expect(M.modelOf("gemini-4-hydrogen-xhigh", known)).toBe("gemini-4-hydrogen")
		t.expect(M.modelOf("gemini-3.8-flash-medium", known)).toBe("gemini-3.8-flash")
		t.expect(M.modelOf("kimi-code-kimi-for-coding-medium", known)).toBe("kimi-code-kimi-for-coding")
		t.expect(M.modelOf("opencode-deepseek-deepseek-v4-pro-high", known))
			.toBe("opencode-deepseek-deepseek-v4-pro")
		t.expect(M.modelOf("opencode-deepseek-deepseek-flash-medium", known))
			.toBe("opencode-deepseek-deepseek-flash")
	end)
end)
