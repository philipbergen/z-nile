--!strict
-- f0220 AC9: the run as a whole. 60 ticks a second; the same seed and inputs give the same run, tick for tick;
-- any seed works (a fraction is floored, a seed that is not a finite number counts as 0); the state and the
-- events stay JSON-safe as it plays; every event carries its kind's fields; and a run with nobody
-- steering well comes to its end.
local Classic = require("@logic/Classic")
local t = require("@tests/lib/t")

local CFG = Classic.CONFIG

-- a busy player: turning, thrusting, firing, and jumping now and then
local function busy(tick: number): Classic.Input
	return {
		turn = if tick % 90 < 30 then 1 elseif tick % 90 < 45 then -1 else 0,
		thrust = tick % 50 < 10,
		fire = tick % 7 == 0,
		hyperspace = tick % 700 == 0,
	}
end

local function plain(v: any, path: string, bad: { string })
	local kind = type(v)
	if kind == "number" then
		if v ~= v or math.abs(v) == math.huge then
			table.insert(bad, `{path}: {v}`)
		end
	elseif kind == "table" then
		local n, strings, ints = 0, 0, 0
		for k, x in v do
			n += 1
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

-- every kind of event, and the fields it always carries
local FIELDS: { [string]: { string } } = {
	Fire = {},
	Hyperspace = { "x", "y" },
	HyperspaceEnd = {},
	RockHit = { "id", "size", "points", "by" },
	SaucerHit = { "saucer", "points", "by" },
	ExtraLife = { "lives" },
	SaucerAppear = { "saucer" },
	SaucerLeave = { "saucer" },
	SaucerFire = { "saucer" },
	ShipDestroyed = { "cause", "lives", "x", "y" },
	GameOver = {},
	Respawn = { "lives" },
	WaveClear = { "wave" },
	WaveStart = { "wave" },
}

return t.spec("f0220 run", function(it)
	it("runs at 60 ticks a second", function()
		t.expect(Classic.TICK_RATE).toBe(60)
		t.expect(CFG.tickRate).toBe(60)
	end)

	it("replays the same seed and inputs to the same run, tick for tick", function()
		local a, b = Classic.new(42), Classic.new(42)
		t.expect(a).toEqual(b)
		for tick = 1, 3000 do
			local ea = Classic.step(a, busy(tick))
			local eb = Classic.step(b, busy(tick))
			t.expect(ea).toEqual(eb)
			if tick % 100 == 0 then
				t.expect(a).toEqual(b)
			end
		end
		t.expect(a).toEqual(b)
	end)

	it("plays a different run from a different seed", function()
		local a, b = Classic.new(1), Classic.new(2)
		t.expect(
			a.rocks[1].x == b.rocks[1].x and a.rocks[1].y == b.rocks[1].y and a.rocks[1].vx == b.rocks[1].vx
		)
			.toBe(false)
	end)

	it("floors a seed with a fraction, and counts a seed that is not a finite number as 0", function()
		t.expect(Classic.new(7.9)).toEqual(Classic.new(7))
		t.expect(Classic.new(-3.5)).toEqual(Classic.new(-4))
		t.expect(Classic.new(0 / 0)).toEqual(Classic.new(0))
		t.expect(Classic.new(math.huge)).toEqual(Classic.new(0))
		t.expect(Classic.new(-math.huge)).toEqual(Classic.new(0))
		t.expect(Classic.new(1e15)).toEqual(Classic.new(1e15))
		t.expect(Classic.new(5)).toEqual(Classic.new(5 + 2147483646))
	end)

	it("keeps its state and its events JSON-safe as it plays", function()
		local g = Classic.new(9)
		local seen = {}
		for tick = 1, 4000 do
			local events = Classic.step(g, busy(tick))
			local bad = {}
			plain(g, "run", bad)
			plain(events, "events", bad)
			t.expect(table.concat(bad, "\n")).toBe("")
			for _, e in events do
				seen[e.kind] = true
			end
			if g.phase == "gameover" then
				g = Classic.new(tick)
			end
		end
		-- it saw the field busy: shots, hits, saucers, losses
		t.expect(seen.Fire and seen.RockHit and seen.SaucerAppear and seen.ShipDestroyed and seen.Hyperspace)
			.toBe(true)
	end)

	it("gives every event its kind's fields", function()
		local seen = {}
		for seed = 1, 12 do
			local g = Classic.new(seed)
			for tick = 1, 3000 do
				for _, e in Classic.step(g, busy(tick + seed)) do
					local want = FIELDS[e.kind]
					t.expect(want ~= nil).toBe(true)
					local missing = {}
					for _, k in want do
						if (e :: any)[k] == nil then
							table.insert(missing, `{e.kind}.{k}`)
						end
					end
					t.expect(table.concat(missing, " ")).toBe("")
					seen[e.kind] = true
				end
				if g.phase == "gameover" then
					break
				end
			end
		end
		local n = 0
		for _ in seen do
			n += 1
		end
		t.expect(n >= 10).toBe(true)
	end)

	it("comes to its end with nobody steering well, and the end is the last life lost", function()
		local g = Classic.new(3)
		local ended = false
		for tick = 1, 60 * 60 * 10 do
			local events = Classic.step(g, busy(tick))
			for _, e in events do
				if e.kind == "GameOver" then
					ended = true
				end
			end
			if ended then
				break
			end
		end
		t.expect(ended).toBe(true)
		t.expect(g.phase).toBe("gameover")
		t.expect(g.lives).toBe(0)
	end)
end)
