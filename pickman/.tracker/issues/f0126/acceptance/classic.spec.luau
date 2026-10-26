--!strict
-- f0126 AC7: picks in the real maze, with its ghosts. A ghost pill turns the ghosts blue in the step the wall comes
-- down, as a power pellet does; the hole is open in the frame; the classic maze always shows three marked walls,
-- each a wall that can be picked; and a run of picks plays the same twice from one seed.
local Levels = require("@logic/Levels")
local Maze = require("@logic/Maze")
local Movement = require("@logic/Movement")
local Picks = require("@logic/Picks")
local Session = require("@logic/Session")
local t = require("@tests/lib/t")

local classic = Maze.layout("classic")
local CONFIG: Session.Config = { movement = Movement.DEFAULT_CONFIG, maxIntentsPerTick = 4, ghosts = true }

local function new(seed: number): Session.Session
	local s = Session.new(classic, seed, CONFIG)
	Session.join(s, "p")
	return s
end

-- the player starts on (13, 23) heading west and walks to (6, 23): is a marked wall beside that run?
local function markOnRun(s: Session.Session): boolean
	for _, tile in (Session.frame(s, "p").walls :: Session.Walls).marked do
		if tile.x >= 6 and tile.x <= 13 and (tile.y == 22 or tile.y == 24) then
			return true
		end
	end
	return false
end

-- Pick from the start; the WallPicked event and the step it came in, or nil within `limit` steps.
local function pickFromStart(s: Session.Session, limit: number): (Session.Event?, { Session.Event })
	Session.submit(s, "p", "Pick")
	for _ = 1, limit do
		local events = Session.step(s)
		for _, e in events do
			if e.kind == "WallPicked" then
				return e, events
			end
		end
		if s.tick % 10 == 0 then
			Session.submit(s, "p", "Pick")
		end
	end
	return nil, {}
end

return t.spec("f0126 picks in the classic maze", function(it)
	it("always shows three marked walls, each one that can be picked", function()
		for seed = 1, 30 do
			local walls = Session.frame(new(seed), "p").walls :: Session.Walls
			t.expect(#walls.marked).toBe(3)
			for _, tile in walls.marked do
				t.expect(Picks.pickable(classic, tile)).toBe(true)
			end
		end
	end)

	it("a ghost pill turns the ghosts blue in the step the wall comes down", function()
		for seed = 1, 4000 do
			local s = new(seed)
			if markOnRun(s) then
				local before = Session.frame(s, "p")
				local picked = pickFromStart(s, 120)
				if picked and picked.item == "pill" then
					t.expect(before.play.frightened).toBe(0)
					local f = Session.frame(s, "p")
					t.expect(f.play.frightened > 0).toBe(true)
					for _, g in f.ghosts :: { Session.GhostSnapshot } do
						t.expect(g.look == "frightened" or g.look == "eyes").toBe(true)
					end
					local hole = (f.walls :: Session.Walls).opened[1]
					t.expect(hole.x).toBe(picked.x)
					t.expect(hole.y).toBe(picked.y)
					t.expect(Maze.kind(Maze.opened(classic, (f.walls :: Session.Walls).opened), hole))
						.toBe("empty")
					return
				end
			end
		end
		error("no seed picked a pill on the first run")
	end)

	it("one seed plays the same picks twice", function()
		local function play(seed: number): string
			local s = new(seed)
			local out = {}
			for _ = 1, 3 do
				local picked = pickFromStart(s, 300)
				if picked == nil then
					break
				end
				table.insert(out, `{s.tick}:{picked.x},{picked.y}:{picked.item}`)
			end
			table.insert(out, Session.frame(s, "p").pellets)
			return table.concat(out, " ")
		end
		for seed = 1, 4000 do
			if markOnRun(new(seed)) then
				t.expect(play(seed)).toBe(play(seed))
				t.expect(string.find(play(seed), ":", 1, true) ~= nil).toBe(true)
				return
			end
		end
		error("no seed")
	end)

	it(
		"the pick lasts ten paces of the member's own ghosts, their tuning included (f0125's slower ghosts)",
		function()
			local TUNING = 1 / 1.1
			local base = Movement.DEFAULT_CONFIG.speed
			local tuned = Picks.ticks(Levels.ghostSpeed(base, 1, "normal", TUNING), false)
			t.expect(tuned ~= Picks.ticks(Levels.ghostSpeed(base, 1, "normal"), false)).toBe(true)
			for seed = 1, 4000 do
				local s = new(seed)
				if markOnRun(s) then
					local set = (s :: any).members.p.ghosts
					t.expect(set ~= nil).toBe(true)
					set.tuning = TUNING -- as f0125's shipped config makes the member's ghosts
					Session.submit(s, "p", "Pick")
					for _ = 1, 120 do
						for _, e in Session.step(s) do
							if e.kind == "PickStarted" then
								t.expect(e.ticks).toBe(tuned)
								return
							end
						end
						if s.tick % 10 == 0 then
							Session.submit(s, "p", "Pick")
						end
					end
				end
			end
			error("no seed started a pick")
		end
	)
end)
