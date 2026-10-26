--!strict
-- f0126 AC4: what each boon does, in the session. Longer jumps: every hop is a long one (Hop.LONG_TICKS, airborne
-- 1.5 times as long) until the maze is fresh again; a faster pick: the next pick that finishes takes half the time;
-- a ghost pill: a power pellet's frightened time; a long ghost pill: twice that; a blaster shot: one more shot; and
-- pellets back: every eaten pellet and power pellet is there again. Each boon is equally likely.
--
-- The seeds are found by playing: the first seed whose first pick grants the boon a case needs.
local Blaster = require("@logic/Blaster")
local Game = require("@logic/Game")
local Hop = require("@logic/Hop")
local Levels = require("@logic/Levels")
local Maze = require("@logic/Maze")
local Movement = require("@logic/Movement")
local Pellets = require("@logic/Pellets")
local Picks = require("@logic/Picks")
local Session = require("@logic/Session")
local t = require("@tests/lib/t")

local CORRIDOR = Maze.parse({ "#########", "#########", "#.....P.#", "#########", "#########" }, "corridor")
-- level 1's pick, from the tables (43 and 22 steps today)
local PICK_TICKS = Picks.ticks(Levels.ghostSpeed(Movement.DEFAULT_CONFIG.speed, 1, "normal"), false)
local FAST_TICKS = Picks.ticks(Levels.ghostSpeed(Movement.DEFAULT_CONFIG.speed, 1, "normal"), true)
local PLAY: Session.Config = {
	movement = Movement.DEFAULT_CONFIG,
	maxIntentsPerTick = 4,
	play = Game.CLASSIC_CONFIG,
}

local function new(seed: number, config: Session.Config?): Session.Session
	local s = Session.new(CORRIDOR, seed, config)
	Session.join(s, "p")
	return s
end

local function step(s: Session.Session, raws: { string }?): { Session.Event }
	local list: { string } = raws or {}
	for _, raw in list do
		Session.submit(s, "p", raw)
	end
	return Session.step(s)
end

local function has(events: { Session.Event }, kind: string): Session.Event?
	for _, e in events do
		if e.kind == kind then
			return e
		end
	end
	return nil
end

-- Asks for a pick and steps until a pick finishes or `limit` steps pass; returns the WallPicked event (or nil) and
-- every event on the way.
local function pickOnce(s: Session.Session, limit: number): (Session.Event?, { Session.Event })
	local all: { Session.Event } = {}
	Session.submit(s, "p", "Pick")
	for _ = 1, limit do
		local events = Session.step(s)
		for _, e in events do
			table.insert(all, e)
		end
		local picked = has(events, "WallPicked")
		if picked then
			return picked, all
		end
		if has(events, "Stopped") then
			Session.submit(s, "p", "Back") -- the corridor's end: walk back past the marks
		end
		if has(events, "PickStarted") == nil and s.tick % 8 == 0 then
			Session.submit(s, "p", "Pick")
		end
	end
	return nil, all
end

-- The first seed whose first pick grants `boon` (and, with `ok`, whose session and events then pass `ok`), its
-- session just after that pick, and the step it finished in.
local function withBoon(
	boon: Picks.Boon,
	config: Session.Config?,
	ok: ((Session.Session, { Session.Event }) -> boolean)?
): (Session.Session, number)
	for seed = 1, 3000 do
		local s = new(seed, config)
		if config and config.play then
			for _ = 1, 60 do
				Session.step(s) -- "Ready!"
			end
		end
		local picked, events = pickOnce(s, 200)
		if picked and picked.item == boon and (ok == nil or ok(s, events)) then
			return s, s.tick
		end
	end
	error(`no seed grants {boon} first`)
end

-- After a pick in a PLAY session: walk west to the end, back east to the last pellet, through the level-clear
-- pause and "Ready!" into level 2.
local function clearLevel(s: Session.Session)
	local level = Session.frame(s, "p").play.level
	for _ = 1, 400 do
		local events = step(s)
		if has(events, "Stopped") then
			step(s, { "Back" })
		end
		if Session.frame(s, "p").play.level > level and Session.frame(s, "p").play.phase == "playing" then
			return
		end
	end
	error("the level did not clear")
end

-- A death in a PLAY session, through the dying pause and "Ready!" back into play.
local function respawn(s: Session.Session)
	Session.kill(s, "p")
	for _ = 1, 110 do
		Session.step(s)
	end
	t.expect(Session.frame(s, "p").play.phase).toBe("playing")
end

