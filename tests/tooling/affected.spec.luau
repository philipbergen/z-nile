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

	it("a directory prefix selects everything under it", function()
		t.expect(select({ `{ROOT}/B` })).toEqual({ `{ROOT}/b_check.luau` })
	end)

	it("ignores require-like text in comments", function()
		local R = "req" .. "uire"
		local src = `-- {R}("./gone")\n--[[ {R}("./gone2") ]]\nlocal A = {R}("./A")\n`
		t.expect((string.find(graph.stripComments(src), "gone", 1, true))).toBe(nil)
		t.expect(string.find(graph.stripComments(src), "./A", 1, true) ~= nil).toBe(true)
	end)

	it("never strips code: strings containing -- or --[[, and ---[[ toggles, keep later requires", function()
		local R = "req" .. "uire"
		local cases = {
			`local s = "a -- b"; local A = {R}("./A")\n`,
			`local s = "--[[" local A = {R}("./A") local x = t[i[1]]\n`,
			`---[[\nlocal A = {R}("./A")\n--]]\n`,
			`local s = [[ -- ]] local A = {R}("./A")\n`,
			`local s = 'it\\'s -- fine' local A = {R}("./A")\n`,
		}
		for _, src in cases do
			t.expect(string.find(graph.stripComments(src), `{R}("./A")`, 1, true) ~= nil).toBe(true)
		end
	end)

	it("strips block comments with levels", function()
		local R = "req" .. "uire"
		local src = `--[==[ {R}("./gone") ]] still comment ]==]\nlocal A = {R}("./A")\n`
		local out = graph.stripComments(src)
		t.expect((string.find(out, "gone", 1, true))).toBe(nil)
		t.expect(string.find(out, `{R}("./A")`, 1, true) ~= nil).toBe(true)
	end)

	it("specs that load the place depend implicitly on src/ and default.project.json", function()
		local g: graph.Graph = {
			files = { "p.spec.luau", "u.spec.luau", "helper.luau", graph.PLACE_LIB },
			deps = {
				["p.spec.luau"] = { "helper.luau" },
				["helper.luau"] = { graph.PLACE_LIB },
				["u.spec.luau"] = {},
				[graph.PLACE_LIB] = {},
			},
			unresolved = {},
			dynamic = {},
		}
		local function sel(changed: { string }): { string }
			return graph.affectedSpecs(g, changed, function(f)
				return string.match(f, "%.spec%.luau$") ~= nil
			end)
		end
		t.expect(sel({ "src" })).toEqual({ "p.spec.luau" })
		t.expect(sel({ "src/shared/Logic/X/init.luau" })).toEqual({ "p.spec.luau" })
		t.expect(sel({ "default.project.json" })).toEqual({ "p.spec.luau" })
		t.expect(sel({ "srcfoo/x.luau", "tests/other.luau" })).toEqual({})
	end)

	it("an unrelated change selects nothing", function()
		t.expect(select({ "README.md" })).toEqual({})
	end)
end)
