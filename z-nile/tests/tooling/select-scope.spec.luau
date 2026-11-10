--!strict
-- c0239 AC6: `select.scope(ctx, changed)` names one project only for a non-empty selection inside that project, with
-- every changed path under its home and nothing forcing; "ALL" for everything else. Plain tables, no I/O.
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

local function ctx(inputs: sel.Inputs?): sel.Context
	return {
		rules = rules,
		graph = {
			files = {
				"pickman/src/A.luau",
				"pickman/tests/unit/a.spec.luau",
				"snake/src/S.luau",
				"snake/tests/unit/s.spec.luau",
				"z-nile/tests/tooling/z.spec.luau",
			},
			deps = {
				["pickman/tests/unit/a.spec.luau"] = { "pickman/src/A.luau" },
				["snake/tests/unit/s.spec.luau"] = { "snake/src/S.luau" },
			},
			unresolved = {},
			dynamic = {},
		},
		inputs = inputs or {},
		places = {},
	}
end

return t.spec("c0239 select.scope", function(it)
	it("AC6: a pure change inside one project names it", function()
		t.expect(sel.scope(ctx(), { "pickman/src/A.luau" })).toBe("pickman")
		t.expect(sel.scope(ctx(), { "snake/src/S.luau", "snake/tests/unit/s.spec.luau" })).toBe("snake")
	end)

	it("AC6: an empty change set and an empty selection are ALL", function()
		t.expect(sel.scope(ctx(), {})).toBe("ALL")
		t.expect(sel.scope(ctx(), { "pickman/src/Unread.luau" })).toBe("ALL")
	end)

	it("AC6: a forcing path is ALL, whatever else changed", function()
		t.expect(sel.scope(ctx(), { "z-nile/lib/changed.luau" })).toBe("ALL")
		t.expect(sel.scope(ctx(), { "pickman/src/A.luau", "z-nile/lib/changed.luau" })).toBe("ALL")
		t.expect(sel.scope(ctx(), { "pickman/default.project.json" })).toBe("ALL")
	end)

	it(
		"AC6: rule 4: a changed path outside the project's home keeps ALL even when it selects nothing",
		function()
			t.expect(sel.scope(ctx(), { "pickman/src/A.luau", "SETUP.md" })).toBe("ALL")
			t.expect(sel.scope(ctx(), { "pickman/src/A.luau", "snake/notes.md" })).toBe("ALL")
			t.expect(sel.scope(ctx(), { "pickman/src/A.luau", "pickman/.tracker/notes.md" })).toBe("pickman")
		end
	)

	it("AC6: rule 3: specs of two projects are ALL, whichever comes first", function()
		t.expect(sel.scope(ctx(), { "pickman/src/A.luau", "snake/src/S.luau" })).toBe("ALL")
		t.expect(sel.scope(ctx(), { "snake/src/S.luau", "pickman/src/A.luau" })).toBe("ALL")
		local shared = ctx({
			["pickman/tests/unit/a.spec.luau"] = { "z-nile/tests/shared.txt" },
			["z-nile/tests/tooling/z.spec.luau"] = { "z-nile/tests/shared.txt" },
		})
		t.expect(sel.scope(shared, { "z-nile/tests/shared.txt" })).toBe("z-nile")
	end)

	it("AC6: suite isolation beats a * declaration in another suite", function()
		t.expect(sel.scope(ctx({ ["snake/tests/unit/s.spec.luau"] = { "*" } }), { "z-nile/tests/note.txt" }))
			.toBe("ALL") -- z-nile's change selects no spec, so scope stays ALL
		local starred = ctx({
			["pickman/tests/unit/a.spec.luau"] = { "*" },
			["z-nile/tests/tooling/z.spec.luau"] = { "*" },
		})
		t.expect(sel.affected(starred, { "pickman/src/A.luau" }))
			.toEqual({ "pickman/tests/unit/a.spec.luau" })
		t.expect(sel.affected(starred, { "z-nile/tests/note.txt" }))
			.toEqual({ "z-nile/tests/tooling/z.spec.luau" })
	end)
end)
