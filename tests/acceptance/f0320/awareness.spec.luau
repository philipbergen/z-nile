--!strict
-- f0320: danger awareness in first person. A radar around the player (up is where the camera looks) and
-- edge indicators for ghosts that are close along the maze but outside the field of view; an indicator
-- grows and brightens as its ghost nears, and says which way to look. All engine-free numbers.
local Awareness = require("@logic/Awareness")
local Maze = require("@logic/Maze")
local t = require("@tests/lib/t")

local classic = Maze.layout("classic")
local PI = math.pi
local HALF_PI = PI / 2

local function ghost(x: number, y: number, look: string?): Awareness.Ghost
	return { x = x, y = y, look = (look or "normal") :: any }
end

local function pose(x: number, y: number, yaw: number?): Awareness.Pose
	return { x = x, y = y, yaw = yaw or 0 }
end

return t.spec("f0320 awareness", function(it)
	it("the bearing is the angle from where the camera looks, positive to the left", function()
		local p = pose(10, 10, 0) -- looking north (-y)
		t.expect(Awareness.bearing(p, 10, 6)).toBeNear(0, 1e-9)
		t.expect(Awareness.bearing(p, 6, 10)).toBeNear(HALF_PI, 1e-9) -- west is on the left
		t.expect(Awareness.bearing(p, 14, 10)).toBeNear(-HALF_PI, 1e-9)
		t.expect(math.abs(Awareness.bearing(p, 10, 14))).toBeNear(PI, 1e-9)
		-- turned to look west: the old north is now on the right
		local west = pose(10, 10, HALF_PI)
		t.expect(Awareness.bearing(west, 3, 10)).toBeNear(0, 1e-9)
		t.expect(Awareness.bearing(west, 10, 6)).toBeNear(-HALF_PI, 1e-9)
	end)

	it(
		"an edge point lies on the screen border, straight up for ahead and straight down for behind",
		function()
			local function onBorder(u: number, v: number): boolean
				return math.abs(math.max(math.abs(u), math.abs(v)) - 1) < 1e-9
			end
			local u, v = Awareness.edgePoint(0, 16 / 9)
			t.expect(u).toBeNear(0, 1e-9)
			t.expect(v).toBeNear(-1, 1e-9)
			u, v = Awareness.edgePoint(PI, 16 / 9)
			t.expect(u).toBeNear(0, 1e-9)
			t.expect(v).toBeNear(1, 1e-9)
			u, v = Awareness.edgePoint(HALF_PI, 16 / 9) -- left
			t.expect(u).toBeNear(-1, 1e-9)
			t.expect(v).toBeNear(0, 1e-9)
			u, v = Awareness.edgePoint(-HALF_PI, 16 / 9)
			t.expect(u).toBeNear(1, 1e-9)
			for i = -17, 18 do
				local b = i * PI / 18
				local pu, pv = Awareness.edgePoint(b, 16 / 9)
				t.expect(onBorder(pu, pv)).toBe(true)
			end
		end
	)

	it("the distance is tiles along the maze, not in a straight line", function()
		t.expect(Awareness.pathDistance(classic, { x = 6, y = 5 }, { x = 6, y = 5 }, 30)).toBe(0)
		t.expect(Awareness.pathDistance(classic, { x = 6, y = 5 }, { x = 9, y = 5 }, 30)).toBe(3)
		-- two corridors 3 apart in a straight line with a wall between them: down, along and back up
		t.expect(Awareness.pathDistance(classic, { x = 6, y = 6 }, { x = 9, y = 6 }, 30)).toBe(5)
		-- farther than the limit is nil
		t.expect(Awareness.pathDistance(classic, { x = 6, y = 6 }, { x = 9, y = 6 }, 4)).toBe(nil)
		t.expect(Awareness.pathDistance(classic, { x = 1, y = 1 }, { x = 26, y = 29 }, 10)).toBe(nil)
		-- the tunnel is a shortcut
		t.expect(Awareness.pathDistance(classic, { x = 0, y = 14 }, { x = 27, y = 14 }, 10)).toBe(1)
	end)

	it("a ghost behind or to the side gets an indicator; one inside the field of view gets none", function()
		local p = pose(10, 23, HALF_PI) -- in the bottom corridor, looking west
		t.expect(#Awareness.indicators(classic, p, { ghost(7, 23) })).toBe(0) -- ahead
		local list = Awareness.indicators(classic, p, { ghost(13, 23) }) -- behind
		t.expect(#list).toBe(1)
		t.expect(math.abs(list[1].bearing)).toBeNear(PI, 1e-9)
		t.expect(list[1].distance).toBe(3)
		t.expect(list[1].index).toBe(1)
		-- to the side: from (12,23) looking west, the corridor up at x = 12 is on the right
		local side = Awareness.indicators(classic, pose(12, 23, HALF_PI), { ghost(12, 21) })
		t.expect(#side).toBe(1)
		t.expect(side[1].bearing).toBeNear(-HALF_PI, 1e-9)
		t.expect(side[1].distance).toBe(2)
	end)

	it(
		"the field of view is the camera's: vertical 80 degrees on a 16:9 screen is about 112 degrees across",
		function()
			-- looking west along row 23 and then turned 54 and 60 degrees: a ghost 3 tiles ahead along the corridor
			-- sits at those bearings from the camera. Half of 112 degrees is 56: 54 is on screen, 60 is not.
			local ghosts = { ghost(7, 23) }
			local inside = Awareness.indicators(classic, pose(10, 23, HALF_PI + math.rad(54)), ghosts)
			local outside = Awareness.indicators(classic, pose(10, 23, HALF_PI + math.rad(60)), ghosts)
			t.expect(#inside).toBe(0)
			t.expect(#outside).toBe(1)
			t.expect(math.abs(outside[1].bearing)).toBeNear(math.rad(60), 1e-9)
		end
	)

	it("a narrower screen shows less: on a portrait aspect the same 54 degrees is off screen", function()
		local ghosts = { ghost(7, 23) }
		local p = pose(10, 23, HALF_PI + math.rad(54))
		t.expect(#Awareness.indicators(classic, p, ghosts, { aspect = 16 / 9 })).toBe(0)
		t.expect(#Awareness.indicators(classic, p, ghosts, { aspect = 1 })).toBe(1) -- 80 degrees across: half is 40
		-- and a wider camera shows more: 100 degrees vertical makes 60 degrees on screen at 16:9
		local wide = pose(10, 23, HALF_PI + math.rad(60))
		t.expect(#Awareness.indicators(classic, wide, ghosts, { verticalFieldOfView = math.rad(100) }))
			.toBe(0)
	end)

	it(
		"eyes are never indicated, and a ghost far along the maze is not either, however close it looks",
		function()
			local p = pose(10, 23, HALF_PI)
			t.expect(#Awareness.indicators(classic, p, { ghost(13, 23, "eyes") })).toBe(0)
			-- 3 tiles away in a straight line, 5 along the maze: out of reach for a reach of 4, in for 8
			local q = pose(6, 6, 0)
			local other = ghost(9, 6)
			t.expect(#Awareness.indicators(classic, q, { other }, { maxDistance = 4 })).toBe(0)
			local reach = Awareness.indicators(classic, q, { other }, { maxDistance = 8 })
			t.expect(#reach).toBe(1)
			t.expect(reach[1].distance).toBe(5)
		end
	)

	it("an indicator grows and brightens, strictly, the closer its ghost gets, within its bounds", function()
		local p = pose(6, 5, 0)
		local lastSize, lastBright = -1, -1
		for tiles = 12, 1, -1 do
			-- the ghost behind the player on row 5, `tiles` away
			local list = Awareness.indicators(
				classic,
				p,
				{ ghost(6 + tiles, 5) },
				{ verticalFieldOfView = math.rad(20), aspect = 1 }
			)
			t.expect(#list).toBe(1)
			t.expect(list[1].distance).toBe(tiles)
			t.expect(list[1].size > lastSize).toBe(true)
			t.expect(list[1].brightness > lastBright).toBe(true)
			t.expect(
				list[1].size >= Awareness.DEFAULTS.minSize and list[1].size <= Awareness.DEFAULTS.maxSize
			)
				.toBe(true)
			t.expect(list[1].brightness >= Awareness.DEFAULTS.minBrightness and list[1].brightness <= 1)
				.toBe(true)
			lastSize, lastBright = list[1].size, list[1].brightness
		end
	end)

	it(
		"lists the nearest ghost first, keeps each ghost's place and look, and does not touch its input",
		function()
			local p = pose(10, 23, HALF_PI) -- looking west: everything below is behind
			local ghosts = { ghost(18, 23, "frightened"), ghost(12, 23), ghost(15, 23, "blinking") }
			local copy = { { x = 18, y = 23 }, { x = 12, y = 23 }, { x = 15, y = 23 } }
			local list = Awareness.indicators(classic, p, ghosts)
			t.expect(#list).toBe(3)
			t.expect(list[1].index).toBe(2)
			t.expect(list[2].index).toBe(3)
			t.expect(list[2].look).toBe("blinking")
			t.expect(list[3].index).toBe(1)
			t.expect(list[3].look).toBe("frightened")
			for i, g in ghosts do
				t.expect(g.x).toBe(copy[i].x)
				t.expect(g.y).toBe(copy[i].y)
			end
		end
	)

	it("options replace the defaults: a longer reach and other bounds", function()
		local p = pose(10, 23, HALF_PI)
		local far = ghost(18, 23) -- 8 tiles behind
		t.expect(#Awareness.indicators(classic, p, { far }, { maxDistance = 4 })).toBe(0)
		t.expect(#Awareness.indicators(classic, p, { far }, { maxDistance = 8 })).toBe(1)
		local scaled = Awareness.indicators(
			classic,
			p,
			{ ghost(11, 23) },
			{ minSize = 0.5, maxSize = 2, minBrightness = 0.6, maxDistance = 10 }
		)
		t.expect(scaled[1].size).toBeNear(0.5 + 1.5 * 0.9, 1e-9)
		t.expect(scaled[1].brightness).toBeNear(0.6 + 0.4 * 0.9, 1e-9)
	end)

	it(
		"the radar has the walls around the player and the ghosts within reach, turned so up is where the camera looks",
		function()
			local p = pose(1, 5, 0) -- row 5 is open; row 4 above is wall at x = 2..5
			local north = Awareness.radar(classic, p, {}, 3)
			t.expect(north.radius).toBe(3)
			local function hasWall(r: Awareness.Radar, x: number, y: number): boolean
				for _, w in r.walls do
					if math.abs(w.x - x) < 1e-9 and math.abs(w.y - y) < 1e-9 then
						return true
					end
				end
				return false
			end
			t.expect(hasWall(north, 1, -1)).toBe(true) -- (2,4) is a wall up and to the right
			t.expect(hasWall(north, 0, 0)).toBe(false) -- the player's own tile is open
			t.expect(hasWall(north, 0, -1)).toBe(false) -- (1,4) is a pellet corridor
			-- turn to face east: what was to the right is now behind... the wall at (2,4) is on the left, ahead
			local east = Awareness.radar(classic, pose(1, 5, -HALF_PI), {}, 3)
			t.expect(hasWall(east, 0, -1)).toBe(false)
			t.expect(hasWall(east, -1, -1)).toBe(true) -- left of the line of sight, one tile ahead
		end
	)

	it(
		"ghost blips are offsets from the player in the same turned frame, within the radius only, with their look",
		function()
			local p = pose(13, 23, 0)
			local r = Awareness.radar(
				classic,
				p,
				{ ghost(13, 20), ghost(10, 23, "frightened"), ghost(13, 40), ghost(2, 2) },
				7
			)
			t.expect(#r.blips).toBe(2)
			t.expect(r.blips[1].x).toBeNear(0, 1e-9)
			t.expect(r.blips[1].y).toBeNear(-3, 1e-9) -- three tiles ahead
			t.expect(r.blips[2].x).toBeNear(-3, 1e-9) -- three tiles to the left
			t.expect(r.blips[2].y).toBeNear(0, 1e-9)
			t.expect(r.blips[2].look).toBe("frightened")
			-- looking west instead: the ghost that was ahead is now on the right
			local w = Awareness.radar(classic, pose(13, 23, HALF_PI), { ghost(13, 20) }, 7)
			t.expect(w.blips[1].x).toBeNear(3, 1e-9)
			t.expect(w.blips[1].y).toBeNear(0, 1e-9)
		end
	)

	it("a ghost behind the player through the tunnel wrap gets an arrow pointing behind", function()
		-- the player in the left tunnel looking east, the ghost at the other end of the row: 4 tiles away through the wrap
		local list = Awareness.indicators(classic, pose(2, 14, -HALF_PI), { ghost(26, 14) })
		t.expect(#list).toBe(1)
		t.expect(list[1].distance).toBe(4)
		t.expect(math.abs(list[1].bearing)).toBeNear(PI, 1e-9)
	end)

	it(
		"the arrow follows the path, not the ghost's row: a ghost one row off the tunnel is reached across the wrap too",
		function()
			-- the player in the right tunnel looking east; the ghost 10 tiles ahead through the wrap, one row up
			local ahead = Awareness.indicators(classic, pose(25, 14, -HALF_PI), { ghost(6, 13) })
			t.expect(#ahead).toBe(1)
			t.expect(ahead[1].distance).toBe(10)
			t.expect(math.abs(ahead[1].bearing) < 0.2).toBe(true)
			-- and it does not flip from ahead to behind as the ghost's y crosses the middle of the tile
			for _, y in { 13.4, 13.5, 13.6 } do
				local list = Awareness.indicators(classic, pose(25, 14, -HALF_PI), { ghost(6, y) })
				t.expect(#list).toBe(1)
				t.expect(math.abs(list[1].bearing) < 0.2).toBe(true)
			end
		end
	)

	it("a ghost coming down a column behind the player into the tunnel is indicated, behind", function()
		-- the player in the left tunnel looking east; the ghost 10 and 11 tiles away the other way round, through the wrap
		for _, y in { 13, 12 } do
			local list = Awareness.indicators(classic, pose(2, 14, -HALF_PI), { ghost(21, y) })
			t.expect(#list).toBe(1)
			t.expect(list[1].distance).toBe(10 + (13 - y))
			t.expect(math.abs(list[1].bearing) > 2.5).toBe(true)
		end
	end)

	it(
		"the arrow does not flicker as a chasing ghost crosses the edge of the map: positions are not wrapped, tiles are",
		function()
			-- the player in the left tunnel looking east; the ghost runs east through the right edge, 27.0 to 27.99 and on
			-- from -0.99: it is always just behind the player, and the arrow behind never goes
			local last: number? = nil
			for _, x in { 26.9, 27, 27.2, 27.4, 27.5, 27.6, 27.8, 27.9, -0.1, -0.4, -0.6 } do
				local list = Awareness.indicators(classic, pose(2, 14, -HALF_PI), { ghost(x, 14) })
				t.expect(#list).toBe(1)
				t.expect(math.abs(list[1].bearing) > 3.0).toBe(true)
				local d = list[1].distance
				if last then
					t.expect(math.abs(d - last) <= 1).toBe(true) -- the distance moves by whole tiles, one at a time
				end
				last = d
			end
		end
	)

	it(
		"the ghost's own fraction counts: the bearing is exact for a ghost between tiles, off the tunnel and through the wrap",
		function()
			-- off the tunnel: a ghost walking along the open row 5 to the east of the player at (6,5) looking north
			local p = pose(6, 5, 0)
			for _, x in { 8, 8.2, 8.4, 8.5, 8.7 } do
				local list = Awareness.indicators(classic, p, { ghost(x, 5) })
				t.expect(#list).toBe(1)
				t.expect(list[1].bearing).toBeNear(Awareness.bearing(p, x, 5), 1e-9)
			end
			-- through the wrap: the player at (2,14) looking east, the ghost at x = 27.3, 27.7 and -0.3 (a little to the side)
			local q = pose(2, 14, -HALF_PI)
			for _, x in { 27.3, 27.7, -0.3 } do
				local list = Awareness.indicators(classic, q, { ghost(x, 14.4) })
				t.expect(#list).toBe(1)
				local shifted = if x > 14 then x - 28 else x
				t.expect(list[1].bearing).toBeNear(Awareness.bearing(q, shifted, 14.4), 1e-9)
			end
		end
	)

	it(
		"the bearing is exact across the edge: the fractions of both positions count, not just the tiles",
		function()
			-- the player looking east crosses the right edge (27.0 to 27.9); the ghost stands at x = 0, a little to the side.
			-- In the wrapped maze it is 28 - x tiles ahead, whatever the player's tile
			for _, x in { 27, 27.2, 27.4, 27.5, 27.6, 27.9 } do
				local list = Awareness.indicators(classic, pose(x, 14, -HALF_PI), { ghost(0, 14.4) })
				t.expect(#list).toBe(1)
				t.expect(list[1].bearing)
					.toBeNear(Awareness.bearing(pose(x, 14, -HALF_PI), x + (28 - x), 14.4), 1e-9)
			end
		end
	)

	it("the arrow does not flicker as the player crosses the edge either, eastwards or westwards", function()
		-- looking east, the player half way across the right edge (27.0 to 27.99), a ghost ahead through the wrap
		for _, x in { 27, 27.4, 27.5, 27.6, 27.9 } do
			local list = Awareness.indicators(classic, pose(x, 14, -HALF_PI), { ghost(3, 14) })
			t.expect(#list).toBe(1)
			t.expect(math.abs(list[1].bearing) < 0.2).toBe(true)
		end
		-- looking west, the player half way across the left edge (0 to -0.99), a ghost ahead through the wrap
		for _, x in { 0, -0.4, -0.6, -0.9 } do
			local list = Awareness.indicators(classic, pose(x, 14, HALF_PI), { ghost(24, 14) })
			t.expect(#list).toBe(1)
			t.expect(math.abs(list[1].bearing) < 0.2).toBe(true)
		end
	end)

	it("a ghost ahead through the wrap cannot be seen, so it gets an arrow pointing ahead", function()
		local list = Awareness.indicators(classic, pose(2, 14, HALF_PI), { ghost(26, 14) }) -- looking west
		t.expect(#list).toBe(1)
		t.expect(list[1].distance).toBe(4)
		t.expect(list[1].bearing).toBeNear(0, 1e-9)
		-- the same two columns on a row that does not wrap are far apart along the maze: no arrow
		t.expect(#Awareness.indicators(classic, pose(2, 5, HALF_PI), { ghost(26, 5) })).toBe(0)
	end)

	it("a ghost across the tunnel wrap shows by the short way round, on the tunnel row only", function()
		local r = Awareness.radar(classic, pose(1, 14, 0), { ghost(26, 14) }, 7)
		t.expect(#r.blips).toBe(1)
		t.expect(r.blips[1].x).toBeNear(-3, 1e-9)
		-- the same columns on a row that does not wrap are 25 tiles apart: not on the radar
		local other = Awareness.radar(classic, pose(1, 5, 0), { ghost(26, 5) }, 7)
		t.expect(#other.blips).toBe(0)
	end)

	it(
		"the walls move with the player: the radar is centred on where the player is, not on their tile",
		function()
			-- at (6.4, 5) looking north the wall at tile (5,4) is 1.4 tiles to the left and one up
			local r = Awareness.radar(classic, pose(6.4, 5, 0), {}, 3)
			local found = false
			for _, w in r.walls do
				if math.abs(w.x - -1.4) < 1e-9 and math.abs(w.y - -1) < 1e-9 then
					found = true
				end
			end
			t.expect(found).toBe(true)
			-- a ghost standing on the same corridor tile as the wall's neighbour shows beside the walls, not half a tile off
			local blip = Awareness.radar(classic, pose(6.4, 5, 0), { ghost(7, 5) }, 3).blips[1]
			t.expect(blip.x).toBeNear(0.6, 1e-9)
		end
	)

	it(
		"a ghost one row off the tunnel is on the radar by the short way when the player is in the tunnel",
		function()
			local r = Awareness.radar(classic, pose(27, 14, 0), { ghost(6, 13) }, 7)
			t.expect(#r.blips).toBe(1)
			t.expect(r.blips[1].x).toBeNear(7, 1e-9)
			t.expect(r.blips[1].y).toBeNear(-1, 1e-9)
		end
	)

	it(
		"the radar does not wrap vertically: nothing from the far side of the maze appears near an edge",
		function()
			-- the player on row 1 and a ghost on row 29 are 38 tiles apart along the maze
			local r = Awareness.radar(classic, pose(6, 1, 0), { ghost(6, 29) }, 7)
			t.expect(#r.blips).toBe(0)
			-- no wall is drawn above the top wall: every wall dot has a tile of the maze behind it
			for _, w in r.walls do
				t.expect(w.y >= -1 - 1e-9).toBe(true) -- the player is on row 1: the top wall is one row up
			end
			local bottom = Awareness.radar(classic, pose(6, 29, 0), {}, 7)
			for _, w in bottom.walls do
				t.expect(w.y <= 1 + 1e-9).toBe(true)
			end
		end
	)

	it(
		"off the left and right edges the radar draws nothing: only the tunnel row continues, and it holds no walls",
		function()
			local edge = Awareness.radar(classic, pose(1, 5, 0), {}, 3)
			for _, w in edge.walls do
				t.expect(w.x >= -1 - 1e-9).toBe(true) -- the left wall is one column away; nothing is drawn beyond it
			end
			local right = Awareness.radar(classic, pose(26, 5, 0), {}, 3)
			for _, w in right.walls do
				t.expect(w.x <= 1 + 1e-9).toBe(true)
			end
		end
	)

	it("the defaults are the documented ones", function()
		t.expect(Awareness.RADAR_RADIUS).toBe(7)
		t.expect(Awareness.DEFAULTS.maxDistance).toBe(12)
		t.expect(Awareness.DEFAULTS.minSize).toBe(0.25)
		t.expect(Awareness.DEFAULTS.maxSize).toBe(1)
		t.expect(Awareness.DEFAULTS.minBrightness).toBe(0.3)
		t.expect(Awareness.DEFAULTS.verticalFieldOfView).toBeNear(math.rad(80), 1e-12)
		t.expect(Awareness.DEFAULTS.aspect).toBeNear(16 / 9, 1e-12)
	end)

	it("four ghosts are worked out in well under a millisecond a frame", function()
		local p = pose(10, 23, 0.3)
		local ghosts = { ghost(12, 23), ghost(20, 23), ghost(6, 23, "frightened"), ghost(13, 14) }
		local started = os.clock()
		for _ = 1, 200 do
			Awareness.indicators(classic, p, ghosts)
			Awareness.radar(classic, p, ghosts)
		end
		-- 200 frames in under 2 s: about 50 times the measured cost
		t.expect(os.clock() - started < 2).toBe(true)
	end)
end)
