--!strict
-- Structural rules from the `testing` skill for the tooling (z-nile's): its specs, scripts and engine. pickman's
-- rules (src/, Logic, features, its architecture map) are pickman/tests/meta/architecture.spec.luau, run from
-- pickman/ (c0120).
local fs = require("@lune/fs")
local graph = require("../../z-nile/lib/graph")
local t = require("@tests/lib/t")

return t.spec("architecture (tooling)", function(it)
	it("every require under tests/ resolves", function()
		local g = graph.build({ "tests" })
		local msgs = {}
		for _, u in g.unresolved do
			table.insert(msgs, `{u.file}: require("{u.spec}")`)
		end
		t.expect(table.concat(msgs, "\n")).toBe("")
	end)

	it("every Luau file is --!strict", function()
		local bad = {}
		-- z-nile/ is the engine and the gate (c0114); its .tracker/ holds tracker documents and unpromoted specs
		local all = graph.listLuau("tests", graph.listLuau("scripts", graph.listLuau("z-nile")))
		for _, f in all do
			if string.sub(f, 1, 15) == "z-nile/.tracker" then
				continue
			end
			if not string.match(fs.readFile(f), "^%-%-!strict") then
				table.insert(bad, f)
			end
		end
		t.expect(table.concat(bad, "\n")).toBe("")
	end)
end)
