--!strict
-- c0251 AC13 and AC18: the skills, `.models.toml`'s comments and the README state the tier rule and no longer say a challenge is
-- never run by the model that wrote the text; the README's c0251 markers read `*exists*`; AGENTS.md is untouched (c0332's);
-- and the root `.models.toml` names Fable in the design-challenge, raft and code-review pools, Opus in final-review's, and
-- `stream-review` on `claude-haiku-5-5` with fallbacks `kimi` and `grok`.
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
	it("AC13: zz-review states the tier rule, the interactive pick and the Fallback: line", function()
		local text = skill("zz-review")
		at(text, "`stream-review` for a stream review", "zz-review")
		at(text, "tier 1 differs from the author and from the previous round", "zz-review")
		at(text, "tier 2 differs from the author only", "zz-review")
		at(text, "tier 3 is the author's own family, the flagged fallback", "zz-review")
		at(text, "the exact model that wrote the text last", "zz-review")
		at(text, "and it never stops the chain", "zz-review")
		at(text, "`[families]`", "zz-review")
		at(text, "`./zn dispatch zz-review <id> --mode <m> --dry-run --author <its model id>`", "zz-review")
		at(text, "the `pick:` line", "zz-review")
		at(
			text,
			"the `--author` typed, `ZN_MODEL`, the spend rows, and the writing role's first choice",
			"zz-review"
		)
		at(text, "`./zn dispatch zz-review <id> --mode <m> --author <its model id>`", "zz-review")
		at(
			text,
			"`./zn spend … --author <its model id>` and `./zn commit … --author <its model id>`",
			"zz-review"
		)
		at(text, "unchanged except for the `Model:`, `Effort:` and `Fallback:` lines it records", "zz-review")
		at(text, "which any item, marked or not, and a stream review allow", "zz-review")
		at(text, "(design, code, final, idea or stream)", "zz-review")
		at(text, "the board prints it", "zz-review")
		at(text, "`Fallback: <reason>` is a stamped line the tool writes", "zz-review")
		at(text, "never the reviewer and never typed", "zz-review")
		at(text, "or carries a `Fallback:` line", "zz-review")
		absent(text, "A challenge is never run by the model that wrote the text", "zz-review")
		absent(text, "so that model is dropped", "zz-review")
		absent(text, "naming the author would drop it", "zz-review")
	end)

	it("AC13: z-design, z-raft, zz-execute and zz-rules restate who reviews", function()
		local design = skill("z-design")
		at(design, "on the model line the picker chooses away from the one that wrote the design", "z-design")
		at(design, "start the reviewer subagent on the `pick:` model", "z-design")
		at(design, "or one flagged `Fallback:`, is superseded by a new round", "z-design")
		at(design, "or run the review with `--author <your model id>`", "z-design")
		at(design, "`--effort <level>` and `--author <your model id>`", "z-design")
		absent(design, "never on the model that wrote the design", "z-design")
		local raft = skill("z-raft")
		at(raft, "The picker chooses the model line away from the one that wrote the raft", "z-raft")
		at(raft, "or one flagged `Fallback:`, is superseded by a new round", "z-raft")
		-- the old sentence is gone
		absent(raft, "naming the author would drop it", "z-raft")
		absent(raft, "That role names no author", "z-raft")
		local execute = skill("zz-execute")
		at(
			execute,
			"on the model line the picker chooses away from the one that wrote the code",
			"zz-execute"
		)
		at(execute, "start the reviewer subagent on the `pick:` model", "zz-execute")
		at(execute, "or one flagged `Fallback:`, is superseded by a new round", "zz-execute")
		at(execute, "on the `pick:` model of its `--dry-run`", "zz-execute")
		at(execute, "`./zn commit --phase code-review --model <id> --author <your model id>`", "zz-execute")
		absent(execute, "never on the model that wrote the code", "zz-execute")
		local rules = skill("zz-rules")
		at(rules, "a `Fallback:` line it derives itself", "zz-rules")
		at(rules, "with a derived `Fallback:` line", "zz-rules")
		at(rules, "against `--author <the lead's model id>` (else `ZN_MODEL`, else the rows)", "zz-rules")
		at(rules, "A role's `pool` lists `[member.<name>]` models", "zz-rules")
		at(rules, "`rotate = true`", "zz-rules")
		at(rules, "`code-review`, `stream-review` and `final-review`", "zz-rules")
		absent(rules, "a try whose model is that author's is dropped", "zz-rules")
		absent(rules, "naming the author would drop it", "zz-rules")
	end)

	it(
		"AC13: the review-model rule and the visible record keep their text, and zz-review's record names the flag",
		function()
			local review = skill("zz-review")
			at(
				review,
				"**Review models.** Every review but a stream review runs on a review model",
				"zz-review"
			)
			at(review, "`claude-opus-`, `claude-fable-` or `kimi-code-k3`", "zz-review")
			at(review, "the next round supersedes it", "zz-review")
			at(review, "flagged on the board with the command that re-reviews it", "zz-review")
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
		at(readme, "The board flags fallback reviews", "README")
	end)

	it("AC13: .models.toml's header comment states the pool, the tiers and the picker", function()
		local text = read(".models.toml")
		at(text, "A role's tries are its own model, the members its `pool` lists", ".models.toml")
		at(text, "rotate = true", ".models.toml")
		at(text, "tier 1", ".models.toml")
		at(text, "tier 3", ".models.toml")
		at(text, "[families] maps a model line to its id prefixes", ".models.toml")
		absent(text, "naming the author would drop that model", ".models.toml")
		absent(text, "would drop", ".models.toml")
	end)

	it("AC13: AGENTS.md carries none of the new rule text (it is c0332's)", function()
		local agents = read("AGENTS.md")
		for _, word in { "stream-review", "Fallback:", "reviewpool", "[families]", "rotate = true", "tier 3" } do
			absent(agents, word, "AGENTS.md")
		end
	end)

	it("AC18: the root .models.toml names the members, the pools and rotate on the review roles", function()
		local layers = { M.parse(read(".models.toml"), ".models.toml") }
		local layer: any = layers[1]
		t.expect(layer.members.fable.model).toBe("claude-fable-5-2")
		t.expect(layer.members.fable.cli).toBe("claude")
		t.expect(layer.members.opus.model).toBe("claude-opus-5-5")
		t.expect(layer.members.opus.cli).toBe("claude")
		t.expect(layer.roles["design-challenge"].pool).toEqual({ "fable" })
		t.expect(layer.roles.raft.pool).toEqual({ "fable" })
		t.expect(layer.roles["code-review"].pool).toEqual({ "fable" })
		t.expect(layer.roles["final-review"].pool).toEqual({ "opus" })
		for _, role in
			{ "idea-challenge", "design-challenge", "raft", "code-review", "final-review", "stream-review" }
		do
			t.expect(layer.roles[role].rotate).toBe(true)
		end
		for _, role in { "idea", "design", "implementation" } do
			t.expect(layer.roles[role].rotate).toBe(nil)
			t.expect(layer.roles[role].pool).toBe(nil)
		end
		t.expect(layer.roles["idea-challenge"].pool).toBe(nil)
		t.expect(layer.roles["idea-challenge"].author).toBe("idea")
		t.expect(layer.roles["code-review"].author).toBe("implementation")
		-- the model lines
		local families = M.families(layers)
		for _, name in { "opus", "fable", "sonnet", "haiku", "kimi", "grok", "deepseek" } do
			t.expect(families[name] ~= nil).toBe(true)
		end
		t.expect(families.opus).toEqual({ "claude-opus-" })
	end)

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
			t.expect(tryIds(layers, "zz-review", "final")).toEqual({
				"claude:claude-fable-5-2",
				"claude:claude-opus-5-5",
				"kimi:kimi-code-k3.1-pro",
				"grok:grok-4.7",
				"agent:claude-opus-5-5",
			})
			-- the authoring roles keep their order: no member, no rotation
			t.expect(tryIds(layers, "z-run")).toEqual({
				"claude:claude-sonnet-5-5",
				"kimi:kimi-code-k3.1-pro",
				"grok:grok-4.7",
				"agent:claude-opus-5-5",
			})
			t.expect(tryIds(layers, "z-design")[2]).toBe("kimi:kimi-code-k3.1-pro")
			-- z-raft authors on the `raft` role, which a raft review gives a Fable member: the authoring step does not
			t.expect(tryIds(layers, "z-raft")).toEqual({
				"claude:claude-opus-5-5",
				"kimi:kimi-code-k3.1-pro",
				"grok:grok-4.7",
				"agent:claude-opus-5-5",
			})
		end
	)

	it(
		"AC18: stream-review is claude-haiku-5-5 with the cheap Sonnet member and no CLI fallback, and the cheap role runs a stream review",
		function()
			local layers = { M.parse(read(".models.toml"), ".models.toml") }
			local layer: any = layers[1]
			local stream = layer.roles["stream-review"]
			t.expect(stream.model).toBe("claude-haiku-5-5")
			t.expect(stream.cli).toBe("claude")
			t.expect(stream.runtime).toBe("claude-cli")
			-- the cheap second model is Sonnet; kimi and grok are not cheap, so the role has no CLI fallback
			t.expect(stream.pool).toEqual({ "sonnet" })
			t.expect(stream.fallbacks).toEqual({})
			t.expect(layer.members.sonnet.model).toBe("claude-sonnet-5-5")
			t.expect(layer.members.sonnet.cli).toBe("claude")
			t.expect(stream.rotate).toBe(true)
			local r = M.resolve(layers, "zz-review", "stream")
			t.expect(r.skill).toBe("stream-review")
			t.expect(tryIds(layers, "zz-review", "stream")).toEqual({
				"claude:claude-haiku-5-5",
				"claude:claude-sonnet-5-5",
			})
			-- the code-review role is no longer the stream's
			t.expect(r.specs.claude.model == M.resolve(layers, "zz-review", "code").specs.claude.model)
				.toBe(false)
		end
	)
end)
