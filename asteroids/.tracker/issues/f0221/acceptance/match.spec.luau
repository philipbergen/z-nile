--!strict
-- f0221 AC5: the match as a whole. It runs at the solo 60 ticks a second; the same seed and inputs give the same
-- match, tick for tick, and another seed another; each player's input is sanitized as the solo input is (junk, a
-- missing inputs table or a missing entry is no input); the state and the events stay JSON-safe as it plays; every
-- event of a player's own carries their slot, and the field's events none; and a match with nobody steering well
-- comes to its end, both players out.
local Classic = require("@logic/Classic")
local TwoPlayer = require("@logic/TwoPlayer")
local t = require("@tests/lib/t")

-- the match's step, taking any inputs (the cases hand it junk and mixed lists too)
local step = TwoPlayer.step :: (TwoPlayer.Match, any) -> { Classic.Event }

-- both players' inputs for one tick
local function pair(a: Classic.Input?, b: Classic.Input?): { Classic.Input? }
	return { a, b }
end

-- each player busy in their own way
local function busy(tick: number, slot: number): Classic.Input
	local k = tick + slot * 37
	return {
		turn = if k % 90 < 30 then 1 elseif k % 90 < 45 then -1 else 0,
		thrust = k % 50 < 10,
		fire = k % (5 + slot) == 0,
		hyperspace = k % 700 == 0,
	}
end

local function inputs(tick: number): any
	return { busy(tick, 1), busy(tick, 2) }
end

local function plain(v: any, path: string, bad: { string })
	local kind = type(v)
	if kind == "number" then
		if v ~= v or math.abs(v) == math.huge then
			table.insert(bad, `{path}: {v}`)
		end
	elseif kind == "table" then
		local strings, ints = 0, 0
		for k, x in v do
			if type(k) == "string" then
				strings += 1
			elseif type(k) == "number" and k == math.floor(k) and k >= 1 then
				ints += 1
			else
				table.insert(bad, `{path}: key {tostring(k)}`)
			end
			plain(x, `{path}.{tostring(k)}`, bad)
		end
		if strings > 0 and ints > 0 then
			table.insert(bad, `{path}: mixed keys`)
		elseif ints > 0 and ints ~= #v then
			table.insert(bad, `{path}: sparse array`)
		end
	elseif kind ~= "string" and kind ~= "boolean" then
		table.insert(bad, `{path}: {kind}`)
	end
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

local OWN = {
	Fire = true,
	Hyperspace = true,
	HyperspaceEnd = true,
	RockHit = true,
	SaucerHit = true,
	ExtraLife = true,
	ShipDestroyed = true,
	GameOver = true,
	Respawn = true,
}
local FIELD = {
	SaucerAppear = true,
	SaucerLeave = true,
	SaucerFire = true,
	WaveClear = true,
	WaveStart = true,
	Bounce = true,
	MatchOver = true,
}

-- play a busy match, reviving each player once, for n ticks: every event and the state after each tick
local function play(seed: number, n: number, config: TwoPlayer.Config?): ({ Classic.Event }, TwoPlayer.Match)
	local m = TwoPlayer.new(seed, config)
	local all = {}
	local revived = { false, false }
	for tick = 1, n do
		for _, e in step(m, inputs(tick)) do
			table.insert(all, e)
		end
		for slot = 1, 2 do
			if m.pilots[slot].phase == "gameover" and not revived[slot] then
				revived[slot] = TwoPlayer.revive(m, slot)
			end
		end
	end
	return all, m
end

