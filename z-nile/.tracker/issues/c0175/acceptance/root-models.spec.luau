--!strict
-- c0175 AC8, AC9 and AC10: the root `.models.toml` as the new CLIs change it, and the review rule they must not change.
-- AC8: no agy or opencode id other than Opus passes a review kind, and no opencode id does (the user's ruling: opencode serves
-- authoring and stream reviews only). AC9: every id any CLI reaches has a model line in `[families]`, each opencode provider its
-- own. AC10: where agy and opencode sit in the roles' tries, and what each try is recorded as. Pure: reads the repository's file.
local family = require("@znile/engine/family")
local fs = require("@lune/fs")
local models = require("@znile/engine/models")
local process = require("@lune/process")
local reviewmodel = require("@znile/engine/reviewmodel")
local t = require("@tests/lib/t")

local M: any = models
local R: any = reviewmodel
local F: any = family

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

return t.spec("c0175 the root .models.toml and the review rule", function(it)
	it(
		"AC8: Opus through agy passes the review kinds at any effort, as Opus through claude does; the other agy models do not",
		function()
			for _, effort in { "low", "medium", "high" } do
				t.expect(R.ok(`claude-opus-5-5-{effort}`, effort)).toBe(true)
			end
			t.expect(R.ok("claude-opus-5-5", "high")).toBe(true)
			t.expect(R.ok("kimi-code-k3.1-pro", "high")).toBe(true)
			t.expect(R.ok("kimi-code-k3-256k", nil)).toBe(true)
			for _, id in
				{
					"claude-sonnet-5-5-high",
					"gemini-4-argon-high",
					"gemini-4-hydrogen-xhigh",
					"gemini-pro-orchestrator-g1-pro",
					"gemini-3.8-flash-medium",
					"gpt-oss-120b-medium",
				}
			do
				t.expect(R.ok(id, "high")).toBe(false)
			end
		end
	)

	it("AC8: no opencode id passes a review kind, at any effort, xai's Grok at xhigh included", function()
		for _, id in OPENCODE_MODELS do
			for _, effort in { "low", "high", "xhigh", "max" } do
				t.expect(R.ok(id, effort)).toBe(false)
				t.expect(R.ok(`{id}-{effort}`, effort)).toBe(false)
			end
		end
		t.expect(R.ok("deepseek-v4-pro", "max")).toBe(false)
		t.expect(R.ok("grok-4.7", "xhigh")).toBe(true) -- the grok CLI's own is unchanged
	end)

	it(
		"AC8: no review role of the root file has an opencode try, and no review model the file can pick is refused for its kind",
		function()
			for _, mode in { "design", "raft", "code", "final" } do
				for _, id in tryIds("zz-review", mode) do
					t.expect((string.find(id, "opencode", 1, true))).toBe(nil)
				end
			end
			t.expect(
				string.find(table.concat(tryIds("zz-review", "stream"), " "), "opencode", 1, true) ~= nil
			)
				.toBe(true)
			-- every agy try of a review mode is Opus: the one agy model that passes
			for _, mode in { "design", "raft", "code", "final" } do
				for _, s in M.tries(M.resolve(layers(), "zz-review", mode)) do
					if s.cli == "agy" then
						t.expect(R.ok(M.id(s), s.effort)).toBe(true)
					end
				end
			end
		end
	)

	it(
		"AC9: every model line a CLI reaches is in [families]: agy's Gemini, Claude and GPT-OSS ids, each opencode provider its own",
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
			for _, id in OPENCODE_MODELS do
				t.expect(F.of(id, families) ~= nil).toBe(true)
			end
			t.expect(F.of("opencode-deepseek-deepseek-v4-pro", families)).toBe("opencode-deepseek")
			t.expect(F.of("opencode-opencode-big-pickle", families)).toBe("opencode-opencode")
		end
	)

	it("AC9: an opencode model is never in the model line of the same model reached another way", function()
		local families = M.families(layers())
		t.expect(F.of("opencode-xai-grok-4.7", families)).toBe("opencode-xai")
		t.expect(F.same(F.of("opencode-xai-grok-4.7", families), F.of("grok-4.7", families))).toBe(false)
		t.expect(
			F.same(F.of("opencode-deepseek-deepseek-v4-pro", families), F.of("deepseek-v4-pro", families))
		)
			.toBe(false)
		-- the old deepseek line is gone: no id reaches it
		t.expect(families.deepseek).toBe(nil)
	end)

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

	it(
		"AC10: agy ends every role's CLIs and opencode ends the authoring roles' and the stream review's, in the file's order",
		function()
			local l: any = layers()[1]
			for _, role in { "idea", "design", "implementation" } do
				t.expect(l.roles[role].fallbacks).toEqual({ "kimi", "grok", "agent", "agy", "opencode" })
			end
			for _, role in { "idea-challenge", "design-challenge", "raft", "code-review", "final-review" } do
				t.expect(l.roles[role].fallbacks).toEqual({ "kimi", "grok", "agent", "agy" })
			end
			t.expect(l.roles["stream-review"].fallbacks).toEqual({ "opencode" })
			t.expect(l.roles["stream-review"].pool).toEqual({ "sonnet", "gemini-flash", "deepseek-flash" })
			t.expect(l.fallbacks.agy).toEqual({ model = "claude-opus-5-5", runtime = "agy-cli" })
			t.expect(l.fallbacks.opencode)
				.toEqual({ model = "opencode-deepseek-deepseek-v4-pro", runtime = "opencode-cli" })
			t.expect(l.members["gemini-flash"])
				.toEqual({ cli = "agy", model = "gemini-3.8-flash", runtime = "agy-cli" })
			t.expect(l.members["deepseek-flash"]).toEqual({
				cli = "opencode",
				model = "opencode-deepseek-deepseek-flash",
				runtime = "opencode-cli",
			})
		end
	)

	it(
		"AC10: each try is recorded as the model and effort that ran: agy's Opus at high where the stage asks xhigh",
		function()
			-- design-challenge asks xhigh: claude takes it, agy's Opus cannot
			t.expect(tryIds("zz-review", "design")).toEqual({
				"claude:claude-opus-5-5-xhigh",
				"claude:claude-fable-5-2-xhigh",
				"kimi:kimi-code-k3.1-pro-xhigh",
				"grok:grok-4.7-xhigh",
				"agent:claude-opus-5-5-xhigh",
				"agy:claude-opus-5-5-high",
			})
			t.expect(tryIds("z-run")).toEqual({
				"claude:claude-sonnet-5-5-high",
				"kimi:kimi-code-k3.1-pro-high",
				"grok:grok-4.7-high",
				"agent:claude-opus-5-5-high",
				"agy:claude-opus-5-5-high",
				"opencode:opencode-deepseek-deepseek-v4-pro-high",
			})
			t.expect(tryIds("zz-review", "stream")).toEqual({
				"claude:claude-haiku-5-5-medium",
				"claude:claude-sonnet-5-5-medium",
				"agy:gemini-3.8-flash-medium",
				"opencode:opencode-deepseek-deepseek-flash-medium",
				"opencode:opencode-deepseek-deepseek-v4-pro-medium",
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

	it(
		"AC10: the author record matches Opus through agy to Opus through claude, and each new id to its own model",
		function()
			local known = M.knownModels(layers())
			t.expect(M.modelOf("claude-opus-5-5-high", known)).toBe("claude-opus-5-5")
			t.expect(M.modelOf("gemini-3.8-flash-medium", known)).toBe("gemini-3.8-flash")
			t.expect(M.modelOf("opencode-deepseek-deepseek-v4-pro-high", known))
				.toBe("opencode-deepseek-deepseek-v4-pro")
			t.expect(M.modelOf("opencode-deepseek-deepseek-flash-medium", known))
				.toBe("opencode-deepseek-deepseek-flash")
		end
	)
end)
