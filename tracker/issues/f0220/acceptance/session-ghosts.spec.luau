--!strict
-- f0220: the ghosts inside a Session. They are off unless the config asks for them (and the maze has ghost
-- data); they only move while the run is in play; a normal ghost on the player costs a life, a blue one is
-- eaten for the chain's points; a death sends everybody home; the last pellet wins over a ghost that
-- arrives at the same moment; and the blue time ends the very tick the run's power does.
local Game = require("@logic/Game")
local Ghosts = require("@logic/Ghosts")
local Maze = require("@logic/Maze")
local Pellets = require("@logic/Pellets")
local Session = require("@logic/Session")
local t = require("@tests/lib/t")

local classic = Maze.layout("classic")
local CORRIDOR = Maze.parse({ "###############", "#            P#", "###############" }, "corridor")

local function new(config: Session.Config?): Session.Session
	local s = Session.new(classic, 1, config or Session.GAME_CONFIG)
	Session.join(s, "p")
	return s
end

local function ghostsOf(s: Session.Session): Ghosts.Set
	return s.members.p.ghosts :: Ghosts.Set
end

local function playing(s: Session.Session): Session.Session
	for _ = 1, 61 do
		Session.step(s)
	end
	return s
end

-- in play, and the idle player has run west to the wall at 6,23 and stopped: it no longer moves, so a
-- ghost put on its tile stays on it
local function settled(s: Session.Session): Session.Session
	playing(s)
	for _ = 1, 40 do
		Session.step(s)
	end
	return s
end

local function kinds(events: { Session.Event }): { string }
	local out = {}
	for _, e in events do
		table.insert(out, e.kind)
	end
	return out
end

local function has(events: { Session.Event }, kind: string): boolean
	return table.find(kinds(events), kind) ~= nil
end

local function tiles(set: Ghosts.Set): string
	local out = {}
	for _, g in set.ghosts do
		table.insert(out, `{g.tile.x},{g.tile.y},{g.progress},{g.status}`)
	end
	return table.concat(out, ";")
end

-- a ghost stands on the player's tile, as if it had just arrived there
local function onPlayer(s: Session.Session, name: Ghosts.Name): Ghosts.Ghost
	local g = Ghosts.ghost(ghostsOf(s), name)
	local at = require("@logic/Movement").occupied(s.maze, s.members.p.move)
	g.tile, g.progress, g.status = { x = at.x, y = at.y }, 0, "active"
	return g
end

