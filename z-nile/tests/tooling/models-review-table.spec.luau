--!strict
-- f0421, agy: a CLI may name other models for its review activities, in a `[clis.<cli>.review]` sub-table. An alias resolves
-- from it for design-review, raft-review, code-review, final-review and idea-challenge, and from the plain alias for every other
-- activity. A review on the writer's own model is allowed, not preferred (owner, 2026-11-24), so a table may give a writer
-- and its reviewer one model; a CLI delivers a review when its review alias resolves. The other four CLIs resolve exactly what
-- they did before the sub-table existed.
local fs = require("@lune/fs")
local models = require("@znile/engine/models")
local process = require("@lune/process")
local t = require("@tests/lib/t")

local TOP = (string.gsub(process.exec("git", { "rev-parse", "--show-toplevel" }).stdout, "%s+$", ""))

local function has(s: string, part: string): boolean
	return string.find(s, part, 1, true) ~= nil
end

-- the repository's root file without its agy table, so each case writes the agy table it needs
local function withoutAgy(): string
	local text = fs.readFile(`{TOP}/.models.toml`)
	local a = string.find(text, "# agy (Antigravity)", 1, true) :: number
	local b = string.find(text, "\n[activities.idea]", a, true) :: number
	return string.sub(text, 1, a - 1) .. string.sub(text, b + 1)
end

local AGY = [[
[clis.agy]
xlight = { model = "gemini-4-neon-low" }
light = { model = "gemini-4-neon-medium" }
heavy = { model = "gemini-4-neon-high" }
[clis.agy.review]
light = { model = "gemini-4-argon-medium" }
heavy = { model = "gemini-4-argon-high" }
]]

local function layers(extra: string): { models.Layer }
	return { models.parse(`{withoutAgy()}\n{extra}`, ".models.toml") }
end

local function loadError(extra: string): string
	local ok, e = pcall(function()
		models.config(layers(extra))
	end)
	t.expect(ok).toBe(false)
	return tostring(e)
end

local function model(l: { models.Layer }, cli: string, act: string, lvl: string): string
	local s = models.resolveActivity(l, cli, act, lvl :: any)
	return if s then s.model .. (if s.effort then `@{s.effort}` else "") else "-"
end

-- What the four older CLIs resolved before the sub-table existed (captured from the engine before the change), per activity at
-- easy, normal and risky.
local BEFORE = {
	"claude idea claude-opus-5-5@high claude-opus-5-5@high claude-opus-5-5@high",
	"claude idea-challenge claude-fable-5-2@xhigh claude-fable-5-2@xhigh claude-fable-5-2@xhigh",
	"claude design claude-haiku-5-5@low claude-sonnet-5-5@medium claude-opus-5-5@high",
	"claude design-review claude-sonnet-5-5@medium claude-opus-5-5@high claude-fable-5-2@xhigh",
	"claude raft claude-haiku-5-5@low claude-sonnet-5-5@medium claude-opus-5-5@high",
	"claude raft-review claude-sonnet-5-5@medium claude-opus-5-5@high claude-fable-5-2@xhigh",
	"claude code claude-haiku-5-5@low claude-sonnet-5-5@medium claude-opus-5-5@high",
	"claude code-review claude-sonnet-5-5@medium claude-opus-5-5@high claude-fable-5-2@xhigh",
	"claude final-review claude-fable-5-2@xhigh claude-fable-5-2@xhigh claude-fable-5-2@xhigh",
	"claude approve claude-opus-5-5@high claude-opus-5-5@high claude-opus-5-5@high",
	"grok idea - - -",
	"grok idea-challenge - - -",
	"grok design - grok-4.7@high -",
	"grok design-review grok-4.7@high - -",
	"grok raft - grok-4.7@high -",
	"grok raft-review grok-4.7@high - -",
	"grok code - grok-4.7@high -",
	"grok code-review grok-4.7@high - -",
	"grok final-review - - -",
	"grok approve - - -",
	"agent idea claude-opus-5-5@high claude-opus-5-5@high claude-opus-5-5@high",
	"agent idea-challenge - - -",
	"agent design - - claude-opus-5-5@high",
	"agent design-review - claude-opus-5-5@high -",
	"agent raft - - claude-opus-5-5@high",
	"agent raft-review - claude-opus-5-5@high -",
	"agent code - - claude-opus-5-5@high",
	"agent code-review - claude-opus-5-5@high -",
	"agent final-review - - -",
	"agent approve claude-opus-5-5@high claude-opus-5-5@high claude-opus-5-5@high",
	"kimi idea kimi-code-k3.1-pro kimi-code-k3.1-pro kimi-code-k3.1-pro",
	"kimi idea-challenge - - -",
	"kimi design - - kimi-code-k3.1-pro",
	"kimi design-review - kimi-code-k3.1-pro -",
	"kimi raft - - kimi-code-k3.1-pro",
	"kimi raft-review - kimi-code-k3.1-pro -",
	"kimi code - - kimi-code-k3.1-pro",
	"kimi code-review - kimi-code-k3.1-pro -",
	"kimi final-review - - -",
	"kimi approve kimi-code-k3.1-pro kimi-code-k3.1-pro kimi-code-k3.1-pro",
}

