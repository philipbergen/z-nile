--!strict
-- c0020 AC1: place.resolveRequire follows Roblox require-by-string semantics on instance trees.
local place = require("@tests/lib/place")
local roblox = require("@lune/roblox")
local t = require("@tests/lib/t")

local Instance = roblox.Instance

local function make(class: string, name: string, parent: any?): any
	local i = Instance.new(class)
	i.Name = name
	i.Parent = parent
	return i
end

-- Logic (Folder)
--   Maze (ModuleScript, from Maze/init.luau)
--     Grid (ModuleScript)
--     Data (Folder)
--       Level1 (ModuleScript)
--   Movement (ModuleScript)
--   Notes (StringValue)
local logic = make("Folder", "Logic")
local maze = make("ModuleScript", "Maze", logic)
local grid = make("ModuleScript", "Grid", maze)
local data = make("Folder", "Data", maze)
local level1 = make("ModuleScript", "Level1", data)
local movement = make("ModuleScript", "Movement", logic)
make("StringValue", "Notes", logic)

return t.spec("place.resolveRequire", function(it)
	it("@self resolves the script's own children", function()
		t.expect(place.resolveRequire(maze, "@self/Grid")).toBe(grid)
		t.expect(place.resolveRequire(maze, "@self/Data/Level1")).toBe(level1)
	end)

	it("./ resolves siblings (children of the script's Parent)", function()
		t.expect(place.resolveRequire(movement, "./Maze")).toBe(maze)
		t.expect(place.resolveRequire(grid, "./Data/Level1")).toBe(level1)
	end)

	it("../ climbs one level per segment", function()
		t.expect(place.resolveRequire(grid, "../Movement")).toBe(movement)
		t.expect(place.resolveRequire(level1, "../../Movement")).toBe(movement)
	end)

	it("a missing segment resolves to nil", function()
		t.expect(place.resolveRequire(movement, "./Nope")).toBe(nil)
		t.expect(place.resolveRequire(maze, "@self/Data/Nope")).toBe(nil)
	end)

	it("a target that is not a ModuleScript resolves to nil", function()
		t.expect(place.resolveRequire(movement, "./Notes")).toBe(nil)
		t.expect(place.resolveRequire(maze, "@self/Data")).toBe(nil)
	end)

	it("aliases are not valid in Roblox source and resolve to nil", function()
		t.expect(place.resolveRequire(movement, "@logic/Maze")).toBe(nil)
		t.expect(place.resolveRequire(movement, "@lune/fs")).toBe(nil)
	end)

	it("extracts string-literal require specs from source", function()
		-- built by concatenation so this file contains no literal require text for the graph scanner
		local R = "req" .. "uire"
		local src = `local A = {R}("./A")\nlocal B = {R}("@self/B")\nlocal s = "{R}(x)"\n`
		t.expect(place.requireSpecs(src)).toEqual({ "./A", "@self/B" })
	end)
end)
