--!strict
-- c0251 AC13 and AC18: the skills, `.models.toml`'s comments and the README state the tier rule, the designed-by line and the
-- frontier floor, and no longer say a challenge is never run by the model that wrote the text or that a review must run on a
-- review model; the README's c0251 markers read `*exists*`; AGENTS.md is untouched (c0332's); and the root `.models.toml` names
-- Fable in the design-challenge, raft-review and code-review pools, no pool on final-review (Fable, kimi, grok, then Opus on the
-- agent), the stream-review list (Haiku, Sonnet, grok-4.6, composer) and the `raft` role apart from `raft-review`.
local fs = require("@lune/fs")
local models = require("@znile/engine/models")
local process = require("@lune/process")
local t = require("@tests/lib/t")

local M: any = models

-- the spec runs from z-nile/ (its home): the repository's files are read from its top
local TOP = (string.gsub(process.exec("git", { "rev-parse", "--show-toplevel" }).stdout, "%s+$", ""))
local function read(path: string): string
	return fs.readFile(`{TOP}/{path}`)
end
local function at(text: string, needle: string, where: string)
	if not string.find(text, needle, 1, true) then
		error(`{where} does not say: {needle}`, 2)
	end
end
local function absent(text: string, needle: string, where: string)
	if string.find(text, needle, 1, true) then
		error(`{where} still says: {needle}`, 2)
	end
end
local function skill(name: string): string
	return read(`z-nile/skills/{name}/SKILL.md`)
end

local function tryIds(layers: { any }, skillName: string, mode: string?): { string }
	local out = {}
	for _, s in M.tries(M.resolve(layers, skillName, mode)) do
		table.insert(out, `{s.cli}:{s.model}`)
	end
	return out
end