return t.spec("f0221 match", function(it)
	it("runs at the solo 60 ticks a second", function()
		t.expect(TwoPlayer.CONFIG.classic.tickRate).toBe(60)
		t.expect(TwoPlayer.new(1).config.tickRate).toBe(Classic.TICK_RATE)
	end)

	it("replays the same seed and inputs to the same match, tick for tick", function()
		local a, b = TwoPlayer.new(7), TwoPlayer.new(7)
		for tick = 1, 3000 do
			local ea = step(a, inputs(tick))
			local eb = step(b, inputs(tick))
			t.expect(ea).toEqual(eb)
			if tick % 250 == 0 then
				t.expect(copy(a)).toEqual(copy(b))
			end
		end
		t.expect(copy(a)).toEqual(copy(b))
	end)

	it("plays a different match from a different seed", function()
		local a, b = TwoPlayer.new(1), TwoPlayer.new(2)
		t.expect(copy(a.rocks) ~= nil).toBe(true)
		local same = true
		for i, r in a.rocks do
			local o = b.rocks[i]
			same = same and o ~= nil and o.x == r.x and o.y == r.y and o.vx == r.vx
		end
		t.expect(same).toBe(false)
		-- the seed is read as the solo one is: a fraction floored, not a finite number 0
		t.expect(copy(TwoPlayer.new(3.75))).toEqual(copy(TwoPlayer.new(3)))
		t.expect(copy(TwoPlayer.new(0 / 0))).toEqual(copy(TwoPlayer.new(0)))
	end)

	it("reads each player's input as the solo input: exactly 1 or -1, exactly true", function()
		local m = TwoPlayer.new(1)
		m.rocks, m.waveTimer, m.saucerElapsed = {}, 1e9, -1e9
		local before = copy(m)
		t.expect(#step(m, nil)).toBe(0)
		local junks: { any } = {}
		local five: any, word: any = 5, "x"
		table.insert(junks, word)
		table.insert(junks, five)
		table.insert(junks, {})
		table.insert(junks, { word, five })
		local bad: any = { turn = 2, thrust = 1, fire = "yes", hyperspace = 1 }
		table.insert(junks, { bad })
		for _, junk in junks do
			t.expect(#step(m, junk)).toBe(0)
		end
		for slot = 1, 2 do
			t.expect(copy(m.pilots[slot].ship)).toEqual(before.pilots[slot].ship)
			t.expect(#m.pilots[slot].shots).toBe(0)
		end
		-- a missing first entry still reads the second
		step(m, pair(nil, { turn = 1 }))
		t.expect(m.pilots[1].ship.heading).toBe(64)
		t.expect(m.pilots[2].ship.heading).toBe(67)
	end)

	it("keeps its state and its events JSON-safe as it plays", function()
		local events, m = play(3, 4000)
		local bad = {}
		plain(m, "match", bad)
		plain(events, "events", bad)
		t.expect(table.concat(bad, "; ")).toBe("")
		t.expect(#events > 100).toBe(true)
	end)

	it("tags every event of a player's own with their slot, and the field's with none", function()
		local cfg = table.clone(TwoPlayer.CONFIG :: any)
		cfg.friendlyFire = true
		local seen: { [string]: boolean } = {}
		for seed = 1, 3 do
			for _, config in { nil, cfg } :: { any } do
				local events = play(seed, 5000, config)
				for _, e in events do
					seen[e.kind] = true
					if OWN[e.kind] then
						t.expect(e.player == 1 or e.player == 2).toBe(true)
					elseif FIELD[e.kind] then
						t.expect(e.player).toBe(nil)
					else
						error(`expected only the known kinds, got {e.kind}`)
					end
					if e.kind == "ShipDestroyed" and e.cause == "shot" then
						t.expect(e.shooter == 3 - (e.player :: number)).toBe(true)
					else
						t.expect(e.shooter).toBe(nil)
					end
				end
			end
		end
		for _, kind in
			{ "Fire", "Hyperspace", "RockHit", "ShipDestroyed", "Respawn", "WaveClear", "WaveStart" }
		do
			t.expect(seen[kind]).toBe(true)
		end
	end)

	it("comes to its end with nobody steering well, both players out", function()
		local m = TwoPlayer.new(11)
		local ended = false
		for tick = 1, 60 * 60 * 20 do
			for _, e in step(m, inputs(tick)) do
				if e.kind == "MatchOver" then
					ended = true
				end
			end
			if ended then
				break
			end
		end
		t.expect(ended).toBe(true)
		t.expect(m.phase).toBe("gameover")
		t.expect(m.pilots[1].phase).toBe("gameover")
		t.expect(m.pilots[2].phase).toBe("gameover")
	end)
end)
