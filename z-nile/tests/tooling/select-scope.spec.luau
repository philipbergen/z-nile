--!strict
-- c0239 AC6, on the watch map: `select.scope` names one project only for a non-empty selection inside that
-- project, with every changed path under its home. An empty selection is "ALL". Plain tables, no I/O.
local sel = require("@znile/lib/select")
local t = require("@tests/lib/t")

local rules: sel.Rules = {
	homes = {
		{ name = "pickman", prefix = "pickman/" },
		{ name = "snake", prefix = "snake/" },
		{ name = "z-nile", prefix = "z-nile/" },
	},
	roots = { "pickman/.tracker", "snake/.tracker", "z-nile/.tracker" },
}

local function ctx(watches: { [string]: { string } }?): sel.Context
	return {
		rules = rules,
		graph = { files = {}, deps = {}, unresolved = {}, dynamic = {} },
		inputs = {},
		places = {},
		watches = watches or {
			["pickman/tests/unit/a.spec.luau"] = { "pickman/src/A.luau" },
			["snake/tests/unit/s.spec.luau"] = { "snake/src/S.luau" },
		},
	}
end

return t.spec("c0239 select.scope", function(it)
	it("a watched source file inside one project names it", function()
		t.expect(sel.scope(ctx(), { "pickman/src/A.luau" })).toBe("pickman")
		t.expect(sel.scope(ctx(), { "snake/src/S.luau", "snake/tests/unit/s.spec.luau" })).toBe("snake")
	end)

	it("an empty change set and an unwatched path are ALL", function()
		t.expect(sel.scope(ctx(), {})).toBe("ALL")
		t.expect(sel.scope(ctx(), { "pickman/src/Unread.luau" })).toBe("ALL")
		t.expect(sel.affected(ctx(), { "z-nile/skills/zz-test/SKILL.md" })).toEqual({})
		t.expect(sel.affected(ctx(), { "pickman/.tracker/issues/f0001/f0001.md" })).toEqual({})
	end)

	it("an unwatched engine or project file does not name a project by itself", function()
		t.expect(sel.scope(ctx(), { "z-nile/lib/changed.luau" })).toBe("ALL")
		t.expect(sel.scope(ctx(), { "pickman/src/A.luau", "z-nile/lib/changed.luau" })).toBe("ALL")
		t.expect(sel.scope(ctx(), { "pickman/default.project.json" })).toBe("ALL")
	end)

	it("a changed path outside the project's home keeps ALL", function()
		t.expect(sel.scope(ctx(), { "pickman/src/A.luau", "SETUP.md" })).toBe("ALL")
		t.expect(sel.scope(ctx(), { "pickman/src/A.luau", "snake/notes.md" })).toBe("ALL")
		t.expect(sel.scope(ctx(), { "pickman/src/A.luau", "pickman/.tracker/notes.md" })).toBe("pickman")
	end)

	it("watch files in two projects are ALL", function()
		t.expect(sel.scope(ctx(), { "pickman/src/A.luau", "snake/src/S.luau" })).toBe("ALL")
		local shared = ctx({
			["pickman/tests/unit/a.spec.luau"] = { "z-nile/tests/shared.txt" },
			["z-nile/tests/tooling/z.spec.luau"] = { "z-nile/tests/shared.txt" },
		})
		t.expect(sel.scope(shared, { "z-nile/tests/shared.txt" })).toBe("ALL")
		t.expect(sel.affected(shared, { "z-nile/tests/shared.txt" })).toEqual({
			"pickman/tests/unit/a.spec.luau",
			"z-nile/tests/tooling/z.spec.luau",
		})
	end)

	it("a changed spec is selected even when no watch file names it yet", function()
		t.expect(sel.affected(ctx(), { "pickman/tests/unit/new.spec.luau" })).toEqual({
			"pickman/tests/unit/new.spec.luau",
		})
	end)
end)
