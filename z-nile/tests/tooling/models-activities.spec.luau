--!strict
-- f0421 slice 2, step 5 (A): `[clis.<cli>]` and `[activities.<a>]` parse, and `models.config`, `resolveActivity`, `can`,
-- `canList`, `need`, `sameModel` and `activityFor` resolve them. Pure: texts in, results out. It reads the root
-- `.models.toml` (still the legacy tables: step 8 adds the seed) for the legacy derivation and the three file shapes.
-- `models.resolve` is still the role lookup the dispatcher calls (step 6 moves it), so the activity lookup is
-- `resolveActivity`.
local fs = require("@lune/fs")
local models = require("@znile/engine/models")
local process = require("@lune/process")
local t = require("@tests/lib/t")

local TOP = (string.gsub(process.exec("git", { "rev-parse", "--show-toplevel" }).stdout, "%s+$", ""))

local function has(s: string, part: string): boolean
	return string.find(s, part, 1, true) ~= nil
end

-- The design's seed (step 8's content), as a text here: claude has all four aliases, grok only light, agent and kimi only heavy.
local CLIS = [[
[clis.claude]
xlight = { model = "claude-haiku-5-5", effort = "low" }
light = { model = "claude-sonnet-5-5", effort = "medium" }
heavy = { model = "claude-opus-5-5", effort = "high" }
ultra = { model = "claude-fable-5-2", effort = "xhigh", context = 1000000 }
[clis.grok]
light = { model = "grok-4.7", effort = "high" }
[clis.agent]
heavy = { model = "claude-opus-5-5", effort = "high" }
max_calls = 200
max_minutes = 240
[clis.kimi]
heavy = { model = "kimi-code-k3.1-pro" }
]]
local ACTIVITIES = [[
[activities.idea]
max_tokens = 300000
all = "heavy"
[activities.idea-challenge]
max_tokens = 300000
all = "ultra"
[activities.design]
max_tokens = 3000000
easy = "xlight"
normal = "light"
risky = "heavy"
[activities.design-review]
max_tokens = 3000000
easy = "light"
normal = "heavy"
risky = "ultra"
[activities.raft]
max_tokens = 3000000
easy = "xlight"
normal = "light"
risky = "heavy"
[activities.raft-review]
max_tokens = 3000000
easy = "light"
normal = "heavy"
risky = "ultra"
[activities.code]
max_tokens = 12000000
easy = "xlight"
normal = "light"
risky = "heavy"
[activities.code-review]
max_tokens = 2000000
easy = "light"
normal = "heavy"
risky = "ultra"
[activities.final-review]
max_tokens = 2000000
all = "ultra"
[activities.approve]
max_tokens = 3000000
all = "heavy"
]]
local SEED = CLIS .. ACTIVITIES

local function layer(text: string, path: string?): models.Layer
	return models.parse(text, path or ".models.toml")
end

local function rejects(text: string, want: string)
	local ok, err = pcall(function()
		models.config({ layer(text) })
	end)
	t.expect(ok).toBe(false)
	if not has(tostring(err), want) then
		error(`wanted {want}, got {tostring(err)}`, 2)
	end
end

