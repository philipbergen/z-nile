--!strict
-- E1 (f0203 prep): does arcade's Rng, given pickman's three streams as parameters, give exactly the states and draws
-- pickman's Ghosts, Picks and Blaster generators give today? Run against the prototype in arcade/src (prep only).
local Blaster = require("../../../../../pickman/src/shared/Logic/Blaster")
local GhostRng = require("../../../../../pickman/src/shared/Logic/Ghosts/Rng")
local Picks = require("../../../../../pickman/src/shared/Logic/Picks")
local Rng = require("../../../../src/shared/Logic/Rng")

local M = 2147483647
-- 9e10: a UserId-sized seed (pickman seeds with player.UserId). Above 2^53/69621 (about 1.29e11) pickman's Picks
-- product loses precision and arcade's (reduced first) stays exact, so the streams differ there (E1 result).
local seeds = { 0, 1, 7, 42, 123456789, -7, 9e10, 4.6 }
local bad = 0
local golden = {}
for _, seed in seeds do
	-- Ghosts: Rng.seed(seed), then Rng.next(state, n)
	local g = Rng.new(seed, { multiplier = 16807, mix = 1, offset = 0 })
	local s = GhostRng.seed(seed)
	if g.state ~= s then
		bad += 1
		print("ghosts seed", seed, g.state, s)
	end
	for i = 1, 50 do
		local n = (i % 9) + 1
		local k
		s, k = GhostRng.next(s, n)
		local got = Rng.int(g, n)
		if got ~= k or g.state ~= s then
			bad += 1
			print("ghosts", seed, i, got, k)
		end
	end
	-- Picks: Picks.new(seed).rng, then rng = rng * 48271 % M, roll = rng % n + 1
	local p = Picks.new(seed)
	local pg = Rng.new(seed, { multiplier = 48271, mix = 69621, offset = 7 })
	if pg.state ~= p.rng then
		bad += 1
		print("picks seed", seed, pg.state, p.rng)
	end
	local ps = p.rng
	for i = 1, 50 do
		ps = (ps * 48271) % M
		local got = Rng.int(pg, 6)
		if got ~= ps % 6 + 1 then
			bad += 1
			print("picks", seed, i)
		end
	end
	-- Blaster: Blaster.new(seed).rng, drop: rng * 16807 % M, dropped = rng % 100 < 50
	local b = Blaster.new(seed)
	local bg = Rng.new(seed, { multiplier = 16807, mix = 48271, offset = 11 })
	if bg.state ~= b.rng then
		bad += 1
		print("blaster seed", seed, bg.state, b.rng)
	end
	for i = 1, 50 do
		b.shots = 0
		local dropped = Blaster.drop(b)
		local got = Rng.int(bg, 100) <= Blaster.DROP_PERCENT
		if got ~= dropped or bg.state ~= b.rng then
			bad += 1
			print("blaster", seed, i)
		end
	end
end
-- golden values for the acceptance spec: the default stream, seed 42, the first eight int(1000) draws
local d = Rng.new(42)
local first = { d.state }
for _ = 1, 8 do
	table.insert(first, Rng.int(d, 1000))
end
print("default seed 42: state then int(1000) x8:", table.concat(first, ", "))
for _, st in { { 16807, 1, 0 }, { 48271, 69621, 7 }, { 16807, 48271, 11 } } do
	local x = Rng.new(2024, { multiplier = st[1], mix = st[2], offset = st[3] })
	local row = { x.state }
	for _ = 1, 6 do
		table.insert(row, Rng.int(x, 97))
	end
	print(`stream {st[1]},{st[2]},{st[3]} seed 2024: state then int(97) x6:`, table.concat(row, ", "))
end
print(if bad == 0 then "E1 PASS" else `E1 FAIL {bad}`)
