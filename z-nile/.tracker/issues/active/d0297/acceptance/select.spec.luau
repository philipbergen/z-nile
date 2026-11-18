--!strict
-- d0297: the selector never names a sequestered spec (a spec under a project root: an item's acceptance/ or
-- proofs/, a raft's folder), whether the change adds it or the branch's `current` list names it. The one way in is
-- `own`, the caller's own list (./zn finish's ticket, --own-acceptance), which keeps the `only` filter and the
-- home-relative form. Plain tables, no I/O.
local sel = require("@znile/lib/select")
local t = require("@tests/lib/t")

local SPEC = "pickman/tests/unit/a.spec.luau"
local SRC = "pickman/src/A.luau"
local PROMOTED = "pickman/tests/" .. "acceptance/c0010/p.spec.luau"
local OWN = "pickman/.tracker/issues/active/c0010/acceptance/own.spec.luau"
-- every folder a sequestered spec can sit in, under both kinds of root
local SEQUESTERED = {
	"z-nile/.tracker/issues/c0261/acceptance/docs.spec.luau", -- the captured reproduction
	"pickman/.tracker/issues/f0001/acceptance/a.spec.luau",
	"pickman/.tracker/issues/active/f0002/acceptance/b.spec.luau",
	"pickman/.tracker/issues/f0003/proofs/race.spec.luau",
	"z-nile/.tracker/rafts/R0010/r.spec.luau",
	"snake/.tracker/issues/c0004/acceptance/s.spec.luau",
}

local rules: sel.Rules = {
	homes = {
		{ name = "pickman", prefix = "pickman/" },
		{ name = "snake", prefix = "snake/" },
		{ name = "z-nile", prefix = "z-nile/" },
	},
	roots = { "pickman/.tracker", "snake/.tracker", "z-nile/.tracker" },
}

local function ctx(current: { string }?, own: { string }?): sel.Context
	return {
		rules = rules,
		graph = { files = {}, deps = {}, unresolved = {}, dynamic = {} },
		inputs = {},
		places = {},
		watches = { [SPEC] = { SRC }, [PROMOTED] = { SRC } },
		current = current,
		own = own,
	}
end

return t.spec("d0297 the selector never names a sequestered spec", function(it)
	it("AC1: a changed spec under a project root is never selected, with or without a project", function()
		local c = ctx()
		for _, path in SEQUESTERED do
			t.expect(sel.affected(c, { path })).toEqual({})
			t.expect(sel.affected(c, { path }, "pickman")).toEqual({})
			t.expect(sel.affected(c, { path }, "z-nile")).toEqual({})
		end
		-- a prep branch: every sequestered spec and its documents at once
		local prep = table.clone(SEQUESTERED)
		table.insert(prep, "z-nile/.tracker/issues/c0261/c0261.md")
		table.insert(prep, "z-nile/.tracker/issues/c0261/check.sh")
		t.expect(sel.affected(c, prep)).toEqual({})
		-- controls: a spec the change adds under tests/ is still selected, and so is a promoted acceptance spec
		local added = "pickman/tests/unit/new.spec.luau"
		local mixed = table.clone(SEQUESTERED)
		table.insert(mixed, added)
		t.expect(sel.affected(c, mixed)).toEqual({ added })
		t.expect(sel.affected(c, mixed, "pickman")).toEqual({ "tests/unit/new.spec.luau" })
		t.expect(sel.affected(c, { PROMOTED })).toEqual({ PROMOTED })
		t.expect(sel.affected(c, { "z-nile/tests/" .. "acceptance/c0120/docs.spec.luau" })).toEqual({
			"z-nile/tests/" .. "acceptance/c0120/docs.spec.luau",
		})
		t.expect(sel.affected(c, { SRC })).toEqual({ PROMOTED, SPEC })
	end)

	it("AC1: a change of only sequestered specs and tracker documents scopes to ALL", function()
		local prep = table.clone(SEQUESTERED)
		table.insert(prep, "z-nile/.tracker/issues/c0261/c0261.md")
		t.expect(sel.scope(ctx(), prep)).toBe("ALL")
		t.expect(sel.scope(ctx(), { "z-nile/.tracker/issues/c0261/acceptance/docs.spec.luau" })).toBe("ALL")
	end)

	it("AC1: a sequestered spec in the branch's current list is dropped, a promoted one kept", function()
		local c = ctx({ OWN, PROMOTED })
		t.expect(sel.affected(c, { SRC })).toEqual({ PROMOTED, SPEC })
		t.expect(sel.affected(c, { SRC }, "pickman")).toEqual({
			"tests/" .. "acceptance/c0010/p.spec.luau",
			"tests/unit/a.spec.luau",
		})
		t.expect(sel.affected(ctx({ OWN }), { "pickman/src/Other.luau" })).toEqual({})
		t.expect(sel.scope(ctx({ OWN }), { "pickman/src/Other.luau" })).toBe("ALL")
	end)

	it(
		"AC1: the caller's own list is the one way a sequestered spec is selected, and it keeps the project filter",
		function()
			local c = ctx({ OWN, PROMOTED }, { OWN, PROMOTED })
			t.expect(sel.affected(c, { SRC })).toEqual({ OWN, PROMOTED, SPEC })
			t.expect(sel.affected(c, { SRC }, "pickman")).toEqual({
				".tracker/issues/active/c0010/acceptance/own.spec.luau",
				"tests/" .. "acceptance/c0010/p.spec.luau",
				"tests/unit/a.spec.luau",
			})
			t.expect(sel.affected(c, { SRC }, "z-nile")).toEqual({})
			-- named once even when the change also adds it, and `own` lets in only what it names
			local twice = sel.affected(ctx({ OWN }, { OWN }), { OWN, SEQUESTERED[2] }) :: { string }
			t.expect(twice).toEqual({ OWN })
			t.expect(sel.affected(ctx(nil, {}), SEQUESTERED)).toEqual({})
			-- the gate's scope never takes a caller's own list: a layer's tracker change alone is ALL, `own` or not
			local doc = "pickman/.tracker/issues/active/c0010/c0010.md"
			t.expect(sel.scope(ctx(nil, { OWN }), { doc })).toBe("ALL")
			t.expect(sel.scope(ctx({ OWN }, { OWN }), { doc, OWN })).toBe("ALL")
		end
	)
end)