return t.spec("f0220 ghosts in a session", function(it)
	it(
		"the ghosts are on in GAME_CONFIG and off in the default config, and a maze without ghost data has none",
		function()
			t.expect(Session.GAME_CONFIG.ghosts).toBe(true)
			t.expect(Session.DEFAULT_CONFIG.ghosts).toBe(nil)
			local plain = new(Session.DEFAULT_CONFIG)
			t.expect(plain.members.p.ghosts).toBe(nil)
			local custom = Session.new(CORRIDOR, 1, Session.GAME_CONFIG)
			Session.join(custom, "p")
			t.expect(custom.members.p.ghosts).toBe(nil)
			for _ = 1, 100 do
				Session.step(custom)
			end
			t.expect(custom.members.p.play.lives).toBe(3)
		end
	)

	it("the ghosts stand still through the ready pause and begin when the run is in play", function()
		local s = new()
		local before = tiles(ghostsOf(s))
		for _ = 1, 59 do
			Session.step(s)
		end
		t.expect(tiles(ghostsOf(s))).toBe(before)
		for _ = 1, 3 do
			Session.step(s)
		end
		t.expect(tiles(ghostsOf(s)) ~= before).toBe(true)
	end)

	it(
		"a normal ghost arriving on the player takes a life, names itself, and the run starts dying",
		function()
			local s = settled(new())
			onPlayer(s, "inky")
			local events = Session.step(s)
			t.expect(has(events, "Caught")).toBe(true)
			t.expect(has(events, "LifeLost")).toBe(true)
			for _, e in events do
				if e.kind == "Caught" then
					t.expect(e.ghost).toBe("inky")
				end
			end
			t.expect(s.members.p.play.lives).toBe(2)
			t.expect(s.members.p.play.phase).toBe("dying")
		end
	)

	it(
		"nothing moves while the player is dying, and after the pause everything is home: the player at the spawn, the ghosts at their starts, the pellets as they were",
		function()
			local s = playing(new())
			for _ = 1, 40 do
				Session.step(s)
			end
			local remaining = Pellets.remaining(s.members.p.pellets)
			onPlayer(s, "blinky")
			Session.step(s)
			local frozen = tiles(ghostsOf(s))
			for _ = 1, 40 do
				Session.step(s)
			end
			t.expect(tiles(ghostsOf(s))).toBe(frozen)
			local events: { Session.Event } = {}
			for _ = 1, 10 do
				for _, e in Session.step(s) do
					table.insert(events, e)
				end
			end
			t.expect(has(events, "Ready")).toBe(true)
			local set = ghostsOf(s)
			t.expect(Ghosts.ghost(set, "blinky").tile).toEqual({ x = 14, y = 11 })
			t.expect(Ghosts.ghost(set, "pinky").status).toBe("house")
			t.expect(Ghosts.ghost(set, "clyde").status).toBe("house")
			t.expect(Pellets.remaining(s.members.p.pellets)).toBe(remaining)
			t.expect(set.house.global).toBe(0) -- the house counts with its global counter after a death
			local snap = Session.snapshot(s, "p")
			t.expect(snap.player.x).toBe(13)
			t.expect(snap.player.y).toBe(23)
		end
	)

	it(
		"a blue ghost on the player is eaten for 200, the next for 400, and the score and the ghost follow",
		function()
			local s = settled(new())
			local set = ghostsOf(s)
			Ghosts.power(set, 300)
			onPlayer(s, "pinky")
			local first = Session.step(s)
			local ate: Session.Event? = nil
			for _, e in first do
				if e.kind == "GhostEaten" then
					ate = e
				end
			end
			t.expect(ate ~= nil).toBe(true)
			t.expect((ate :: Session.Event).points).toBe(200)
			t.expect((ate :: Session.Event).ghost).toBe("pinky")
			t.expect(s.members.p.play.score >= 200).toBe(true)
			t.expect(Ghosts.ghost(set, "pinky").status).toBe("eyes")
			local scoreAfterFirst = s.members.p.play.score
			onPlayer(s, "clyde").frightened = true
			local second = Session.step(s)
			local points = 0
			for _, e in second do
				if e.kind == "GhostEaten" then
					points = e.points :: number
				end
			end
			t.expect(points).toBe(400)
			t.expect(s.members.p.play.score >= scoreAfterFirst + 400).toBe(true)
			t.expect(s.members.p.play.phase).toBe("playing") -- eating a ghost costs no life
		end
	)

	it("a normal ghost and a blue one at the same moment: the life is lost and nothing is eaten", function()
		local s = settled(new())
		local set = ghostsOf(s)
		Ghosts.power(set, 300)
		onPlayer(s, "pinky").frightened = true
		onPlayer(s, "blinky").frightened = false
		local score = s.members.p.play.score
		local events = Session.step(s)
		t.expect(has(events, "LifeLost")).toBe(true)
		t.expect(has(events, "GhostEaten")).toBe(false)
		t.expect(s.members.p.play.score).toBe(score)
	end)

	it("the last pellet clears the level even when a ghost arrives on the same tick", function()
		local s = playing(new())
		local pellets = s.members.p.pellets
		-- leave exactly the pellet the player is about to eat, two tiles west of the spawn
		local keep = { x = 12, y = 23 }
		for _, tile in Pellets.tiles(pellets) do
			if tile.x ~= keep.x or tile.y ~= keep.y then
				Pellets.eat(pellets, tile)
			end
		end
		t.expect(Pellets.remaining(pellets)).toBe(1)
		local g = Ghosts.ghost(ghostsOf(s), "blinky")
		g.tile, g.progress, g.heading, g.status = { x = 12, y = 23 }, 0, "W", "active"
		local events: { Session.Event } = {}
		for _ = 1, 3 do
			for _, e in Session.step(s) do
				table.insert(events, e)
			end
		end
		t.expect(has(events, "LevelCleared")).toBe(true)
		t.expect(has(events, "Caught")).toBe(false) -- no contact is even reported
		t.expect(has(events, "LifeLost")).toBe(false)
		t.expect(s.members.p.play.lives).toBe(3)
	end)

	it(
		"a power pellet turns the ghosts blue, and their blue time ends the very tick the run's power does",
		function()
			local s = playing(new())
			-- the tile the player is about to enter holds a power pellet
			local pellets = s.members.p.pellets
			pellets.cells[23 * classic.width + 12 + 1] = "power"
			local started: number? = nil
			local ended: number? = nil
			local blueUntil: number? = nil
			for tick = 1, 400 do
				local events = Session.step(s)
				if has(events, "PowerStarted") and started == nil then
					started = tick
				end
				if has(events, "PowerEnded") then
					ended = tick
				end
				local set = ghostsOf(s)
				-- the ghost clock and the run's clock stay equal throughout
				t.expect(set.frightened).toBe(s.members.p.play.frightened)
				if started and not ended then
					for _, g in set.ghosts do
						if g.status ~= "eyes" then
							t.expect(g.frightened).toBe(true)
						end
					end
					blueUntil = tick
				end
				if ended then
					for _, g in set.ghosts do
						t.expect(g.frightened).toBe(false)
					end
					break
				end
			end
			t.expect(started ~= nil and ended ~= nil).toBe(true)
			t.expect((ended :: number) - (started :: number)).toBe(180)
			t.expect(blueUntil).toBe((ended :: number) - 1)
		end
	)

	it("events about a ghost carry its name, and the house's first release is announced", function()
		local s = new()
		local all: { Session.Event } = {}
		for _ = 1, 70 do
			for _, e in Session.step(s) do
				table.insert(all, e)
			end
		end
		local released = false
		for _, e in all do
			if e.kind == "GhostReleased" then
				released = true
				t.expect(e.ghost).toBe("pinky")
			end
		end
		t.expect(released).toBe(true)
	end)

	it("a new run starts everything over: the ghosts at their starts and the timetable at scatter", function()
		local s = playing(new())
		for _ = 1, 3 do
			onPlayer(s, "blinky")
			Session.step(s)
			for _ = 1, 140 do
				Session.step(s)
			end
		end
		t.expect(s.members.p.play.phase).toBe("gameover")
		local _, ok = Session.playAgain(s, "p")
		t.expect(ok).toBe(true)
		local set = ghostsOf(s)
		t.expect(set.mode).toBe("scatter")
		t.expect(set.level).toBe(1)
		t.expect(Ghosts.ghost(set, "inky").status).toBe("house")
		t.expect(set.house.global).toBe(nil)
		t.expect(Game.canMove(s.members.p.play)).toBe(false) -- the ready pause again
	end)

	it("every pellet the player eats counts for the house: the ghost next in line counts them", function()
		local s = new()
		local eaten = 0
		for _ = 1, 100 do
			for _, e in Session.step(s) do
				if e.kind == "PelletEaten" then
					eaten += 1
				end
			end
		end
		t.expect(eaten > 4).toBe(true)
		-- Pinky left at once (its limit is 0), so every pellet counted for Inky, the next in line
		t.expect(ghostsOf(s).house.personal.inky).toBe(eaten)
		t.expect(ghostsOf(s).house.personal.pinky).toBe(0)
	end)

	it(
		"a ghost and the player that swap tiles within one tick, through real movement, are a meeting",
		function()
			local s = playing(new()) -- the player is at 13,23 heading west, 30 units on
			for _, g in ghostsOf(s).ghosts do
				g.tile, g.progress, g.status = { x = 3, y = 1 }, 0, "active" -- everybody else far away
			end
			local ghost = Ghosts.ghost(ghostsOf(s), "blinky")
			-- on the next tile west, heading east, 40 units on: this tick the player crosses to the west tile
			-- while the ghost crosses to the east one
			ghost.tile, ghost.heading, ghost.progress = { x = 12, y = 23 }, "E", 40
			local events = Session.step(s)
			t.expect(has(events, "Caught")).toBe(true)
			t.expect(has(events, "LifeLost")).toBe(true)
		end
	)

	it(
		"a power pellet eaten on the tile where a normal ghost arrives makes it a blue ghost that is eaten",
		function()
			local s = playing(new())
			for _, g in ghostsOf(s).ghosts do
				g.tile, g.progress, g.status = { x = 3, y = 1 }, 0, "active"
			end
			s.members.p.pellets.cells[23 * classic.width + 12 + 1] = "power"
			local ghost = Ghosts.ghost(ghostsOf(s), "inky")
			ghost.tile, ghost.heading, ghost.progress = { x = 12, y = 23 }, "E", 0
			local events = Session.step(s)
			t.expect(has(events, "PowerStarted")).toBe(true)
			t.expect(has(events, "GhostEaten")).toBe(true)
			t.expect(has(events, "LifeLost")).toBe(false)
			t.expect(s.members.p.play.lives).toBe(3)
		end
	)

	it(
		"a blue ghost met on the very tick the power ends is a normal ghost again: the life is lost",
		function()
			local s = settled(new())
			local set = ghostsOf(s)
			Ghosts.power(set, 1)
			s.members.p.play.frightened = 1 -- the run's power ends in this step too
			onPlayer(s, "clyde").frightened = true
			local events = Session.step(s)
			t.expect(has(events, "PowerEnded")).toBe(true)
			t.expect(has(events, "LifeLost")).toBe(true)
			t.expect(has(events, "GhostEaten")).toBe(false)
		end
	)

	it("two blue ghosts met in one tick are eaten in the order of the ghosts, 200 then 400", function()
		local s = settled(new())
		local set = ghostsOf(s)
		Ghosts.power(set, 300)
		onPlayer(s, "inky").frightened = true
		onPlayer(s, "pinky").frightened = true
		local points = {}
		local who = {}
		for _, e in Session.step(s) do
			if e.kind == "GhostEaten" then
				table.insert(points, e.points :: number)
				table.insert(who, tostring(e.ghost))
			end
		end
		t.expect(who).toEqual({ "pinky", "inky" })
		t.expect(points).toEqual({ 200, 400 })
	end)

	it("a ghost and the player pass each other across the tunnel's edge and are a meeting", function()
		local s = playing(new())
		for _, g in ghostsOf(s).ghosts do
			g.tile, g.progress, g.status = { x = 3, y = 1 }, 0, "active"
		end
		-- the player at the west end of the tunnel row heading west, half way across the edge; the ghost at the east end
		-- heading east: this tick they swap the tiles on either side of the edge
		local move = s.members.p.move
		move.tile, move.heading, move.progress, move.moving = { x = 0, y = 14 }, "W", 50, true
		local ghost = Ghosts.ghost(ghostsOf(s), "blinky")
		ghost.tile, ghost.heading, ghost.progress = { x = 27, y = 14 }, "E", 50
		local events = Session.step(s)
		t.expect(has(events, "Caught")).toBe(true)
	end)

	it("each ghost's jump tick is recorded: a tunnel wrap now, every ghost at a reset", function()
		local s = playing(new())
		for _, g in ghostsOf(s).ghosts do
			g.tile, g.progress, g.status = { x = 3, y = 1 }, 0, "active"
		end
		local blinky = Ghosts.ghost(ghostsOf(s), "blinky")
		blinky.tile, blinky.heading, blinky.progress = { x = 0, y = 14 }, "W", 110
		Session.step(s)
		t.expect(s.members.p.ghostJump.blinky).toBe(s.tick)
		t.expect(s.members.p.ghostJump.pinky).toBe(nil)
		local before = s.tick
		onPlayer(s, "clyde")
		Session.kill(s, "p")
		for _ = 1, 50 do
			Session.step(s)
		end
		for _, name: Ghosts.Name in Ghosts.NAMES do
			t.expect(s.members.p.ghostJump[name] > before).toBe(true)
		end
	end)

	it("a snapshot of a ghost-less session is exactly what it was before", function()
		local s = new(Session.DEFAULT_CONFIG)
		local keys = {}
		for k in Session.snapshot(s, "p") do
			table.insert(keys, k)
		end
		table.sort(keys)
		t.expect(keys).toEqual({ "maze", "player", "tick", "v" })
	end)
end)
