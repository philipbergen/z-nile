--!strict
-- c0175 AC1 and AC2: `agy` and `opencode` are supported CLIs in `.models.toml` (their runtimes, their model ids, a wrong-CLI id
-- or runtime refused when the file loads), and an agy try runs at an effort the model offers, so `models.id` records the effort
-- that ran. Pure: texts in, results out. New exports are read through `any`.
local models = require("@znile/engine/models")
local t = require("@tests/lib/t")

local M: any = models

local function has(s: string, part: string): boolean
	return string.find(s, part, 1, true) ~= nil
end
local function errorOf(fn: () -> ()): string
	local ok: boolean, e: any = pcall(fn)
	if ok then
		error("expected an error", 2)
	end
	return tostring(e)
end
local function layer(text: string): any
	return M.parse(text, ".models.toml")
end

local ROLE =
	'[roles.design]\nmodel = "claude-opus-5-5"\ncli = "claude"\nruntime = "claude-cli"\nrank = 4\nmax_tokens = 5000\neffort = "xhigh"\nfallbacks = ["agy", "opencode"]\n'

return t.spec("c0175 agy and opencode in .models.toml", function(it)
	it("AC1: models.CLIS lists agy and opencode, each with its one local runtime", function()
		t.expect(table.find(M.CLIS, "agy") ~= nil).toBe(true)
		t.expect(table.find(M.CLIS, "opencode") ~= nil).toBe(true)
		-- the four before them are as they were
		for _, cli in { "claude", "grok", "agent", "kimi" } do
			t.expect(table.find(M.CLIS, cli) ~= nil).toBe(true)
		end
		t.expect(M.RUNTIMES.agy).toEqual({ "agy-cli" })
		t.expect(M.RUNTIMES.opencode).toEqual({ "opencode-cli" })
	end)

	it(
		"AC1: parse accepts agy's gemini-, claude- and gpt- ids and opencode's opencode-<provider>-<model> ids",
		function()
			local text = table.concat({
				ROLE,
				'[fallback.agy]\nmodel = "claude-opus-5-5"\nruntime = "agy-cli"\n',
				'[fallback.opencode]\nmodel = "opencode-deepseek-deepseek-v4-pro"\nruntime = "opencode-cli"\n',
				'[member.flash]\ncli = "agy"\nmodel = "gemini-3.8-flash"\nruntime = "agy-cli"\n',
				'[member.oss]\ncli = "agy"\nmodel = "gpt-oss-120b"\nruntime = "agy-cli"\n',
				'[member.grokish]\ncli = "opencode"\nmodel = "opencode-xai-grok-4.7"\nruntime = "opencode-cli"\n',
				'[member.zen]\ncli = "opencode"\nmodel = "opencode-opencode-big-pickle"\nruntime = "opencode-cli"\n',
				'[member.copilot]\ncli = "opencode"\nmodel = "opencode-github_copilot-gpt-5"\nruntime = "opencode-cli"\n',
			}, "\n")
			local l = layer(text)
			t.expect(l.fallbacks.agy.model).toBe("claude-opus-5-5")
			t.expect(l.fallbacks.opencode.runtime).toBe("opencode-cli")
			t.expect(l.members.flash.cli).toBe("agy")
			t.expect(l.members.copilot.model).toBe("opencode-github_copilot-gpt-5")
			t.expect(l.roles.design.fallbacks).toEqual({ "agy", "opencode" })
		end
	)

	it(
		"AC1: parse refuses another CLI's model or runtime on agy and opencode, naming the file and the key",
		function()
			local bad: { { string } } = {
				{
					'[fallback.agy]\nmodel = "kimi-code-k3.1-pro"\nruntime = "agy-cli"\n',
					"fallback.agy.model is kimi-code-k3.1-pro, not a model of cli agy",
				},
				{ '[fallback.agy]\nmodel = "grok-4.7"\nruntime = "agy-cli"\n', "not a model of cli agy" },
				{
					'[fallback.agy]\nmodel = "claude-opus-5-5"\nruntime = "cursor-cli"\n',
					"not a runtime of agy",
				},
				{
					'[fallback.agy]\nmodel = "claude-opus-5-5"\nruntime = "opencode-cli"\n',
					"not a runtime of agy",
				},
				{
					'[fallback.opencode]\nmodel = "deepseek-v4-pro"\nruntime = "opencode-cli"\n',
					"not a model of cli opencode",
				},
				{
					'[fallback.opencode]\nmodel = "claude-opus-5-5"\nruntime = "opencode-cli"\n',
					"not a model of cli opencode",
				},
				{
					'[fallback.opencode]\nmodel = "opencode-deepseek"\nruntime = "opencode-cli"\n',
					"not a model of cli opencode",
				},
				{
					'[fallback.opencode]\nmodel = "opencode-deepseek-deepseek-v4-pro"\nruntime = "agy-cli"\n',
					"not a runtime of opencode",
				},
				{
					'[member.x]\ncli = "agy"\nmodel = "opencode-xai-grok-4.7"\nruntime = "agy-cli"\n',
					"not a model of cli agy",
				},
				{
					'[roles.design]\ncli = "opencode"\nmodel = "gemini-3.8-flash"\nruntime = "opencode-cli"\n',
					"not a model of cli opencode",
				},
				{
					'[roles.design]\nfallbacks = ["gemini"]\n',
					"not a supported CLI (claude, grok, agent, kimi, agy, opencode)",
				},
			}
			for _, case in bad do
				local e = errorOf(function()
					layer(case[1])
				end)
				if not (has(e, case[2]) and has(e, ".models.toml")) then
					error(`expected {case[2]}, got: {e}`, 0)
				end
			end
		end
	)

	it("AC2: effortFor lowers agy's effort to the highest the model offers: Opus tops out at high", function()
		t.expect(M.effortFor("agy", "claude-opus-5-5", "xhigh")).toBe("high")
		t.expect(M.effortFor("agy", "claude-opus-5-5", "max")).toBe("high")
		t.expect(M.effortFor("agy", "claude-opus-5-5", "high")).toBe("high")
		t.expect(M.effortFor("agy", "claude-opus-5-5", "medium")).toBe("medium")
		t.expect(M.effortFor("agy", "claude-sonnet-5-5", "xhigh")).toBe("high")
		t.expect(M.effortFor("agy", "gemini-4-hydrogen", "xhigh")).toBe("xhigh")
		t.expect(M.effortFor("agy", "gemini-4-hydrogen", "max")).toBe("xhigh")
		t.expect(M.effortFor("agy", "gemini-4-argon", "xhigh")).toBe("high")
		t.expect(M.effortFor("agy", "gemini-3.8-flash", "xhigh")).toBe("high")
		t.expect(M.effortFor("agy", "gpt-oss-120b", "xhigh")).toBe("medium")
		t.expect(M.effortFor("agy", "gpt-oss-120b", "low")).toBe("medium")
	end)

	it(
		"AC2: effortFor gives a model that offers none no effort, and leaves other CLIs and unknown models alone",
		function()
			t.expect(M.effortFor("agy", "gemini-pro-orchestrator-g1-pro", "high")).toBe(nil)
			t.expect(M.effortFor("agy", "claude-opus-5-5", nil)).toBe(nil)
			t.expect(M.effortFor("agy", "gemini-9-new", "xhigh")).toBe("xhigh")
			t.expect(M.effortFor("agy", "claude-opus-5-5", "turbo")).toBe("turbo")
			for _, cli in { "claude", "grok", "agent", "kimi", "opencode" } do
				t.expect(M.effortFor(cli, "claude-opus-5-5", "xhigh")).toBe("xhigh")
				t.expect(M.effortFor(cli, "claude-opus-5-5", "max")).toBe("max")
			end
		end
	)

	it(
		"AC2: a try on agy carries the lowered effort, so the spend row's model id records what ran",
		function()
			local text = table.concat({
				ROLE,
				'[fallback.agy]\nmodel = "claude-opus-5-5"\nruntime = "agy-cli"\n',
				'[fallback.opencode]\nmodel = "opencode-deepseek-deepseek-v4-pro"\nruntime = "opencode-cli"\n',
				'[roles.design-challenge]\nmodel = "claude-opus-5-5"\ncli = "claude"\nruntime = "claude-cli"\nrank = 4\nmax_tokens = 5000\neffort = "xhigh"\npool = ["flash"]\nfallbacks = ["agy"]\n',
				'[member.flash]\ncli = "agy"\nmodel = "gemini-3.8-flash"\nruntime = "agy-cli"\n',
			}, "\n")
			local layers = { layer(text) }
			local tries = M.tries(M.resolve(layers, "z-design"))
			t.expect(#tries).toBe(3)
			t.expect(tries[1].cli).toBe("claude")
			t.expect(M.id(tries[1])).toBe("claude-opus-5-5-xhigh") -- claude takes xhigh as it is
			t.expect(tries[2].cli).toBe("agy")
			t.expect(tries[2].effort).toBe("high")
			t.expect(M.id(tries[2])).toBe("claude-opus-5-5-high")
			t.expect(tries[3].cli).toBe("opencode")
			t.expect(M.id(tries[3])).toBe("opencode-deepseek-deepseek-v4-pro-xhigh")
			-- a pool member on agy is lowered the same way
			local review = M.tries(M.resolve(layers, "zz-review", "design"))
			t.expect(#review).toBe(3)
			t.expect(review[2].cli).toBe("agy")
			t.expect(review[2].model).toBe("gemini-3.8-flash")
			t.expect(M.id(review[2])).toBe("gemini-3.8-flash-high")
			t.expect(M.id(review[3])).toBe("claude-opus-5-5-high")
		end
	)

	it("AC2: an agy role of its own is lowered the same way", function()
		local l = layer(
			'[roles.design]\nmodel = "claude-opus-5-5"\ncli = "agy"\nruntime = "agy-cli"\nrank = 4\nmax_tokens = 5000\neffort = "max"\n'
		)
		local r = M.resolve({ l }, "z-design")
		t.expect(M.id(r.specs.agy)).toBe("claude-opus-5-5-high")
	end)
end)
