--!strict
-- c0117 AC1, AC2: .models.toml stacks like .gitignore (a closer file replaces only the keys it sets), a raft takes the
-- stronger spec whole per CLI (higher rank, then larger max_tokens), only the supported CLIs and their runtimes exist,
-- and nothing defaults. One shape: roles, fallbacks and dispatch. A fallback try carries the role's rank, cap and effort.
-- Pure: models.parse and models.resolve over layers built from text; one case reads the real root .models.toml.
local fs = require("@lune/fs")
local models = require("@znile/engine/models")
local t = require("@tests/lib/t")
-- c0117 runs from its project's home, z-nile/ (c0120): every path of the real tree this spec reads is the
-- repository's, from its top
local TOP = (
	string.gsub(require("@lune/process").exec("git", { "rev-parse", "--show-toplevel" }).stdout, "%s+$", "")
)

local ROOT = [[
[dispatch]
stall_seconds = 300

[fallback.kimi]
model = "kimi-code-k3.1-pro"
runtime = "kimi-cli"

[fallback.grok]
model = "grok-4.7"
runtime = "grok-cli"

[roles.design]
model = "claude-opus-5-5"
cli = "claude"
runtime = "claude-cli"
rank = 3
max_tokens = 300000
effort = "high"
fallbacks = ["kimi", "grok"]
]]

local function layer(text: string, path: string?): models.Layer
	return models.parse(text, path or "x/.models.toml")
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
local function spec(cli: string, rank: number, max: number, model: string?): models.Spec
	return {
		cli = cli,
		model = model or `{cli}-m{rank}-{max}`,
		rank = rank,
		runtime = models.RUNTIMES[cli][1],
		maxTokens = max,
	}
end

