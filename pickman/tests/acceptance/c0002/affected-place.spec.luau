--!strict
-- c0020 AC3: specs that load the built place are affected by any src/ or project-file change,
-- even though they do not require src/ directly.
-- c0120 override: the spec runs from its project's home after the move
local graph = require("@znile/lib/graph")
local t = require("@tests/lib/t")

local function isSpec(f: string): boolean
	return string.match(f, "%.spec%.luau$") ~= nil
end

local function has(list: { string }, item: string): boolean
	return table.find(list, item) ~= nil
end

return t.spec("affected: place specs", function(it)
	local g = graph.build({ "src", "tests" })

	it("exposes the place library path", function()
		t.expect(graph.PLACE_LIB).toBe("tests/lib/place.luau")
	end)

	it("a src change selects place specs but not unrelated unit specs", function()
		local selected = graph.affectedSpecs(g, { "src/server/Main.server.luau" }, isSpec)
		t.expect(has(selected, "tests/place/structure.spec.luau")).toBe(true)
		t.expect(has(selected, "tests/unit/smoke.spec.luau")).toBe(false)
	end)

	it("a default.project.json change selects place specs", function()
		local selected = graph.affectedSpecs(g, { "default.project.json" }, isSpec)
		t.expect(has(selected, "tests/place/structure.spec.luau")).toBe(true)
	end)

	it("selects by dependency on the place library, not by directory", function()
		local synthetic: graph.Graph = {
			files = { "x/p.spec.luau", "x/q.spec.luau", "tests/lib/place.luau" },
			deps = {
				["x/p.spec.luau"] = { "tests/lib/place.luau" },
				["x/q.spec.luau"] = {},
				["tests/lib/place.luau"] = {},
			},
			unresolved = {},
			dynamic = {},
		}
		t.expect(graph.affectedSpecs(synthetic, { "src/client/Foo.luau" }, isSpec))
			.toEqual({ "x/p.spec.luau" })
	end)

	it("an unrelated change does not select place specs", function()
		local selected = graph.affectedSpecs(g, { "README.md" }, isSpec)
		t.expect(has(selected, "tests/place/structure.spec.luau")).toBe(false)
	end)
end)