return t.spec("c0251 docs and the root .models.toml", function(it)
	it(
		"AC13: zz-review states the tier rule, the designed-by line, the interactive pick, the Fallback: line and the floor",
		function()
			local text = skill("zz-review")
			at(text, "`stream-review` for a stream review", "zz-review")
			at(text, "`raft-review` for a raft (the `raft` role writes one)", "zz-review")
			at(text, "tier 1 differs from the author and from the previous round", "zz-review")
			at(text, "tier 2 differs from the author only", "zz-review")
			at(text, "tier 3 is the author's own family, the recorded fallback", "zz-review")
			at(text, "the exact model that wrote the text last", "zz-review")
			at(text, "and it never stops the chain", "zz-review")
			at(text, "`[families]`", "zz-review")
			at(text, 'a model the table cannot place is never "different"', "zz-review")
			at(text, "The author is recorded, never assumed", "zz-review")
			at(text, "`designed-by: <model id>` front-matter line", "zz-review")
			at(
				text,
				"a design review or raft review of a document with no such line is refused, and there is no `--author` flag",
				"zz-review"
			)
			at(
				text,
				"The stream-review list, in `.models.toml`, is Haiku, then Sonnet, then grok-4.6 and composer",
				"zz-review"
			)
			at(text, "`./zn dispatch zz-review <id> --mode <m> --dry-run`", "zz-review")
			at(text, "the `pick:` line", "zz-review")
			at(
				text,
				"unchanged except for the `Model:`, `Effort:` and `Fallback:` lines it records",
				"zz-review"
			)
			at(text, "`Fallback: <reason>` is a stamped line the tool writes", "zz-review")
			at(text, "never the reviewer and never typed", "zz-review")
			at(text, "nothing flags it or asks for a re-review", "zz-review")
			at(
				text,
				"**Review records and the frontier floor.** Any model may run any review: there is no list of review models",
				"zz-review"
			)
			at(text, "the **frontier floor**", "zz-review")
			at(text, "the `[review] frontier` list of `.models.toml`", "zz-review")
			at(text, "naming `no-frontier-review`", "zz-review")
			at(text, "`./zn dispatch zz-review <R-id> --mode final --frontier`", "zz-review")
			at(text, "waits (exit 6) while none has quota", "zz-review")
			at(text, "A round that records a `Fallback:` line allows no second round", "zz-review")
			absent(text, "A challenge is never run by the model that wrote the text", "zz-review")
			absent(text, "so that model is dropped", "zz-review")
			absent(text, "naming the author would drop it", "zz-review")
			absent(text, "--author <its model id>", "zz-review")
			absent(text, "the board prints it", "zz-review")
			absent(text, "flagged on the board", "zz-review")
			absent(text, "runs on a review model", "zz-review")
			absent(text, "the next round supersedes it", "zz-review")
		end
	)

	it("AC13: z-design, z-raft, zz-execute and zz-rules restate who reviews", function()
		local design = skill("z-design")
		at(design, "on the model line the picker chooses away from the one that wrote the design", "z-design")
		at(design, "start the reviewer subagent on the `pick:` model", "z-design")
		at(design, "`designed-by: <the model id that wrote the design>`", "z-design")
		at(design, "the extra round of the frontier floor", "z-design")
		at(design, "**Review records and the frontier floor.**", "z-design")
		absent(design, "never on the model that wrote the design", "z-design")
		absent(design, "--author", "z-design")
		absent(design, "or one flagged `Fallback:`", "z-design")
		local raft = skill("z-raft")
		at(raft, "The role is `raft-review`; `raft` is the role that writes a raft", "z-raft")
		at(raft, "`designed-by: <the model id that wrote it>`", "z-raft")
		at(raft, "The picker chooses the model line away from the one that wrote the raft", "z-raft")
		at(raft, "except the extra round of the frontier floor at a landing", "z-raft")
		absent(raft, "naming the author would drop it", "z-raft")
		absent(raft, "That role names no author", "z-raft")
		absent(raft, "flagged", "z-raft")
		local execute = skill("zz-execute")
		at(
			execute,
			"on the model line the picker chooses away from the one that wrote the code",
			"zz-execute"
		)
		at(execute, "start the reviewer subagent on the `pick:` model", "zz-execute")
		at(execute, "on the `pick:` model of its `--dry-run`", "zz-execute")
		at(execute, "`./zn commit --phase code-review --model <id>` stamps `Fallback:` itself", "zz-execute")
		at(execute, "run one more round with `--frontier` before `done`", "zz-execute")
		at(execute, "`done` refuses with `no-frontier-review`", "zz-execute")
		absent(execute, "never on the model that wrote the code", "zz-execute")
		absent(execute, "--author", "zz-execute")
		local rules = skill("zz-rules")
		at(rules, "a `Fallback:` line it derives itself", "zz-rules")
		at(rules, "with a derived `Fallback:` line", "zz-rules")
		at(rules, "the design's or raft's `designed-by` line", "zz-rules")
		at(rules, "A role's `pool` lists `[member.<name>]` models", "zz-rules")
		at(rules, "`rotate = true`", "zz-rules")
		at(rules, "`raft-review`, `code-review`, `stream-review` and `final-review`", "zz-rules")
		at(rules, "`frontier = [...]`", "zz-rules")
		at(rules, "never assumed", "zz-rules")
		absent(rules, "a try whose model is that author's is dropped", "zz-rules")
		absent(rules, "naming the author would drop it", "zz-rules")
		absent(rules, "--author", "zz-rules")
	end)

	it(
		"AC13: the old review-model rule is gone from every skill, and the frontier floor is stated in the five that carried it",
		function()
			for _, name in { "zz-review", "z-design", "z-raft", "zz-execute", "zz-rules" } do
				local text = skill(name)
				at(text, "Any model may run any review: there is no list of review models", name)
				at(text, "`no-frontier-review`", name)
				at(text, "`./zn dispatch zz-review <R-id> --mode final --frontier`", name)
				absent(
					text,
					"**Review models.** Every review but a stream review runs on a review model",
					name
				)
				absent(text, "`claude-opus-`, `claude-fable-` or `kimi-code-k3`", name)
				absent(text, "a review step starts no try the rule would refuse", name)
			end
		end
	)

	it("AC13: the README says the pool exists and its c0251 markers read exists", function()
		local readme = read("z-nile/README.md")
		at(readme, "| cross-model review pool, same-family fallback | c0251 | exists |", "README")
		at(readme, "*exists* (c0251)", "README")
		absent(readme, "| cross-model review pool, same-family fallback | c0251 | captured |", "README")
		absent(readme, "*captured* (c0251)", "README")
		absent(
			readme,
			"today `idea-challenge` and `code-review` name an `author`, which drops that model",
			"README"
		)
		-- line 108's old rule is reworded, keeping the words c0264's done check pins
		absent(
			readme,
			"which drops that model; `design-challenge` and a raft's review run on the same model as their author",
			"README"
		)
		at(readme, "Every review runs on an expensive role", "README")
		at(readme, "except a stream review, which runs on the cheap `stream-review` role", "README")
		at(readme, "`raft-review` for a raft's review", "README")
		at(readme, "Any model may run any review. The one quality rule is the frontier floor", "README")
		absent(
			readme,
			"A command refuses a design review or a final review recorded off its role's kind of model",
			"README"
		)
		-- "Reviews by different models" keeps exactly two labels, `c0251` then a bare one (c0264's label places)
		local from = string.find(readme, "### Reviews by different models", 1, true) :: number
		local upto = string.find(readme, "### The full-force review", from, true) :: number
		local section = string.sub(readme, from, upto - 1)
		t.expect(select(2, string.gsub(section, "%*exists%*", ""))).toBe(2)
		t.expect(select(2, string.gsub(section, "%*exists%* %(c0251%)", ""))).toBe(1)
		t.expect(select(2, string.gsub(section, "%*captured%*", ""))).toBe(0)
		at(readme, "`[families]`", "README")
		-- every sentence of the section stays
		at(
			readme,
			"Same-family review (Opus reviewing Opus) is fine, but it is the fallback and never the only choice",
			"README"
		)
		at(readme, "nothing flags it", "README")
		absent(readme, "The board flags fallback reviews", "README")
		absent(readme, "ask for a cross-model re-review", "README")
	end)

	it("AC13: .models.toml's header comment states the pool, the tiers and the picker", function()
		local text = read(".models.toml")
		at(text, "A role's tries are its own model, the members its `pool` lists", ".models.toml")
		at(text, "rotate = true", ".models.toml")
		at(text, "tier 1", ".models.toml")
		at(text, "tier 3", ".models.toml")
		at(text, "[families] maps a model line to its id prefixes", ".models.toml")
		at(text, "the one quality rule is the [review] frontier floor", ".models.toml")
		at(text, "`designed-by` line of its document", ".models.toml")
		at(text, "raft-review", ".models.toml")
		absent(text, "naming the author would drop that model", ".models.toml")
		absent(text, "would drop", ".models.toml")
		absent(text, "flagged", ".models.toml")
	end)

	it("AC13: AGENTS.md carries none of the new rule text (it is c0332's)", function()
		local agents = read("AGENTS.md")
		for _, word in { "stream-review", "Fallback:", "reviewpool", "[families]", "rotate = true", "tier 3" } do
			absent(agents, word, "AGENTS.md")
		end
	end)

	it(
		"AC18: the root .models.toml names the members, the pools, rotate on the review roles and the frontier list",
		function()
			local layers = { M.parse(read(".models.toml"), ".models.toml") }
			local layer: any = layers[1]
			t.expect(layer.members.fable.model).toBe("claude-fable-5-2")
			t.expect(layer.members.fable.cli).toBe("claude")
			t.expect(layer.members.opus).toBe(nil)
			t.expect(layer.roles["design-challenge"].pool).toEqual({ "fable" })
			t.expect(layer.roles["raft-review"].pool).toEqual({ "fable" })
			t.expect(layer.roles["code-review"].pool).toEqual({ "fable" })
			t.expect(layer.roles["final-review"].pool).toBe(nil)
			-- user, 2026-11-16: writing a raft and reviewing one are two roles; the writing role does not rotate
			t.expect(layer.roles.raft.pool).toBe(nil)
			t.expect(layer.roles.raft.rotate).toBe(nil)
			for _, role in
				{
					"idea-challenge",
					"design-challenge",
					"raft-review",
					"code-review",
					"final-review",
					"stream-review",
				}
			do
				t.expect(layer.roles[role].rotate).toBe(true)
			end
			for _, role in { "idea", "design", "raft", "implementation" } do
				t.expect(layer.roles[role].rotate).toBe(nil)
				t.expect(layer.roles[role].pool).toBe(nil)
			end
			t.expect(layer.roles["idea-challenge"].pool).toBe(nil)
			t.expect(layer.roles["idea-challenge"].author).toBe("idea")
			t.expect(layer.roles["code-review"].author).toBe("implementation")
			-- the model lines
			local families = M.families(layers)
			for _, name in { "opus", "fable", "sonnet", "haiku", "kimi", "grok", "deepseek", "composer" } do
				t.expect(families[name] ~= nil).toBe(true)
			end
			t.expect(families.opus).toEqual({ "claude-opus-" })
			t.expect(M.frontier(layers)[1]).toBe("claude-opus-5-5")
		end
	)

	it(
		"AC18: the pools in the order the tries run them: primary, the pool member, then the CLI fallbacks",
		function()
			local layers = { M.parse(read(".models.toml"), ".models.toml") }
			t.expect(tryIds(layers, "zz-review", "design")).toEqual({
				"claude:claude-opus-5-5",
				"claude:claude-fable-5-2",
				"kimi:kimi-code-k3.1-pro",
				"grok:grok-4.7",
				"agent:claude-opus-5-5",
			})
			t.expect(tryIds(layers, "zz-review", "code")).toEqual(tryIds(layers, "zz-review", "design"))
			t.expect(tryIds(layers, "zz-review", "raft")).toEqual(tryIds(layers, "zz-review", "design"))
			-- user, 2026-11-16: the final review is Fable, kimi k3.1 pro, grok 4.7 (at the role's xhigh), then Opus last
			t.expect(tryIds(layers, "zz-review", "final")).toEqual({
				"claude:claude-fable-5-2",
				"kimi:kimi-code-k3.1-pro",
				"grok:grok-4.7",
				"agent:claude-opus-5-5",
			})
			t.expect(M.resolve(layers, "zz-review", "final").specs.grok.effort).toBe("xhigh")
			-- the authoring roles keep their order: no member, no rotation
			t.expect(tryIds(layers, "z-run")).toEqual({
				"claude:claude-sonnet-5-5",
				"kimi:kimi-code-k3.1-pro",
				"grok:grok-4.7",
				"agent:claude-opus-5-5",
			})
			t.expect(tryIds(layers, "z-design")[2]).toBe("kimi:kimi-code-k3.1-pro")
			-- z-raft writes on the `raft` role, which has no Fable member: that is the raft-review role's
			t.expect(M.resolve(layers, "zz-review", "raft").skill).toBe("raft-review")
			t.expect(tryIds(layers, "z-raft")).toEqual({
				"claude:claude-opus-5-5",
				"kimi:kimi-code-k3.1-pro",
				"grok:grok-4.7",
				"agent:claude-opus-5-5",
			})
		end
	)

	it(
		"AC18: the stream-review list is Haiku, Sonnet, grok-4.6, then composer, with no CLI fallback; kimi r2.8 is not seeded",
		function()
			local layers = { M.parse(read(".models.toml"), ".models.toml") }
			local layer: any = layers[1]
			local stream = layer.roles["stream-review"]
			t.expect(stream.model).toBe("claude-haiku-5-5")
			t.expect(stream.cli).toBe("claude")
			t.expect(stream.runtime).toBe("claude-cli")
			t.expect(stream.pool).toEqual({ "sonnet", "grok46", "composer" })
			t.expect(stream.fallbacks).toEqual({})
			t.expect(layer.members.sonnet.model).toBe("claude-sonnet-5-5")
			t.expect(layer.members.sonnet.cli).toBe("claude")
			t.expect(layer.members.grok46.model).toBe("grok-4.6")
			t.expect(layer.members.grok46.cli).toBe("grok")
			t.expect(layer.members.grok46.runtime).toBe("grok-cli")
			t.expect(layer.members.composer.model).toBe("composer-2.5")
			t.expect(layer.members.composer.cli).toBe("agent")
			t.expect(layer.members.composer.runtime).toBe("cursor-cli")
			t.expect(stream.rotate).toBe(true)
			local r = M.resolve(layers, "zz-review", "stream")
			t.expect(r.skill).toBe("stream-review")
			t.expect(tryIds(layers, "zz-review", "stream")).toEqual({
				"claude:claude-haiku-5-5",
				"claude:claude-sonnet-5-5",
				"grok:grok-4.6",
				"agent:composer-2.5",
			})
			-- no id for kimi r2.8 exists on any CLI's list, so none is seeded
			for _, name in layer.roles["stream-review"].pool do
				t.expect((string.find(layer.members[name].model, "r2", 1, true))).toBe(nil)
			end
			-- the code-review role is no longer the stream's
			t.expect(r.specs.claude.model == M.resolve(layers, "zz-review", "code").specs.claude.model)
				.toBe(false)
		end
	)
end)
