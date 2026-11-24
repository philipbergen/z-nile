--!strict
-- f0221 AC2: each player has their own ship, shots, score, lives and extra lives, so it is a race for the most
-- points on shared rocks. Player 1 steers with inputs[1] and player 2 with inputs[2]; each has 4 shots; the points
-- of a rock or a saucer go to the player whose shot or ship broke it, and a loss costs only that player a life;
-- each lost ship comes back at its own home. The saucer fires at the nearer ship on the field and aims from that
-- player's score; its shot destroys the first exposed ship it reaches. The tick's lead (player 1 on the first tick,
-- player 2 on the next, and so on) goes first and wins every tie.
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

local SOLO = Classic.CONFIG
local F = SOLO.field

local function quiet(seed: number?): TwoPlayer.Match
	local m = TwoPlayer.new(seed or 1)
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

local function rock(id: number, size: "large" | "medium" | "small", x: number, y: number): Classic.Rock
	return { id = id, size = size, x = x, y = y, vx = 0, vy = 0 }
end

local function still(kind: "large" | "small", x: number, y: number): any
	return { kind = kind, x = x, y = y, vx = 0, vy = 0, travelled = 0, fireElapsed = 1e9, turnElapsed = -1e9 }
end

-- the heading of the saucer's newest shot
local function shotHeading(m: TwoPlayer.Match): number
	local s = m.saucerShots[#m.saucerShots]
	return Field.heading(s.vx, s.vy)
end

return t.spec("f0221 scores", function(it)
	it("steers player 1 by inputs[1] and player 2 by inputs[2]", function()
		local m = quiet()
		step(m, pair({ turn = 1 }, { thrust = true }))
		local p1, p2 = m.pilots[1].ship, m.pilots[2].ship
		t.expect(p1.heading).toBe(67)
		t.expect(p1.vx).toBe(0)
		t.expect(p1.vy).toBe(0)
		t.expect(p2.heading).toBe(64)
		t.expect(p2.vy > 0).toBe(true)
		step(m, pair(nil, { turn = -1 }))
		t.expect(m.pilots[1].ship.heading).toBe(67)
		t.expect(m.pilots[2].ship.heading).toBe(61)
	end)

	it("gives each player their own 4 shots, from their own nose", function()
		local m = quiet()
		local fires = only(run(m, 6, pair({ fire = true }, { fire = true })), "Fire")
		t.expect(#m.pilots[1].shots).toBe(4)
		t.expect(#m.pilots[2].shots).toBe(4)
		t.expect(#fires).toBe(8)
		local by = { 0, 0 }
		for _, e in fires do
			local k = e.player
			t.expect(k == 1 or k == 2).toBe(true)
			by[k :: number] += 1
		end
		t.expect(by).toEqual({ 4, 4 })
		local m2 = quiet()
		step(m2, pair(nil, { fire = true }))
		t.expect(#m2.pilots[1].shots).toBe(0)
		local shot = m2.pilots[2].shots[1]
		t.expect(shot.x).toBeNear(768, 1e-9)
		t.expect(shot.y).toBeNear(384 + 12 + 8, 1e-9)
	end)

	it("scores a rock for the player whose shot breaks it", function()
		local m = quiet()
		table.insert(m.rocks, rock(700, "small", 768, 384 + 40))
		local hits = only(run(m, 5, pair(nil, { fire = true })), "RockHit")
		t.expect(#hits).toBe(1)
		t.expect(hits[1].player).toBe(2)
		t.expect(hits[1].by).toBe("shot")
		t.expect(m.pilots[2].score).toBe(100)
		t.expect(m.pilots[1].score).toBe(0)
	end)

	it("scores a ram for the player who rams, and costs only that player a life", function()
		local m = quiet()
		table.insert(m.rocks, rock(701, "small", 256 + 15, 384))
		local events = run(m, 1, nil)
		local hit = only(events, "RockHit")
		local lost = only(events, "ShipDestroyed")
		t.expect(#hit).toBe(1)
		t.expect(hit[1].player).toBe(1)
		t.expect(hit[1].by).toBe("ship")
		t.expect(#lost).toBe(1)
		t.expect(lost[1].player).toBe(1)
		t.expect(lost[1].cause).toBe("rock")
		t.expect(m.pilots[1].score).toBe(100)
		t.expect(m.pilots[1].lives).toBe(2)
		t.expect(m.pilots[2].lives).toBe(3)
		t.expect(m.pilots[2].score).toBe(0)
		t.expect(m.pilots[2].shipState).toBe("alive")
	end)

	it("gives each player their own extra life at every 10,000", function()
		local m = quiet()
		m.pilots[2].score = 9950
		table.insert(m.rocks, rock(702, "small", 768, 384 + 40))
		local extra = only(run(m, 5, pair(nil, { fire = true })), "ExtraLife")
		t.expect(#extra).toBe(1)
		t.expect(extra[1].player).toBe(2)
		t.expect(extra[1].lives).toBe(4)
		t.expect(m.pilots[2].lives).toBe(4)
		t.expect(m.pilots[1].lives).toBe(3)
		t.expect(m.pilots[2].nextExtra).toBe(20000)
		t.expect(m.pilots[1].nextExtra).toBe(10000)
	end)

	it("brings each lost ship back at its own home, protected", function()
		local m = quiet()
		m.pilots[2].ship.x, m.pilots[2].ship.y = 900, 700
		table.insert(m.rocks, rock(703, "small", 900 + 15, 700))
		run(m, 1, nil)
		t.expect(m.pilots[2].shipState).toBe("dead")
		t.expect(m.pilots[2].ship.x).toBe(768)
		t.expect(m.pilots[2].ship.y).toBe(384)
		local back = only(run(m, SOLO.respawnTicks, nil), "Respawn")
		t.expect(#back).toBe(1)
		t.expect(back[1].player).toBe(2)
		t.expect(m.pilots[2].shipState).toBe("alive")
		t.expect(m.pilots[2].ship.x).toBe(768)
		t.expect(m.pilots[2].ship.y).toBe(384)
		t.expect(m.pilots[2].protect).toBe(SOLO.protectTicks)
		-- its home must be clear of rocks and the saucer, as the solo centre must
		local w = quiet()
		w.pilots[1].shipState, w.pilots[1].timer = "dead", 1
		w.pilots[1].ship.x, w.pilots[1].ship.y = 256, 384
		table.insert(w.rocks, rock(704, "large", 256 + 40 + 79, 384))
		t.expect(#only(run(w, 5, nil), "Respawn")).toBe(0)
		w.rocks = {}
		t.expect(#only(run(w, 1, nil), "Respawn")).toBe(1)
		-- the other ship parked on the home does not hold the respawn: the two then bounce apart
		local camp = quiet()
		camp.pilots[1].shipState, camp.pilots[1].timer = "dead", 1
		camp.pilots[1].ship.x, camp.pilots[1].ship.y = 256, 384
		camp.pilots[2].ship.x, camp.pilots[2].ship.y = 256 + 5, 384
		local events = run(camp, 1, nil)
		t.expect(#only(events, "Respawn")).toBe(1)
		t.expect(#only(events, "Bounce")).toBe(1)
		t.expect(camp.pilots[1].shipState).toBe("alive")
	end)

	it("fires the saucer at the nearer ship on the field, aimed from that player's score", function()
		for seed = 1, 20 do
			for target = 1, 2 do
				local m = quiet(seed)
				local p = m.pilots[target]
				m.pilots[1].score = if target == 1 then 40000 else 0
				m.pilots[2].score = if target == 2 then 40000 else 0
				m.saucer = still("small", p.ship.x, p.ship.y + 150)
				local fired = only(run(m, 1, nil), "SaucerFire")
				t.expect(#fired).toBe(1)
				t.expect(fired[1].player).toBe(nil)
				t.expect(shotHeading(m)).toBe(Field.heading(0, -150))
			end
		end
		-- the nearer the short way across the wrap, where a raw difference names the other ship
		for _, c in { { 100, 700, 1000, 1 }, { 324, 924, 24, 2 } } do
			local m = quiet()
			m.pilots[1].ship.x, m.pilots[2].ship.x = c[1], c[2]
			m.pilots[1].score, m.pilots[2].score = 40000, 40000
			m.saucer = still("small", c[3], 384)
			run(m, 1, nil)
			local p = m.pilots[c[4]].ship
			t.expect(shotHeading(m)).toBe(Field.heading(Field.delta(F, c[3], 384, p.x, p.y)))
		end
		-- aimed from the target's own score, not the other player's: a target with none is aimed at loosely
		local missed = { 0, 0 }
		for seed = 1, 20 do
			for target = 1, 2 do
				local m = quiet(seed)
				local p = m.pilots[target]
				m.pilots[target].score = 0
				m.pilots[3 - target].score = 40000
				m.saucer = still("small", p.ship.x, p.ship.y + 150)
				run(m, 1, nil)
				if shotHeading(m) ~= Field.heading(0, -150) then
					missed[target] += 1
				end
			end
		end
		t.expect(missed[1] > 0).toBe(true)
		t.expect(missed[2] > 0).toBe(true)
	end)

	it("holds the saucer's fire while neither ship is on the field, and fires at the one that is", function()
		local m = quiet()
		m.pilots[1].shipState, m.pilots[1].timer = "dead", 1e9
		m.pilots[2].score = 40000
		m.saucer = still("small", 256, 384 + 100)
		local fired = only(run(m, 1, nil), "SaucerFire")
		t.expect(#fired).toBe(1)
		local dx, dy = Field.delta(F, 256, 484, 768, 384)
		t.expect(shotHeading(m)).toBe(Field.heading(dx, dy))
		local n = quiet()
		n.pilots[1].shipState, n.pilots[1].timer = "dead", 1e9
		n.pilots[2].shipState, n.pilots[2].timer = "hyperspace", 1e9
		n.saucer = still("small", 256, 484)
		t.expect(#only(run(n, 60, nil), "SaucerFire")).toBe(0)
		t.expect(#n.saucerShots).toBe(0)
	end)

	it("lets a saucer shot destroy the first exposed ship it reaches, and pass a protected one", function()
		local m = quiet()
		local p1, p2 = m.pilots[1], m.pilots[2]
		p2.ship.x, p2.ship.y = 256 + 30, 384
		p1.protect = 1e9
		-- a shot that reaches player 1 (protected) on this tick and player 2 (exposed) on the sixth
		table.insert(m.saucerShots, { x = 256 - 14, y = 384, vx = 6, vy = 0, life = 60 })
		local lost = only(run(m, 6, nil), "ShipDestroyed")
		t.expect(#lost).toBe(1)
		t.expect(lost[1].player).toBe(2)
		t.expect(lost[1].cause).toBe("saucershot")
		t.expect(p1.lives).toBe(3)
		t.expect(p2.lives).toBe(2)
		-- both exposed and both within its move: the one it reaches first along the move takes it, though
		-- player 1 leads this tick
		local w = quiet()
		w.pilots[1].ship.x, w.pilots[1].ship.y = 250, 373
		w.pilots[2].ship.x, w.pilots[2].ship.y = 262, 395
		table.insert(w.saucerShots, { x = 290, y = 384, vx = -40, vy = 0, life = 60 })
		local first = only(run(w, 1, nil), "ShipDestroyed")
		t.expect(#first).toBe(1)
		t.expect(first[1].player).toBe(2)
		t.expect(w.pilots[1].lives).toBe(3)
	end)

	it("leads with player 1 on the first tick and player 2 on the next, and the lead wins a tie", function()
		for _, lead in { 1, 2 } do
			local m = quiet()
			if lead == 2 then
				run(m, 1, nil)
			end
			-- one small rock both players' shots reach on the same tick, from either side
			table.insert(m.rocks, rock(705, "small", 512, 600))
			m.pilots[1].shots = { { x = 512 - 16, y = 600, vx = 8, vy = 0, life = 60 } }
			m.pilots[2].shots = { { x = 512 + 16, y = 600, vx = -8, vy = 0, life = 60 } }
			local hits = only(run(m, 1, nil), "RockHit")
			t.expect(#hits).toBe(1)
			t.expect(hits[1].player).toBe(lead)
			t.expect(m.pilots[lead].score).toBe(100)
			t.expect(m.pilots[3 - lead].score).toBe(0)
		end
		-- the saucer's aim between two ships equally near goes to the lead too
		for _, lead in { 1, 2 } do
			local m = quiet()
			if lead == 2 then
				run(m, 1, nil)
			end
			m.pilots[1].score, m.pilots[2].score = 40000, 40000
			m.saucer = still("small", 512, 384)
			run(m, 1, nil)
			local dx = if lead == 1 then -256 else 256
			t.expect(shotHeading(m)).toBe(Field.heading(dx, 0))
		end
		-- two ships ramming one small rock on one tick: the lead's collision comes first (its points, its life)
		for _, lead in { 1, 2 } do
			local m = quiet()
			if lead == 2 then
				run(m, 1, nil)
			end
			m.pilots[1].ship.x, m.pilots[1].ship.y = 500, 500
			m.pilots[2].ship.x, m.pilots[2].ship.y = 530, 500
			m.rocks = { rock(706, "small", 515, 500) }
			local events = run(m, 1, nil)
			local lost = only(events, "ShipDestroyed")
			t.expect(#lost).toBe(1)
			t.expect(lost[1].player).toBe(lead)
			t.expect(only(events, "RockHit")[1].player).toBe(lead)
			t.expect(m.pilots[lead].score).toBe(100)
			t.expect(m.pilots[3 - lead].lives).toBe(3)
		end
		-- two jumps on one tick: the lead draws first, so its spot is the one it gets jumping alone
		local jump = { hyperspace = true }
		for _, lead in { 1, 2 } do
			local both, alone = quiet(3), quiet(3)
			if lead == 2 then
				run(both, 1, nil)
				run(alone, 1, nil)
			end
			run(both, 1, pair(jump, jump))
			run(alone, 1, if lead == 1 then pair(jump, nil) else pair(nil, jump))
			t.expect(both.pilots[lead].shipState).toBe("hyperspace")
			t.expect(both.pilots[lead].ship.x).toBe(alone.pilots[lead].ship.x)
			t.expect(both.pilots[lead].ship.y).toBe(alone.pilots[lead].ship.y)
		end
		-- two returns from hyperspace on one tick: the lead's roll is the first draw
		for _, lead in { 1, 2 } do
			for seed = 1, 60 do
				local both, alone = quiet(seed), quiet(seed)
				if lead == 2 then
					run(both, 1, nil)
					run(alone, 1, nil)
				end
				for _, m in { both, alone } do
					m.pilots[lead].shipState, m.pilots[lead].timer = "hyperspace", 1
				end
				both.pilots[3 - lead].shipState, both.pilots[3 - lead].timer = "hyperspace", 1
				run(both, 1, nil)
				run(alone, 1, nil)
				t.expect(both.pilots[lead].shipState).toBe(alone.pilots[lead].shipState)
			end
		end
	end)
end)
