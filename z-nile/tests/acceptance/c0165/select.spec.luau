--!strict
-- The watch map is the one predicate of selection. A path selects a spec exactly when
-- it is that spec, its watch file, or a path the watch file names. Nothing falls back to every spec.
local select = require("@znile/lib/select")
local t = require("@tests/lib/t")

local SPEC = "pickman/tests/unit/a.spec.luau"
local WATCH = "pickman/tests/unit/a.watch.txt"
local SRC = "pickman/src/A.luau"
local rules: select.Rules = {
	homes = {
		{ name = "pickman", prefix = "pickman/" },
		{ name = "z-nile", prefix = "z-nile/" },
	},
	roots = { "pickman/.tracker", "z-nile/.tracker" },
}
local function ctx(): select.Context
	return {
		rules = rules,
		graph = { files = {}, deps = {}, unresolved = {}, dynamic = {} },
		inputs = {},
		places = {},
		watches = { [SPEC] = { SRC } },
	}
end

return t.spec("c0165 the watch map selects a spec from the paths its watch names", function(it)
	it("a watched source file selects that spec and no other, and a skill selects nothing", function()
		local c = ctx()
		t.expect(select.affected(c, { SRC })).toEqual({ SPEC })
		t.expect(select.affected(c, { "z-nile/skills/zz-test/SKILL.md" })).toEqual({})
		t.expect(select.affected(c, { "pickman/.tracker/issues/f0001/f0001.md" })).toEqual({})
		t.expect(select.affected(c, { "z-nile/engine/main.luau" })).toEqual({})
		t.expect(select.affected(c, { "pickman/default.project.json" }, "pickman")).toEqual({})
		t.expect(select.isInput(c, SPEC, SRC)).toBe(true)
		t.expect(select.isInput(c, SPEC, WATCH)).toBe(true)
		t.expect(select.isInput(c, SPEC, SPEC)).toBe(true)
		t.expect(select.isInput(c, SPEC, "README.md")).toBe(false)
	end)
end)
