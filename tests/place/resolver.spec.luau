--!strict
-- place.resolveRequire rejects malformed specs instead of resolving them leniently, so the
-- place-rules oracle never passes a require that Roblox would reject (review-001 F2).
local place = require("@tests/lib/place")
local roblox = require("@lune/roblox")
local t = require("@tests/lib/t")

local function make(class: string, name: string, parent: any?): any
	local i = roblox.Instance.new(class)
	i.Name = name
	i.Parent = parent
	return i
end

local logic = make("Folder", "Logic")
local maze = make("ModuleScript", "Maze", logic)
local grid = make("ModuleScript", "Grid", maze)
local data = make("Folder", "Data", maze)
local level1 = make("ModuleScript", "Level1", data)
make("ModuleScript", "Movement", logic)

return t.spec("place.resolveRequire (malformed specs)", function(it)
	it("a spec with no path after its prefix is nil", function()
		t.expect(place.resolveRequire(maze, "@self")).toBe(nil)
		t.expect(place.resolveRequire(grid, "./")).toBe(nil)
		t.expect(place.resolveRequire(level1, "../")).toBe(nil)
	end)

	it("empty and . segments are nil", function()
		t.expect(place.resolveRequire(grid, "./Data//Level1")).toBe(nil)
		t.expect(place.resolveRequire(grid, "./Data/./Level1")).toBe(nil)
		t.expect(place.resolveRequire(grid, "./Data/Level1/")).toBe(nil)
	end)

	it(".. is only valid as leading ../ segments", function()
		t.expect(place.resolveRequire(grid, "./../Movement")).toBe(nil)
		t.expect(place.resolveRequire(maze, "@self/../Movement")).toBe(nil)
		t.expect(place.resolveRequire(grid, "../Maze/../Movement")).toBe(nil)
		t.expect(place.resolveRequire(level1, "../../Movement") ~= nil).toBe(true)
	end)
end)
