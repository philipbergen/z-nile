--!strict
-- f0217 AC6: the match as a whole. A match is plain data stepped once per tick (Classic's 60 a second) with both
-- players' inputs, each read alone and sanitized as in solo; the same seed and inputs give the same match, tick
-- for tick; its state and events are JSON-safe for the server to replicate; and it plays to its end.
local TwoPlayer = require("@logic/TwoPlayer")
local t = require("@tests/lib/t")

local function script(tick: number, p: number): { move: number, fire: boolean }
	local phase = ((tick + p * 70) // 150) % 2
	return { move = if phase == 0 then 1 else -1, fire = (tick + p) % 7 == 0 }
end

local function encode(v: any, out: { string })
	if type(v) == "table" then
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

local function play(seed: number, ticks: number): (TwoPlayer.Match, string)
	local g = TwoPlayer.new(seed)
	local trace = {}
	for tick = 1, ticks do
		for _, e in TwoPlayer.step(g, { script(tick, 1), script(tick, 2) }) do
			table.insert(trace, `{tick}:{e.kind}:{e.player or ""}:{e.col or ""}`)
		end
		for p = 1, 2 do
			if TwoPlayer.phaseOf(g, p) == "gameover" then
				TwoPlayer.revive(g, p)
			end
		end
	end
	return g, table.concat(trace, " ")
end

-- the first value that is not plain data: finite numbers, strings, booleans, and tables with string keys or a
-- dense array
local function unsafe(v: any, path: string): string?
	local ty = type(v)
	if ty == "number" then
		return if v == v and math.abs(v) ~= math.huge then nil else path
	elseif ty == "table" then
		local n = #v
		for k, x in v do
			if type(k) == "number" then
				if not (k >= 1 and k <= n and k == math.floor(k)) then
					return path .. "[" .. tostring(k) .. "]"
				end
			elseif type(k) ~= "string" then
				return path
			end
			local bad = unsafe(x, path .. "." .. tostring(k))
			if bad then
				return bad
			end
		end
		return nil
	end
	return if ty == "string" or ty == "boolean" then nil else path
end

-- values of any shape, handed to step as its inputs
local function junk(v: any): any
	return v
end

local function two(a: any, b: any): any
	return { a, b }
end

return t.spec("f0217 match", function(it)
	it("replays the same seed and inputs to the same match, tick for tick", function()
		local a, ta = play(7, 2500)
		local b, tb = play(7, 2500)
		t.expect(ta).toBe(tb)
		t.expect(digest(a)).toBe(digest(b))
		t.expect(#ta > 0).toBe(true)
	end)

	it("plays a different match from a different seed", function()
		local _, ta = play(7, 2500)
		local _, tb = play(8, 2500)
		t.expect(ta ~= tb).toBe(true)
	end)

	it("keeps its state and its events JSON-safe as it plays", function()
		local g = TwoPlayer.new(3)
		for tick = 1, 2500 do
			for _, e in TwoPlayer.step(g, { script(tick, 1), script(tick, 2) }) do
				t.expect(unsafe(e, "event")).toBe(nil)
				t.expect(type(e.kind)).toBe("string")
			end
			t.expect(unsafe(g, "match")).toBe(nil)
			for p = 1, 2 do
				if TwoPlayer.phaseOf(g, p) == "gameover" then
					TwoPlayer.revive(g, p)
				end
			end
		end
	end)

	it("reads each player's input alone, and only an exact move and fire", function()
		local g = TwoPlayer.new(1)
		local c1, c2 = g.sides[1].run.cannon, g.sides[2].run.cannon
		TwoPlayer.step(g, { {}, { move = 1 } })
		t.expect(g.sides[1].run.cannon).toBe(c1)
		t.expect(g.sides[2].run.cannon).toBe(c2 + 1)
		TwoPlayer.step(g, two({ move = 2 }, { move = "1" }))
		TwoPlayer.step(g, two({ move = 0.5 }, { move = -1.5 }))
		t.expect(g.sides[1].run.cannon).toBe(c1)
		t.expect(g.sides[2].run.cannon).toBe(c2 + 1)
		TwoPlayer.step(g, two({ fire = 1 }, { fire = "true" }))
		TwoPlayer.step(g, junk("junk"))
		TwoPlayer.step(g, two(5, false))
		t.expect(g.sides[1].run.shot).toBe(nil)
		t.expect(g.sides[2].run.shot).toBe(nil)
		TwoPlayer.step(g, { { fire = true } })
		t.expect(g.sides[1].run.shot ~= nil).toBe(true)
		t.expect(g.sides[2].run.shot).toBe(nil)
		t.expect(g.sides[1].run.shotsFired).toBe(1)
	end)

	it("plays a whole match to its end with no input", function()
		local g = TwoPlayer.new(1)
		local ends = {}
		for _ = 1, 100000 do
			for _, e in TwoPlayer.step(g, nil) do
				if e.kind == "GameOver" then
					table.insert(ends, e.reason)
					TwoPlayer.retire(g, e.player :: number)
				end
			end
			if g.phase == "over" then
				break
			end
		end
		t.expect(g.phase).toBe("over")
		t.expect(#ends).toBe(2)
		for p = 1, 2 do
			t.expect(TwoPlayer.phaseOf(g, p)).toBe("out")
			t.expect(g.sides[p].run.score).toBe(0)
		end
	end)
end)
