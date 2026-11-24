--!strict
-- f0421, agy: a CLI may name other models for its review activities, in a `[clis.<cli>.review]` sub-table. An alias resolves
-- from it for design-review, raft-review, code-review, final-review and idea-challenge, and from the plain alias for every other
-- activity. The reviewer-is-not-the-writer check compares the resolved pair, and a CLI delivers a review when its review alias
-- resolves. The other four CLIs resolve exactly what they did before the sub-table existed.
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
	it("the repository's root file gives agy Neon for writing and Argon for reviewing, and loads", function()
		local l = { models.parse(fs.readFile(`{TOP}/.models.toml`), ".models.toml") }
		models.config(l)
		t.expect(model(l, "agy", "code", "normal")).toBe("gemini-4-neon-medium")
		t.expect(model(l, "agy", "design", "easy")).toBe("gemini-4-neon-low")
		t.expect(model(l, "agy", "code", "risky")).toBe("gemini-4-neon-high")
		t.expect(model(l, "agy", "code-review", "normal")).toBe("gemini-4-argon-high")
		t.expect(model(l, "agy", "design-review", "easy")).toBe("gemini-4-argon-medium")
		t.expect(model(l, "agy", "code-review", "risky")).toBe("-")
		t.expect(model(l, "agy", "final-review", "normal")).toBe("-")
		t.expect(model(l, "agy", "idea-challenge", "normal")).toBe("-")
	end)

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
			t.expect(
				has(
					loadError(
						'[clis.agy]\nlight = { model = "gemini-4-neon-medium" }\n[clis.agy.review]\nheavy = { model = "claude-opus-5-5" }\n'
					),
					"clis.agy.review.heavy.model is claude-opus-5-5, not a model of cli agy"
				)
			).toBe(true)
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
		"the writer and the reviewer must resolve to different models: one model at two efforts is refused",
		function()
			local e = loadError(
				'[clis.agy]\nlight = { model = "gemini-4-neon-medium" }\nheavy = { model = "gemini-4-neon-high" }\n'
			)
			t.expect(has(e, "both resolve to gemini-4-neon-")).toBe(true)
			t.expect(has(e, "a reviewer never runs on the writer's model")).toBe(true)
			-- a review table naming the writer's model is refused the same way
			local e2 = loadError(
				'[clis.agy]\nlight = { model = "gemini-4-neon-medium" }\nheavy = { model = "gemini-4-argon-high" }\n[clis.agy.review]\nheavy = { model = "gemini-4-neon-high" }\n'
			)
			t.expect(has(e2, "a reviewer never runs on the writer's model")).toBe(true)
			-- neon writes, argon reviews: it loads
			models.config(layers(AGY))
		end
	)

	it(
		"a CLI delivers a review when its review alias resolves, and a writer activity when its plain alias does",
		function()
			local l = { models.parse(fs.readFile(`{TOP}/.models.toml`), ".models.toml") }
			t.expect(models.waiting(l, "code-review", "normal"))
				.toBe("code-review/normal (heavy: claude, agent, kimi, agy)")
			t.expect(models.waiting(l, "code-review", "risky")).toBe("code-review/risky (ultra: claude)")
			t.expect(models.waiting(l, "final-review", "normal")).toBe("final-review/normal (ultra: claude)")
			t.expect(models.waiting(l, "design", "easy")).toBe("design/easy (xlight: claude, agy)")
			t.expect(table.concat(models.canList(l, "agy"), ",")).toBe(
				"idea/easy,idea/normal,idea/risky,design/easy,design/normal,design/risky,design-review/easy,design-review/normal,raft/easy,raft/normal,raft/risky,raft-review/easy,raft-review/normal,code/easy,code/normal,code/risky,code-review/easy,code-review/normal,approve/easy,approve/normal,approve/risky"
			)
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
