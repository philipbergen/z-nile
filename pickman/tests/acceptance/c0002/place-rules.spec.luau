--!strict
-- c0020 AC2: the Rojo-built place satisfies the structural rules.
local place = require("@tests/lib/place")
local t = require("@tests/lib/t")

local game = place.load()
local ROOTS = {
	"ReplicatedStorage.Shared.",
	"ServerScriptService.Server.",
	"StarterPlayer.StarterPlayerScripts.Client.",
}

return t.spec("place rules", function(it)
	it("lists scripts only from the three script roots, including both Main scripts", function()
		local names = {}
		for _, s in place.scripts(game) do
			local full = s:GetFullName()
			local ok = false
			for _, prefix in ROOTS do
				ok = ok or string.sub(full, 1, #prefix) == prefix
			end
			t.expect(ok).toBe(true)
			names[full] = true
		end
		t.expect(names["ServerScriptService.Server.Main"]).toBe(true)
		t.expect(names["StarterPlayer.StarterPlayerScripts.Client.Main"]).toBe(true)
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
