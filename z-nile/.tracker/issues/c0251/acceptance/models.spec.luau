--!strict
-- c0251 AC16: a role may name `pool` members (`[member.<name>]` with cli, model and runtime) beside `fallbacks`. Its tries are the
-- primary, the members, then the fallbacks; two on one CLI coexist; `Resolved.order` and `.specs` keep the per-CLI view; `forRaft`
-- keys the tries by CLI and model; `knownModels` reads the members; and each malformed member is refused. Pure: .models.toml texts.
local models = require("@znile/engine/models")
local t = require("@tests/lib/t")

local M: any = models

local BASE = [[
[fallback.kimi]
model = "kimi-code-k3.1-pro"
runtime = "kimi-cli"

[fallback.grok]
model = "grok-4.7"
runtime = "grok-cli"

[fallback.agent]
model = "claude-opus-5-5"
runtime = "cursor-cli"
max_calls = 30
max_minutes = 60

[member.fable]
cli = "claude"
model = "claude-fable-5-2"
runtime = "claude-cli"

[member.opus-cursor]
cli = "agent"
model = "claude-opus-5-4"
runtime = "cursor-cli"
max_calls = 10
max_minutes = 20
]]

local ROLE = [[
[roles.design-challenge]
model = "claude-opus-5-5"
cli = "claude"
runtime = "claude-cli"
rank = 4
max_tokens = 3000
effort = "xhigh"
pool = ["fable"]
fallbacks = ["kimi", "grok", "agent"]
]]

local function errorOf(f: () -> ()): string
	local ok, e = pcall(f)
	return if ok then "" else tostring(e)
end
local function has(text: string, needle: string): boolean
	return string.find(text, needle, 1, true) ~= nil
end
local function layer(text: string, path: string?): any
	return M.parse(text, path or ".models.toml")
end
local function ids(tries: { models.Spec }): { string }
	local out = {}
	for _, s in tries do
		table.insert(out, `{s.cli}:{s.model}`)
	end
	return out
end

