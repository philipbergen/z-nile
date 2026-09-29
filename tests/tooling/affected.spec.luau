--!strict
-- The affected-test selector must pick exactly the specs that depend on a change.
local graph = require("../../scripts/lib/graph")
local t = require("@tests/lib/t")

local ROOT = "tests/fixtures/graph"

local function select(changed: { string }): { string }
	return graph.affectedSpecs(graph.build({ ROOT }), changed, function(f)
		return string.match(f, "_check%.luau$") ~= nil
	end)
end

return t.spec("affected", function(it)
	it("resolves @self, ../ from init.luau, and ./ requires", function()
		local g = graph.build({ ROOT })
		t.expect(g.deps[`{ROOT}/A/init.luau`]).toEqual({ `{ROOT}/A/Impl.luau` })
		t.expect(g.deps[`{ROOT}/B/init.luau`]).toEqual({ `{ROOT}/A/init.luau` })
		t.expect(g.deps[`{ROOT}/b_check.luau`]).toEqual({ `{ROOT}/B/init.luau` })
		t.expect(#g.unresolved).toBe(0)
	end)

	it("resolution agrees with Lune's real require", function()
		t.expect(require("../fixtures/graph/b_check").value).toBe(2)
	end)

	it("a change deep in A selects A's and B's checks", function()
		t.expect(select({ `{ROOT}/A/Impl.luau` })).toEqual({ `{ROOT}/a_check.luau`, `{ROOT}/b_check.luau` })
	end)

	it("a change in B selects only B's check", function()
		t.expect(select({ `{ROOT}/B/init.luau` })).toEqual({ `{ROOT}/b_check.luau` })
	end)

	it("an unrelated change selects nothing", function()
		t.expect(select({ "README.md" })).toEqual({})
	end)
end)
