--!strict
-- f0143 AC2: the boost in a Session. "Boost" (Boost.INTENT) is an intent beside the movement, fire and hop intents;
-- it counts toward the per-tick limit, one a tick. In play it starts at the start of the player's play in the step
-- (a Boosted event; the frame's boosted is the tick), and while Boost.active the step covers
-- Boost.speed(level speed, true, Movement.UNITS) units. Outside play it does nothing and is not kept. The next boost
-- waits Boost.TICKS + Boost.COOLDOWN steps. A death's respawn ends it, and the next life has one ready. Each player
-- has their own. A hop and a boost in one tick both start, and a pellet eaten while boosting owes the boosted
-- distance (the eating rule at the step's speed).
local Boost = require("@logic/Boost")
local Game = require("@logic/Game")
local Hop = require("@logic/Hop")
local Maze = require("@logic/Maze")
local Movement = require("@logic/Movement")
local Pellets = require("@logic/Pellets")
local Session = require("@logic/Session")
local t = require("@tests/lib/t")

-- a long straight corridor: the player spawns at its east end heading west, with room for a boost and more
local ROW = "#" .. string.rep(" ", 77) .. "P#"
local LONG = Maze.parse({ string.rep("#", 80), ROW, string.rep("#", 80) }, "long")
-- the same corridor with a pellet on every tile, for the eating pause
local DOTTED =
	Maze.parse({ string.rep("#", 80), "#" .. string.rep(".", 77) .. "P#", string.rep("#", 80) }, "dotted")
local FREE: Session.Config = { movement = { speed = 30, turnBufferTicks = 24 }, maxIntentsPerTick = 4 }
local CLASSIC: Session.Config =
	{ movement = { speed = 30, turnBufferTicks = 24 }, maxIntentsPerTick = 4, play = Game.CLASSIC_CONFIG }
local EATING: Session.Config =
	{ movement = { speed = 30, turnBufferTicks = 24 }, maxIntentsPerTick = 4, eatSlowdown = true }

local function new(config: Session.Config, ...: string): Session.Session
	local s = Session.new(LONG, 1, config)
	local ids = { ... }
	if #ids == 0 then
		ids = { "p" }
	end
	for _, id in ids do
		Session.join(s, id)
	end
	return s
end

local function count(events: { Session.Event }, kind: string): number
	local n = 0
	for _, e in events do
		if e.kind == kind then
			n += 1
		end
	end
	return n
end

local function boost(s: Session.Session, id: string?): { Session.Event }
	local ok, why = Session.submit(s, id or "p", Boost.INTENT)
	assert(ok, why)
	return Session.step(s)
end

-- units the player moved along the corridor in one step
local function travelled(s: Session.Session, id: string?): number
	local x0 = Movement.position(s.members[id or "p"].move)
	Session.step(s)
	local x1 = Movement.position(s.members[id or "p"].move)
	return math.floor(math.abs(x1 - x0) * Movement.UNITS + 0.5)
end

local function playing(s: Session.Session): Session.Session
	while Session.frame(s, "p").play.phase ~= "playing" do
		Session.step(s)
	end
	return s
end

return t.spec("f0143 the boost in a session", function(it)
	it('accepts "Boost" and no other spelling; it counts toward the per-tick limit, one a tick', function()
		local ok, why = Session.submit(new(FREE), "p", "Boost")
		t.expect(ok).toBe(true)
		t.expect(why).toBe(nil)
		for _, v in { "boost", "BOOST", "Boost ", { "Boost" }, 1, true } :: { any } do
			local refused, reason = Session.submit(new(FREE), "p", v)
			t.expect(refused).toBe(false)
			t.expect(reason).toBe("invalid intent")
		end
		local s = new(FREE)
		t.expect((Session.submit(s, "p", Boost.INTENT))).toBe(true)
		local again, reason = Session.submit(s, "p", Boost.INTENT)
		t.expect(again).toBe(false)
		t.expect(reason).toBe("rate limited")
		local q = new(FREE)
		for _ = 1, 3 do
			t.expect((Session.submit(q, "p", "Forward"))).toBe(true)
		end
		t.expect((Session.submit(q, "p", Boost.INTENT))).toBe(true)
		local over, why2 = Session.submit(q, "p", "Forward")
		t.expect(over).toBe(false)
		t.expect(why2).toBe("rate limited")
	end)

	it("in play a boost starts this step: a Boosted event, and the frame says the tick", function()
		local s = new(FREE)
		Session.step(s)
		t.expect(Session.frame(s, "p").boosted).toBe(nil)
		local events = boost(s)
		t.expect(count(events, "Boosted")).toBe(1)
		t.expect(Session.frame(s, "p").boosted).toBe(s.tick)
	end)

	it(
		"a boosted step covers round(speed * FACTOR) units, for TICKS steps, then the level's speed again",
		function()
			local s = new(FREE)
			Session.step(s)
			t.expect(travelled(s)).toBe(30)
			t.expect((Session.submit(s, "p", Boost.INTENT))).toBe(true)
			for _ = 1, Boost.TICKS do
				t.expect(travelled(s)).toBe(45)
			end
			t.expect(travelled(s)).toBe(30)
			t.expect(travelled(s)).toBe(30)
		end
	)

	it("outside play a boost does nothing and is not kept", function()
		local s = new(CLASSIC)
		local events = boost(s) -- the ready phase
		t.expect(count(events, "Boosted")).toBe(0)
		t.expect(Session.frame(s, "p").boosted).toBe(nil)
		playing(s)
		for _ = 1, 5 do
			t.expect(count(Session.step(s), "Boosted")).toBe(0)
		end
		t.expect(Session.frame(s, "p").boosted).toBe(nil)
	end)

	it("the next boost starts no sooner than TICKS + COOLDOWN steps after the last", function()
		local s = new(FREE)
		Session.step(s)
		boost(s)
		local first = s.tick
		local nextAt: number? = nil
		for _ = 1, Boost.TICKS + Boost.COOLDOWN + 5 do
			if count(boost(s), "Boosted") > 0 then
				nextAt = s.tick
				break
			end
		end
		t.expect(nextAt).toBe(first + Boost.TICKS + Boost.COOLDOWN)
	end)

	it("a death ends the boost and the next life has one ready", function()
		local s = playing(new(CLASSIC))
		boost(s)
		Session.step(s)
		Session.kill(s, "p")
		local respawned = false
		for _ = 1, 400 do
			Session.step(s)
			if Session.frame(s, "p").play.phase == "playing" then
				respawned = true
				break
			end
		end
		t.expect(respawned).toBe(true)
		t.expect(Session.frame(s, "p").boosted).toBe(nil)
		t.expect(count(boost(s), "Boosted")).toBe(1)
	end)

	it("each player has their own boost", function()
		local s = new(FREE, "p", "q")
		Session.step(s)
		boost(s, "p")
		t.expect(Session.frame(s, "p").boosted).toBe(s.tick)
		t.expect(Session.frame(s, "q").boosted).toBe(nil)
		t.expect(travelled(s, "q")).toBe(30)
		local events = boost(s, "q") -- p's cooldown is not q's
		t.expect(count(events, "Boosted")).toBe(1)
		t.expect(Session.frame(s, "q").boosted).toBe(s.tick)
	end)

	it(
		"a boost and a hop in one tick both start, and a pellet eaten while boosting owes the boosted distance",
		function()
			local s = new(FREE)
			Session.step(s)
			t.expect((Session.submit(s, "p", Hop.INTENT))).toBe(true)
			local events = boost(s)
			t.expect(count(events, "Hopped")).toBe(1)
			t.expect(count(events, "Boosted")).toBe(1)

			local e = Session.new(DOTTED, 1, EATING)
			Session.join(e, "p")
			Session.step(e)
			t.expect((Session.submit(e, "p", Boost.INTENT))).toBe(true)
			local item: Pellets.Kind? = nil
			for _ = 1, Boost.TICKS do
				local before = e.members.p.stall
				for _, ev in Session.step(e) do
					if ev.kind == "PelletEaten" and item == nil and before == 0 then
						item = ev.item :: Pellets.Kind
					end
				end
				if item then
					break
				end
			end
			assert(item, "a pellet is eaten while boosting")
			local boosted = Boost.speed(30, true, Movement.UNITS)
			t.expect(e.members.p.stall)
				.toBe(Pellets.stallUnits(item :: Pellets.Kind, boosted, Session.TICK_RATE))
			t.expect(e.members.p.stall ~= Pellets.stallUnits(item :: Pellets.Kind, 30, Session.TICK_RATE))
				.toBe(true)
		end
	)
end)
