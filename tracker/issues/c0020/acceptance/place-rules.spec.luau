--!strict
-- c0020 AC2: the Rojo-built place satisfies the structural rules.
local place = require("@tests/lib/place")
local t = require("@tests/lib/t")

local game = place.load()

return t.spec("place rules", function(it)
	it("finds the three script roots", function()
		t.expect(#place.scripts(game) >= 2).toBe(true)
	end)

	it("every script in the place starts with --!strict", function()
		local bad = {}
		for _, s in place.scripts(game) do
			if not string.match(s.Source, "^%-%-!strict") then
				table.insert(bad, s:GetFullName())
			end
		end
		t.expect(table.concat(bad, "\n")).toBe("")
	end)

	it("ReplicatedStorage.Shared contains no Script or LocalScript", function()
		local shared = game:GetService("ReplicatedStorage"):FindFirstChild("Shared")
		t.expect(shared ~= nil).toBe(true)
		local bad = {}
		for _, d in shared:GetDescendants() do
			if d.ClassName == "Script" or d.ClassName == "LocalScript" then
				table.insert(bad, d:GetFullName())
			end
		end
		t.expect(table.concat(bad, "\n")).toBe("")
	end)

	it("every string require in src resolves to a ModuleScript in the DataModel", function()
		local bad = {}
		for _, s in place.scripts(game) do
			for _, spec in place.requireSpecs(s.Source) do
				if place.resolveRequire(s, spec) == nil then
					table.insert(bad, `{s:GetFullName()}: require("{spec}")`)
				end
			end
		end
		t.expect(table.concat(bad, "\n")).toBe("")
	end)
end)