-- Three deaths, then a new run, back into play.
local function newRun(s: Session.Session)
	while not Session.isOver(s, "p") do
		Session.kill(s, "p")
		for _ = 1, 110 do
			Session.step(s)
		end
	end
	local _, ok = Session.playAgain(s, "p")
	t.expect(ok).toBe(true)
	for _ = 1, 62 do
		Session.step(s)
	end
end

-- The length of the next hop: hop now and read the frame.
local function nextHop(s: Session.Session): number
	step(s, { "Hop" })
	return Session.frame(s, "p").hopTicks :: number
end

-- The steps the next pick takes.
local function nextPick(s: Session.Session): number
	local _, events = pickOnce(s, 400)
	local started = has(events, "PickStarted")
	t.expect(started ~= nil).toBe(true)
	return (started :: Session.Event).ticks :: number
end

return t.spec("f0126 boons", function(it)
	it("longer jumps: the next hop is a long one, airborne 15 steps instead of 10", function()
		t.expect(Hop.LONG_TICKS).toBe(19)
		local s = withBoon("jumps")
		t.expect((Session.frame(s, "p").boon :: Session.BoonGrant).kind).toBe("jumps")
		step(s, { "Hop" })
		local f = Session.frame(s, "p")
		t.expect(f.hopTicks).toBe(Hop.LONG_TICKS)
		local started = f.hopped :: number
		local airborne = 0
		for k = started, started + Hop.LONG_TICKS do
			if Hop.airborne(started, k, Hop.LONG_TICKS) then
				airborne += 1
			end
		end
		t.expect(airborne).toBe(15)
	end)

	it("the session's airborne rule follows the long hop: pellets passed late in it are not eaten", function()
		-- picked on the spawn's own tile, so the pellets west of it are all still there when the long hop starts
		local s = withBoon("jumps", nil, function(c, events)
			return has(events, "PickStarted") ~= nil and Session.frame(c, "p").player.x > 5.5
		end)
		step(s, { "Hop" })
		local started = Session.frame(s, "p").hopped :: number
		local late = 0 -- pellet tiles entered while airborne only because the hop is long
		for _ = 1, Hop.LONG_TICKS do
			local events = step(s)
			local longAir = Hop.airborne(started, s.tick, Hop.LONG_TICKS)
			local shortAir = Hop.airborne(started, s.tick)
			for _, e in events do
				if e.kind == "PelletEaten" then
					t.expect(longAir).toBe(false)
				end
				if e.kind == "Entered" and longAir and not shortAir then
					late += 1
				end
			end
		end
		t.expect(late >= 1).toBe(true)
	end)

	it("longer jumps last until the maze is fresh: a new run hops at the normal length", function()
		local s = withBoon("jumps", PLAY)
		for _ = 1, 3 do
			Session.kill(s, "p")
			for _ = 1, 110 do
				Session.step(s)
			end
		end
		t.expect(Session.isOver(s, "p")).toBe(true)
		local _, ok = Session.playAgain(s, "p")
		t.expect(ok).toBe(true)
		for _ = 1, 62 do
			Session.step(s)
		end
		step(s, { "Hop" })
		t.expect(Session.frame(s, "p").hopTicks).toBe(Hop.TICKS)
	end)

	it(
		"a faster pick: the next pick takes half the time, and spends the boon: the one after takes the whole time",
		function()
			for seed = 1, 3000 do
				local s = new(seed)
				local first = pickOnce(s, 200)
				if first and first.item == "fastpick" then
					local second, events = pickOnce(s, 400)
					if second and second.item ~= "fastpick" then
						local third, more = pickOnce(s, 400)
						if third then
							t.expect((has(events, "PickStarted") :: Session.Event).ticks).toBe(FAST_TICKS)
							t.expect((has(more, "PickStarted") :: Session.Event).ticks).toBe(PICK_TICKS)
							return
						end
					end
				end
			end
			error("no seed gave a fast pick followed by two picks")
		end
	)

	it("a wasted fast pick keeps the faster pick for the next one", function()
		local s = withBoon("fastpick")
		Session.submit(s, "p", "Pick")
		local started: Session.Event? = nil
		for _ = 1, 400 do
			local events = Session.step(s)
			started = has(events, "PickStarted")
			if started then
				break
			end
			if has(events, "Stopped") then
				Session.submit(s, "p", "Back")
			end
			if s.tick % 8 == 0 then
				Session.submit(s, "p", "Pick")
			end
		end
		t.expect((started :: Session.Event).ticks).toBe(FAST_TICKS)
		t.expect((Session.frame(s, "p").pick :: Session.Pick).fast).toBe(true)
		local stop = step(s, { "Back" })
		t.expect(has(stop, "PickStopped") ~= nil).toBe(true)
		local _, after = pickOnce(s, 400)
		t.expect((has(after, "PickStarted") :: Session.Event).ticks).toBe(FAST_TICKS)
	end)

	it("a ghost pill: the level's frightened time starts, as from a power pellet", function()
		local s, at = withBoon("pill")
		local f = Session.frame(s, "p")
		t.expect(f.tick).toBe(at)
		t.expect(f.play.frightened).toBe(Levels.frightenedTicks(1, Session.TICK_RATE))
	end)

	it("a long ghost pill: twice the level's frightened time", function()
		local s = withBoon("longpill")
		t.expect(Session.frame(s, "p").play.frightened).toBe(2 * Levels.frightenedTicks(1, Session.TICK_RATE))
	end)

	it("the pill's time is announced as a power period, for the ghosts to turn blue", function()
		local found = 0
		for _, boon: Picks.Boon in { "pill", "longpill" } :: { Picks.Boon } do
			for seed = 1, 3000 do
				local s = new(seed)
				local picked, events = pickOnce(s, 200)
				if picked and picked.item == boon then
					local power = has(events, "PowerStarted") :: Session.Event
					t.expect(power ~= nil).toBe(true)
					local want = Levels.frightenedTicks(1, Session.TICK_RATE)
					t.expect(power.ticks).toBe(if boon == "pill" then want else 2 * want)
					found += 1
					break
				end
			end
		end
		t.expect(found).toBe(2)
	end)

	it("a blaster shot: one more shot held, every time", function()
		local found = 0
		for seed = 1, 3000 do
			local s = new(seed)
			local picked, events = pickOnce(s, 200)
			if picked and picked.item == "shot" then
				found += 1
				t.expect(Session.frame(s, "p").shots).toBe(1)
				t.expect(has(events, "ShotGained") ~= nil).toBe(true)
				if found == 8 then
					return
				end
			end
		end
		error("fewer than 8 seeds grant a shot first")
	end)

	it("a shot granted while three are held is wasted", function()
		local b = Blaster.new(1)
		t.expect(Blaster.gain(b)).toBe(true)
		t.expect(Blaster.gain(b)).toBe(true)
		t.expect(Blaster.gain(b)).toBe(true)
		t.expect(b.shots).toBe(3)
		t.expect(Blaster.gain(b)).toBe(false)
		t.expect(b.shots).toBe(3)
		local rng = b.rng
		Blaster.gain(b)
		t.expect(b.rng).toBe(rng) -- no roll: the drops that follow are as they were
	end)

	it("pellets back: every eaten pellet and power pellet is there again", function()
		local full = Pellets.encode(Pellets.new(CORRIDOR))
		-- a pick away from the spawn, so pellets were eaten on the way to it
		local s = withBoon("pellets", nil, function(_, events)
			return has(events, "PelletEaten") ~= nil
		end)
		t.expect(Session.frame(s, "p").pellets).toBe(full)
	end)

	it("each boon is about as likely as the next, over many runs", function()
		local counts: { [string]: number } = {}
		local runs = 0
		for seed = 1, 900 do
			local picked = pickOnce(new(seed), 200)
			if picked then
				runs += 1
				counts[picked.item :: string] = (counts[picked.item :: string] or 0) + 1
			end
		end
		t.expect(runs >= 850).toBe(true)
		for _, boon in Picks.BOONS do
			local n = counts[boon] or 0
			t.expect(n > runs / 6 * 0.7 and n < runs / 6 * 1.3).toBe(true)
		end
	end)

	it("longer jumps: kept over a death, ended by a new level", function()
		local s = withBoon("jumps", PLAY)
		respawn(s)
		t.expect(nextHop(s)).toBe(Hop.LONG_TICKS)
		local again = withBoon("jumps", PLAY)
		clearLevel(again)
		t.expect(nextHop(again)).toBe(Hop.TICKS)
	end)

	it("a banked faster pick is kept over a death and a new level, and dropped by a new run", function()
		local s = withBoon("fastpick", PLAY)
		respawn(s)
		t.expect(nextPick(s)).toBe(FAST_TICKS)
		local level = withBoon("fastpick", PLAY)
		clearLevel(level)
		-- level 2's ghosts are faster, so its fast pick is half of level 2's pick
		t.expect(nextPick(level)).toBe(Picks.ticks(Levels.ghostSpeed(30, 2, "normal"), true))
		t.expect(Picks.ticks(Levels.ghostSpeed(30, 2, "normal"), true)).toBe(19)
		local run = withBoon("fastpick", PLAY)
		newRun(run)
		t.expect(nextPick(run)).toBe(PICK_TICKS)
	end)

	it("the frame's last boon is kept over a death and a new level, and gone in a new run", function()
		local s = withBoon("shot", PLAY)
		local boon = Session.frame(s, "p").boon :: Session.BoonGrant
		respawn(s)
		t.expect((Session.frame(s, "p").boon :: Session.BoonGrant).tick).toBe(boon.tick)
		clearLevel(s)
		t.expect((Session.frame(s, "p").boon :: Session.BoonGrant).kind).toBe("shot")
		newRun(s)
		t.expect(Session.frame(s, "p").boon).toBe(nil)
	end)

	it("after a long hop the next waits the cool-down after its own landing", function()
		local s = withBoon("jumps")
		local hops: { number } = {}
		for _ = 1, Hop.LONG_TICKS + Hop.COOLDOWN + 5 do
			if has(step(s, { "Hop" }), "Hopped") then
				table.insert(hops, s.tick)
			end
		end
		t.expect(#hops).toBe(2)
		t.expect(hops[2] - hops[1]).toBe(Hop.LONG_TICKS + Hop.COOLDOWN)
	end)

	it("no pick starts in the air of a long hop", function()
		for seed = 1, 3000 do
			local s = new(seed)
			local picked = pickOnce(s, 200)
			if picked and picked.item == "jumps" then
				step(s, { "Hop", "Pick" })
				local hopped = Session.frame(s, "p").hopped :: number
				local started: number? = nil
				for _ = 1, 40 do
					if has(step(s, if s.tick % 6 == 0 then { "Pick" } else nil), "PickStarted") then
						started = s.tick
						break
					end
				end
				if started then
					t.expect(started >= hopped + Hop.LONG_TICKS).toBe(true)
					return
				end
			end
		end
		error("no seed picked during a long hop's reach")
	end)

	it(
		"pellets back brings back the eaten power pellets too, and feeds no pellets to the ghost house",
		function()
			local POWER =
				Maze.parse({ "#########", "#########", "#....oP.#", "#########", "#########" }, "power")
			local full = Pellets.encode(Pellets.new(POWER))
			for seed = 1, 3000 do
				local s = Session.new(POWER, seed)
				Session.join(s, "p")
				local picked, events = pickOnce(s, 200)
				local ate = false
				for _, e in events do
					ate = ate or (e.kind == "PelletEaten" and e.item == "power")
				end
				if picked and picked.item == "pellets" and ate then
					t.expect(Session.frame(s, "p").pellets).toBe(full)
					local back = Pellets.decode(POWER, Session.frame(s, "p").pellets)
					for i, slot in Pellets.slots(POWER) do
						t.expect(back[i]).toBe(true)
						t.expect(slot.kind == "pellet" or slot.kind == "power").toBe(true)
					end
					-- the finishing step's events: the boon, no eating (the house counts PelletEaten)
					local last: { Session.Event } = {}
					for k = #events, 1, -1 do
						table.insert(last, 1, events[k])
						if events[k].kind == "WallPicked" then
							break
						end
					end
					t.expect(has(last, "PelletsBack") ~= nil).toBe(true)
					t.expect(has(last, "PelletEaten")).toBe(nil)
					return
				end
			end
			error("no seed gives pellets back after eating the power pellet")
		end
	)

	it("a shot boon with three shots held gains nothing and says nothing", function()
		for seed = 1, 400 do
			local s = new(seed)
			for _ = 1, 80 do
				local before = Session.frame(s, "p").shots
				local picked, events = pickOnce(s, 400)
				if picked == nil then
					break
				end
				t.expect(Session.frame(s, "p").pick).toBe(nil)
				if picked.item == "shot" and before == 3 then
					t.expect(Session.frame(s, "p").shots).toBe(3)
					t.expect(has(events, "ShotGained")).toBe(nil)
					return
				end
			end
		end
		error("no seed granted a shot while three were held")
	end)

	it("a pick while the ghosts are blue still lasts a hunting ghost's ten tiles", function()
		local s = withBoon("longpill", nil, function(c)
			return Session.frame(c, "p").play.frightened > 0
		end)
		Session.submit(s, "p", "Pick")
		for _ = 1, 120 do
			local events = Session.step(s)
			local started = has(events, "PickStarted")
			if started then
				t.expect(Session.frame(s, "p").play.frightened > 0).toBe(true)
				t.expect(started.ticks).toBe(PICK_TICKS)
				return
			end
			if has(events, "Stopped") then
				Session.submit(s, "p", "Back")
			end
			if s.tick % 8 == 0 then
				Session.submit(s, "p", "Pick")
			end
		end
		error("no pick started while the ghosts were blue")
	end)
end)
