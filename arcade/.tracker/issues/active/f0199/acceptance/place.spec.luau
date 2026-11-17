--!strict
-- f0199 AC3: in the built library place, Travel and Places are where every place's adapters will require them:
-- ModuleScripts at ReplicatedStorage.Arcade.Logic.Travel (shared, so a client screen may read its Phase type) and
-- ReplicatedStorage.Arcade.Places, reached by `@game/ReplicatedStorage/Arcade/...`, holding their sources. Travel is a
-- leaf that requires nothing and names no place (arcade-arch rule 1); Places' one require resolves to Travel.
local fs = require("@lune/fs")
local place = require("@tests/lib/place")
local t = require("@tests/lib/t")

local SOURCE = "src/shared/Logic/Travel/init.luau"
local PLACES_SOURCE = "src/shared/Places.luau"

return t.spec("f0199 Travel in the built place", function(it)
	local game = place.load()

	local function at(path: { string }): any
		local node: any = game:GetService("ReplicatedStorage")
		for _, name in path do
			node = node and node:FindFirstChild(name)
		end
		return node
	end

	local function travel(): any
		return at({ "Arcade", "Logic", "Travel" })
	end

	it("ReplicatedStorage.Arcade.Logic.Travel is a ModuleScript holding the feature's source", function()
		local node = travel()
		t.expect(node ~= nil and node.ClassName).toBe("ModuleScript")
		t.expect(node.Source).toBe(fs.readFile(SOURCE))
	end)

	it("an adapter's @game/ReplicatedStorage/Arcade/Logic/Travel resolves to it", function()
		local node = travel()
		t.expect(node ~= nil).toBe(true)
		t.expect(place.resolveRequire(node, "@game/ReplicatedStorage/Arcade/Logic/Travel")).toBe(node)
	end)

	it("it is a leaf: it requires nothing, and ServerStorage.Arcade holds no Travel", function()
		local node = travel()
		t.expect(node ~= nil).toBe(true)
		t.expect(place.requireSpecs(node.Source)).toEqual({})
		local server = game:GetService("ServerStorage"):FindFirstChild("Arcade")
		t.expect(server ~= nil and server:FindFirstChild("Travel", true)).toBe(nil)
	end)

	it("Travel names no place: the place names live in Places, outside Logic", function()
		local node = travel()
		t.expect(node ~= nil).toBe(true)
		local found = {}
		for _, name in { "portal", "pickman", "snake", "invaders", "asteroids", "lobby" } do
			if string.find(string.lower(node.Source), name, 1, true) then
				table.insert(found, name)
			end
		end
		t.expect(table.concat(found, ", ")).toBe("")
	end)

	it("ReplicatedStorage.Arcade.Places is a ModuleScript holding its source, reached by @game", function()
		local node = at({ "Arcade", "Places" })
		t.expect(node ~= nil and node.ClassName).toBe("ModuleScript")
		t.expect(node.Source).toBe(fs.readFile(PLACES_SOURCE))
		t.expect(place.resolveRequire(node, "@game/ReplicatedStorage/Arcade/Places")).toBe(node)
	end)

	it("Places requires one module, and it resolves to Travel in the instance tree", function()
		local node = at({ "Arcade", "Places" })
		t.expect(node ~= nil).toBe(true)
		local specs = place.requireSpecs(node.Source)
		t.expect(#specs).toBe(1)
		t.expect(place.resolveRequire(node, specs[1])).toBe(travel())
	end)
end)
