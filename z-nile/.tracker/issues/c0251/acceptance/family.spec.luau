--!strict
-- c0251 AC1 and AC2: `family.of` maps a model id to its model line by the longest matching prefix, and `.models.toml` reads
-- the `[families]` table, a role's `rotate`, and the `stream-review` role. Pure: texts in, results out.
local models = require("@znile/engine/models")
local t = require("@tests/lib/t")

local family: any = require("@znile/engine/family")
local M: any = models

local function errorOf(f: () -> ()): string
	local ok, e = pcall(f :: any)
	if ok then
		return ""
	end
	return tostring(e)
end

local function has(text: string, needle: string): boolean
	return string.find(text, needle, 1, true) ~= nil
end

local TABLE = {
	opus = { "claude-opus-" },
	fable = { "claude-fable-" },
	kimi = { "kimi-" },
	grok = { "grok-" },
}

local ROLE = [[
[fallback.kimi]
model = "kimi-code-k3.1-pro"
runtime = "kimi-cli"

[roles.raft]
model = "claude-opus-5-5"
cli = "claude"
runtime = "claude-cli"
rank = 3
max_tokens = 1000
effort = "high"
fallbacks = ["kimi"]
]]

local function layer(text: string, path: string?): any
	return M.parse(text, path or ".models.toml")
end