-- `text` with `from` replaced by `to` (it must occur).
local function replaceIn(text: string, from: string, to: string): string
	local at = string.find(text, from, 1, true)
	if not at then
		error(`no {from}`, 3)
	end
	return string.sub(text, 1, at - 1) .. to .. string.sub(text, at + #from)
end

-- SEED with `from` replaced by `to` (it must occur).
local function seedWith(from: string, to: string): string
	return replaceIn(SEED, from, to)
end

local function root(): string
	return fs.readFile(`{TOP}/.models.toml`)
end

return t.spec("f0421 slice 2: aliases and models per activity (parse, config, resolve)", function(it)
	it("AC17: [clis] and [activities] parse; a CLI with only some aliases is valid", function()
		local l = layer(SEED)
		t.expect(l.hasActivities).toBe(true)
		t.expect(l.clis.claude.ultra.context).toBe(1000000)
		t.expect(l.clis.grok.heavy).toBe(nil)
		t.expect(l.clis.agent.max_calls).toBe(200)
		t.expect(l.activities.code.risky.alias).toBe("heavy")
		t.expect(l.activities.code.max_tokens).toBe(12000000)
		local specific = layer(`{SEED}\n`, "x")
		t.expect(specific.path).toBe("x")
		local cfg = models.config({ l })
		t.expect(cfg.legacy).toBe(false)
		t.expect(cfg.clis.grok.aliases.light.model).toBe("grok-4.7")
		t.expect(cfg.clis.grok.aliases.heavy).toBe(nil)
		t.expect(cfg.clis.claude.runtime).toBe("claude-cli")
	end)

	it("AC17: the three file shapes parse: legacy only, both, new only", function()
		local legacy = layer(root())
		t.expect(legacy.hasActivities).toBe(false)
		t.expect(legacy.roles.design ~= nil).toBe(true)
		local both = layer(`{root()}\n{SEED}`)
		t.expect(both.hasActivities).toBe(true)
		t.expect(both.roles.design ~= nil).toBe(true)
		t.expect(both.clis.claude.light.model).toBe("claude-sonnet-5-5")
		local only = layer(SEED)
		t.expect((next(only.roles))).toBe(nil)
		-- the walk with both uses the new tables; roles and fallbacks are ignored
		local spec = models.resolveActivity({ both }, "claude", "design", "easy")
		t.expect((spec :: models.Spec).model).toBe("claude-haiku-5-5")
		-- the root file today carries neither new table: older engines refuse them, so step 8 waits (the rollout)
		t.expect(has(root(), "[clis")).toBe(false)
		t.expect(has(root(), "[activities")).toBe(false)
	end)

	it("AC17: an unknown table names clis, activities, dispatch and rounds", function()
		local ok, err = pcall(function()
			models.parse("[nope]\nx = 1\n", ".models.toml")
		end)
		t.expect(ok).toBe(false)
		t.expect(has(tostring(err), "clis, activities")).toBe(true)
		t.expect(has(tostring(err), "dispatch and rounds")).toBe(true)
	end)

	it("AC18: resolve gives an alias's model, effort and context, and nil with why otherwise", function()
		local l = layer(SEED)
		local spec = models.resolveActivity({ l }, "claude", "code-review", "normal") :: models.Spec
		t.expect(spec.model).toBe("claude-opus-5-5")
		t.expect(spec.effort).toBe("high")
		t.expect(spec.alias).toBe("heavy")
		t.expect(spec.runtime).toBe("claude-cli")
		t.expect(spec.maxTokens).toBe(2000000)
		local ultra = models.resolveActivity({ l }, "claude", "final-review", "risky") :: models.Spec
		t.expect(ultra.context).toBe(1000000)
		-- a nil level is normal
		local nilLevel = models.resolveActivity({ l }, "claude", "code-review", nil) :: models.Spec
		t.expect(nilLevel.alias).toBe("heavy")
		-- a CLI without the alias
		local none, why = models.resolveActivity({ l }, "grok", "code-review", "normal")
		t.expect(none).toBe(nil)
		t.expect(why).toBe("grok does not define heavy")
		local light = models.resolveActivity({ l }, "grok", "code", "normal") :: models.Spec
		t.expect(light.model).toBe("grok-4.7")
		-- agent keeps its caps
		local agent = models.resolveActivity({ l }, "agent", "approve", "easy") :: models.Spec
		t.expect(agent.maxCalls).toBe(200)
		t.expect(agent.maxMinutes).toBe(240)
		-- the writer's setting serves the answer, trace and fix activities
		local answer = models.resolveActivity({ l }, "claude", "design-answer", "risky") :: models.Spec
		t.expect(answer.alias).toBe("heavy")
		t.expect((models.resolveActivity({ l }, "claude", "fix", "easy") :: models.Spec).alias).toBe("xlight")
	end)

	it("AC18: a specific model resolves with its own effort and context on a CLI that has it", function()
		local text = seedWith(
			'risky = "heavy"\n[activities.design-review]',
			'risky = { model = "claude-opus-5-5", effort = "xhigh", context = 500000 }\n[activities.design-review]'
		)
		local l = layer(text)
		local spec = models.resolveActivity({ l }, "claude", "design", "risky") :: models.Spec
		t.expect(spec.model).toBe("claude-opus-5-5")
		t.expect(spec.effort).toBe("xhigh")
		t.expect(spec.context).toBe(500000)
		t.expect(spec.alias).toBe(nil)
		-- agent has that model (its heavy), grok does not
		t.expect((models.resolveActivity({ l }, "agent", "design", "risky") :: models.Spec).model)
			.toBe("claude-opus-5-5")
		local none, why = models.resolveActivity({ l }, "grok", "design", "risky")
		t.expect(none).toBe(nil)
		t.expect(why).toBe("grok does not have claude-opus-5-5")
		-- the CLI's `models` list counts
		local listed = layer(seedWith("[clis.kimi]\n", '[clis.kimi]\nmodels = ["kimi-code-k3.1-flash"]\n'))
		t.expect(listed.clis.kimi.models[1]).toBe("kimi-code-k3.1-flash")
	end)

	it("AC18: can is true exactly when resolve is not nil", function()
		local l = layer(SEED)
		for _, cli in models.CLIS do
			for _, act in models.ACTIVITIES do
				for _, lvl in { "easy", "normal", "risky" } do
					local spec = models.resolveActivity({ l }, cli, act, lvl :: any)
					t.expect(models.can({ l }, cli, act, lvl :: any)).toBe(spec ~= nil)
				end
			end
		end
		t.expect(models.can({ l }, "claude", "code-review", nil)).toBe(true)
		t.expect(models.can({ l }, "grok", "code-review", nil)).toBe(false)
	end)

	it("AC19: every load error, word for word, naming the file", function()
		local function parseFails(text: string, want: string)
			local ok, err = pcall(function()
				models.parse(text, "near/.models.toml")
			end)
			t.expect(ok).toBe(false)
			t.expect(tostring(err)).toBe(`near/.models.toml: {want}`)
		end
		parseFails(
			'[clis.gemini]\nlight = { model = "x" }\n',
			"clis.gemini is not a supported CLI (claude, grok, agent, kimi)"
		)
		parseFails(
			'[clis.claude]\nfast = { model = "claude-x" }\n',
			"clis.claude.fast is not an alias or setting (xlight, light, heavy, ultra, models, runtime, max_calls, max_minutes)"
		)
		parseFails('[clis.claude]\nlight = { effort = "low" }\n', "clis.claude.light has no model")
		parseFails(
			'[clis.claude]\nlight = { model = "gpt-4" }\n',
			"clis.claude.light.model is gpt-4, not a model of cli claude"
		)
		parseFails(
			"[activities.nap]\nmax_tokens = 1\n",
			"activities.nap is not an activity (idea, idea-challenge, design, design-review, raft, raft-review, code, code-review, final-review, approve)"
		)
		parseFails(
			'[activities.code]\nsometimes = "light"\n',
			"activities.code.sometimes is not max_tokens or a level (easy, normal, risky, all)"
		)
		parseFails(
			'[activities.idea]\neasy = "light"\n',
			"activities.idea.easy: idea has one setting for every level: write all"
		)
		parseFails(
			'[activities.code]\neasy = "turbo"\n',
			"activities.code.easy names turbo, which is not an alias (xlight, light, heavy, ultra)"
		)
		-- config errors name the closest file
		local function configFails(text: string, want: string)
			local ok, err = pcall(function()
				models.config({ layer("", "far/.models.toml"), layer(text, "near/.models.toml") })
			end)
			t.expect(ok).toBe(false)
			t.expect(tostring(err)).toBe(`near/.models.toml: {want}`)
		end
		configFails(
			seedWith('risky = "heavy"\n[activities.design-review]', "\n[activities.design-review]"),
			"activities.design has no setting for risky"
		)
		configFails(seedWith("max_tokens = 12000000\n", ""), "activities.code has no max_tokens")
		configFails(
			CLIS .. ACTIVITIES:gsub('%[activities.approve%]\nmax_tokens = 3000000\nall = "heavy"\n', ""),
			"activities.approve has no setting for all"
		)
		configFails(
			seedWith('xlight = { model = "claude-haiku-5-5", effort = "low" }\n', ""),
			"activities.design.easy needs xlight and no CLI in [clis] delivers it"
		)
		configFails(
			seedWith("max_calls = 200\n", ""),
			"clis.agent has no max_calls (agent reports no running token count, so its step stops after max_calls model calls; calls are not tokens: tune it)"
		)
		configFails(
			seedWith(
				'normal = "heavy"\nrisky = "ultra"\n[activities.raft]',
				'normal = "light"\nrisky = "ultra"\n[activities.raft]'
			),
			"at level normal, design and design-review both resolve to claude-sonnet-5-5 on claude: a reviewer never runs on the writer's model"
		)
	end)

	it("AC19: the idea pair at every level, and a writer and reviewer on one model", function()
		rejects(
			seedWith(
				'[activities.idea-challenge]\nmax_tokens = 300000\nall = "ultra"',
				'[activities.idea-challenge]\nmax_tokens = 300000\nall = "heavy"'
			),
			"at every level, idea and idea-challenge both resolve to claude-opus-5-5 on claude: a reviewer never runs on the writer's model"
		)
	end)

	it(
		"AC20: a walk is refused when no CLI delivers an activity at a level, and loads when one does",
		function()
			-- nothing delivers ultra
			rejects(
				seedWith('ultra = { model = "claude-fable-5-2", effort = "xhigh", context = 1000000 }\n', ""),
				"activities.idea-challenge.all needs ultra and no CLI in [clis] delivers it"
			)
			-- only grok has light, and one CLI is enough: drop claude's light and the walk still loads
			local ok = pcall(function()
				models.config({
					layer(seedWith('light = { model = "claude-sonnet-5-5", effort = "medium" }\n', "")),
				})
			end)
			t.expect(ok).toBe(true)
			-- a specific model nobody has
			rejects(
				seedWith(
					'risky = "heavy"\n[activities.design-review]',
					'risky = { model = "claude-opus-9-9", effort = "high" }\n[activities.design-review]'
				),
				"activities.design.risky needs claude-opus-9-9-high and no CLI in [clis] delivers it"
			)
		end
	)

	it(
		"AC21: one model for writer and reviewer on one CLI is refused whatever the effort and context; author refuses at use",
		function()
			rejects(
				seedWith(
					'normal = "heavy"\nrisky = "ultra"\n[activities.raft]',
					'normal = { model = "claude-sonnet-5-5", effort = "max", context = 1000000 }\nrisky = "ultra"\n[activities.raft]'
				),
				"at level normal, design and design-review both resolve to claude-sonnet-5-5 on claude"
			)
			-- the seed's shape is fine: no pair shares a model anywhere
			t.expect((pcall(models.config, { layer(SEED) }))).toBe(true)
			local l = layer(SEED)
			local spec, why =
				models.resolveActivity({ l }, "claude", "code-review", "normal", "claude-opus-5-5-high")
			t.expect(spec).toBe(nil)
			t.expect(why).toBe("claude-opus-5-5 wrote the text: a reviewer never runs on the writer's model")
			t.expect((models.resolveActivity({ l }, "claude", "code-review", "normal", "claude-opus-5-5")))
				.toBe(nil)
			t.expect(
				models.resolveActivity({ l }, "claude", "code-review", "normal", "claude-sonnet-5-5-medium")
					~= nil
			).toBe(true)
		end
	)

	it(
		"AC22: canList for the seed: 30 pairs for claude, 6 light for grok, 12 heavy for agent and kimi",
		function()
			local l = layer(SEED)
			t.expect(#models.canList({ l }, "claude")).toBe(30)
			local grok = models.canList({ l }, "grok")
			t.expect(grok).toEqual({
				"design/normal",
				"design-review/easy",
				"raft/normal",
				"raft-review/easy",
				"code/normal",
				"code-review/easy",
			})
			local agent = models.canList({ l }, "agent")
			t.expect(#agent).toBe(12)
			t.expect(models.canList({ l }, "kimi")).toEqual(agent)
			-- a one-setting activity appears at each level, in ACTIVITIES order then easy, normal, risky
			t.expect(agent[1]).toBe("idea/easy")
			t.expect(agent[3]).toBe("idea/risky")
			t.expect(agent[#agent]).toBe("approve/risky")
		end
	)

	it(
		"AC22: need names the alias, or a specific setting's id; sameModel ignores a trailing effort",
		function()
			local l = layer(SEED)
			t.expect(models.need({ l }, "code-review", "normal")).toBe("heavy")
			t.expect(models.need({ l }, "final-review", "easy")).toBe("ultra")
			local specific = layer(
				seedWith(
					'risky = "heavy"\n[activities.design-review]',
					'risky = { model = "claude-opus-5-5", effort = "xhigh" }\n[activities.design-review]'
				)
			)
			t.expect(models.need({ specific }, "design", "risky")).toBe("claude-opus-5-5-xhigh")
			t.expect(models.sameModel("claude-opus-5-5-high", "claude-opus-5-5")).toBe(true)
			t.expect(models.sameModel("claude-opus-5-5-xhigh", "claude-opus-5-5-low")).toBe(true)
			t.expect(models.sameModel("claude-opus-5-5", "claude-opus-5-5")).toBe(true)
			t.expect(models.sameModel("claude-opus-5-5", "claude-sonnet-5-5")).toBe(false)
			t.expect(models.sameModel("claude-opus-5-5", nil)).toBe(false)
		end
	)

	it("a closer file replaces an alias, a `models` list and a max_tokens, each whole", function()
		local near = layer(
			[[
[clis.claude]
heavy = { model = "claude-opus-5-6" }
[activities.code]
max_tokens = 5
]],
			"near/.models.toml"
		)
		local walk = { layer(SEED), near }
		local heavy = models.resolveActivity(walk, "claude", "code-review", "normal") :: models.Spec
		t.expect(heavy.model).toBe("claude-opus-5-6")
		t.expect(heavy.effort).toBe(nil) -- replaced whole: the far file's effort is gone
		t.expect((models.resolveActivity(walk, "claude", "code", "normal") :: models.Spec).maxTokens).toBe(5)
		t.expect((models.resolveActivity(walk, "claude", "code", "easy") :: models.Spec).alias).toBe("xlight")
	end)

	it("F2: within one file a level key beats that file's all", function()
		local one = layer(
			seedWith(
				'[activities.code]\nmax_tokens = 12000000\neasy = "xlight"\nnormal = "light"\nrisky = "heavy"\n',
				'[activities.code]\nmax_tokens = 5\nall = "xlight"\nrisky = "heavy"\n'
			)
		)
		t.expect((models.resolveActivity({ one }, "claude", "code", "easy") :: models.Spec).alias)
			.toBe("xlight")
		t.expect((models.resolveActivity({ one }, "claude", "code", "normal") :: models.Spec).alias)
			.toBe("xlight")
		t.expect((models.resolveActivity({ one }, "claude", "code", "risky") :: models.Spec).alias)
			.toBe("heavy")
	end)

	it(
		"F2: across files a near all replaces every level the far files set, and a near level key only that level",
		function()
			local allNear = { layer(SEED), layer('[activities.code]\nall = "xlight"\n', "near/.models.toml") }
			for _, lvl in { "easy", "normal", "risky" } do
				t.expect((models.resolveActivity(allNear, "claude", "code", lvl :: any) :: models.Spec).alias)
					.toBe("xlight")
			end
			local levelNear =
				{ layer(SEED), layer('[activities.code]\nnormal = "xlight"\n', "near/.models.toml") }
			t.expect((models.resolveActivity(levelNear, "claude", "code", "easy") :: models.Spec).alias)
				.toBe("xlight")
			t.expect((models.resolveActivity(levelNear, "claude", "code", "normal") :: models.Spec).alias)
				.toBe("xlight")
			t.expect((models.resolveActivity(levelNear, "claude", "code", "risky") :: models.Spec).alias)
				.toBe("heavy")
			-- the far file's `all` in turn is replaced by a near level key: the other levels keep it
			local far = layer('[activities.idea]\nmax_tokens = 1\nall = "heavy"\n', "far")
			t.expect(far.activities.idea.all.alias).toBe("heavy")
		end
	)

	it("activityFor maps a skill and a review mode to its activity, raft mode to raft-review", function()
		t.expect(models.activityFor("zz-review", "design")).toBe("design-review")
		t.expect(models.activityFor("zz-review", "raft")).toBe("raft-review")
		t.expect(models.activityFor("zz-review", "final")).toBe("final-review")
		t.expect(models.activityFor("zz-review", "code")).toBe("code-review")
		t.expect(models.activityFor("zz-review", "stream")).toBe("code-review")
		t.expect(models.activityFor("z-run", nil)).toBe("code")
		t.expect(models.activityFor("z-design", nil)).toBe("design")
		t.expect(models.activityFor("z-raft", nil)).toBe("raft")
		t.expect(models.activityFor("z-ticket", nil)).toBe("idea")
		t.expect(models.activityFor("idea-challenge", nil)).toBe("idea-challenge")
		t.expect(models.activityFor("z-ready", nil)).toBe(nil)
	end)

	it(
		"AC24: a legacy walk resolves each activity at each level to its role's model, and each fallback's on its CLI",
		function()
			local l = layer(root())
			local role: { [string]: string } = {
				idea = "idea",
				["idea-challenge"] = "idea-challenge",
				design = "design",
				["design-review"] = "design-challenge",
				raft = "raft",
				["raft-review"] = "raft",
				code = "implementation",
				["code-review"] = "code-review",
				["final-review"] = "final-review",
				approve = "approve",
			}
			t.expect(models.config({ l }).legacy).toBe(true)
			for act, r in role do
				local want = models.resolveRole({ l }, r)
				for _, lvl in { "easy", "normal", "risky" } do
					for _, cli in models.CLIS do
						local spec, why = models.resolveActivity({ l }, cli, act, lvl :: any)
						local expected = want.specs[cli]
						if expected == nil then
							t.expect(spec).toBe(nil)
							t.expect(why ~= nil).toBe(true)
						else
							local got = spec :: models.Spec
							t.expect(models.id(got)).toBe(models.id(expected))
							t.expect(got.runtime).toBe(expected.runtime)
							t.expect(got.maxTokens).toBe(expected.maxTokens)
							t.expect(got.maxCalls).toBe(expected.maxCalls)
						end
					end
				end
			end
			-- today's role cap and fallbacks, spelled out
			local review = models.resolveActivity({ l }, "claude", "design-review", "normal") :: models.Spec
			t.expect(models.id(review)).toBe("claude-opus-5-5-xhigh")
			t.expect(review.maxTokens).toBe(3000000)
			t.expect((models.resolveActivity({ l }, "grok", "code", "easy") :: models.Spec).model)
				.toBe("grok-4.7")
			t.expect(models.canList({ l }, "grok")[1]).toBe("idea/easy")
			-- idea-challenge keeps its `author`: the legacy author refusal is at use
			t.expect(models.need({ l }, "code", "risky")).toBe("claude-sonnet-5-5-high")
			-- a role the file lacks cannot be delivered, and is not an error
			local partial = layer(
				'[roles.design]\nmodel = "claude-opus-5-5"\ncli = "claude"\nruntime = "claude-cli"\nrank = 1\nmax_tokens = 5\n'
			)
			t.expect(models.can({ partial }, "claude", "design", "easy")).toBe(true)
			t.expect(models.can({ partial }, "claude", "code", "easy")).toBe(false)
		end
	)

	it("AC24: the legacy lookups still answer as today on the root file", function()
		local l = layer(root())
		local run = models.resolve({ l }, "z-run")
		t.expect(run.order[1]).toBe("claude")
		t.expect(run.specs.claude.model).toBe("claude-sonnet-5-5")
		local challenge = models.resolve({ l }, "idea-challenge")
		t.expect(challenge.authorModel).toBe("claude-fable-5-2-medium")
		t.expect(models.roleFor("zz-review", "design")).toBe("design-challenge")
		t.expect(models.rounds({ l }).design.normal).toBe(5)
	end)

	it("an empty walk and an unknown activity are errors, not a nil", function()
		t.expect(function()
			models.config({})
		end).toThrow("nothing defaults")
		t.expect(function()
			models.resolveActivity({ layer(SEED) }, "claude", "nap", "easy")
		end).toThrow("nap is not an activity")
	end)

	it(
		"F3: a legacy walk ignores the caller's author (only the role's own author field applies); a new-shape walk applies it",
		function()
			local legacy = layer(root())
			local spec = models.resolveActivity(
				{ legacy },
				"claude",
				"design-review",
				"normal",
				"claude-opus-5-5-high"
			)
			t.expect(spec ~= nil).toBe(true)
			local review = models.resolveActivity(
				{ layer(SEED) },
				"claude",
				"code-review",
				"normal",
				"claude-opus-5-5-high"
			)
			t.expect(review).toBe(nil)
		end
	)

	it("F4: a legacy role's own author refuses the fallback on the author's model", function()
		local l = layer([[
[roles.idea]
model = "claude-opus-5-5"
cli = "claude"
runtime = "claude-cli"
rank = 1
max_tokens = 10
effort = "high"
[roles.idea-challenge]
model = "claude-sonnet-5-5"
cli = "claude"
runtime = "claude-cli"
rank = 1
max_tokens = 10
effort = "high"
author = "idea"
fallbacks = ["agent"]
[fallback.agent]
model = "claude-opus-5-5"
runtime = "cursor-cli"
max_calls = 5
max_minutes = 5
]])
		t.expect((models.resolveActivity({ l }, "claude", "idea-challenge", "easy") :: models.Spec).model)
			.toBe("claude-sonnet-5-5")
		local none, why = models.resolveActivity({ l }, "agent", "idea-challenge", "easy")
		t.expect(none).toBe(nil)
		t.expect(why).toBe("claude-opus-5-5 wrote the text: a reviewer never runs on the writer's model")
		t.expect(models.can({ l }, "agent", "idea-challenge", "easy")).toBe(false)
	end)

	it("F4: a specific model resolves through a CLI's `models` list, and only on that CLI", function()
		local withList = seedWith("[clis.kimi]\n", '[clis.kimi]\nmodels = ["kimi-code-k3.1-flash"]\n')
		local l = layer(
			replaceIn(
				withList,
				'risky = "heavy"\n[activities.design-review]',
				'risky = { model = "kimi-code-k3.1-flash" }\n[activities.design-review]'
			)
		)
		local spec = models.resolveActivity({ l }, "kimi", "design", "risky") :: models.Spec
		t.expect(spec.model).toBe("kimi-code-k3.1-flash")
		t.expect(spec.alias).toBe(nil)
		local none, why = models.resolveActivity({ l }, "claude", "design", "risky")
		t.expect(none).toBe(nil)
		t.expect(why).toBe("claude does not have kimi-code-k3.1-flash")
	end)

	it(
		"F4: a walk is new-shape as soon as any file has [activities]: roles are ignored, and the merged activities must be complete",
		function()
			-- a far new-shape file with a near file of roles only: new-shape, the roles are ignored
			local mixed = {
				layer(SEED),
				layer(
					'[roles.design]\nmodel = "claude-opus-5-5"\ncli = "claude"\nruntime = "claude-cli"\nrank = 1\nmax_tokens = 5\n',
					"near/.models.toml"
				),
			}
			t.expect(models.config(mixed).legacy).toBe(false)
			t.expect((models.resolveActivity(mixed, "claude", "design", "easy") :: models.Spec).model)
				.toBe("claude-haiku-5-5")
			-- a legacy root with a near [activities] that is not complete: new-shape, refused naming the near file
			local ok, err = pcall(function()
				models.config({
					layer(root()),
					layer('[activities.code]\nmax_tokens = 1\nall = "light"\n', "pickman/.models.toml"),
				})
			end)
			t.expect(ok).toBe(false)
			t.expect(tostring(err)).toBe("pickman/.models.toml: activities.idea has no setting for all")
		end
	)

	it("F4: AC24's oracle spelled out: today's roles and fallbacks, literally", function()
		local l = layer(root())
		local function got(cli: string, act: string): string
			local spec = models.resolveActivity({ l }, cli, act, "normal") :: models.Spec
			return `{spec.model} {spec.effort or "-"}`
		end
		t.expect(got("claude", "code-review")).toBe("claude-opus-5-5 xhigh")
		t.expect(got("grok", "code-review")).toBe("grok-4.7 xhigh")
		t.expect(got("claude", "code")).toBe("claude-sonnet-5-5 high")
		t.expect(got("kimi", "design-review")).toBe("kimi-code-k3.1-pro xhigh")
		t.expect(got("agent", "final-review")).toBe("claude-opus-5-5 xhigh")
		t.expect(got("claude", "idea")).toBe("claude-fable-5-2 medium")
	end)

	it(
		"F5: an effort outside low, medium, high, xhigh and max is refused at parse; model ids compare case-insensitively",
		function()
			local ok, err = pcall(function()
				models.parse(
					'[clis.claude]\nlight = { model = "claude-sonnet-5-5", effort = "extreme" }\n',
					"x"
				)
			end)
			t.expect(ok).toBe(false)
			t.expect(tostring(err))
				.toBe("x: clis.claude.light.effort is extreme: low, medium, high, xhigh, max")
			t.expect(models.sameModel("Claude-Opus-5-5-HIGH", "claude-opus-5-5")).toBe(true)
		end
	)

	it("F6: a level that is not easy, normal or risky is a named problem, not a crash", function()
		local l = layer(SEED)
		local spec, why = models.resolveActivity({ l }, "claude", "code", "bogus" :: any)
		t.expect(spec).toBe(nil)
		t.expect(why).toBe("bogus is not a level (easy, normal, risky)")
		t.expect(models.can({ l }, "claude", "code", "bogus" :: any)).toBe(false)
		local ok, err = pcall(models.need, { l }, "code", "bogus" :: any)
		t.expect(ok).toBe(false)
		t.expect(err).toBe("bogus is not a level (easy, normal, risky)")
	end)

	it(
		"F7: context and caps are finite whole numbers in a sane bound, and `models` is a real list",
		function()
			local function bad(text: string, want: string)
				local ok, err = pcall(function()
					models.parse(text, "x")
				end)
				t.expect(ok).toBe(false)
				t.expect(tostring(err)).toBe(`x: {want}`)
			end
			bad(
				'[clis.claude]\nlight = { model = "claude-sonnet-5-5", context = inf }\n',
				"clis.claude.light.context is inf: a whole number of tokens, 1 to 1000000000"
			)
			bad(
				'[clis.claude]\nlight = { model = "claude-sonnet-5-5", context = 1000000000000 }\n',
				"clis.claude.light.context is 1000000000000: a whole number of tokens, 1 to 1000000000"
			)
			bad(
				"[activities.code]\nmax_tokens = inf\n",
				"activities.code.max_tokens is inf: a whole number, 1 to 1000000000"
			)
			bad(
				"[clis.agent]\nmax_calls = inf\n",
				"clis.agent.max_calls is inf: a whole number, 1 to 1000000000"
			)
			bad('[clis.kimi]\nmodels = { a = "kimi-code-x" }\n', "clis.kimi.models is a list of model ids")
		end
	)

	it("F8: a config error names the file its faulty key is in, not always the closest", function()
		local farBad = seedWith(
			'normal = "heavy"\nrisky = "ultra"\n[activities.raft]',
			'normal = "light"\nrisky = "ultra"\n[activities.raft]'
		)
		local quiet = '[clis.grok]\nlight = { model = "grok-4.7", effort = "high" }\n'
		local ok, err = pcall(function()
			models.config({ layer(farBad, "far/.models.toml"), layer(quiet, "near/.models.toml") })
		end)
		t.expect(ok).toBe(false)
		t.expect(has(tostring(err), "far/.models.toml: at level normal, design and design-review")).toBe(true)
		-- the near file sets the clashing setting: the near file is named
		local ok2, err2 = pcall(function()
			models.config({
				layer(SEED, "far/.models.toml"),
				layer('[activities.design-review]\nnormal = "light"\n', "near/.models.toml"),
			})
		end)
		t.expect(ok2).toBe(false)
		t.expect(has(tostring(err2), "near/.models.toml: at level normal, design and design-review"))
			.toBe(true)
	end)

	it("F8: deliverers names the CLIs that can run an activity at a level", function()
		local l = layer(SEED)
		t.expect(models.deliverers({ l }, "code-review", "normal")).toEqual({ "claude", "agent", "kimi" })
		t.expect(models.deliverers({ l }, "code", "normal")).toEqual({ "claude", "grok" })
		t.expect(models.deliverers({ layer(root()) }, "code-review", "normal"))
			.toEqual({ "claude", "grok", "agent", "kimi" })
	end)

	it(
		"F9: on a legacy walk a missing role is not a raise: need names the role, and nothing can deliver it",
		function()
			local partial = layer(
				'[roles.design]\nmodel = "claude-opus-5-5"\ncli = "claude"\nruntime = "claude-cli"\nrank = 1\nmax_tokens = 5\n'
			)
			t.expect(models.need({ partial }, "approve", "normal")).toBe("role approve")
			t.expect(#models.deliverers({ partial }, "approve", "normal")).toBe(0)
		end
	)

	it(
		"F10: --can is a no-value flag for ./zn model only: main.luau's global boolean list no longer has it",
		function()
			local main = fs.readFile(`{TOP}/z-nile/engine/main.luau`)
			t.expect(has(main, 'or a == "--can"')).toBe(false)
			t.expect(has(main, '{ ["--can"] = false }')).toBe(true)
		end
	)
end)
