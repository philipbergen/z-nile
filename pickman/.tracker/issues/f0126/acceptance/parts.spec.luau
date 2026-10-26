--!strict
-- f0126 AC5: the pieces the pick changes in other features. Movement stops a player on a centre and lets them go
-- again; a hop has a length (Hop.LONG_TICKS for the jumps boon) and keeps today's behaviour without one; a power
-- period can be lengthened; ghosts walk a copy of their maze with the holes open. On the client side: F is the
-- pick key, marked walls are runs of their own, and the frame's maze, its walls key, the pick bar and the boon
-- banner are pure functions of the frame.
local Awareness = require("@logic/Awareness")
local Game = require("@logic/Game")
local Ghosts = require("@logic/Ghosts")
local Hop = require("@logic/Hop")
local Hud = require("@logic/Hud")
local Levels = require("@logic/Levels")
local Maze = require("@logic/Maze")
local Movement = require("@logic/Movement")
local Picks = require("@logic/Picks")
local Session = require("@logic/Session")
local Touch = require("@logic/Touch")
local View = require("@logic/View")
local t = require("@tests/lib/t")

local classic = Maze.layout("classic")
local CORRIDOR = Maze.parse({ "#########", "#########", "#.....P.#", "#########", "#########" }, "corridor")

local function at(x: number, y: number): Maze.Tile
	return { x = x, y = y }
end

local function frameWith(opened: { Maze.Tile }, marked: { Maze.Tile }?): Session.Frame
	local s = Session.new(classic, 1)
	Session.join(s, "p")
	local f = Session.frame(s, "p")
	f.walls = { opened = opened, marked = marked or {} }
	return f
end

