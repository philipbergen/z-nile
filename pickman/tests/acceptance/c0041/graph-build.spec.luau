--!strict
-- c0390 AC2: graph.resolve and graph.build follow @game requires, so the meta rules and the
-- affected-spec selector see adapter -> Logic edges.
local fs = require("@lune/fs")
-- c0120 override: this spec runs from pickman/; the graph fixture is z-nile's, z-nile/tests/fixtures/graph, so ../z-nile/ in front.
local graph = require("@znile/lib/graph")
local t = require("@tests/lib/t")

local DIR = ".cache/c0390-graph"
local R = "req" .. "uire" -- never write a literal require call here; the scanner would read it

local ROOTS: { graph.GameRoot } = {
	-- c0120 override: the tooling's files live in z-nile/ (its home)
	{ instance = "ReplicatedStorage/Shared", path = "../z-nile/tests/fixtures/graph" },
}

local function setup()
	if fs.isDir(DIR) then
		fs.removeDir(DIR)
	end
	fs.writeDir(DIR)
	fs.writeFile(
		`{DIR}/adapter.luau`,
		`--!strict\nlocal A = {R}("@game/ReplicatedStorage/Shared/A")\nlocal N = {R}("@game/ReplicatedStorage/Shared/Nope")\nreturn A\n`
	)
end

return t.spec("c0390 graph resolve and build with @game", function(it)
	it("resolve delegates @game specs to the given roots", function()
		-- c0120 override: the tooling's files live in z-nile/ (its home)
		t.expect(graph.resolve("src/server/X.luau", "@game/ReplicatedStorage/Shared/A", ROOTS))
			.toBe("../z-nile/tests/fixtures/graph/A/init.luau")
		t.expect(graph.resolve("src/server/X.luau", "@game/ReplicatedStorage/Shared/Nope", ROOTS)).toBe(nil)
	end)

	it("resolve still handles relative specs and .luaurc aliases as before", function()
		-- c0120 override: the tooling's files live in z-nile/ (its home)
		t.expect(graph.resolve("../z-nile/tests/fixtures/graph/a_check.luau", "./A", ROOTS))
			.toBe("../z-nile/tests/fixtures/graph/A/init.luau")
		t.expect(graph.resolve("tests/x.luau", "@tests/lib/t", ROOTS)).toBe("tests/lib/t.luau")
	end)

	it("build records @game edges and reports unresolved @game requires", function()
		setup()
		local ok, err = pcall(function()
			local g = graph.build({ DIR }, ROOTS)
			-- c0120 override: the tooling's files live in z-nile/ (its home)
			t.expect(g.deps[`{DIR}/adapter.luau`]).toEqual({ "../z-nile/tests/fixtures/graph/A/init.luau" })
			t.expect(#g.unresolved).toBe(1)
			t.expect(g.unresolved[1].spec).toBe("@game/ReplicatedStorage/Shared/Nope")
			t.expect(#g.dynamic).toBe(0)
		end)
		fs.removeDir(DIR)
		if not ok then
			error(err, 0)
		end
	end)

	it("resolve and build without roots use graph.gameRoots(), looked up at call time", function()
		-- default.project.json maps no fixture, so stand in for it through the module table
		setup()
		local orig = graph.gameRoots
		graph.gameRoots = function(_project: any?): { graph.GameRoot }
			return ROOTS
		end
		local ok, err = pcall(function()
			-- c0120 override: the tooling's files live in z-nile/ (its home)
			t.expect(graph.resolve("src/server/X.luau", "@game/ReplicatedStorage/Shared/A"))
				.toBe("../z-nile/tests/fixtures/graph/A/init.luau")
			local g = graph.build({ DIR })
			-- c0120 override: the tooling's files live in z-nile/ (its home)
			t.expect(g.deps[`{DIR}/adapter.luau`]).toEqual({ "../z-nile/tests/fixtures/graph/A/init.luau" })
			t.expect(#g.unresolved).toBe(1)
		end)
		graph.gameRoots = orig
		fs.removeDir(DIR)
		if not ok then
			error(err, 0)
		end
	end)
end)