return t.spec("c0117 .models.toml", function(it)
	it("a closer file replaces only the keys it sets, and every try of the role carries that cap", function()
		local closer = layer("[roles.design]\nmax_tokens = 1000\n", "pickman/.models.toml")
		local r = models.resolve({ layer(ROOT, ".models.toml"), closer }, "z-design")
		local c = r.specs.claude
		t.expect(c.maxTokens).toBe(1000)
		t.expect(c.model).toBe("claude-opus-5-5")
		t.expect(c.rank).toBe(3)
		t.expect(c.runtime).toBe("claude-cli")
		t.expect(c.effort).toBe("high")
		-- the fallback was not named in the closer file; it still runs at the role's cap and effort
		t.expect(r.specs.grok.model).toBe("grok-4.7")
		t.expect(r.specs.grok.maxTokens).toBe(1000)
		t.expect(r.specs.grok.rank).toBe(3)
		t.expect(r.specs.grok.effort).toBe("high")
		t.expect(r.settings.stallSeconds).toBe(300)
	end)

	it("a closer fallbacks list replaces the try list, and each setting is replaced on its own", function()
		local closer = layer('[roles.design]\nfallbacks = ["grok"]\n[dispatch]\nauto_merge = ["prep"]\n')
		local r = models.resolve({ layer(ROOT, ".models.toml"), closer }, "z-design")
		t.expect(r.order).toEqual({ "claude", "grok" })
		t.expect(r.settings.autoMerge).toEqual({ "prep" })
		t.expect(r.settings.stallSeconds).toBe(300)
		local only = models.resolve({
			layer(ROOT, ".models.toml"),
			layer('[roles.design]\ncli = "grok"\nmodel = "grok-4.7"\nruntime = "grok-cli"\nfallbacks = []\n'),
		}, "z-design")
		local tries = models.tries(only)
		t.expect(#tries).toBe(1)
		t.expect(tries[1].cli).toBe("grok")
		t.expect(tries[1].maxTokens).toBe(300000)
		t.expect(tries[1].effort).toBe("high")
	end)

	it(
		"settings come from the walk, closest first; an unset auto_merge is none, and so is any error",
		function()
			local root = layer('[dispatch]\nauto_merge = ["prep", "raft"]\ntool_seconds = 600\n')
			local item = layer("[dispatch]\nauto_merge = []\n")
			t.expect(models.settings({ root }).autoMerge).toEqual({ "prep", "raft" })
			t.expect(models.settings({ root, item }).autoMerge).toEqual({})
			t.expect(models.settings({ root, item }).toolSeconds).toBe(600)
			t.expect(models.settings({}).autoMerge).toEqual({})
			t.expect(models.settings({}).stallSeconds).toBe(300)
			t.expect(models.settings({}).toolSeconds).toBe(900)
			t.expect(has(
				errorOf(function()
					layer('[dispatch]\nauto_merge = ["run"]\n')
				end),
				"only prep, raft"
			)).toBe(true)
		end
	)

	it("tries are the role's CLI, then its fallbacks", function()
		local r = models.resolve({ layer(ROOT) }, "z-design")
		local clis = {}
		for _, s in models.tries(r) do
			table.insert(clis, s.cli)
		end
		t.expect(clis).toEqual({ "claude", "kimi", "grok" })
	end)

	it("the higher rank wins whole, with its own cap", function()
		local strong = spec("claude", 3, 1000, "strong")
		local weak = spec("claude", 2, 900000, "weak")
		local best = models.strongest({ weak, strong })
		t.expect(best.model).toBe("strong")
		t.expect(best.maxTokens).toBe(1000)
	end)

	it("the same rank takes the larger max_tokens, and its model with it; a tie keeps the first", function()
		local a = spec("grok", 2, 1000, "a")
		local b = spec("grok", 2, 5000, "b")
		t.expect(models.strongest({ a, b }).model).toBe("b")
		t.expect(models.strongest({ b, a }).model).toBe("b")
		local c = spec("grok", 2, 5000, "c")
		t.expect(models.strongest({ b, c }).model).toBe("b")
		t.expect(has(
			errorOf(function()
				models.strongest({})
			end),
			"no specs"
		)).toBe(true)
	end)

	it("a raft takes, per CLI, the stronger of its members' specs, in the raft's own try list", function()
		local root = layer(ROOT, ".models.toml")
		local cheap =
			models.resolve({ root, layer("[roles.design]\nrank = 1\nmax_tokens = 10\n") }, "z-design")
		local rich = models.resolve({ root }, "z-design")
		local r = models.forRaft(rich, { cheap, rich })
		t.expect(r.specs.claude.rank).toBe(3)
		t.expect(r.specs.claude.maxTokens).toBe(300000)
		t.expect(r.order).toEqual({ "claude", "kimi", "grok" })
		local low = models.forRaft(rich, { cheap, cheap })
		t.expect(low.specs.claude.maxTokens).toBe(10)
		t.expect(has(
			errorOf(function()
				models.forRaft(rich, {})
			end),
			"no member"
		)).toBe(true)
	end)

	it("refuses a CLI the file does not support, in a role or in its fallbacks", function()
		local e = errorOf(function()
			layer('[roles.design]\ncli = "codex"\n')
		end)
		t.expect(has(e, "codex is not a supported CLI") or has(e, "not a supported CLI")).toBe(true)
		t.expect(has(e, "x/.models.toml")).toBe(true)
		t.expect(has(
			errorOf(function()
				layer('[roles.design]\nfallbacks = ["cursor"]\n')
			end),
			"not a supported CLI"
		)).toBe(true)
		t.expect(has(
			errorOf(function()
				layer('[roles.design]\nfallbacks = ["claude", "claude"]\n')
			end),
			"twice"
		)).toBe(true)
	end)

	it("order and a skill table are refused at load, and so is a fallback's rank, cap or effort", function()
		t.expect(has(
			errorOf(function()
				layer('order = ["claude", "grok"]\n')
			end),
			"order is gone"
		)).toBe(true)
		t.expect(has(
			errorOf(function()
				layer('[z-design.claude]\nmodel = "claude-opus-5-5"\n')
			end),
			"skill tables are gone"
		)).toBe(true)
		t.expect(has(
			errorOf(function()
				layer(
					'[fallback.kimi]\nmodel = "kimi-code-k3.1-pro"\nruntime = "kimi-cli"\nmax_tokens = 300000\n'
				)
			end),
			"fallback.kimi.max_tokens belongs to the role, not the fallback"
		)).toBe(true)
		t.expect(has(
			errorOf(function()
				layer('[fallback.grok]\nmodel = "grok-4.7"\nruntime = "grok-cli"\neffort = "high"\n')
			end),
			"fallback.grok.effort belongs to the role, not the fallback"
		)).toBe(true)
	end)

	it("a runtime belongs to its CLI: each CLI's one local runtime, and no other", function()
		local modelOf = {
			claude = "claude-opus-5-5",
			grok = "grok-4.7",
			kimi = "kimi-code-k3.1-pro",
			agent = "claude-opus-5-5",
		}
		for cli, runtimes in models.RUNTIMES do
			for _, rt in runtimes do
				local model = modelOf[cli]
				if cli == "claude" then
					layer(`[roles.design]\ncli = "claude"\nmodel = "{model}"\nruntime = "{rt}"\n`)
				else
					layer(`[fallback.{cli}]\nmodel = "{model}"\nruntime = "{rt}"\n`)
				end
			end
		end
		t.expect(models.RUNTIMES).toEqual({
			claude = { "claude-cli" },
			grok = { "grok-cli" },
			agent = { "cursor-cli" },
			kimi = { "kimi-cli" },
		})
		t.expect(has(
			errorOf(function()
				layer('[roles.design]\ncli = "claude"\nmodel = "claude-opus-5-5"\nruntime = "claude-cloud"\n')
			end),
			"not a runtime of claude"
		)).toBe(true)
		t.expect(has(
			errorOf(function()
				layer('[fallback.grok]\nmodel = "grok-4.7"\nruntime = "cursor-cli"\n')
			end),
			"not a runtime of grok"
		)).toBe(true)
	end)

	it("a spec missing a field is an error naming the role and the field", function()
		local e = errorOf(function()
			models.resolve({
				layer(
					'[roles.design]\nmodel = "claude-opus-5-5"\ncli = "claude"\nruntime = "claude-cli"\nmax_tokens = 5\n'
				),
			}, "z-design")
		end)
		t.expect(has(e, "roles.design has no rank")).toBe(true)
		t.expect(has(
			errorOf(function()
				layer("[roles.design]\ntemperature = 1\n")
			end),
			"roles.design.temperature is not a field"
		)).toBe(true)
		t.expect(has(
			errorOf(function()
				layer("[roles.design]\nrank = 2.5\n")
			end),
			"whole number"
		)).toBe(true)
	end)

	it("agent's specs need max_calls and max_minutes, never unlimited; the other CLIs' don't", function()
		local base =
			'[roles.design]\nmodel = "claude-opus-5-5"\ncli = "agent"\nruntime = "cursor-cli"\nrank = 1\nmax_tokens = 5\n'
		local e = errorOf(function()
			models.resolve({ layer(base) }, "z-design")
		end)
		t.expect(has(e, "no max_calls")).toBe(true)
		t.expect(has(e, "calls are not tokens")).toBe(true)
		t.expect(has(
			errorOf(function()
				models.resolve({ layer(base .. "max_calls = 30\n") }, "z-design")
			end),
			"no max_minutes"
		)).toBe(true)
		local r = models.resolve({ layer(base .. "max_calls = 30\nmax_minutes = 60\n") }, "z-design")
		t.expect(r.specs.agent.maxCalls).toBe(30)
		t.expect(r.specs.agent.maxMinutes).toBe(60)
		t.expect(models.resolve({ layer(ROOT) }, "z-design").specs.claude.maxCalls).toBe(nil)
		t.expect(has(
			errorOf(function()
				layer("[roles.design]\nmax_calls = 0\n")
			end),
			"whole number"
		)).toBe(true)
	end)

	it(
		"nothing defaults: no file, a role no file names, or a skill that is not a step is an error naming it",
		function()
			t.expect(has(
				errorOf(function()
					models.resolve({}, "z-design")
				end),
				"nothing defaults"
			)).toBe(true)
			t.expect(has(
				errorOf(function()
					models.resolve({ layer("[dispatch]\nstall_seconds = 300\n") }, "z-design")
				end),
				"names role design"
			)).toBe(true)
			t.expect(has(
				errorOf(function()
					models.resolve({ layer(ROOT) }, "z-ready")
				end),
				"z-ready is not a model step"
			)).toBe(true)
		end
	)

	it("a repeated table or key is the reader's error, never a silent pick", function()
		local e = errorOf(function()
			layer("[roles.design]\nrank = 1\n[roles.design]\nrank = 2\n")
		end)
		t.expect(has(e, "x/.models.toml")).toBe(true)
		t.expect(has(e, "duplicate")).toBe(true)
	end)

	it("the model id a row records carries its effort", function()
		local s = spec("grok", 4, 9, "grok-4.7")
		t.expect(models.id(s)).toBe("grok-4.7")
		s.effort = "xhigh"
		t.expect(models.id(s)).toBe("grok-4.7-xhigh")
	end)

	it("walks from the repository root down to the folder, root first", function()
		t.expect(models.folders("pickman/.tracker/issues/c0010")).toEqual({
			".",
			"pickman",
			"pickman/.tracker",
			"pickman/.tracker/issues",
			"pickman/.tracker/issues/c0010",
		})
		t.expect(models.folders(".")).toEqual({ "." })
	end)

	it("the root .models.toml resolves every model step, and a fallback carries the role's cap", function()
		local layers = { models.parse(fs.readFile(`{TOP}/.models.toml`), ".models.toml") }
		for _, skill in { "z-ticket", "z-design", "z-raft", "z-run", "zz-review" } do
			local r = models.resolve(layers, skill)
			t.expect(r.fromRoles).toBe(true)
			for _, cli in { "claude", "kimi", "grok", "agent" } do
				t.expect(r.specs[cli] ~= nil).toBe(true)
			end
			t.expect(#models.tries(r)).toBe(4)
		end
		local idea = models.resolve(layers, "z-ticket")
		t.expect(idea.specs.claude.model).toBe("claude-fable-5-2")
		t.expect(idea.specs.claude.effort).toBe("medium")
		local run = models.resolve(layers, "z-run")
		t.expect(run.specs.claude.model).toBe("claude-sonnet-5-5")
		t.expect(run.specs.kimi.maxTokens).toBe(12000000)
		t.expect(run.specs.kimi.effort).toBe("high")
		t.expect(run.specs.kimi.rank).toBe(3)
		t.expect(run.specs.grok.maxTokens).toBe(12000000)
		t.expect(run.specs.agent.maxCalls).toBe(200)
		local review = models.resolve(layers, "zz-review")
		t.expect(review.specs.grok.effort).toBe("xhigh")
		t.expect(review.specs.grok.maxTokens).toBe(2000000)
		t.expect(review.specs.grok.rank).toBe(4)
		t.expect(models.roleFor("zz-review", "raft")).toBe("raft")
		t.expect(models.roleFor("zz-review", "design")).toBe("design-challenge")
	end)
end)
