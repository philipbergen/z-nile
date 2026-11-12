--!strict
-- The watch map is the one predicate of selection and of fingerprints. A path selects a spec exactly when
-- it is that spec, its watch file, or a path the watch file names. Nothing falls back to every spec.
local fingerprint = require("@znile/lib/fingerprint")
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
local GIT: fingerprint.GitState = { head = string.rep("a", 40), refs = {} }
local function blob(id: string): fingerprint.Blobs
	return {
		[SPEC] = "100644 spec",
		[WATCH] = "100644 watch",
		[SRC] = `100644 {id}`,
		["README.md"] = "100644 readme",
	}
end

return t.spec("c0165 the watch map selects and fingerprints the same paths", function(it)
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

	it("the fingerprint changes when a watched blob changes and not when an unwatched one does", function()
		local c = ctx()
		local tools = "tools"
		local first = fingerprint.of(c, SPEC, blob("1"), tools, "affected", GIT)
		local same = fingerprint.of(c, SPEC, blob("1"), tools, "affected", GIT)
		t.expect(same).toBe(first)
		local changed = fingerprint.of(c, SPEC, blob("2"), tools, "affected", GIT)
		t.expect(changed ~= first).toBe(true)
		local blobs = blob("1")
		blobs["README.md"] = "100644 other"
		t.expect(fingerprint.of(c, SPEC, blobs, tools, "affected", GIT)).toBe(first)
	end)
end)
