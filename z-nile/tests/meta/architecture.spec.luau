--!strict
-- Structural rules from the `testing` skill for the tooling (z-nile's), run from its home z-nile/ (c0120): its specs,
-- its engine and libraries, and the root's scripts/ (c0114's shims, which belong to no project). pickman's rules
-- (src/, Logic, features, its architecture map) are pickman/tests/meta/architecture.spec.luau, run from pickman/.
local fs = require("@lune/fs")
local graph = require("../../lib/graph")
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
		-- this home is the engine and the gate (c0114); its .tracker/ holds tracker documents and unpromoted specs, and
		-- its .cache/ the fixtures' copies
		local all: { string } = graph.listLuau("../scripts")
		for _, name in fs.readDir(".") do
			if name ~= ".tracker" and name ~= ".cache" then
				if fs.isDir(name) then
					graph.listLuau(name, all)
				elseif string.match(name, "%.luau$") then
					table.insert(all, name)
				end
			end
		end
		for _, f in all do
			if not string.match(fs.readFile(f), "^%-%-!strict") then
				table.insert(bad, f)
			end
		end
		t.expect(table.concat(bad, "\n")).toBe("")
	end)
end)
