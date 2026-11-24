--!strict
-- f0221 AC3: by default a shot passes through the other player's ship (no friendly fire), and the two ships bounce
-- off each other; each is one switch the user may change. A bounce: two ships on the field whose centres are
-- closer than their two radii move half the overlap apart along the line of centres, swap their speeds along it if
-- they are closing (equal masses), and stay within the top speed; protected ships bounce too, ships away in
-- hyperspace or lost do not, and touching never costs a life. With friendly fire on, a shot destroys the other
-- player's exposed ship (the nearest target along its move wins, a rock or the saucer on a tie), scores nothing,
-- and names its shooter; a protected ship, and the shooter's own, it passes.
local Classic = require("@logic/Classic")
local Field = require("@logic/Field")
local TwoPlayer = require("@logic/TwoPlayer")
local t = require("@tests/lib/t")

-- the match's step, taking any inputs (the cases hand it junk and mixed lists too)
local step = TwoPlayer.step :: (TwoPlayer.Match, any) -> { Classic.Event }

-- both players' inputs for one tick
local function pair(a: Classic.Input?, b: Classic.Input?): { Classic.Input? }
	return { a, b }
end

local F = Classic.CONFIG.field
local MAX = Classic.CONFIG.ship.maxSpeed

local function with(changes: { [string]: any }, classic: { [string]: any }?): TwoPlayer.Config
	local c = table.clone(TwoPlayer.CONFIG :: any)
	for k, v in changes do
		c[k] = v
	end
	if classic then
		local cc = table.clone(c.classic)
		for k, v in classic do
			cc[k] = v
		end
		c.classic = cc
	end
	return c
end

local NO_DRAG = table.freeze((function()
	local s = table.clone(Classic.CONFIG.ship :: any)
	s.drag = 0
	return s
end)())

local function quiet(config: TwoPlayer.Config?): TwoPlayer.Match
	local m = TwoPlayer.new(1, config)
	m.rocks = {}
	m.waveTimer = 1e9
	m.saucerElapsed = -1e9
	return m
end

local function run(m: TwoPlayer.Match, n: number, inputs: any): { Classic.Event }
	local all = {}
	for _ = 1, n do
		for _, e in step(m, inputs) do
			table.insert(all, e)
		end
	end
	return all
end

local function only(events: { Classic.Event }, kind: string): { Classic.Event }
	local out = {}
	for _, e in events do
		if e.kind == kind then
			table.insert(out, e)
		end
	end
	return out
end

local function place(m: TwoPlayer.Match, slot: number, x: number, y: number, vx: number, vy: number)
	local s = m.pilots[slot].ship
	s.x, s.y, s.vx, s.vy = x, y, vx, vy
end

-- player 1 at (256, 384) pointing right, player 2 straight ahead of it at (400, 384)
local function lineUp(m: TwoPlayer.Match)
	m.pilots[1].ship.heading = 0
	place(m, 2, 400, 384, 0, 0)
end

local function speed(s: { vx: number, vy: number }): number
	return math.sqrt(s.vx * s.vx + s.vy * s.vy)
end

