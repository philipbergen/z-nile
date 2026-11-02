--!strict
-- c0138 AC1: `trail.renamed` names the ids a compaction renames: both sides of every pair whose sides differ in the
-- whole map text, nothing for a pair whose sides agree or a comment, and nil when a map does not parse. `trail.resets`
-- says whether such a set starts a new life for an id: it names it, or could not be read. `trail.renames` reads a
-- commit's map files with git and says nil (unreadable) when it can't; its fixture cases are kept.spec's. Pure except
-- `renames`, whose cases here only read.
local t = require("@tests/lib/t")
local trail = require("@znile/engine/trail")

-- git's empty tree: a tree object, not a commit; git prints an error and lists nothing, so this is the "no map file" branch
local EMPTY_TREE = "4b825dc642cb6eb9a060e54bf8d69288fbee4904"

local function set(list: { string }): { [string]: boolean }
	local out: { [string]: boolean } = {}
	for _, id in list do
		out[id] = true
	end
	return out
end

return t.spec("c0138 the ids a compaction map renames", function(it)
	it("names both sides of every pair whose sides differ, issues and rafts alike", function()
		local got = trail.renamed({ "# ./zn compact, test\nc0300 c0030\nc0500 c0020\nR0200 R0020\n" })
		t.expect(got).toEqual(set({ "c0300", "c0030", "c0500", "c0020", "R0200", "R0020" }))
	end)

	it("names the old side alone and the new side alone, each from its own pair", function()
		-- c0900 only ever appears on the left, c0009 only on the right
		local got = trail.renamed({ "c0900 c0009\n" }) :: { [string]: boolean }
		t.expect(got.c0900).toBe(true)
		t.expect(got.c0009).toBe(true)
		t.expect(got.c0090).toBe(nil)
	end)

	it(
		"names nothing for a pair whose sides agree, a comment or an empty map, and is not nil for them",
		function()
			t.expect(trail.renamed({ "# only a header\nc0010 c0010\nR0010 R0010\n" })).toEqual({})
			t.expect(trail.renamed({ "" })).toEqual({})
			t.expect(trail.renamed({})).toEqual({})
			-- a kept id beside renamed ones stays out
			local got = trail.renamed({ "c0010 c0010\nc0300 c0030\n" }) :: { [string]: boolean }
			t.expect(got.c0010).toBe(nil)
			t.expect(got.c0030).toBe(true)
		end
	)

	it("is nil when a map line does not parse, changes a prefix or repeats an id", function()
		t.expect(trail.renamed({ "# broken\nnot a map line\n" })).toBe(nil)
		t.expect(trail.renamed({ "c0300 R0030\n" })).toBe(nil)
		t.expect(trail.renamed({ "c0300 c0030\nc0400 c0030\n" })).toBe(nil)
		t.expect(trail.renamed({ "c0300 c0030\nc0300 c0031\n" })).toBe(nil)
	end)

	it("joins the maps of several files and is nil when any one of them does not parse", function()
		local both = trail.renamed({ "c0300 c0030\n", "c0500 c0020\n" })
		t.expect(both).toEqual(set({ "c0300", "c0030", "c0500", "c0020" }))
		t.expect(trail.renamed({ "c0300 c0030\n", "nope\n" })).toBe(nil)
		t.expect(trail.renamed({ "nope\n", "c0300 c0030\n" })).toBe(nil)
		-- two maps that repeat a new id are each fine: the legacy and the current map are read apart
		t.expect(trail.renamed({ "c0300 c0030\n", "c0400 c0030\n" }))
			.toEqual(set({ "c0300", "c0030", "c0400" }))
	end)

	it("starts a new life only for an id the set names, or when the set is unreadable", function()
		local renamed = trail.renamed({ "c0300 c0030\n" })
		t.expect(trail.resets(renamed, "c0030")).toBe(true)
		t.expect(trail.resets(renamed, "c0300")).toBe(true)
		t.expect(trail.resets(renamed, "c0010")).toBe(false)
		t.expect(trail.resets({}, "c0010")).toBe(false)
		t.expect(trail.resets(nil, "c0010")).toBe(true)
	end)

	it("reads a commit that git can't read as unreadable (nil), never as no renames", function()
		t.expect(trail.renames(string.rep("0", 40))).toBe(nil)
		t.expect(trail.renames(EMPTY_TREE)).toBe(nil)
	end)
end)
