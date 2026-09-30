--!strict
local graph = require("@scripts/lib/graph")
local t = require("@tests/lib/t")

return t.spec("graph.gameRoots", function(it)
	it("sorts by instance path length and skips $ properties", function()
		local roots = graph.gameRoots({
			tree = {
				["$className"] = "DataModel",
				A = { ["$path"] = "x/a", B = { ["$path"] = "y" } },
				C = { ["$path"] = "z" },
			},
		})
		t.expect(#roots).toBe(3)
		t.expect(roots[1].instance).toBe("A/B")
		t.expect(roots[1].path).toBe("y")
	end)

	it("caches the default project but never answers an explicit one from it", function()
		t.expect(graph.gameRoots()).toBe(graph.gameRoots())
		t.expect(#graph.gameRoots({ tree = {} })).toBe(0)
	end)
end)
