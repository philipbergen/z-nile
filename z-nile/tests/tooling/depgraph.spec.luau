--!strict
-- f0422: the dependency rules over open units: bands, downstream counts and the order.
local depgraph = require("@znile/engine/depgraph")
local t = require("@tests/lib/t")

local function unit(id: string, waitsOn: { string }): depgraph.Unit
	return { id = id, waitsOn = waitsOn }
end

-- d waits on b and c, which wait on a; e waits on d
local DIAMOND =
	{ unit("a", {}), unit("b", { "a" }), unit("c", { "a" }), unit("d", { "b", "c" }), unit("e", { "d" }) }

return t.spec("depgraph", function(it)
	it("an empty input gives empty results", function()
		local bands, cyclic = depgraph.bands({})
		t.expect(bands).toEqual({})
		t.expect(cyclic).toEqual({})
		t.expect(depgraph.unblocks({})).toEqual({})
		t.expect(depgraph.order({}, {})).toEqual({})
	end)

	it("a chain has one band per step", function()
		local bands = depgraph.bands({ unit("c", { "b" }), unit("b", { "a" }), unit("a", {}) })
		t.expect(bands).toEqual({ a = 0, b = 1, c = 2 })
	end)

	it("a diamond puts a unit one past its highest dependency", function()
		local bands, cyclic = depgraph.bands(DIAMOND)
		t.expect(bands).toEqual({ a = 0, b = 1, c = 1, d = 2, e = 3 })
		t.expect(cyclic).toEqual({})
	end)

	it("a unit waiting on bands 0 and 2 is in band 3", function()
		local bands =
			depgraph.bands({ unit("x", {}), unit("y", { "x" }), unit("z", { "y" }), unit("w", { "x", "z" }) })
		t.expect(bands.w).toBe(3)
	end)

	it("a hub with many dependents unblocks all of them", function()
		local units = { unit("hub", {}) }
		for i = 1, 20 do
			table.insert(units, unit(string.format("s%02d", i), { "hub" }))
		end
		local bands = depgraph.bands(units)
		local counts = depgraph.unblocks(units)
		t.expect(counts.hub).toBe(20)
		t.expect(counts.s07).toBe(0)
		t.expect(bands.s20).toBe(1)
	end)

	it("a waitsOn id that is not a unit is ignored", function()
		local units = { unit("a", { "gone" }), unit("b", { "a", "gone" }) }
		t.expect((depgraph.bands(units))).toEqual({ a = 0, b = 1 })
		t.expect(depgraph.unblocks(units)).toEqual({ a = 1, b = 0 })
	end)

	it(
		"a cycle ends, lists its members, and puts them and what waits behind them past the acyclic bands",
		function()
			local units = {
				unit("a", {}),
				unit("b", { "a" }),
				unit("x", { "y", "a" }),
				unit("y", { "x" }),
				unit("z", { "x" }),
				unit("self", { "self" }),
			}
			local bands, cyclic = depgraph.bands(units)
			t.expect(bands).toEqual({ a = 0, b = 1, x = 2, y = 2, z = 2, self = 2 })
			t.expect(cyclic).toEqual({ "self", "x", "y" })
			local only = depgraph.bands({ unit("p", { "q" }), unit("q", { "p" }) })
			t.expect(only).toEqual({ p = 1, q = 1 })
			-- downstream counts also end on a cycle
			t.expect(depgraph.unblocks(units).x).toBe(2)
		end
	)

	it("unblocks counts every distinct unit downstream, once", function()
		t.expect(depgraph.unblocks(DIAMOND)).toEqual({ a = 4, b = 2, c = 2, d = 1, e = 0 })
	end)

	it("order puts the most unblocking first, ties by id, and leaves the input alone", function()
		local ids = { "e", "c", "a", "b", "d" }
		local counts = depgraph.unblocks(DIAMOND)
		t.expect(depgraph.order(ids, counts)).toEqual({ "a", "b", "c", "d", "e" })
		t.expect(depgraph.order({ "q", "p", "r" }, { r = 5, p = 1, q = 1 })).toEqual({ "r", "p", "q" })
		t.expect(ids).toEqual({ "e", "c", "a", "b", "d" })
	end)
end)