return t.spec("c0251 families and rotate in .models.toml", function(it)
	it(
		"AC1: family.of returns the family of the longest matching prefix, whatever the table order",
		function()
			-- a shorter prefix of another family never beats a longer one, in either insertion order
			local a = { broad = { "claude-" }, narrow = { "claude-opus-" } }
			local b = { narrow = { "claude-opus-" }, broad = { "claude-" } }
			t.expect(family.of("claude-opus-5-5", a)).toBe("narrow")
			t.expect(family.of("claude-opus-5-5", b)).toBe("narrow")
			t.expect(family.of("claude-sonnet-5-5", a)).toBe("broad")
			t.expect(family.of("claude-sonnet-5-5", b)).toBe("broad")
			-- within one family the list order is no rule either
			local c = { claude = { "claude-", "claude-opus-" }, other = { "claude-op" } }
			t.expect(family.of("claude-opus-5-5", c)).toBe("claude")
			local d = { other = { "claude-op" }, claude = { "claude-opus-", "claude-" } }
			t.expect(family.of("claude-opus-5-5", d)).toBe("claude")
			t.expect(family.of("claude-opus-5-5", TABLE)).toBe("opus")
			t.expect(family.of("kimi-code-k3.1-pro", TABLE)).toBe("kimi")
			t.expect(family.of("grok-4.7", TABLE)).toBe("grok")
		end
	)

	it("AC1: family.of gives nil when no prefix matches, and tolerates a context marker like [1m]", function()
		t.expect(family.of("gemini-3", TABLE)).toBe(nil)
		t.expect(family.of("", TABLE)).toBe(nil)
		t.expect(family.of("claude-opus-5-5", {})).toBe(nil)
		t.expect(family.of("claude-opus-5-5[1m]", TABLE)).toBe("opus")
		t.expect(family.of("claude-fable-5-2[200k]", TABLE)).toBe("fable")
		-- a prefix is matched at the start of the id, not inside it
		t.expect(family.of("xclaude-opus-5-5", TABLE)).toBe(nil)
	end)

	it("AC1: family.same is false when either side is nil, and true for one family", function()
		t.expect(family.same(nil, "opus")).toBe(false)
		t.expect(family.same("opus", nil)).toBe(false)
		t.expect(family.same(nil, nil)).toBe(false)
		t.expect(family.same("opus", "opus")).toBe(true)
		t.expect(family.same("opus", "fable")).toBe(false)
	end)

	it("AC2: models.parse reads [families] into the layer", function()
		local l = layer('[families]\nopus = ["claude-opus-"]\nkimi = ["kimi-", "moonshot-"]\n')
		t.expect(l.families).toEqual({ opus = { "claude-opus-" }, kimi = { "kimi-", "moonshot-" } })
		t.expect(layer("[dispatch]\nstall_seconds = 60\n").families).toEqual({})
	end)

	it("AC2: a closer file replaces only the family keys it sets", function()
		local root = layer('[families]\nopus = ["claude-opus-"]\nkimi = ["kimi-"]\n')
		local closer = layer('[families]\nkimi = ["kimi-code-"]\n', "pickman/.models.toml")
		local merged = M.families({ root, closer })
		t.expect(merged.opus).toEqual({ "claude-opus-" })
		t.expect(merged.kimi).toEqual({ "kimi-code-" })
		t.expect(M.families({})).toEqual({})
	end)

	it(
		"AC2: a prefix under two families, a non-list, an empty prefix and an empty list are refused",
		function()
			local dup = errorOf(function()
				layer('[families]\nopus = ["claude-"]\nfable = ["claude-"]\n')
			end)
			t.expect(has(dup, "claude-")).toBe(true)
			t.expect(has(dup, ".models.toml")).toBe(true)
			t.expect(errorOf(function()
				layer('[families]\nopus = "claude-opus-"\n')
			end) ~= "").toBe(true)
			t.expect(errorOf(function()
				layer('[families]\nopus = [""]\n')
			end) ~= "").toBe(true)
			t.expect(errorOf(function()
				layer("[families]\nopus = []\n")
			end) ~= "").toBe(true)
			t.expect(errorOf(function()
				layer('families = "x"\n')
			end) ~= "").toBe(true)
		end
	)

	it("AC2: rotate takes only a boolean on a role", function()
		local l = layer(ROLE .. "rotate = true\n")
		t.expect(l.roles.raft.rotate).toBe(true)
		t.expect(layer(ROLE .. "rotate = false\n").roles.raft.rotate).toBe(false)
		for _, bad in { 'rotate = "yes"\n', "rotate = 1\n", "rotate = []\n" } do
			local e = errorOf(function()
				layer(ROLE .. bad)
			end)
			t.expect(has(e, "rotate")).toBe(true)
			t.expect(has(e, "roles.raft")).toBe(true)
		end
		-- rotate is no key of a fallback
		t.expect(errorOf(function()
			layer('[fallback.kimi]\nmodel = "kimi-code-k3.1-pro"\nruntime = "kimi-cli"\nrotate = true\n')
		end) ~= "").toBe(true)
	end)

	it(
		"AC2: roleFor gives stream-review for a stream review, and the other modes keep their roles",
		function()
			t.expect(M.roleFor("zz-review", "stream")).toBe("stream-review")
			t.expect(M.roleFor("zz-review", "code")).toBe("code-review")
			t.expect(M.roleFor("zz-review", nil)).toBe("code-review")
			t.expect(M.roleFor("zz-review", "design")).toBe("design-challenge")
			t.expect(M.roleFor("zz-review", "raft")).toBe("raft")
			t.expect(M.roleFor("zz-review", "final")).toBe("final-review")
		end
	)

	it(
		"AC2: a rotate role whose model has no family fails at resolve, naming the role and the model",
		function()
			-- loads fine: the check is at resolve, so a fixture with no [families] and no rotate loads as before
			local plain = layer(ROLE)
			local r = M.resolve({ plain }, "z-raft")
			t.expect(#M.tries(r)).toBe(2)
			local rotating = layer(ROLE .. "rotate = true\n")
			local e = errorOf(function()
				M.resolve({ rotating }, "z-raft")
			end)
			t.expect(has(e, "raft")).toBe(true)
			t.expect(has(e, "claude-opus-5-5")).toBe(true)
			t.expect(has(e, "[families]")).toBe(true)
			-- the same role resolves once every model has a family
			local fams = layer('[families]\nopus = ["claude-opus-"]\nkimi = ["kimi-"]\n')
			local ok = M.resolve({ fams, rotating }, "z-raft")
			t.expect(ok.rotate).toBe(true)
			t.expect(ok.families.opus).toEqual({ "claude-opus-" })
			-- a family missing for the fallback alone fails too
			local noKimi = layer('[families]\nopus = ["claude-opus-"]\n')
			local e2 = errorOf(function()
				M.resolve({ noKimi, rotating }, "z-raft")
			end)
			t.expect(has(e2, "kimi-code-k3.1-pro")).toBe(true)
		end
	)
end)
