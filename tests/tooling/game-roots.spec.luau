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
		-- equal instance-path length: alphabetical tie-break keeps the order deterministic
		t.expect(roots[2].instance).toBe("A")
		t.expect(roots[3].instance).toBe("C")
	end)

	it("caches the default project but never answers an explicit one from it", function()
		t.expect(graph.gameRoots()).toBe(graph.gameRoots())
		t.expect(#graph.gameRoots({ tree = {} })).toBe(0)
		t.expect(table.isfrozen(graph.gameRoots())).toBe(true)
	end)

	it("resolveGame rejects an explicit init segment", function()
		local roots = { { instance = "ReplicatedStorage/Shared", path = "tests/fixtures/graph" } }
		t.expect(graph.resolveGame("@game/ReplicatedStorage/Shared/B/init", roots)).toBe(nil)
		t.expect(graph.resolveGame("@game/ReplicatedStorage/Shared/B", roots))
			.toBe("tests/fixtures/graph/B/init.luau")
	end)
end)
