--!strict
-- f0221 AC4: a player whose last life is lost is out of play (their run is over) and the other plays on alone: the
-- out player's input does nothing, their ship stays gone, their shots leave the field at once, and their score,
-- the wave and their revives stay for the boards. The waves keep coming to the survivor at 1.5 x the rocks, clear
-- of the survivor only. With both out the match is over and nothing changes. A revive gives an out player 3 new
-- lives, keeping their score and their next extra life; their ship comes back at its home once that is clear,
-- protected; it restarts a finished match too. A player who leaves is out for good (no revive), their ship and
-- shots gone at once, and the other plays on; the last to leave ends the match.
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

local function quiet(seed: number?, config: TwoPlayer.Config?): TwoPlayer.Match
	local m = TwoPlayer.new(seed or 1, config)
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

local function kinds(events: { Classic.Event }): { string }
	local out = {}
	for _, e in events do
		table.insert(out, e.kind)
	end
	return out
end

-- the player rams a small rock (no pieces) where their ship is, on the next tick
local function ram(m: TwoPlayer.Match, slot: number)
	local s = m.pilots[slot].ship
	table.insert(m.rocks, { id = 900 + slot, size = "small", x = s.x + 15, y = s.y, vx = 0, vy = 0 })
end

local function copy(v: any): any
	if type(v) ~= "table" then
		return v
	end
	local out = {}
	for k, x in v do
		out[k] = copy(x)
	end
	return out
end

-- player slot on their last life rams a rock and is out
local function knockOut(m: TwoPlayer.Match, slot: number): { Classic.Event }
	m.pilots[slot].lives = 1
	m.pilots[slot].protect = 0
	ram(m, slot)
	return run(m, 1, nil)
end