return t.spec("f0221 contact", function(it)
	it("defaults to no friendly fire and ships that bounce", function()
		t.expect(TwoPlayer.CONFIG.friendlyFire).toBe(false)
		t.expect(TwoPlayer.CONFIG.shipsBounce).toBe(true)
		t.expect(TwoPlayer.new(1).pair).toBe(TwoPlayer.CONFIG)
	end)

	it("lets a shot pass through the other player's ship by default", function()
		local m = quiet()
		lineUp(m)
		local events = run(m, 1, pair({ fire = true }, nil))
		for _, e in run(m, 29, nil) do
			table.insert(events, e)
		end
		t.expect(#only(events, "ShipDestroyed")).toBe(0)
		t.expect(m.pilots[2].lives).toBe(3)
		t.expect(m.pilots[2].shipState).toBe("alive")
		-- the shot has flown past player 2 and is still in flight
		t.expect(#m.pilots[1].shots).toBe(1)
		t.expect(m.pilots[1].shots[1].x > 400 + 12).toBe(true)
	end)

	it(
		"with friendly fire on, destroys the other player's exposed ship, scores nothing and names the shooter",
		function()
			local m = quiet(with({ friendlyFire = true }))
			lineUp(m)
			local events = run(m, 1, pair({ fire = true }, nil))
			for _, e in run(m, 29, nil) do
				table.insert(events, e)
			end
			local lost = only(events, "ShipDestroyed")
			t.expect(#lost).toBe(1)
			t.expect(lost[1].player).toBe(2)
			t.expect(lost[1].cause).toBe("shot")
			t.expect(lost[1].shooter).toBe(1)
			t.expect(m.pilots[2].lives).toBe(2)
			t.expect(m.pilots[1].lives).toBe(3)
			t.expect(m.pilots[1].score).toBe(0)
			t.expect(m.pilots[2].score).toBe(0)
			-- the shot that hit is gone, long before its 60 ticks
			t.expect(#m.pilots[1].shots).toBe(0)
			-- player 2's shots at player 1 work the same way
			local back = quiet(with({ friendlyFire = true }))
			lineUp(back)
			back.pilots[2].ship.heading = 128
			local lost2 = only(run(back, 1, pair(nil, { fire = true })), "ShipDestroyed")
			for _, e in only(run(back, 29, nil), "ShipDestroyed") do
				table.insert(lost2, e)
			end
			t.expect(#lost2).toBe(1)
			t.expect(lost2[1].player).toBe(1)
			t.expect(lost2[1].shooter).toBe(2)
		end
	)

	it("with friendly fire on, passes a protected ship and the shooter's own", function()
		local m = quiet(with({ friendlyFire = true }))
		lineUp(m)
		m.pilots[2].protect = 1e9
		t.expect(#only(run(m, 30, pair({ fire = true }, nil)), "ShipDestroyed")).toBe(0)
		-- a shot of player 1's that flies straight through player 1's own ship
		local own = quiet(with({ friendlyFire = true }))
		own.pilots[1].shots = { { x = 256 - 20, y = 384, vx = 8, vy = 0, life = 60 } }
		t.expect(#only(run(own, 5, nil), "ShipDestroyed")).toBe(0)
		t.expect(own.pilots[1].lives).toBe(3)
	end)

	it(
		"with friendly fire on, gives the shot to a rock or the saucer before the other ship along its move",
		function()
			local m = quiet(with({ friendlyFire = true }))
			lineUp(m)
			table.insert(m.rocks, { id = 800, size = "small", x = 330, y = 384, vx = 0, vy = 0 })
			local events = run(m, 12, pair({ fire = true }, nil))
			t.expect(#only(events, "RockHit")).toBe(1)
			t.expect(only(events, "RockHit")[1].player).toBe(1)
			-- a rock and the ship at the same point along the move: the rock takes it
			local tie = quiet(with({ friendlyFire = true }))
			place(tie, 2, 600, 600, 0, 0)
			tie.rocks = { { id = 801, size = "small", x = 600 - 2, y = 600, vx = 0, vy = 0 } }
			-- reaches the rock (radius 10) and the ship (radius 12) at the same point of its move
			tie.pilots[1].shots = { { x = 600 - 2 - 10 - 4, y = 600, vx = 8, vy = 0, life = 60 } }
			local e2 = run(tie, 1, nil)
			t.expect(#only(e2, "RockHit")).toBe(1)
			t.expect(#only(e2, "ShipDestroyed")).toBe(0)
			-- and the converse: the other ship nearer along the move than a rock, or than the saucer, takes it
			for _, what in { "rock", "saucer" } do
				local near = quiet(with({ friendlyFire = true }))
				place(near, 2, 600, 600, 0, 0)
				if what == "rock" then
					near.rocks = { { id = 802, size = "small", x = 603, y = 600, vx = 0, vy = 0 } }
				else
					near.saucer = {
						kind = "small",
						x = 603,
						y = 600,
						vx = 0,
						vy = 0,
						travelled = 0,
						fireElapsed = -1e9,
						turnElapsed = -1e9,
					} :: any
				end
				-- the ship's edge is 1 along the move (t = 1/8), the rock's or the saucer's 6 (t = 6/8)
				near.pilots[1].shots = { { x = 587, y = 600, vx = 8, vy = 0, life = 60 } }
				local e3 = run(near, 1, nil)
				local lost = only(e3, "ShipDestroyed")
				t.expect(#lost).toBe(1)
				t.expect(lost[1].shooter).toBe(1)
				t.expect(#only(e3, "RockHit")).toBe(0)
				t.expect(#only(e3, "SaucerHit")).toBe(0)
				t.expect(#near.rocks + (if near.saucer then 1 else 0)).toBe(1)
			end
		end
	)

	it(
		"bounces two ships that touch: they move apart and swap their speeds along the line between them",
		function()
			local m = quiet(with({}, { ship = NO_DRAG }))
			place(m, 1, 300, 384, 2, 0)
			place(m, 2, 320, 384, -2, 0)
			local events = run(m, 1, nil)
			t.expect(#only(events, "Bounce")).toBe(1)
			local a, b = m.pilots[1].ship, m.pilots[2].ship
			-- after their own moves they were 16 apart (302 and 318): each moved 4 apart, to 24
			t.expect(a.x).toBeNear(298, 1e-9)
			t.expect(b.x).toBeNear(322, 1e-9)
			t.expect(Field.distance(F, a.x, a.y, b.x, b.y)).toBeNear(24, 1e-9)
			t.expect(a.vx).toBeNear(-2, 1e-9)
			t.expect(b.vx).toBeNear(2, 1e-9)
			t.expect(a.vy).toBeNear(0, 1e-9)
			t.expect(b.vy).toBeNear(0, 1e-9)
			t.expect(#only(events, "ShipDestroyed")).toBe(0)
			t.expect(m.pilots[1].lives).toBe(3)
			t.expect(m.pilots[2].lives).toBe(3)
			-- they fly apart afterwards: no second bounce
			t.expect(#only(run(m, 10, nil), "Bounce")).toBe(0)
		end
	)

	it("swaps only the speeds along the line between them, and bounces across the wrap", function()
		local m = quiet(with({}, { ship = NO_DRAG }))
		-- on a slant across the right edge; player 2 is still
		place(m, 1, 1021, 100, 1, 0)
		place(m, 2, 5, 106, 0, 0)
		-- after their moves: player 1 at (1022, 100), player 2 at (5, 106): 7 across the wrap and 6 up
		run(m, 1, nil)
		local a, b = m.pilots[1].ship, m.pilots[2].ship
		local dx, dy = 7, 6
		local d = math.sqrt(dx * dx + dy * dy)
		local nx, ny = dx / d, dy / d
		local along = 1 * nx -- player 1's speed along the line; player 2 has none
		t.expect(a.vx).toBeNear(1 - along * nx, 1e-9)
		t.expect(a.vy).toBeNear(0 - along * ny, 1e-9)
		t.expect(b.vx).toBeNear(along * nx, 1e-9)
		t.expect(b.vy).toBeNear(along * ny, 1e-9)
		-- their momentum is kept
		t.expect(a.vx + b.vx).toBeNear(1, 1e-9)
		t.expect(a.vy + b.vy).toBeNear(0, 1e-9)
		t.expect(Field.distance(F, a.x, a.y, b.x, b.y)).toBeNear(24, 1e-9)
		local ex, ey = Field.wrap(F, 1022 - nx * (24 - d) / 2, 100 - ny * (24 - d) / 2)
		t.expect(a.x).toBeNear(ex, 1e-9)
		t.expect(a.y).toBeNear(ey, 1e-9)
	end)

	it("separates ships that touch while moving apart, and keeps their speeds", function()
		local m = quiet(with({}, { ship = NO_DRAG }))
		place(m, 1, 300, 384, -1, 0)
		place(m, 2, 320, 384, 1, 0)
		local events = run(m, 1, nil)
		t.expect(#only(events, "Bounce")).toBe(1)
		local a, b = m.pilots[1].ship, m.pilots[2].ship
		t.expect(Field.distance(F, a.x, a.y, b.x, b.y)).toBeNear(24, 1e-9)
		t.expect(a.vx).toBeNear(-1, 1e-9)
		t.expect(b.vx).toBeNear(1, 1e-9)
		-- two ships exactly touching (24 apart) do not bounce: touching is not overlapping
		local rest = quiet(with({}, { ship = NO_DRAG }))
		place(rest, 1, 300, 384, 0, 0)
		place(rest, 2, 324, 384, 0, 0)
		t.expect(#only(run(rest, 1, nil), "Bounce")).toBe(0)
		t.expect(rest.pilots[1].ship.x).toBe(300)
		-- two ships on the same point move apart along the field's x, player 1 to the left
		-- (whoever leads the tick)
		for _, lead in { 1, 2 } do
			local same = quiet(with({}, { ship = NO_DRAG }))
			if lead == 2 then
				run(same, 1, nil)
			end
			place(same, 1, 500, 500, 0, 0)
			place(same, 2, 500, 500, 0, 0)
			run(same, 1, nil)
			t.expect(same.pilots[1].ship.x).toBeNear(488, 1e-9)
			t.expect(same.pilots[2].ship.x).toBeNear(512, 1e-9)
			t.expect(same.pilots[1].ship.y).toBeNear(500, 1e-9)
		end
	end)

	it("never pushes a ship past the top speed", function()
		local m = quiet()
		-- player 1 mostly sideways at top speed, player 2 straight at it at top speed
		place(m, 1, 300, 384, 0.3, MAX - 0.01)
		place(m, 2, 318, 384, -MAX, 0)
		local events = run(m, 1, nil)
		t.expect(#only(events, "Bounce")).toBe(1)
		t.expect(speed(m.pilots[1].ship) <= MAX + 1e-9).toBe(true)
		t.expect(speed(m.pilots[2].ship) <= MAX + 1e-9).toBe(true)
		t.expect(speed(m.pilots[1].ship) > MAX - 0.1).toBe(true)
	end)

	it("bounces protected ships too, but not a ship in hyperspace or lost", function()
		local m = quiet()
		m.pilots[1].protect = 100
		m.pilots[2].protect = 100
		place(m, 1, 300, 384, 0, 0)
		place(m, 2, 310, 384, 0, 0)
		t.expect(#only(run(m, 1, nil), "Bounce")).toBe(1)
		for _, state in { "hyperspace", "dead" } do
			local w = quiet()
			place(w, 1, 300, 384, 0, 0)
			place(w, 2, 310, 384, 0, 0)
			w.pilots[2].shipState = state :: any
			w.pilots[2].timer = 1e9
			t.expect(#only(run(w, 1, nil), "Bounce")).toBe(0)
			t.expect(w.pilots[1].ship.x).toBe(300)
			t.expect(w.pilots[2].ship.x).toBe(310)
		end
	end)

	it("with bouncing off, lets the ships pass through each other unharmed", function()
		local m = quiet(with({ shipsBounce = false }, { ship = NO_DRAG }))
		place(m, 1, 300, 384, 2, 0)
		place(m, 2, 320, 384, -2, 0)
		local events = run(m, 10, nil)
		t.expect(#only(events, "Bounce")).toBe(0)
		t.expect(#only(events, "ShipDestroyed")).toBe(0)
		t.expect(m.pilots[1].ship.x).toBeNear(320, 1e-9)
		t.expect(m.pilots[2].ship.x).toBeNear(300, 1e-9)
		t.expect(m.pilots[1].ship.vx).toBeNear(2, 1e-9)
		-- two ships on one point: a saucer shot reaches both at once, and the tick's lead takes it
		for _, lead in { 1, 2 } do
			local w = quiet(with({ shipsBounce = false }))
			if lead == 2 then
				run(w, 1, nil)
			end
			place(w, 1, 500, 500, 0, 0)
			place(w, 2, 500, 500, 0, 0)
			-- it reaches 12 from the shared centre within this tick's move
			table.insert(w.saucerShots, { x = 500 - 15, y = 500, vx = 6, vy = 0, life = 60 })
			local lost = only(run(w, 1, nil), "ShipDestroyed")
			t.expect(#lost).toBe(1)
			t.expect(lost[1].player).toBe(lead)
		end
	end)
end)