return t.spec("c0251 several models on one CLI", function(it)
	it("AC16: [member.*] and a role's pool parse", function()
		local l = layer(BASE .. ROLE)
		t.expect(l.members.fable)
			.toEqual({ cli = "claude", model = "claude-fable-5-2", runtime = "claude-cli" })
		t.expect(l.members["opus-cursor"].max_calls).toBe(10)
		t.expect(l.roles["design-challenge"].pool).toEqual({ "fable" })
		t.expect(layer(BASE).roles).toEqual({})
	end)

	it("AC16: the tries are the primary, the members in the order listed, then the fallbacks", function()
		local r = M.resolve({ layer(BASE .. ROLE) }, "zz-review", "design")
		t.expect(ids(M.tries(r))).toEqual({
			"claude:claude-opus-5-5",
			"claude:claude-fable-5-2",
			"kimi:kimi-code-k3.1-pro",
			"grok:grok-4.7",
			"agent:claude-opus-5-5",
		})
		-- members after fallbacks is wrong: reorder the pool and the tries follow the pool
		local two = M.resolve({
			layer(BASE .. ROLE),
			layer('[roles.design-challenge]\npool = ["opus-cursor", "fable"]\n', "x/.models.toml"),
		}, "zz-review", "design")
		t.expect(ids(M.tries(two))).toEqual({
			"claude:claude-opus-5-5",
			"agent:claude-opus-5-4",
			"claude:claude-fable-5-2",
			"kimi:kimi-code-k3.1-pro",
			"grok:grok-4.7",
			"agent:claude-opus-5-5",
		})
	end)

	it(
		"AC16: two specs on claude coexist, each with its own model, and a member carries the role's rank, cap and effort",
		function()
			local r = M.resolve({ layer(BASE .. ROLE) }, "zz-review", "design")
			local tries = M.tries(r)
			t.expect(#tries).toBe(5)
			t.expect(tries[1].cli).toBe("claude")
			t.expect(tries[2].cli).toBe("claude")
			t.expect(tries[2].model).toBe("claude-fable-5-2")
			t.expect(tries[2].effort).toBe("xhigh")
			t.expect(tries[2].rank).toBe(4)
			t.expect(tries[2].maxTokens).toBe(3000)
			t.expect(tries[2].runtime).toBe("claude-cli")
			t.expect(tries[2].member).toBe("fable")
			t.expect(tries[1].member).toBe(nil)
			-- a call-capped member keeps its own caps
			local capped = M.resolve({
				layer(BASE .. ROLE .. ""),
				layer('[roles.design-challenge]\npool = ["opus-cursor"]\n', "x/.models.toml"),
			}, "zz-review", "design")
			t.expect(M.tries(capped)[2].maxCalls).toBe(10)
			t.expect(M.tries(capped)[2].maxMinutes).toBe(20)
		end
	)

	it("AC16: order and specs keep the per-CLI view: each CLI once, its first spec", function()
		local r = M.resolve({ layer(BASE .. ROLE) }, "zz-review", "design")
		t.expect(r.order).toEqual({ "claude", "kimi", "grok", "agent" })
		t.expect(r.specs.claude.model).toBe("claude-opus-5-5")
		t.expect(r.specs.claude.member).toBe(nil)
		t.expect(r.specs.kimi.model).toBe("kimi-code-k3.1-pro")
		t.expect(r.specs.agent.model).toBe("claude-opus-5-5")
		-- a member on a CLI the role has not named yet adds that CLI at its place, once
		local cursorFirst = M.resolve({
			layer(BASE .. ROLE),
			layer(
				'[roles.design-challenge]\npool = ["opus-cursor", "fable"]\nfallbacks = ["kimi"]\n',
				"x/.models.toml"
			),
		}, "zz-review", "design")
		t.expect(cursorFirst.order).toEqual({ "claude", "agent", "kimi" })
		t.expect(cursorFirst.specs.agent.model).toBe("claude-opus-5-4")
		-- a role with no pool is what it was
		local plain =
			M.resolve({ layer(BASE .. string.gsub(ROLE, 'pool = %["fable"%]\n', "")) }, "zz-review", "design")
		t.expect(plain.order).toEqual({ "claude", "kimi", "grok", "agent" })
		t.expect(#M.tries(plain)).toBe(4)
		t.expect(#plain.pool).toBe(4)
	end)

	it("AC16: Resolved.pool is the tries in order, and models.tries returns it", function()
		local r = M.resolve({ layer(BASE .. ROLE) }, "zz-review", "design")
		t.expect(ids(r.pool)).toEqual(ids(M.tries(r)))
		t.expect(#r.pool).toBe(5)
	end)

	it(
		"AC16: a member that is a CLI name, a name with no member, a name listed twice and a repeated cli and model are refused",
		function()
			local cliName = errorOf(function()
				layer('[member.claude]\ncli = "claude"\nmodel = "claude-fable-5-2"\nruntime = "claude-cli"\n')
			end)
			t.expect(has(cliName, "member.claude")).toBe(true)
			t.expect(has(cliName, ".models.toml")).toBe(true)
			local unknown = errorOf(function()
				M.resolve({ layer(BASE .. string.gsub(ROLE, '"fable"', '"nobody"')) }, "zz-review", "design")
			end)
			t.expect(has(unknown, "nobody")).toBe(true)
			t.expect(has(unknown, "member.nobody")).toBe(true)
			local twice = errorOf(function()
				layer(BASE .. string.gsub(ROLE, '"fable"', '"fable", "fable"'))
			end)
			t.expect(has(twice, "fable")).toBe(true)
			t.expect(has(twice, "twice")).toBe(true)
			-- the same cli and model twice in one role: a member equal to the primary
			local repeated = errorOf(function()
				M.resolve({
					layer(BASE .. ROLE),
					layer(
						'[member.dup]\ncli = "claude"\nmodel = "claude-opus-5-5"\nruntime = "claude-cli"\n[roles.design-challenge]\npool = ["dup"]\n',
						"x/.models.toml"
					),
				}, "zz-review", "design")
			end)
			t.expect(has(repeated, "claude-opus-5-5")).toBe(true)
			t.expect(has(repeated, "repeats")).toBe(true)
		end
	)

	it(
		"AC16: a member with the wrong runtime, a model of another CLI, no cli or a role-only key is refused",
		function()
			local runtime = errorOf(function()
				layer('[member.x]\ncli = "claude"\nmodel = "claude-fable-5-2"\nruntime = "grok-cli"\n')
			end)
			t.expect(has(runtime, "member.x.runtime")).toBe(true)
			t.expect(has(runtime, "claude-cli")).toBe(true)
			local shape = errorOf(function()
				layer('[member.x]\ncli = "claude"\nmodel = "grok-4.7"\nruntime = "claude-cli"\n')
			end)
			t.expect(has(shape, "member.x.model")).toBe(true)
			t.expect(has(shape, "claude")).toBe(true)
			-- a member with no cli anywhere on the walk is refused when a role's pool names it (a closer file may set it)
			local noCli = errorOf(function()
				M.resolve({
					layer(BASE .. ROLE),
					layer(
						'[member.x]\nmodel = "claude-fable-5-3"\nruntime = "claude-cli"\n[roles.design-challenge]\npool = ["x"]\n',
						"x/.models.toml"
					),
				}, "zz-review", "design")
			end)
			t.expect(has(noCli, "member.x")).toBe(true)
			t.expect(has(noCli, "no cli")).toBe(true)
			t.expect(has(
				errorOf(function()
					layer(
						'[member.x]\ncli = "claude"\nmodel = "claude-fable-5-2"\nruntime = "claude-cli"\nrank = 3\n'
					)
				end),
				"belongs to the role"
			)).toBe(true)
			t.expect(has(
				errorOf(function()
					layer('[member.x]\ncli = "codex"\nmodel = "claude-fable-5-2"\nruntime = "claude-cli"\n')
				end),
				"not a supported CLI"
			)).toBe(true)
			-- a call-capped CLI's member needs its cap
			local cap = errorOf(function()
				M.resolve({
					layer(BASE .. ROLE),
					layer(
						'[member.nocap]\ncli = "agent"\nmodel = "claude-opus-5-4"\nruntime = "cursor-cli"\n[roles.design-challenge]\npool = ["nocap"]\n',
						"x/.models.toml"
					),
				}, "zz-review", "design")
			end)
			t.expect(has(cap, "max_calls")).toBe(true)
			-- a pool that is not a list
			t.expect(errorOf(function()
				layer(BASE .. string.gsub(ROLE, 'pool = %["fable"%]', 'pool = "fable"'))
			end) ~= "").toBe(true)
		end
	)

	it("AC16: a closer file replaces only the member keys it sets", function()
		local closer = layer('[member.fable]\nmodel = "claude-fable-5-3"\n', "x/.models.toml")
		local r = M.resolve({ layer(BASE .. ROLE), closer }, "zz-review", "design")
		t.expect(M.tries(r)[2].model).toBe("claude-fable-5-3")
		t.expect(M.tries(r)[2].runtime).toBe("claude-cli")
		t.expect(M.tries(r)[2].cli).toBe("claude")
	end)

	it(
		"AC16: forRaft keys each try by cli and model, taking the strongest of the members' same-keyed entries",
		function()
			local weak = layer("[roles.design-challenge]\nrank = 2\nmax_tokens = 100\n", "m/.models.toml")
			local own = M.resolve({ layer(BASE .. ROLE) }, "zz-review", "design")
			local cheap = M.resolve({ layer(BASE .. ROLE), weak }, "zz-review", "design")
			local rich = own
			local r = M.forRaft(rich, { cheap, cheap })
			t.expect(ids(M.tries(r))).toEqual(ids(M.tries(own)))
			-- the cheap members' caps win here, for the two claude tries separately
			t.expect(M.tries(r)[1].maxTokens).toBe(100)
			t.expect(M.tries(r)[2].maxTokens).toBe(100)
			local mixed = M.forRaft(rich, { cheap, rich })
			t.expect(M.tries(mixed)[1].maxTokens).toBe(3000)
			t.expect(M.tries(mixed)[2].maxTokens).toBe(3000)
			t.expect(mixed.order).toEqual(own.order)
			t.expect(mixed.specs.claude.model).toBe("claude-opus-5-5")
			-- a try only a member has is ignored: the member's Fable is not in the raft's own pool
			local noPool = M.resolve(
				{ layer(BASE .. string.gsub(ROLE, 'pool = %["fable"%]\n', "")) },
				"zz-review",
				"design"
			)
			local ignored = M.forRaft(noPool, { own })
			t.expect(ids(M.tries(ignored))).toEqual(ids(M.tries(noPool)))
			t.expect(has(
				errorOf(function()
					M.forRaft(own, {})
				end),
				"no member"
			)).toBe(true)
		end
	)

	it("AC16: knownModels includes the members' models, bare and sorted", function()
		local known = M.knownModels({ layer(BASE .. ROLE) })
		t.expect(table.find(known, "claude-fable-5-2") ~= nil).toBe(true)
		t.expect(table.find(known, "claude-opus-5-4") ~= nil).toBe(true)
		local sorted = table.clone(known)
		table.sort(sorted)
		t.expect(known).toEqual(sorted)
		-- a Fable record on a role whose primary is Opus is recognised: the effort is cut off, not the model's own hyphens
		t.expect(M.modelOf("claude-fable-5-2-xhigh", known)).toBe("claude-fable-5-2")
		t.expect(M.modelOf("claude-fable-5-2[1m]-high", known)).toBe("claude-fable-5-2")
	end)
end)
