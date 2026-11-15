--!strict
-- f0211 acceptance: the arena of each map (snake/.tracker/game-design.md, "Arena and view" and "Maps"): its side
-- for N players, its speed and goal, the spawns, and the seeded wall roll.
local Maps = require("@logic/Maps")
local t = require("@tests/lib/t")

-- a seeded stand-in for arcade's Rng.draw (f0203): a whole number in 1..n, and an error for any other n, as
-- Rng.int's misuse is
local function drawOf(seed: number): (n: number) -> number
	local s = seed % 2147483646 + 1
	return function(n: number): number
		if type(n) ~= "number" or n < 1 or n ~= math.floor(n) then
			error(`draw: n must be a whole number of at least 1, got {n}`, 2)
		end
		s = (s * 48271) % 2147483647
		return s % n + 1
	end
end

local function tilesOf(w: Maps.Wall): { Maps.Tile }
	local out = {}
	for i = 0, w.length - 1 do
		table.insert(out, if w.dir == "H" then { x = w.x + i, y = w.y } else { x = w.x, y = w.y + i })
	end
	return out
end

local STEP = { N = { 0, -1 }, E = { 1, 0 }, S = { 0, 1 }, W = { -1, 0 } }

-- a spawn's four body tiles (head first) and the three tiles ahead of its head
local function spawnStrip(s: Maps.Spawn): { Maps.Tile }
	local d = STEP[s.heading]
	local out = {}
	for i = 0, 3 do
		table.insert(out, { x = s.x - d[1] * i, y = s.y - d[2] * i })
	end
	for i = 1, 3 do
		table.insert(out, { x = s.x + d[1] * i, y = s.y + d[2] * i })
	end
	return out
end

local function chebyshev(a: Maps.Tile, b: Maps.Tile): number
	return math.max(math.abs(a.x - b.x), math.abs(a.y - b.y))
end

local PLAYERS = { 1, 2, 3, 4, 8, 24 }

-- every layout the wall cases check: maps 1..30 for each player count, three seeds each
local function layouts(): { Maps.Layout }
	local out = {}
	for _, players in PLAYERS do
		for map = 1, 30 do
			for seed = 1, 3 do
				table.insert(out, Maps.roll(map, players, drawOf(seed * 1000 + map * 31 + players)))
			end
		end
	end
	return out
end

local ALL = layouts()