return t.spec("f0221 survivor", function(it)
	it("ends one player's run at their last life, and the other plays on", function()
		local m = quiet()
		local events = knockOut(m, 1)
		t.expect(kinds(events)).toEqual({ "RockHit", "ShipDestroyed", "GameOver" })
		t.expect(only(events, "GameOver")[1].player).toBe(1)
		t.expect(m.pilots[1].phase).toBe("gameover")
		t.expect(m.pilots[1].lives).toBe(0)
		t.expect(m.phase).toBe("playing")
		-- the survivor flies, fires and scores; the out player's input does nothing, and their ship stays gone
		table.insert(m.rocks, { id = 950, size = "small", x = 768, y = 384 + 40, vx = 0, vy = 0 })
		local later =
			run(m, 600, pair({ turn = 1, thrust = true, fire = true, hyperspace = true }, { fire = true }))
		for _, e in later do
			t.expect(e.player ~= 1).toBe(true)
		end
		t.expect(#only(later, "Fire") > 0).toBe(true)
		t.expect(m.pilots[2].score).toBe(100)
		t.expect(m.pilots[1].shipState).toBe("dead")
		t.expect(m.pilots[1].ship.x).toBe(256)
		t.expect(m.pilots[1].ship.y).toBe(384)
		t.expect(m.pilots[1].ship.heading).toBe(64)
		t.expect(#m.pilots[1].shots).toBe(0)
		t.expect(m.phase).toBe("playing")
	end)

	it("takes an out player's shots off the field on the tick they go out", function()
		local m = quiet()
		run(m, 3, pair({ fire = true }, nil))
		t.expect(#m.pilots[1].shots).toBe(3)
		knockOut(m, 1)
		t.expect(#m.pilots[1].shots).toBe(0)
		-- out in hyperspace's explosion, at the start of a tick: the shots never fly that tick
		local h = quiet(1, nil)
		run(h, 2, pair({ fire = true }, nil))
		h.pilots[1].lives = 1
		h.pilots[1].shipState, h.pilots[1].timer = "hyperspace", 1
		h.config = table.clone(h.config :: any);
		(h.config :: any).hyperspaceOdds = 1
		table.insert(h.rocks, { id = 960, size = "small", x = 256, y = 425, vx = 0, vy = 0 })
		local events = run(h, 1, nil)
		t.expect(only(events, "GameOver")[1].player).toBe(1)
		t.expect(#only(events, "RockHit")).toBe(0)
		t.expect(#h.pilots[1].shots).toBe(0)
	end)

	it("keeps the out player's score and revives, and the wave, for the boards", function()
		local m = quiet()
		m.pilots[1].score = 4321
		m.pilots[1].revives = 2
		m.wave = 3
		knockOut(m, 1)
		run(m, 200, nil)
		t.expect(m.pilots[1].score).toBe(4321 + 100)
		t.expect(m.pilots[1].revives).toBe(2)
		t.expect(m.wave).toBe(3)
	end)

	it("keeps the waves coming to the survivor at 1.5 x the rocks, clear of the survivor only", function()
		local m = quiet()
		knockOut(m, 1)
		m.rocks = {}
		m.waveTimer = 0
		local starts = only(run(m, SOLO.waveTicks + 2, nil), "WaveStart")
		t.expect(#starts).toBe(1)
		t.expect(#m.rocks).toBe(9)
		for _, r in m.rocks do
			local s = m.pilots[2].ship
			t.expect(Field.distance(F, r.x, r.y, s.x, s.y) >= SOLO.spawnClear).toBe(true)
		end
		-- an out player's home by the bottom-left corner: the next wave's rocks may start there
		local cfg = table.clone(TwoPlayer.CONFIG :: any)
		cfg.homes = { { x = 40, y = 0 }, TwoPlayer.CONFIG.homes[2] }
		local near = 0
		for seed = 1, 40 do
			local w = quiet(seed, cfg)
			knockOut(w, 1)
			w.rocks = {}
			w.waveTimer = 1
			run(w, 1, nil)
			for _, r in w.rocks do
				if Field.distance(F, r.x, r.y, 40, 0) < SOLO.spawnClear then
					near += 1
				end
			end
		end
		t.expect(near > 0).toBe(true)
	end)

	it("ends the match when both are out, and then nothing changes", function()
		local m = quiet()
		m.pilots[1].lives, m.pilots[2].lives = 1, 1
		ram(m, 1)
		ram(m, 2)
		local events = run(m, 1, nil)
		t.expect(#only(events, "GameOver")).toBe(2)
		t.expect(events[#events].kind).toBe("MatchOver")
		t.expect(events[#events].player).toBe(nil)
		t.expect(m.phase).toBe("gameover")
		local before = copy(m)
		t.expect(#run(m, 300, pair({ fire = true, thrust = true }, { fire = true, turn = 1 }))).toBe(0)
		t.expect(copy(m)).toEqual(before)
		-- one at a time: the second loss ends it
		local w = quiet()
		knockOut(w, 2)
		t.expect(w.phase).toBe("playing")
		local last = knockOut(w, 1)
		t.expect(kinds(last)).toEqual({ "RockHit", "ShipDestroyed", "GameOver", "MatchOver" })
		t.expect(w.phase).toBe("gameover")
	end)

	it("revives an out player with 3 new lives, keeping their score and next extra life", function()
		local m = quiet()
		m.pilots[1].score = 9850
		m.wave = 4
		knockOut(m, 1)
		t.expect(m.pilots[1].score).toBe(9950)
		m.pilots[2].score, m.pilots[2].lives = 1234, 5
		local other = copy(m.pilots[2])
		t.expect(TwoPlayer.revive(m, 1)).toBe(true)
		t.expect(copy(m.pilots[2])).toEqual(other)
		local p = m.pilots[1]
		t.expect(p.phase).toBe("playing")
		t.expect(p.lives).toBe(3)
		t.expect(p.revives).toBe(1)
		t.expect(p.score).toBe(9950)
		t.expect(p.nextExtra).toBe(10000)
		t.expect(m.wave).toBe(4)
		-- the ship comes back at its home on the next tick, protected
		local back = only(run(m, 1, nil), "Respawn")
		t.expect(#back).toBe(1)
		t.expect(back[1].player).toBe(1)
		t.expect(back[1].lives).toBe(3)
		t.expect(p.shipState).toBe("alive")
		t.expect(p.ship.x).toBe(256)
		t.expect(p.ship.y).toBe(384)
		t.expect(p.protect).toBe(SOLO.protectTicks)
		t.expect(m.wave).toBe(4)
		-- the next 100 points reach the extra life the run was already counting toward
		table.insert(m.rocks, { id = 980, size = "small", x = 256, y = 384 + 40, vx = 0, vy = 0 })
		local extra = only(run(m, 5, pair({ fire = true }, nil)), "ExtraLife")
		t.expect(#extra).toBe(1)
		t.expect(extra[1].player).toBe(1)
		t.expect(p.lives).toBe(4)
		-- a second revive later counts again
		knockOut(m, 1)
		t.expect(TwoPlayer.revive(m, 1)).toBe(true)
		t.expect(m.pilots[1].revives).toBe(2)
	end)

	it("brings a revived ship back only once its home is clear", function()
		local m = quiet()
		knockOut(m, 1)
		TwoPlayer.revive(m, 1)
		table.insert(m.rocks, { id = 970, size = "large", x = 256 + 100, y = 384, vx = 0, vy = 0 })
		t.expect(#only(run(m, 30, nil), "Respawn")).toBe(0)
		m.rocks = {}
		t.expect(#only(run(m, 1, nil), "Respawn")).toBe(1)
	end)

	it("restarts a finished match with a revive, and the revived player plays on", function()
		local m = quiet()
		m.pilots[1].lives, m.pilots[2].lives = 1, 1
		ram(m, 1)
		ram(m, 2)
		run(m, 1, nil)
		t.expect(m.phase).toBe("gameover")
		t.expect(TwoPlayer.revive(m, 2)).toBe(true)
		t.expect(m.phase).toBe("playing")
		local events = run(m, 2, pair(nil, { fire = true }))
		t.expect(only(events, "Respawn")[1].player).toBe(2)
		t.expect(only(events, "Fire")[1].player).toBe(2)
		t.expect(m.pilots[1].phase).toBe("gameover")
	end)

	it("refuses a revive for a player still playing, or one who has left", function()
		local m = quiet()
		local before = copy(m)
		t.expect(TwoPlayer.revive(m, 1)).toBe(false)
		t.expect(TwoPlayer.revive(m, 3)).toBe(false)
		t.expect(copy(m)).toEqual(before)
		knockOut(m, 2)
		t.expect(TwoPlayer.leave(m, 2)).toBe(true)
		t.expect(TwoPlayer.revive(m, 2)).toBe(false)
		t.expect(m.pilots[2].phase).toBe("gameover")
		t.expect(m.pilots[2].revives).toBe(0)
	end)

	it("lets a player leave: out for good at once, ship and shots gone, and the other plays on", function()
		local m = quiet()
		run(m, 2, pair(nil, { fire = true, thrust = true }))
		t.expect(TwoPlayer.leave(m, 2)).toBe(true)
		local p = m.pilots[2]
		t.expect(p.left).toBe(true)
		t.expect(p.phase).toBe("gameover")
		t.expect(p.shipState).toBe("dead")
		t.expect(#p.shots).toBe(0)
		t.expect(m.phase).toBe("playing")
		local events = run(m, 200, pair({ fire = true }, { fire = true, thrust = true }))
		for _, e in events do
			t.expect(e.player ~= 2).toBe(true)
		end
		t.expect(#only(events, "Fire") > 0).toBe(true)
		t.expect(TwoPlayer.leave(m, 2)).toBe(false)
		t.expect(TwoPlayer.leave(m, 1)).toBe(true)
		t.expect(m.phase).toBe("gameover")
		t.expect(#run(m, 10, nil)).toBe(0)
	end)
end)
