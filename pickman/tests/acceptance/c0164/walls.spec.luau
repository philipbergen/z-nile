--!strict
-- c0164 AC1: R0056's text pin of Main's wall calls (tests/place/main-walls.spec.luau) is narrowed to where the two
-- calls sit (decided with the user, 2026-11-01: "Keep both"), and what they are handed is pinned by a behaviour case
-- on f0126's Main harness, added to tests/acceptance/f0126/views.spec.luau (a chore may change a promoted spec in
-- its own raft). The case drives Main's real source through a script of play states in the order the game produces them, on bare frames and on busy ones
-- carrying every other frame field and checks that MazeView.edible and DangerHud.wallState get the frame's edible state and flash
-- once every frame. views.spec and the narrowed main-walls.spec are pinned whole: the SHA-256 of its exact text with item ids masked and line endings
-- made LF (lesson zz-test/narrowing-pins-the-whole-file), so nothing else in f0126's file moves.
local fs = require("@lune/fs")
local serde = require("@lune/serde")
local t = require("@tests/lib/t")
local views: any = require("@tests/acceptance/f0126/views.spec")

local VIEWS = "tests/acceptance/f0126/views.spec.luau"
local WALLS = "tests/place/main-walls.spec.luau"
local WALLS_SHA = "07aa01f0259a6d0dde154bcd74ddca57b51abd367ca5cc78f7ff403262aaaaed"
local SHA = "9c01130d52c05cbbb794057cda30ab7df35abb9c213acdc5e50f5c4c8beea04b"
local CASE =
	"Main turns the walls and the radar green while the ghosts are edible, and blue again after, every frame"

local function exact(path: string): string
	local text = string.gsub(fs.readFile(path), "\r\n", "\n")
	text = string.gsub(text, "%f[%w_][fdcR]%d+%f[^%w_]", "ID")
	return text
end

return t.spec("c0164 Main's walls, by behaviour", function(it)
	it(
		"R0056's main-walls.spec is exactly the narrowed one: where the calls sit, not what they are handed",
		function()
			t.expect(serde.hash("sha256", exact(WALLS))).toBe(WALLS_SHA)
		end
	)

	it("views.spec is exactly f0126's with c0164's case added", function()
		t.expect(serde.hash("sha256", exact(VIEWS))).toBe(SHA)
	end)

	it("the case is there once and passes on today's Main", function()
		local found = 0
		for _, c in views.cases do
			if c.name == CASE then
				found += 1
				local ok, err = pcall(c.fn :: () -> any)
				if not ok then
					error(tostring(err), 0)
				end
			end
		end
		t.expect(found).toBe(1)
	end)
end)