return t.spec("f0211 maps", function(it)
	it(
		"the side for N players is ceil(sqrt(400 + 250 * (N - 1))): 20 solo, 26 for 2, 34 for 4, 79 for 24",
		function()
			t.expect(Maps.side(1)).toBe(20)
			t.expect(Maps.side(2)).toBe(26)
			t.expect(Maps.side(3)).toBe(30)
			t.expect(Maps.side(4)).toBe(34)
			t.expect(Maps.side(8)).toBe(47)
			t.expect(Maps.side(16)).toBe(65)
			t.expect(Maps.side(24)).toBe(79)
		end
	)

	it("map 1's arena is the side for its player count (no walls, so it never grows)", function()
		for _, players in PLAYERS do
			local l = Maps.roll(1, players, drawOf(players))
			t.expect(l.map).toBe(1)
			t.expect(l.side).toBe(Maps.side(players))
			t.expect(#l.walls).toBe(0)
		end
	end)

	it("the speed is 4 tiles/s on map 1, +0.25 per map, capped at 7", function()
		t.expect(Maps.speed(1)).toBe(4)
		t.expect(Maps.speed(2)).toBe(4.25)
		t.expect(Maps.speed(5)).toBe(5)
		t.expect(Maps.speed(12)).toBe(6.75)
		t.expect(Maps.speed(13)).toBe(7)
		t.expect(Maps.speed(30)).toBe(7)
	end)

	it("the goal length of map k is 10 + 2k", function()
		t.expect(Maps.goal(1)).toBe(12)
		t.expect(Maps.goal(2)).toBe(14)
		t.expect(Maps.goal(7)).toBe(24)
	end)

	it("map k has k - 1 walls", function()
		for _, l in ALL do
			t.expect(#l.walls).toBe(l.map - 1)
		end
	end)

	it("each wall is one straight segment, H or V, 3 to max(4, floor(side / 3)) tiles long", function()
		local dirs, longest, shortest = {}, {}, math.huge
		for _, l in ALL do
			local cap = math.max(4, math.floor(l.side / 3))
			for _, w in l.walls do
				t.expect(w.dir == "H" or w.dir == "V").toBe(true)
				t.expect(w.length >= 3 and w.length <= cap).toBe(true)
				t.expect(w.length == math.floor(w.length)).toBe(true)
				dirs[w.dir] = true
				shortest = math.min(shortest, w.length)
				if w.length == cap then
					longest[l.side] = true
				end
			end
		end
		-- the whole range of lengths is rolled
		t.expect(dirs.H and dirs.V).toBe(true)
		t.expect(shortest).toBe(3)
		t.expect(longest[20] and longest[26] and longest[79]).toBe(true)
	end)

	it(
		"walls never connect: one empty tile all round each wall, diagonals included, and from the border",
		function()
			for _, l in ALL do
				for i, a in l.walls do
					for _, ta in tilesOf(a) do
						t.expect(ta.x >= 2 and ta.y >= 2 and ta.x <= l.side - 1 and ta.y <= l.side - 1)
							.toBe(true)
						for j = i + 1, #l.walls do
							for _, tb in tilesOf(l.walls[j]) do
								if chebyshev(ta, tb) < 2 then
									error(
										`map {l.map} side {l.side}: walls {i} and {j} touch at {ta.x},{ta.y}`
									)
								end
							end
						end
					end
				end
			end
		end
	)

	it(
		"the direction is rolled: on uncrowded maps (2 to 10) neither H nor V is under 30% of the walls",
		function()
			local n = { H = 0, V = 0 }
			for _, l in ALL do
				if l.map <= 10 then
					for _, w in l.walls do
						n[w.dir] += 1
					end
				end
			end
			local total = n.H + n.V
			t.expect(n.H >= 0.3 * total and n.V >= 0.3 * total).toBe(true)
		end
	)

	it("spawn areas stay clear: no wall within one tile of a spawn's body or the 3 tiles ahead", function()
		for _, l in ALL do
			for _, s in l.spawns do
				for _, st in spawnStrip(s) do
					for _, w in l.walls do
						for _, wt in tilesOf(w) do
							if chebyshev(st, wt) < 2 then
								error(`map {l.map} side {l.side}: a wall at {wt.x},{wt.y} is beside a spawn`)
							end
						end
					end
				end
			end
		end
	end)

	it(
		"one spawn per player, each with its body and the 3 tiles ahead on the board and apart from the others",
		function()
			for _, players in PLAYERS do
				local side = Maps.side(players)
				local spawns = Maps.spawns(side, players)
				t.expect(#spawns).toBe(players)
				local seen = {}
				for _, s in spawns do
					for _, st in spawnStrip(s) do
						t.expect(st.x >= 1 and st.y >= 1 and st.x <= side and st.y <= side).toBe(true)
						local k = `{st.x},{st.y}`
						t.expect(seen[k]).toBe(nil)
						seen[k] = true
					end
				end
			end
			-- a roll's spawns are the spawns for its side
			local l = Maps.roll(3, 4, drawOf(9))
			t.expect(l.spawns).toEqual(Maps.spawns(l.side, 4))
		end
	)

	it(
		"map 2's single wall is near the middle: its midpoint within 2 tiles of the centre on both axes",
		function()
			for _, players in PLAYERS do
				for seed = 1, 40 do
					local l = Maps.roll(2, players, drawOf(seed))
					local w = l.walls[1]
					local c = (l.side + 1) / 2
					local mx = if w.dir == "H" then w.x + (w.length - 1) / 2 else w.x
					local my = if w.dir == "V" then w.y + (w.length - 1) / 2 else w.y
					if math.abs(mx - c) > 2 or math.abs(my - c) > 2 then
						error(
							`{players} players, seed {seed}: map 2's wall's midpoint {mx},{my} is far from {c}`
						)
					end
				end
			end
		end
	)

	it("the roll is seeded: the same draws give the same layout, other draws other walls", function()
		for seed = 1, 5 do
			for map = 2, 12 do
				t.expect(Maps.roll(map, 2, drawOf(seed))).toEqual(Maps.roll(map, 2, drawOf(seed)))
			end
		end
		local distinct = {}
		local n = 0
		for seed = 1, 8 do
			local l = Maps.roll(6, 2, drawOf(seed))
			local parts = {}
			for _, w in l.walls do
				table.insert(parts, `{w.x},{w.y},{w.dir},{w.length}`)
			end
			local k = table.concat(parts, ";")
			if not distinct[k] then
				distinct[k] = true
				n += 1
			end
		end
		t.expect(n >= 6).toBe(true)
		-- map 2's wall moves between seeds too
		local mids = {}
		for seed = 1, 20 do
			local w = Maps.roll(2, 1, drawOf(seed)).walls[1]
			mids[`{w.x},{w.y},{w.dir}`] = true
		end
		local count = 0
		for _ in mids do
			count += 1
		end
		t.expect(count >= 5).toBe(true)
	end)

	it("when the walls don't fit, the arena grows by 2 tiles at a time", function()
		local grown = {}
		for _, l in ALL do
			local base = Maps.side(#l.spawns)
			t.expect(l.side >= base).toBe(true)
			t.expect((l.side - base) % 2).toBe(0)
		end
		-- solo maps 30..45 crowd 20x20: some grow, by exactly 2 first
		for map = 30, 45 do
			for seed = 1, 5 do
				local l = Maps.roll(map, 1, drawOf(seed * 7 + map))
				grown[l.side] = true
			end
		end
		t.expect(grown[22]).toBe(true)
		-- and the grown layout still keeps every rule
		local l = Maps.roll(60, 1, drawOf(3))
		t.expect(l.side > 20).toBe(true)
		t.expect(#l.walls).toBe(59)
		for i, a in l.walls do
			for _, ta in tilesOf(a) do
				t.expect(ta.x >= 2 and ta.y >= 2 and ta.x <= l.side - 1 and ta.y <= l.side - 1).toBe(true)
				for j = i + 1, #l.walls do
					for _, tb in tilesOf(l.walls[j]) do
						t.expect(chebyshev(ta, tb) >= 2).toBe(true)
					end
				end
			end
		end
	end)

	it("the roll always ends, even with a draw that always says 1", function()
		-- a draw that always says 1, and fails the case (rather than hanging it) once a roll has drawn a million times
		local calls = 0
		local ones = function(n: number): number
			if type(n) ~= "number" or n < 1 or n ~= math.floor(n) then
				error(`draw: n must be a whole number of at least 1, got {n}`, 2)
			end
			calls += 1
			if calls > 1000000 then
				error("the roll drew a million times: it does not end")
			end
			return 1
		end
		local l = Maps.roll(8, 1, ones)
		t.expect(#l.walls).toBe(7)
		for i, a in l.walls do
			for _, ta in tilesOf(a) do
				for j = i + 1, #l.walls do
					for _, tb in tilesOf(l.walls[j]) do
						t.expect(chebyshev(ta, tb) >= 2).toBe(true)
					end
				end
			end
		end
	end)

	it("a player count or map below 1 is an error, not a layout", function()
		t.expect(function()
			Maps.side(0)
		end).toThrow()
		t.expect(function()
			Maps.roll(0, 1, drawOf(1))
		end).toThrow()
	end)
end)
