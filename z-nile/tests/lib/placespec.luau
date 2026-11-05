--!strict
-- The place tier every project home has (c0185): each home's tests/place/library.spec.luau returns this called with the
-- home's own place re-export (so the spec's closure names the home, and the selector reruns it when the home's place
-- changes). `cd <home> && lune run tests/run` then builds the home's default place with Rojo and judges it the way Roblox
-- would: the library's folders are in the place (the project file maps them, and the build accepted it), and every string
-- require in the home's own scripts resolves on the instance tree, `@game/ReplicatedStorage/Arcade/...` and
-- `@game/ServerStorage/Arcade/...` included. That is the one way a script reaches another home: a relative path that
-- leaves the home resolves on disk but not in Roblox, and the instance-tree spelling resolves in Roblox but not on disk
-- (c0185 E2).
local t = require("./t")

type Place = typeof(require("./place"))

return function(place: Place): t.Spec
	return t.spec("the built place", function(it)
		local game = place.load()

		it("holds the library: ReplicatedStorage.Arcade and ServerStorage.Arcade are folders", function()
			for _, service in { "ReplicatedStorage", "ServerStorage" } do
				local node = game:GetService(service):FindFirstChild("Arcade")
				t.expect(node ~= nil and node.ClassName).toBe("Folder")
			end
		end)

		it(
			"every string require in the home's scripts resolves to a ModuleScript in the DataModel",
			function()
				local bad = {}
				for _, s in place.scripts(game) do
					for _, spec in place.requireSpecs(s.Source) do
						if place.resolveRequire(s, spec) == nil then
							table.insert(bad, `{s:GetFullName()}: require("{spec}")`)
						end
					end
				end
				t.expect(table.concat(bad, "\n")).toBe("")
			end
		)
	end)
end
