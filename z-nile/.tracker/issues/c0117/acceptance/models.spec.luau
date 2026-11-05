--!strict
-- c0117 AC1, AC2: .models.toml stacks like .gitignore (a closer file replaces only the keys it sets), a raft takes the
-- stronger spec whole per CLI (higher rank, then larger max_tokens), only the three CLIs and their runtimes exist,
-- nothing defaults, and the review model belongs to the CLI. Pure: models.parse and models.resolve over layers built
-- from text; one case reads the real root .models.toml.
local fs = require("@lune/fs")
local models = require("@znile/engine/models")
local t = require("@tests/lib/t")
-- c0117 runs from its project's home, z-nile/ (c0120): every path of the real tree this spec reads is the
-- repository's, from its top
local TOP = (
	string.gsub(require("@lune/process").exec("git", { "rev-parse", "--show-toplevel" }).stdout, "%s+$", "")
)

local ROOT = [[
order = ["claude", "grok", "agent"]

[dispatch]
stall_seconds = 300

[z-design.claude]
model = "claude-opus-5-5"
rank = 3
runtime = "claude-cli"
max_tokens = 300000

[z-design.grok]
model = "grok-4.7"
effort = "high"
rank = 2
runtime = "grok-cli"
max_tokens = 200000

[zz-review.claude]
model = "claude-opus-5-5"
rank = 4
runtime = "claude-cli"
max_tokens = 100000
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
	it(
		"a closer file replaces only the keys it sets: max_tokens closer, model and rank from the root",
		function()
			local closer = layer("[z-design.claude]\nmax_tokens = 1000\n", "pickman/.models.toml")
			local r = models.resolve({ layer(ROOT, ".models.toml"), closer }, "z-design")
			local c = r.specs.claude
			t.expect(c.maxTokens).toBe(1000)
			t.expect(c.model).toBe("claude-opus-5-5")
			t.expect(c.rank).toBe(3)
			t.expect(c.runtime).toBe("claude-cli")
			-- the CLI the closer file did not name keeps the root's whole spec
			t.expect(r.specs.grok.maxTokens).toBe(200000)
			t.expect(r.specs.grok.effort).toBe("high")
			-- the walk's order and settings come from the root
			t.expect(r.order).toEqual({ "claude", "grok", "agent" })
			t.expect(r.settings.stallSeconds).toBe(300)
		end
	)

	it("a closer order replaces the root's whole, and each setting is replaced on its own", function()
		local closer = layer('order = ["grok"]\n[dispatch]\nauto_merge = ["prep"]\n')
		local r = models.resolve({ layer(ROOT, ".models.toml"), closer }, "z-design")
		t.expect(r.order).toEqual({ "grok" })
		t.expect(r.settings.autoMerge).toEqual({ "prep" })
		t.expect(r.settings.stallSeconds).toBe(300)
		local tries = models.tries(r)
		t.expect(#tries).toBe(1)
		t.expect(tries[1].cli).toBe("grok")
	end)

	it(
		"settings come from the walk, closest first; an unset auto_merge is none, and so is any error",
		function()
			local root =
				layer('order = ["claude"]\n[dispatch]\nauto_merge = ["prep", "raft"]\ntool_seconds = 600\n')
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

	it("tries the CLIs of the order that name the skill, in the order's order", function()
		local r = models.resolve(
			{ layer('order = ["agent", "grok", "claude"]\n' .. string.gsub(ROOT, "^order[^\n]*\n", "")) },
			"z-design"
		)
		local clis = {}
		for _, s in models.tries(r) do
			table.insert(clis, s.cli)
		end
		t.expect(clis).toEqual({ "grok", "claude" })
		local only = models.resolve({
			layer(
				'order = ["agent"]\n[z-design.claude]\nmodel = "m"\nrank = 1\nruntime = "claude-cli"\nmax_tokens = 5\n'
			),
		}, "z-design")
		t.expect(has(
			errorOf(function()
				models.tries(only)
			end),
			"z-design"
		)).toBe(true)
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

	it("a raft takes, per CLI, the stronger of its members' specs, in the raft's own order", function()
		local root = layer(ROOT, ".models.toml")
		local cheap =
			models.resolve({ root, layer("[z-design.claude]\nrank = 1\nmax_tokens = 10\n") }, "z-design")
		local rich = models.resolve({ root }, "z-design")
		local own = models.resolve({ root, layer('order = ["grok", "claude"]\n') }, "z-design")
		local r = models.forRaft(own, { cheap, rich })
		t.expect(r.specs.claude.rank).toBe(3)
		t.expect(r.specs.claude.maxTokens).toBe(300000)
		t.expect(r.order).toEqual({ "grok", "claude" })
		-- a closer file can lower its own members' caps when every member shares it
		local low = models.forRaft(own, { cheap, cheap })
		t.expect(low.specs.claude.maxTokens).toBe(10)
		t.expect(has(
			errorOf(function()
				models.forRaft(own, {})
			end),
			"no member"
		)).toBe(true)
	end)

	it("refuses a CLI the file does not support, in a table or in the order", function()
		local e = errorOf(function()
			layer('[z-design.codex]\nmodel = "x"\n')
		end)
		t.expect(has(e, "codex is not a supported CLI")).toBe(true)
		t.expect(has(e, "x/.models.toml")).toBe(true)
		t.expect(has(
			errorOf(function()
				layer('order = ["claude", "cursor"]\n')
			end),
			"cursor, which is not a supported CLI"
		)).toBe(true)
		t.expect(has(
			errorOf(function()
				layer('order = ["claude", "claude"]\n')
			end),
			"twice"
		)).toBe(true)
	end)

	it("a runtime belongs to its CLI: each CLI's two runtimes, and no other", function()
		for cli, runtimes in models.RUNTIMES do
			for _, rt in runtimes do
				layer(`[z-design.{cli}]\nruntime = "{rt}"\n`)
			end
		end
		t.expect(models.RUNTIMES).toEqual({
			claude = { "claude-cli", "claude-cloud" },
			grok = { "grok-cli", "grok-bot" },
			agent = { "cursor-cli", "cursor-app" },
		})
		t.expect(has(
			errorOf(function()
				layer('[z-design.grok]\nruntime = "cursor-cli"\n')
			end),
			"not a runtime of grok"
		)).toBe(true)
	end)

	it("a spec missing a field is an error naming the skill, the CLI and the field", function()
		local e = errorOf(function()
			models.resolve({
				layer(
					'order = ["claude"]\n[z-design.claude]\nmodel = "m"\nruntime = "claude-cli"\nmax_tokens = 5\n'
				),
			}, "z-design")
		end)
		t.expect(has(e, "z-design.claude: no rank")).toBe(true)
		t.expect(has(
			errorOf(function()
				layer("[z-design.claude]\ntemperature = 1\n")
			end),
			"z-design.claude.temperature is not a field"
		)).toBe(true)
		t.expect(has(
			errorOf(function()
				layer("[z-design.claude]\nrank = 2.5\n")
			end),
			"whole number"
		)).toBe(true)
	end)

	it("agent's specs need max_calls and max_minutes, never unlimited; the other CLIs' don't", function()
		local base =
			'order = ["agent", "claude"]\n[z-design.agent]\nmodel = "m"\nrank = 1\nruntime = "cursor-cli"\nmax_tokens = 5\n'
		local e = errorOf(function()
			models.resolve({ layer(base) }, "z-design")
		end)
		t.expect(has(e, "z-design.agent: no max_calls")).toBe(true)
		t.expect(has(e, "calls are not tokens")).toBe(true)
		-- and a wall-time ceiling beside it (review 003 F7)
		t.expect(has(
			errorOf(function()
				models.resolve({ layer(base .. "max_calls = 30\n") }, "z-design")
			end),
			"z-design.agent: no max_minutes"
		)).toBe(true)
		local r = models.resolve({ layer(base .. "max_calls = 30\nmax_minutes = 60\n") }, "z-design")
		t.expect(r.specs.agent.maxCalls).toBe(30)
		t.expect(r.specs.agent.maxMinutes).toBe(60)
		t.expect(models.resolve({ layer(ROOT) }, "z-design").specs.claude.maxCalls).toBe(nil)
		t.expect(has(
			errorOf(function()
				layer("[z-design.agent]\nmax_calls = 0\n")
			end),
			"whole number"
		)).toBe(true)
	end)

	it("nothing defaults: no file, no order, or a skill no file names is an error naming it", function()
		t.expect(has(
			errorOf(function()
				models.resolve({}, "z-design")
			end),
			"nothing defaults"
		)).toBe(true)
		t.expect(has(
			errorOf(function()
				models.resolve({
					layer(
						'[z-design.claude]\nmodel = "m"\nrank = 1\nruntime = "claude-cli"\nmax_tokens = 5\n'
					),
				}, "z-design")
			end),
			"no order"
		)).toBe(true)
		t.expect(has(
			errorOf(function()
				models.resolve({ layer(ROOT) }, "z-run")
			end),
			"names z-run"
		)).toBe(true)
	end)

	it("a repeated table or key is the reader's error, never a silent pick", function()
		local e = errorOf(function()
			layer("[z-design.claude]\nrank = 1\n[z-design.claude]\nrank = 2\n")
		end)
		t.expect(has(e, "x/.models.toml")).toBe(true)
		t.expect(has(e, "duplicate")).toBe(true)
	end)

	it(
		"the review model belongs to the CLI: Opus through claude and agent, grok-4.7 at xhigh through grok",
		function()
			local function review(cli: string, model: string, effort: string?): string?
				local text =
					`order = ["{cli}"]\n[zz-review.{cli}]\nmodel = "{model}"\nrank = 4\nruntime = "{models.RUNTIMES[cli][1]}"\nmax_tokens = 9\nmax_calls = 9\nmax_minutes = 9\n`
				if effort then
					text ..= `effort = "{effort}"\n`
				end
				local ok, e = pcall(models.resolve, { layer(text) }, "zz-review")
				return if ok then nil else tostring(e)
			end
			t.expect(review("claude", "claude-opus-5-5")).toBe(nil)
			t.expect(review("agent", "claude-opus-5-5-high")).toBe(nil)
			t.expect(review("grok", "grok-4.7", "xhigh")).toBe(nil)
			t.expect(has(review("claude", "claude-sonnet-5") or "", "runs on Opus")).toBe(true)
			t.expect(has(review("agent", "grok-4.7-xhigh") or "", "runs on Opus")).toBe(true)
			t.expect(has(review("grok", "grok-4.7", "high") or "", "grok-4.7-xhigh")).toBe(true)
			t.expect(has(review("grok", "grok-4.6", "xhigh") or "", "grok-4.7-xhigh")).toBe(true)
			-- the rule is the review's alone: an author may run on any model
			t.expect(models.reviewRule("z-design", spec("claude", 1, 1, "claude-sonnet-5"))).toBe(nil)
		end
	)

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

	it("the root .models.toml resolves every model step on all three CLIs", function()
		local layers = { models.parse(fs.readFile(`{TOP}/.models.toml`), ".models.toml") }
		for _, skill in { "z-ticket", "z-design", "z-raft", "z-run", "zz-review" } do
			local r = models.resolve(layers, skill)
			for _, cli in models.CLIS do
				t.expect(r.specs[cli] ~= nil).toBe(true)
			end
			t.expect(#models.tries(r)).toBe(3)
		end
	end)
end)
