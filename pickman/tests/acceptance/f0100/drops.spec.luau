--!strict
-- f0100 AC3: where shots come from and how long they last. Every ghost eaten on contact rolls for a drop with the
-- session's own seeded Blaster (so the server decides, and a seed replays the same drops); a ghost that is shot
-- does not roll. At most three are held. Shots outlive a death and a level and are gone on a new run. Every frame
-- carries the count.
local Blaster = require("@logic/Blaster")
local Ghosts = require("@logic/Ghosts")
local Maze = require("@logic/Maze")
local Movement = require("@logic/Movement")
local Pellets = require("@logic/Pellets")
local Session = require("@logic/Session")
local plain = require("@tests/lib/plain")
local t = require("@tests/lib/t")

local classic = Maze.layout("classic")

local function new(seed: number): Session.Session
	local s = Session.new(classic, seed, Session.GAME_CONFIG)
	Session.join(s, "p")
	return s
end

local function ghostsOf(s: Session.Session): Ghosts.Set
	return s.members.p.ghosts :: Ghosts.Set
end

local function settled(s: Session.Session): Session.Session
	for _ = 1, 101 do
		Session.step(s)
	end
	return s
end

local function find(events: { Session.Event }, kind: string): Session.Event?
	for _, e in events do
		if e.kind == kind then
			return e
		end
	end
	return nil
end

-- the first roll of a seed's own Blaster, as the oracle for what the session must do
local function firstDrops(seed: number): boolean
	return Blaster.drop(Blaster.new(seed))
end

local function seedWhere(drops: boolean): number
	for seed = 1, 1000 do
		if firstDrops(seed) == drops then
			return seed
		end
	end
	error("no seed found")
end

-- a blue ghost steps onto the settled player: eaten on contact in the next step
local function eatOne(s: Session.Session, name: Ghosts.Name): { Session.Event }
	local set = ghostsOf(s)
	Ghosts.power(set, 300)
	s.members.p.play.frightened = 300
	local g = Ghosts.ghost(set, name)
	local at = Movement.occupied(s.maze, s.members.p.move)
	g.tile, g.progress, g.status, g.frightened = { x = at.x, y = at.y }, 0, "active", true
	local events = Session.step(s)
	assert(find(events, "GhostEaten"), "the ghost is eaten")
	return events
end

return t.spec("f0100 drops", function(it)
	it("a ghost eaten on contact that rolls a drop gives a shot, with a ShotGained event", function()
		local s = settled(new(seedWhere(true)))
		local events = eatOne(s, "blinky")
		local e = find(events, "ShotGained")
		t.expect(e ~= nil).toBe(true)
		t.expect((e :: Session.Event).ghost).toBe("blinky")
		t.expect((e :: Session.Event).player).toBe("p")
		t.expect(Session.frame(s, "p").shots).toBe(1)
	end)

	it("one that rolls no drop gives nothing", function()
		local s = settled(new(seedWhere(false)))
		local events = eatOne(s, "blinky")
		t.expect(find(events, "ShotGained")).toBe(nil)
		t.expect(Session.frame(s, "p").shots).toBe(0)
	end)

	it("the session's drops are its seed's Blaster rolls, eat after eat", function()
		for _, seed in { 3, 17, 99 } do
			local oracle = Blaster.new(seed)
			local s = settled(new(seed))
			local order: { Ghosts.Name } = { "blinky", "pinky", "inky", "clyde", "blinky", "pinky" }
			for _, name: Ghosts.Name in order do
				oracle.shots = 0
				local want = Blaster.drop(oracle)
				local before = Session.frame(s, "p").shots :: number
				local got = find(eatOne(s, name), "ShotGained") ~= nil
				t.expect(got).toBe(want and before < 3)
			end
		end
	end)

	it("a ghost that is shot rolls no drop", function()
		local seed = seedWhere(true)
		local s = settled(new(seed))
		for _, g in ghostsOf(s).ghosts do
			g.tile, g.status = { x = 13, y = 14 }, "house"
		end
		ghostsOf(s).house.idle = -100000
		local g = Ghosts.ghost(ghostsOf(s), "blinky")
		g.tile, g.progress, g.status = { x = 9, y = 23 }, 0, "active"
		s.members.p.blaster.shots = 1
		Session.submit(s, "p", Blaster.intent("E"))
		local events = Session.step(s)
		t.expect(find(events, "Shot") ~= nil).toBe(true)
		t.expect(find(events, "ShotGained")).toBe(nil)
		t.expect(Session.frame(s, "p").shots).toBe(0)
		-- and the generator did not move: the next contact eat rolls the seed's first roll, which drops
		t.expect(find(eatOne(s, "pinky"), "ShotGained") ~= nil).toBe(true)
	end)

	it("no more than three are held: a drop at three is lost", function()
		local s = settled(new(seedWhere(true)))
		s.members.p.blaster.shots = 3
		local events = eatOne(s, "blinky")
		t.expect(find(events, "ShotGained")).toBe(nil)
		t.expect(Session.frame(s, "p").shots).toBe(3)
	end)

	it("shots outlive a death", function()
		local s = settled(new(1))
		s.members.p.blaster.shots = 2
		Session.kill(s, "p")
		local ready = false
		for _ = 1, 120 do
			for _, e in Session.step(s) do
				if e.kind == "Ready" then
					ready = true
				end
			end
		end
		t.expect(ready).toBe(true)
		t.expect(Session.frame(s, "p").shots).toBe(2)
	end)

	it("shots outlive a cleared level", function()
		local s = settled(new(1))
		s.members.p.blaster.shots = 3
		local member = s.members.p
		-- every pellet but the one north of the player is gone; the player turns right (north) and eats it
		local level = member.play.level
		local cleared = false
		for _, tile in Pellets.tiles(member.pellets) do
			if not (tile.x == 6 and tile.y == 22) then
				Pellets.eat(member.pellets, tile)
			end
		end
		t.expect(Pellets.remaining(member.pellets)).toBe(1)
		Session.submit(s, "p", "Right")
		for _ = 1, 200 do
			if find(Session.step(s), "LevelCleared") then
				cleared = true
			end
		end
		t.expect(cleared).toBe(true)
		t.expect(member.play.level).toBe(level + 1)
		t.expect(Session.frame(s, "p").shots).toBe(3)
	end)

	it("a new run starts with none", function()
		local s = settled(new(1))
		s.members.p.blaster.shots = 3
		local member = s.members.p
		member.play.lives = 1
		Session.kill(s, "p")
		for _ = 1, 60 do
			Session.step(s)
		end
		t.expect(member.play.phase).toBe("gameover")
		t.expect(Session.frame(s, "p").shots).toBe(3) -- the results still show them
		local _, ok = Session.playAgain(s, "p")
		t.expect(ok).toBe(true)
		t.expect(Session.frame(s, "p").shots).toBe(0)
	end)

	it("every frame carries the count as a number, plain data for replication", function()
		local s = new(1)
		local frame = Session.frame(s, "p")
		t.expect(frame.shots).toBe(0)
		s.members.p.blaster.shots = 2
		frame = Session.frame(s, "p")
		t.expect(frame.shots).toBe(2)
		-- c0153: plain data, and a JSON round trip within 1e-9 (Lune's JSON decoder can return a number one ulp off)
		t.expect({ plain.roundTrip(frame, 1e-9) }).toEqual({ true })
		-- the v1 snapshot is unchanged
		local keys = {}
		for k in Session.snapshot(s, "p") :: any do
			table.insert(keys, k)
		end
		table.sort(keys)
		t.expect(keys).toEqual({ "ghosts", "maze", "player", "tick", "v" })
	end)
end)