return t.spec("f0421 agy: a CLI's review activities may run other models than its writers", function(it)
	it(
		"the repository's root file gives agy Neon for writing, Argon for reviewing and Carbon for ultra, and loads",
		function()
			local l = { models.parse(fs.readFile(`{TOP}/.models.toml`), ".models.toml") }
			models.config(l)
			t.expect(model(l, "agy", "code", "normal")).toBe("gemini-4-neon-medium")
			t.expect(model(l, "agy", "design", "easy")).toBe("gemini-4-neon-low")
			t.expect(model(l, "agy", "code", "risky")).toBe("gemini-4-neon-high")
			t.expect(model(l, "agy", "code-review", "normal")).toBe("gemini-4-argon-high")
			t.expect(model(l, "agy", "design-review", "easy")).toBe("gemini-4-argon-medium")
			t.expect(model(l, "agy", "code-review", "risky")).toBe("gemini-4-carbon-high")
			t.expect(model(l, "agy", "final-review", "normal")).toBe("gemini-4-carbon-high")
			t.expect(model(l, "agy", "idea-challenge", "normal")).toBe("gemini-4-carbon-high")
			local ultraAlias = models.resolveAlias(l, "agy", "ultra")
			t.expect(ultraAlias ~= nil and ultraAlias.model).toBe("gemini-4-carbon-high")
		end
	)

	it(
		"the review table is read for review activities only: every other activity, answers included, uses the plain alias",
		function()
			local l = layers(AGY)
			t.expect(model(l, "agy", "design-answer", "normal")).toBe("gemini-4-neon-medium")
			t.expect(model(l, "agy", "code-answer", "risky")).toBe("gemini-4-neon-high")
			t.expect(model(l, "agy", "approve", "normal")).toBe("gemini-4-neon-high")
			t.expect(model(l, "agy", "raft-review", "normal")).toBe("gemini-4-argon-high")
			t.expect(model(l, "agy", "raft", "normal")).toBe("gemini-4-neon-medium")
		end
	)

	it(
		"an alias the CLI defines only for review is allowed: it reviews at a level it does not write at",
		function()
			local l = layers(
				'[clis.agy]\nlight = { model = "gemini-4-neon-medium" }\n[clis.agy.review]\nheavy = { model = "gemini-4-argon-high" }\n'
			)
			t.expect(model(l, "agy", "code-review", "normal")).toBe("gemini-4-argon-high")
			t.expect(model(l, "agy", "code", "risky")).toBe("-")
			t.expect(models.can(l, "agy", "code", "normal")).toBe(true)
		end
	)

	it(
		"a review table is refused when it is not a table of aliases, or names a model the CLI lacks",
		function()
			t.expect(has(loadError("[clis.agy]\nreview = 3\n"), "clis.agy.review is a table of aliases"))
				.toBe(true)
			t.expect(
				has(
					loadError(
						'[clis.agy]\nlight = { model = "gemini-4-neon-medium" }\n[clis.agy.review]\nmedium = { model = "gemini-4-argon-medium" }\n'
					),
					"clis.agy.review.medium is not an alias (xlight, light, heavy, ultra)"
				)
			).toBe(true)
			t.expect(has(
				loadError(
					'[clis.agy]\nlight = { model = "gemini-4-neon-medium" }\n[clis.agy.review]\nheavy = { model = "claude-fable-5-2" }\n'
				),
				-- f0421 slice 3 (review-005 F5): agy runs Claude Opus and Sonnet, so the model it lacks here is Fable
				"clis.agy.review.heavy.model is claude-fable-5-2, not a model of cli agy"
			)).toBe(true)
			t.expect(
				has(
					loadError(
						'[clis.agy]\nlight = { model = "gemini-4-neon-medium" }\n[clis.agy.review]\nheavy = { model = "gemini-4-argon-high", rank = 2 }\n'
					),
					"clis.agy.review.heavy.rank is not a field"
				)
			).toBe(true)
		end
	)

	it(
		"a writer and a reviewer on one model load: another model is preferred, the same one is allowed",
		function()
			-- one CLI, one model at two efforts for writing and for reviewing: no refusal at load
			local same = layers(
				'[clis.agy]\nlight = { model = "gemini-4-neon-medium" }\nheavy = { model = "gemini-4-neon-high" }\n'
			)
			models.config(same)
			t.expect(model(same, "agy", "code-review", "normal")).toBe("gemini-4-neon-high")
			-- a review table naming the writer's own model loads too
			models.config(
				layers(
					'[clis.agy]\nlight = { model = "gemini-4-neon-medium" }\nheavy = { model = "gemini-4-argon-high" }\n[clis.agy.review]\nheavy = { model = "gemini-4-neon-high" }\n'
				)
			)
			-- neon writes, argon reviews: it loads
			models.config(layers(AGY))
		end
	)

	it(
		"a review on the author's model resolves with sameAsAuthor, and one on another model without it",
		function()
			local l = layers(AGY)
			local other = models.resolveActivity(l, "agy", "code-review", "normal", "gemini-4-neon-medium")
			t.expect(other ~= nil and other.model).toBe("gemini-4-argon-high")
			t.expect(other ~= nil and other.sameAsAuthor).toBe(nil)
			-- effort and case are ignored by sameModel: argon at any effort wrote the text
			local mine = models.resolveActivity(l, "agy", "code-review", "normal", "Gemini-4-Argon-low")
			t.expect(mine ~= nil and mine.model).toBe("gemini-4-argon-high")
			t.expect(mine ~= nil and mine.sameAsAuthor).toBe(true)
			-- several writers: any of them marks it, and none refuses it
			local many = models.resolveReview(
				l,
				"agy",
				"design-review",
				"easy",
				{ "gemini-4-neon-low", "gemini-4-argon-high" }
			)
			t.expect(many ~= nil and many.sameAsAuthor).toBe(true)
			local none = models.resolveReview(l, "agy", "design-review", "easy", { "gemini-4-neon-low" })
			t.expect(none ~= nil and none.sameAsAuthor).toBe(nil)
			-- only the author's model delivers it (a CLI with one model): still delivered
			local only = layers(
				'[clis.agy]\nlight = { model = "gemini-4-neon-medium" }\nheavy = { model = "gemini-4-neon-high" }\n'
			)
			local spec = models.resolveActivity(only, "agy", "code-review", "normal", "gemini-4-neon-low")
			t.expect(spec ~= nil and spec.sameAsAuthor).toBe(true)
		end
	)

	it(
		"a closer file's review table merges per alias: an alias it does not repeat keeps the farther file's model",
		function()
			local far = withoutAgy() .. "\n" .. AGY
			local near = '[clis.agy.review]\nheavy = { model = "gemini-4-argon-xhigh" }\n'
			local l = { models.parse(far, "far/.models.toml"), models.parse(near, "near/.models.toml") }
			models.config(l)
			t.expect(model(l, "agy", "code-review", "normal")).toBe("gemini-4-argon-xhigh") -- the near file's heavy
			t.expect(model(l, "agy", "design-review", "easy")).toBe("gemini-4-argon-medium") -- far's light, kept
			t.expect(model(l, "agy", "code", "normal")).toBe("gemini-4-neon-medium") -- writers untouched
		end
	)

	it("an empty review table, or a list where a table belongs, is refused", function()
		t.expect(has(loadError("[clis.agy]\nreview = []\n"), "clis.agy.review is empty")).toBe(true)
		t.expect(
			has(
				loadError('[clis.agy]\nlight = { model = "gemini-4-neon-medium" }\n[clis.agy.review]\n'),
				"clis.agy.review is empty"
			)
		).toBe(true)
		t.expect(has(loadError('[clis.agy]\nreview = ["light"]\n'), "clis.agy.review is a table of aliases"))
			.toBe(true)
	end)

	it("a review that resolves on a writer's model names that writer, the one that matched", function()
		local l = layers(AGY)
		local spec = models.resolveReview(
			l,
			"agy",
			"code-review",
			"normal",
			{ "gemini-4-neon-high", "gemini-4-argon-low" }
		)
		t.expect(spec ~= nil and spec.sameAsAuthor).toBe(true)
		t.expect(spec ~= nil and spec.writer).toBe("gemini-4-argon-low")
		local plain = models.resolveReview(l, "agy", "code-review", "normal", { "gemini-4-neon-high" })
		t.expect(plain ~= nil and plain.writer).toBe(nil)
	end)

	it(
		"a CLI without subagents that runs several models needs the session's model; the others do not",
		function()
			local l = layers(AGY)
			t.expect(models.hasSubagents("claude")).toBe(true)
			t.expect(models.hasSubagents("agy")).toBe(false)
			t.expect(models.modelsOf(l, "agy")).toEqual({
				"gemini-4-argon-high",
				"gemini-4-argon-medium",
				"gemini-4-neon-high",
				"gemini-4-neon-low",
				"gemini-4-neon-medium",
			})
			t.expect(models.needsSession(l, "agy")).toBe(true)
			for _, cli in { "claude", "grok", "agent", "kimi" } do
				t.expect(models.needsSession(l, cli)).toBe(false)
			end
			-- only the activities whose model is the session's own are delivered
			local neon = models.canList(l, "agy", "gemini-4-neon-medium")
			t.expect(table.concat(neon, ",")).toBe("design/normal,raft/normal,code/normal")
			local argon = models.canList(l, "agy", "gemini-4-argon-high")
			t.expect(table.concat(argon, ","))
				.toBe("design-review/normal,raft-review/normal,code-review/normal")
			local spec, why =
				models.resolveActivity(l, "agy", "code-review", "normal", nil, "gemini-4-neon-medium")
			t.expect(spec).toBe(nil)
			t.expect(has(why or "", "gemini-4-argon-high")).toBe(true)
			t.expect(models.can(l, "agy", "code", "normal", "gemini-4-neon-medium")).toBe(true)
			-- the waiting line names what is needed as a worker running that model
			t.expect(models.waiting(l, "code-review", "normal"))
				.toBe("code-review/normal (heavy: claude, agent, kimi, agy running gemini-4-argon-high)")
			-- a CLI with one model ignores a session model
			t.expect(models.can(l, "kimi", "code-review", "normal", "something-else"))
				.toBe(models.can(l, "kimi", "code-review", "normal"))
			t.expect(models.canList(l, "grok", "anything")).toEqual(models.canList(l, "grok"))
			t.expect(models.canList(l, "claude", "anything")).toEqual(models.canList(l, "claude"))
		end
	)

	it(
		"a CLI delivers a review when its review alias resolves, and a writer activity when its plain alias does",
		function()
			local l = { models.parse(fs.readFile(`{TOP}/.models.toml`), ".models.toml") }
			t.expect(models.waiting(l, "code-review", "normal"))
				.toBe("code-review/normal (heavy: claude, agent, kimi, agy running gemini-4-argon-high)")
			t.expect(models.waiting(l, "code-review", "risky"))
				.toBe("code-review/risky (ultra: claude, agy running gemini-4-carbon-high)")
			t.expect(models.waiting(l, "final-review", "normal"))
				.toBe("final-review/normal (ultra: claude, agy running gemini-4-carbon-high)")
			t.expect(models.waiting(l, "design", "easy"))
				.toBe("design/easy (xlight: claude, agy running gemini-4-neon-low)")
			t.expect(table.concat(models.canList(l, "agy"), ","))
				.toBe(table.concat(models.canList(l, "claude"), ","))
			t.expect(table.concat(models.canList(l, "agy", "gemini-4-carbon-high"), ",")).toBe(
				"idea-challenge/easy,idea-challenge/normal,idea-challenge/risky,design-review/risky,raft-review/risky,code-review/risky,final-review/easy,final-review/normal,final-review/risky"
			)
			t.expect(models.modelsOf(l, "agy")).toEqual({
				"gemini-4-argon-high",
				"gemini-4-argon-medium",
				"gemini-4-carbon-high",
				"gemini-4-neon-high",
				"gemini-4-neon-low",
				"gemini-4-neon-medium",
			})
			-- a review-only alias is a review capability only
			local review = layers(
				'[clis.agy]\nlight = { model = "gemini-4-neon-medium" }\n[clis.agy.review]\nheavy = { model = "gemini-4-argon-high" }\n'
			)
			t.expect(models.can(review, "agy", "code-review", "normal")).toBe(true)
			t.expect(models.can(review, "agy", "code", "risky")).toBe(false)
		end
	)

	it(
		"claude, grok, agent and kimi resolve every activity at every level exactly as they did before",
		function()
			local l = { models.parse(fs.readFile(`{TOP}/.models.toml`), ".models.toml") }
			local now = {}
			for _, cli in { "claude", "grok", "agent", "kimi" } do
				for _, act in models.ACTIVITIES do
					table.insert(
						now,
						`{cli} {act} {model(l, cli, act, "easy")} {model(l, cli, act, "normal")} {model(
							l,
							cli,
							act,
							"risky"
						)}`
					)
				end
			end
			t.expect(now).toEqual(BEFORE)
		end
	)
end)