return t.spec("f0126 parts", function(it)
	it(
		"Movement.halt stops a player on a centre, with no buffered turn left and the run restarted",
		function()
			local s = Movement.spawn(CORRIDOR)
			t.expect(s.moving).toBe(true)
			Movement.step(CORRIDOR, s, { "Left" }, Movement.DEFAULT_CONFIG)
			Movement.step(CORRIDOR, s, {}, Movement.DEFAULT_CONFIG)
			Movement.step(CORRIDOR, s, {}, Movement.DEFAULT_CONFIG)
			Movement.step(CORRIDOR, s, {}, Movement.DEFAULT_CONFIG)
			t.expect(s.progress).toBe(0)
			t.expect(s.tile.x).toBe(5)
			Movement.halt(s)
			t.expect(s.moving).toBe(false)
			t.expect(s.buffered).toBe(nil)
			t.expect(s.bufferLeft).toBe(0)
			t.expect(s.run).toBe(0)
			local events = Movement.step(CORRIDOR, s, {}, Movement.DEFAULT_CONFIG)
			t.expect(#events).toBe(0) -- it stays
			t.expect(s.tile.x).toBe(5)
		end
	)

	it("Movement.halt refuses a player between centres", function()
		local s = Movement.spawn(CORRIDOR)
		Movement.step(CORRIDOR, s, {}, Movement.DEFAULT_CONFIG)
		t.expect(s.progress > 0).toBe(true)
		t.expect(function()
			Movement.halt(s)
		end).toThrow("between")
	end)

	it(
		"Movement.resume sets a halted player going when the way ahead is open, and not into a wall",
		function()
			local s = Movement.spawn(CORRIDOR)
			Movement.halt(s)
			Movement.resume(CORRIDOR, s)
			t.expect(s.moving).toBe(true)
			local wall = Movement.spawn(CORRIDOR, "S")
			t.expect(wall.moving).toBe(false)
			Movement.resume(CORRIDOR, wall)
			t.expect(wall.moving).toBe(false)
			-- a hole ahead: it walks into it
			local opened = Maze.open(CORRIDOR, at(6, 3))
			Movement.resume(opened, wall)
			t.expect(wall.moving).toBe(true)
		end
	)

	it(
		"Movement.nextCentre is 0 and the player's tile on a centre, else the distance to the tile ahead",
		function()
			local s = Movement.spawn(CORRIDOR)
			local d, tile = Movement.nextCentre(CORRIDOR, s)
			t.expect(d).toBe(0)
			t.expect(tile.x).toBe(6)
			Movement.step(CORRIDOR, s, {}, { speed = 50, turnBufferTicks = 24 })
			d, tile = Movement.nextCentre(CORRIDOR, s)
			t.expect(d).toBe(70)
			t.expect(tile.x).toBe(5)
			t.expect(tile.y).toBe(2)
		end
	)

	it("a hop's length: the default is Hop.TICKS, as before", function()
		for k = -1, 25 do
			t.expect(Hop.rise(10, 10 + k)).toBe(Hop.rise(10, 10 + k, Hop.TICKS))
			t.expect(Hop.airborne(10, 10 + k)).toBe(Hop.airborne(10, 10 + k, Hop.TICKS))
			t.expect(Hop.canStart(10, 10 + k)).toBe(Hop.canStart(10, 10 + k, Hop.TICKS))
		end
		t.expect(Hop.TICKS + Hop.COOLDOWN).toBe(20)
	end)

	it(
		"a long hop rises as high, lasts Hop.LONG_TICKS, is airborne 15 steps and cools down after landing",
		function()
			local n = 0
			local top = 0
			for k = 0, Hop.LONG_TICKS + 1 do
				if Hop.airborne(0, k, Hop.LONG_TICKS) then
					n += 1
				end
				top = math.max(top, Hop.rise(0, k, Hop.LONG_TICKS))
			end
			t.expect(n).toBe(15)
			t.expect(math.abs(top - Hop.RISE) < 0.2).toBe(true)
			t.expect(Hop.rise(0, Hop.LONG_TICKS, Hop.LONG_TICKS)).toBe(0)
			t.expect(Hop.rise(0, Hop.TICKS, Hop.LONG_TICKS) > 0).toBe(true)
			t.expect(Hop.canStart(0, Hop.LONG_TICKS + Hop.COOLDOWN - 1, Hop.LONG_TICKS)).toBe(false)
			t.expect(Hop.canStart(0, Hop.LONG_TICKS + Hop.COOLDOWN, Hop.LONG_TICKS)).toBe(true)
		end
	)

	it("a length that is not a whole number of steps counts as Hop.TICKS", function()
		for _, bad in { 0, -3, 1.5, 0 / 0, math.huge } do
			t.expect(Hop.rise(0, 6, bad)).toBe(Hop.rise(0, 6))
		end
	end)

	it("Game.power with a factor lengthens the period; without one it is the level's", function()
		local g = Game.new(Game.IMMEDIATE_CONFIG)
		local plain = Game.power(g)
		t.expect(plain[1].ticks).toBe(Levels.frightenedTicks(1, 30))
		local long = Game.power(g, 2)
		t.expect(long[1].ticks).toBe(2 * Levels.frightenedTicks(1, 30))
		t.expect(g.frightened).toBe(2 * Levels.frightenedTicks(1, 30))
	end)

	it("Ghosts.useMaze swaps in a copy of the maze, and refuses another layout", function()
		local set = Ghosts.new(classic, 1)
		local opened = Maze.open(classic, at(14, 10))
		Ghosts.useMaze(set, opened)
		t.expect(set.maze).toBe(opened)
		t.expect(function()
			Ghosts.useMaze(set, CORRIDOR)
		end).toThrow()
	end)

	it("a ghost walks into a hole when it is the way to its target", function()
		-- Blinky starts above the house heading west and scatters to the top right: with (14, 10) open above him,
		-- up is nearer his corner than west
		local function visits(opened: boolean): boolean
			local set = Ghosts.new(classic, 1)
			-- the session hands the maze over in each step's input
			local input: Ghosts.Input = {
				player = at(13, 23),
				heading = "W",
				level = 1,
				baseSpeed = 30,
				tickRate = 30,
				maze = if opened then Maze.open(classic, at(14, 10)) else nil,
			}
			for _ = 1, 30 do
				Ghosts.step(set, input)
				local tile = Ghosts.occupiedTiles(set)[1]
				if tile.x == 14 and tile.y == 10 then
					return true
				end
			end
			return false
		end
		t.expect(visits(true)).toBe(true)
		t.expect(visits(false)).toBe(false)
	end)

	it("F is the pick key; the other keys are as they were", function()
		t.expect(View.action("F")).toBe("Pick")
		t.expect(View.action("f")).toBe(nil)
		t.expect(View.action("E")).toBe("Fire")
		t.expect(View.action("Space")).toBe("Jump")
		t.expect(Movement.isIntent(View.action("F"))).toBe(false)
		t.expect(View.PICK_INTENT).toBe(Picks.INTENT) -- what Controls sends, handed over by View
	end)

	it(
		"View.walls without marks is the same runs as before; with marks each marked wall is a run of its own",
		function()
			local plain = View.walls(classic)
			local same = View.walls(classic, nil, {})
			t.expect(#same).toBe(#plain)
			for i, r in plain do
				t.expect(r.marked).toBe(nil)
				t.expect(`{same[i].x0},{same[i].y0},{same[i].x1}`).toBe(`{r.x0},{r.y0},{r.x1}`)
			end
			local marks = { at(2, 2), at(7, 2) }
			local rects = View.walls(classic, nil, marks)
			local gold = {}
			for _, r in rects do
				if r.marked then
					t.expect(r.x0).toBe(r.x1)
					local k = `{r.x0 % classic.width},{r.y0}` -- a copy in a tunnel margin names the same wall
					if not table.find(gold, k) then
						table.insert(gold, k)
					end
				end
			end
			table.sort(gold)
			t.expect(table.concat(gold, " ")).toBe("2,2 7,2")
		end
	)

	it("the runs with marks cover exactly the same wall tiles, each once", function()
		local function covered(rects: { View.Rect }): { [string]: number }
			local out: { [string]: number } = {}
			for _, r in rects do
				for x = r.x0, r.x1 do
					local k = `{x},{r.y0}`
					out[k] = (out[k] or 0) + 1
				end
			end
			return out
		end
		local a = covered(View.walls(classic))
		local b = covered(View.walls(classic, nil, { at(2, 2), at(3, 2), at(7, 2) }))
		for k, n in a do
			t.expect(b[k]).toBe(n)
		end
		for k in b do
			t.expect(a[k] ~= nil).toBe(true)
		end
	end)

	it("a marked wall in a column the tunnel margin repeats is gold in its copy too", function()
		-- column 25's copy sits 28 columns to the left, in the west margin
		local rects = View.walls(classic, nil, { at(25, 6) })
		local copies = 0
		for _, r in rects do
			if r.marked and r.y0 == 6 and r.x0 % classic.width == 25 then
				copies += 1
			end
		end
		local b = View.bounds(classic)
		t.expect(copies).toBe(if b.x0 <= 25 - classic.width then 2 else 1)
	end)

	it("View.frameMaze is the layout with the frame's holes open, and the layout itself with none", function()
		t.expect(View.frameMaze(frameWith({}))).toBe(classic)
		local m = View.frameMaze(frameWith({ at(14, 10), at(2, 2) }))
		t.expect(m.id).toBe("classic")
		t.expect(Maze.kind(m, at(14, 10))).toBe("empty")
		t.expect(Maze.kind(m, at(2, 2))).toBe("empty")
		t.expect(Maze.kind(m, at(3, 2))).toBe("wall")
		local again = View.frameMaze(frameWith({ at(14, 10), at(2, 2) }))
		t.expect(again).toBe(m) -- the same holes build it once
		local other = View.frameMaze(frameWith({ at(14, 10) }))
		t.expect(Maze.kind(other, at(2, 2))).toBe("wall")
	end)

	it("View.wallsKey changes exactly when the holes or the marks change", function()
		local a = View.wallsKey(frameWith({ at(14, 10) }, { at(2, 2) }))
		t.expect(View.wallsKey(frameWith({ at(14, 10) }, { at(2, 2) }))).toBe(a)
		t.expect(View.wallsKey(frameWith({ at(14, 10) }, { at(3, 2) })) ~= a).toBe(true)
		t.expect(View.wallsKey(frameWith({ at(14, 10), at(1, 1) }, { at(2, 2) })) ~= a).toBe(true)
		-- a hole is not a mark: moving a tile from one list to the other changes the key
		t.expect(
			View.wallsKey(frameWith({}, { at(14, 10), at(2, 2) }))
				~= View.wallsKey(frameWith({ at(14, 10) }, { at(2, 2) }))
		).toBe(true)
	end)

	it("Hud.pickProgress is the share of the pick done at the shown tick, nil without a pick", function()
		local pick: Session.Pick = { wall = at(1, 1), started = 100, ticks = 40, fast = false }
		t.expect(Hud.pickProgress(nil, 120)).toBe(nil)
		t.expect(Hud.pickProgress(pick, 100)).toBe(0)
		t.expect(Hud.pickProgress(pick, 120)).toBe(0.5)
		t.expect(Hud.pickProgress(pick, 140)).toBe(1)
		t.expect(Hud.pickProgress(pick, 150)).toBe(1)
		t.expect(Hud.pickProgress(pick, 90)).toBe(0)
		t.expect(Hud.pickProgress(pick, 0 / 0)).toBe(nil)
	end)

	it("Hud.boonBanner names the latest boon for two real seconds from the step it came in", function()
		t.expect(Hud.BOON_TICKS).toBe(Session.STEP_RATE * 2)
		local boon: Session.BoonGrant = { tick = 50, kind = "longpill" }
		t.expect(Hud.boonBanner(nil, 50)).toBe(nil)
		t.expect(Hud.boonBanner(boon, 49)).toBe(nil)
		t.expect(Hud.boonBanner(boon, 50)).toBe("LONG GHOST PILL")
		t.expect(Hud.boonBanner(boon, 50 + Hud.BOON_TICKS - 1)).toBe("LONG GHOST PILL")
		t.expect(Hud.boonBanner(boon, 50 + Hud.BOON_TICKS)).toBe(nil)
	end)

	it("every boon has a banner of its own", function()
		local seen: { [string]: boolean } = {}
		for _, boon in Picks.BOONS do
			local label = Hud.BOON_LABELS[boon]
			t.expect(type(label) == "string" and label ~= "").toBe(true)
			t.expect(seen[label]).toBe(nil)
			seen[label] = true
		end
	end)

	it(
		"the step's maze replaces the set's: a later step with the plain maze closes the hole again",
		function()
			local set = Ghosts.new(classic, 1)
			local holed = Maze.open(classic, at(14, 10))
			local input: Ghosts.Input =
				{ player = at(13, 23), heading = "W", level = 1, baseSpeed = 30, tickRate = 30, maze = holed }
			Ghosts.step(set, input)
			t.expect(set.maze).toBe(holed)
			input.maze = classic
			Ghosts.step(set, input)
			t.expect(set.maze).toBe(classic)
			input.maze = nil
			Ghosts.step(set, input)
			t.expect(set.maze).toBe(classic) -- no maze in the input keeps the set's
		end
	)

	it(
		"the pick's bar and the boon's banner sit in the safe area, clear of every other HUD block and the radar",
		function()
			local function overlap(a: Hud.Box, b: { x: number, y: number, w: number, h: number }): boolean
				return a.x < b.x + b.w and b.x < a.x + a.w and a.y < b.y + b.h and b.y < a.y + a.h
			end
			local RADAR = (Awareness.RADAR_RADIUS * 2 + 1) * 8 -- DangerHud's cells are 8 pixels
			local screens = {
				{ 320, 568 },
				{ 360, 640 },
				{ 375, 667 },
				{ 390, 844 },
				{ 568, 320 },
				{ 667, 375 },
				{ 844, 390 },
				{ 1024, 768 },
				{ 1280, 720 },
				{ 1920, 1080 },
				{ 2560, 1440 },
			}
			local insets: { Hud.Inset } = {
				{ top = 0, bottom = 0, left = 0, right = 0 },
				{ top = 0, bottom = 21, left = 47, right = 47 },
				{ top = 47, bottom = 34, left = 0, right = 0 },
			}
			for _, wh in screens do
				for _, inset in insets do
					for _, band in { 0, 36, 58 } do -- the top bar's height above the touch frame (Hud.bandTop)
						local l = Hud.layout(wh[1], wh[2], inset)
						local bar, boon = Hud.pickBox(l), Hud.boonBox(l)
						for _, b in { bar, boon } do
							t.expect(b.w > 0 and b.h > 0).toBe(true)
							t.expect(b.x >= l.safeX and b.y >= l.safeY).toBe(true)
							t.expect(b.x + b.w <= l.safeX + l.safeW and b.y + b.h <= l.safeY + l.safeH)
								.toBe(true)
						end
						t.expect(overlap(bar, boon)).toBe(false)
						local blocks = Touch.blocks(l)
						local others =
							{ blocks.score, blocks.level, blocks.lives, blocks.power, Touch.snapRect(l) }
						table.insert(others, Hud.radarBox(wh[1], wh[2], RADAR, false))
						table.insert(others, Hud.radarBox(wh[1], wh[2], RADAR, true, band))
						for _, j in Hud.jumpButtons(0, band, wh[1], wh[2] - band) do
							table.insert(others, j)
						end
						for lives = 0, 6 do -- the shot bars after the lives, in the lives block
							for _, s in Hud.shotIcons(l, lives, 3) do
								table.insert(
									others,
									{ x = blocks.lives.x + s.x, y = blocks.lives.y + s.y, w = s.w, h = s.h }
								)
							end
						end
						for _, o in others do
							t.expect(overlap(bar, o)).toBe(false)
							t.expect(overlap(boon, o)).toBe(false)
						end
					end
				end
			end
		end
	)

	it(
		"View.wallColor: the flash wins, then a marked wall's gold, then the edible green, else blue",
		function()
			-- f0109's colours are read from View (f0109 owns them); only the marks' gold is f0126's
			local function copy(c: any): any
				return { r = c.r, g = c.g, b = c.b }
			end
			local GOLD = { r = 255, g = 215, b = 0 }
			local GREEN, BLUE, WHITE =
				copy((View :: any).WALL_EDIBLE_COLOR), copy((View :: any).WALL_COLOR), copy(View.WHITE)
			local wc = (View :: any).wallColor
			t.expect(wc(false, false, true)).toEqual(GOLD)
			t.expect(wc(false, true, true)).toEqual(GOLD) -- the user: gold while the walls are green
			t.expect(wc(true, true, true)).toEqual(WHITE)
			t.expect(wc(true, false, true)).toEqual(WHITE)
			t.expect(wc(false, true, false)).toEqual(GREEN)
			t.expect(wc(false, false, false)).toEqual(BLUE)
			t.expect(wc(false, true)).toEqual(GREEN) -- no third argument: f0109's two-argument call, as before
			t.expect(wc(false, false)).toEqual(BLUE)
		end
	)

	it(
		"the marks' gold stands at least 30 (CIE76) from every ghost and ghost look, and from the walls' blue and green",
		function()
			-- f0109's measure (its prep's request, 2026-10-26): sRGB to CIE Lab (D65), Euclidean distance
			local function lin(v: number): number
				local c = v / 255
				return if c <= 0.03928 then c / 12.92 else ((c + 0.055) / 1.055) ^ 2.4
			end
			local function lab(c: any): (number, number, number)
				local r, g, b = lin(c.r), lin(c.g), lin(c.b)
				local x = (0.4124 * r + 0.3576 * g + 0.1805 * b) / 0.95047
				local y = 0.2126 * r + 0.7152 * g + 0.0722 * b
				local z = (0.0193 * r + 0.1192 * g + 0.9505 * b) / 1.08883
				local function f(v: number): number
					return if v > 0.008856 then v ^ (1 / 3) else 7.787 * v + 16 / 116
				end
				return 116 * f(y) - 16, 500 * (f(x) - f(y)), 200 * (f(y) - f(z))
			end
			local function distance(a: any, b: any): number
				local l1, a1, b1 = lab(a)
				local l2, a2, b2 = lab(b)
				return math.sqrt((l1 - l2) ^ 2 + (a1 - a2) ^ 2 + (b1 - b2) ^ 2)
			end
			local gold = (View :: any).wallColor(false, false, true)
			-- the user (2026-10-26): a brighter gold, so that every ghost clears f0109's bar, Clyde's orange included
			local n = 0
			for _, c in View.GHOST_COLORS do
				n += 1
				t.expect(distance(gold, c) >= 30).toBe(true)
			end
			t.expect(n >= 4).toBe(true)
			-- and the looks a ghost takes on: frightened blue and the blink's white
			t.expect(distance(gold, View.FRIGHTENED_COLOR) >= 30).toBe(true)
			t.expect(distance(gold, View.WHITE) >= 30).toBe(true)
			t.expect(distance(gold, (View :: any).WALL_COLOR) >= 30).toBe(true)
			t.expect(distance(gold, (View :: any).WALL_EDIBLE_COLOR) >= 30).toBe(true)
		end
	)
end)
