--!strict
-- f0216 AC7: the game as a whole. A game is plain data stepped once per tick at 60 ticks a second: the same seed
-- and the same inputs give the same game, tick for tick, and a different seed a different one (the random
-- columns); its state and events are JSON-safe, so the server can replicate them; time counts in ticks only.
local Classic = require("@logic/Classic")
local Formation = require("@logic/Formation")
local t = require("@tests/lib/t")

local function script(tick: number): Classic.Input
	-- a busy player: sweeps the field and fires whenever it can
	local phase = (tick // 150) % 2
	return { move = if phase == 0 then 1 else -1, fire = tick % 7 == 0 }
end

local function encode(v: any, out: { string })
	local ty = type(v)
	if ty == "table" then
		local keys = {}
		for k in v do
			table.insert(keys, k)
		end
		table.sort(keys, function(a, b)
			return tostring(a) < tostring(b)
		end)
		table.insert(out, "{")
		for _, k in keys do
			table.insert(out, tostring(k) .. "=")
			encode(v[k], out)
			table.insert(out, ",")
		end
		table.insert(out, "}")
	else
		table.insert(out, tostring(v))
	end
end

local function digest(v: any): string
	local out = {}
	encode(v, out)
	return table.concat(out)
end

local function play(seed: number, ticks: number): (Classic.Game, string)
	local g = Classic.new(seed)
	local trace = {}
	for tick = 1, ticks do
		local events = Classic.step(g, script(tick))
		for _, e in events do
			table.insert(trace, `{tick}:{e.kind}:{e.col or ""}`)
		end
		if g.phase == "gameover" then
			Classic.revive(g)
		end
	end
	return g, table.concat(trace, " ")
end

-- plain data only: numbers that are finite, strings, booleans and tables with string keys or a dense array
local function jsonSafe(v: any, path: string)
	local ty = type(v)
	if ty == "number" then
		t.expect(v == v and math.abs(v) ~= math.huge).toBe(true)
	elseif ty == "table" then
		local n = #v
		for k, x in v do
			if type(k) == "number" then
				t.expect(k >= 1 and k <= n and k == math.floor(k)).toBe(true)
			else
				t.expect(type(k)).toBe("string")
			end
			jsonSafe(x, path .. "." .. tostring(k))
		end
	else
		t.expect(ty == "string" or ty == "boolean").toBe(true)
	end
end

return t.spec("f0216 game", function(it)
	it("runs at 60 ticks a second", function()
		t.expect(Classic.TICK_RATE).toBe(60)
		t.expect(Classic.CONFIG.tickRate).toBe(60)
	end)

	it("replays the same seed and inputs to the same game, tick for tick", function()
		local a, ta = play(7, 6000)
		local b, tb = play(7, 6000)
		t.expect(ta).toBe(tb)
		t.expect(digest(a)).toBe(digest(b))
		t.expect(#ta > 0).toBe(true)
	end)

	it("plays a different game from a different seed", function()
		local _, ta = play(7, 6000)
		local _, tb = play(8, 6000)
		t.expect(ta ~= tb).toBe(true)
	end)

	it("treats any seed as a whole number seed, and a seed that is not one as 0", function()
		local _, a = play(0, 2000)
		local _, b = play(0 / 1, 2000)
		t.expect(a).toBe(b)
		local _, c = play(math.huge - math.huge, 2000)
		t.expect(c).toBe(a)
		local _, d = play(math.huge, 2000)
		t.expect(d).toBe(a)
		local _, e = play(5.7, 2000)
		local _, f = play(5, 2000)
		t.expect(e).toBe(f)
	end)

	it("keeps its state and its events JSON-safe as it plays", function()
		local g = Classic.new(3)
		for tick = 1, 3000 do
			for _, e in Classic.step(g, script(tick)) do
				jsonSafe(e, "event")
				t.expect(type(e.kind)).toBe("string")
			end
			jsonSafe(g, "game")
			if g.phase == "gameover" then
				Classic.revive(g)
			end
		end
	end)

	it("tells the beat the march's new wait on every step and advance", function()
		local g = Classic.new(1)
		g.reloadElapsed = -100000
		Formation.kill(g.formation, 3, 3)
		local seen = { March = 0, Advance = 0 }
		for _ = 1, 20000 do
			for _, e in Classic.step(g, nil) do
				if e.kind == "March" or e.kind == "Advance" then
					t.expect(e.interval).toBe(Formation.interval(g.formation))
					t.expect(e.interval).toBe(54)
					seen[e.kind] += 1
				end
			end
			g.reloadElapsed = -100000
			if seen.Advance > 0 then
				break
			end
		end
		t.expect(seen.March > 0).toBe(true)
		t.expect(seen.Advance).toBe(1)
	end)

	it("plays a whole game to its end with no input, and the end is an invasion or the last life", function()
		local g = Classic.new(1)
		local over = nil
		for _ = 1, 200000 do
			for _, e in Classic.step(g, nil) do
				if e.kind == "GameOver" then
					over = e.reason
				end
			end
			if over then
				break
			end
		end
		t.expect(over == "lives" or over == "invasion").toBe(true)
		t.expect(g.phase).toBe("gameover")
		t.expect(g.score).toBe(0)
	end)
end)
