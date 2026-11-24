--!strict
-- f0217 AC5: a lone survivor plays on. When a player's run ends with no revive (TwoPlayer.retire, which the
-- adapter calls when the revive offer ends unbought or the player leaves), their group leaves play at once (the
-- view flies it off) with every alien of theirs still flying in, and later waves come to the remaining player as
-- one solo formation of 5 x 11, flying in from the east like any wave. The match is over once both are out.
local Barriers = require("@logic/Barriers")
local Classic = require("@logic/Classic")
local Formation = require("@logic/Formation")
local TwoPlayer = require("@logic/TwoPlayer")
local t = require("@tests/lib/t")

local C = Classic.CONFIG

-- the kinds of the events this issue defines, in order (a kind a later issue adds is not this spec's)
local KINDS = {}
for _, k in
	{
		"PlayerFire",
		"BarrierHit",
		"AlienHit",
		"MysteryHit",
		"ExtraLife",
		"GroupClear",
		"WaveClear",
		"CannonHit",
		"GameOver",
	}
do
	KINDS[k] = true
end
for _, k in
	{ "March", "Advance", "AlienFire", "MysteryAppear", "MysteryLeave", "Respawn", "WaveStart", "Formed" }
do
	KINDS[k] = true
end

local function kinds(events: { TwoPlayer.Event }): { string }
	local out = {}
	for _, e in events do
		if KINDS[e.kind] then
			table.insert(out, e.kind)
		end
	end
	return out
end

-- only the events of the kinds this issue defines, in order
local function known(events: { TwoPlayer.Event }): { TwoPlayer.Event }
	local out = {}
	for _, e in events do
		if KINDS[e.kind] then
			table.insert(out, e)
		end
	end
	return out
end

local function quiet(g: TwoPlayer.Match)
	for _, side in g.sides do
		side.run.reloadElapsed = -1000000
		side.run.formation.elapsed = -1000000
	end
	g.mystery.elapsed = -1000000
end

local function formed(): TwoPlayer.Match
	local g = TwoPlayer.new(1)
	while g.phase == "flyin" do
		TwoPlayer.step(g, nil)
	end
	quiet(g)
	return g
end

local function run(g: TwoPlayer.Match, n: number, inputs: { Classic.Input? }?): { TwoPlayer.Event }
	local all = {}
	for _ = 1, n do
		for _, e in TwoPlayer.step(g, inputs) do
			table.insert(all, e)
		end
	end
	return known(all)
end

local function killAll(g: TwoPlayer.Match, p: number)
	local f = g.sides[p].run.formation
	for row = 1, f.config.rows do
		for col = 1, f.config.cols do
			Formation.kill(f, row, col)
		end
	end
end

local function lose(g: TwoPlayer.Match, p: number)
	local r = g.sides[p].run
	r.lives = 1
	table.insert(r.bombs, { x = r.cannon, d = C.cannonDepth, slot = 2 })
	quiet(g)
	TwoPlayer.step(g, nil)
	t.expect(TwoPlayer.phaseOf(g, p)).toBe("gameover")
end

return t.spec("f0217 survivor", function(it)
	it(
		"takes a player's group off the field when their run ends with no revive, and the other plays on",
		function()
			local g = formed()
			lose(g, 2)
			local score = g.sides[2].run.score
			local f2 = g.sides[2].run.formation
			local fx, fd = f2.x, f2.d
			t.expect(TwoPlayer.retire(g, 2)).toBe(true)
			-- the group leaves play where it stood (the view flies it off from there)
			t.expect(f2.x).toBe(fx)
			t.expect(f2.d).toBe(fd)
			t.expect(g.sides[2].out).toBe(true)
			t.expect(TwoPlayer.phaseOf(g, 2)).toBe("out")
			t.expect(g.sides[2].run.formation.live).toBe(0)
			t.expect(g.sides[2].run.score).toBe(score)
			t.expect(TwoPlayer.retire(g, 2)).toBe(false)
			t.expect(TwoPlayer.revive(g, 2)).toBe(false)
			-- and a player the match does not have is refused
			t.expect(TwoPlayer.retire(g, 3)).toBe(false)
			t.expect(TwoPlayer.revive(g, 0)).toBe(false)
			-- player 2 does nothing more; player 1 plays on
			g.sides[1].run.formation.elapsed = 0
			local e = run(g, 300, { { move = 1, fire = true }, { move = 1, fire = true } })
			for _, ev in e do
				t.expect(ev.player ~= 2 or ev.shooter == 1).toBe(true)
			end
			t.expect(g.sides[2].run.cannon).toBe(C.cannonStart)
			t.expect(g.phase).toBe("playing")
			t.expect(table.find(kinds(e), "PlayerFire") ~= nil).toBe(true)
		end
	)

	it("lets a player leave while playing, the same way", function()
		local g = formed()
		g.sides[1].run.shot = { x = 30, d = 100 }
		table.insert(g.sides[1].run.bombs, { x = 30, d = 100, slot = 2 })
		t.expect(TwoPlayer.retire(g, 1)).toBe(true)
		t.expect(TwoPlayer.phaseOf(g, 1)).toBe("out")
		t.expect(g.sides[1].run.formation.live).toBe(0)
		t.expect(g.sides[1].run.shot).toBe(nil)
		t.expect(#g.sides[1].run.bombs).toBe(0)
		t.expect(TwoPlayer.phaseOf(g, 2)).toBe("playing")
	end)

	it("drops the leaving player's aliens that are still flying in", function()
		local g = TwoPlayer.new(1)
		run(g, 10)
		TwoPlayer.retire(g, 2)
		t.expect(#g.flyers > 0).toBe(true)
		for _, fl in g.flyers do
			t.expect(fl.player).toBe(1)
		end
		local ticks = 0
		while g.phase == "flyin" and ticks < 400 do
			ticks += 1
			TwoPlayer.step(g, nil)
		end
		t.expect(g.phase).toBe("playing")
		t.expect(g.sides[1].run.formation.live).toBe(40)
		t.expect(g.sides[2].run.formation.live).toBe(0)
	end)

	it("sends every later wave to the survivor as one solo formation of 5 x 11, flying in", function()
		local g = formed()
		TwoPlayer.retire(g, 2)
		for wave = 2, 3 do
			killAll(g, 1)
			local e = run(g, 1)
			t.expect(kinds(e)).toEqual({ "WaveClear" })
			local start = run(g, C.waveClearTicks)
			t.expect(kinds(start)).toEqual({ "WaveStart" })
			t.expect(g.wave).toBe(wave)
			t.expect(g.phase).toBe("flyin")
			t.expect(#g.flyers).toBe(55)
			for k, fl in g.flyers do
				t.expect(fl.player).toBe(1)
				t.expect(fl.start).toBe((k - 1) * TwoPlayer.CONFIG.flyIn.loneGap)
			end
			local f = g.sides[1].run.formation
			t.expect(f.config).toBe(Formation.CLASSIC)
			t.expect(f.live).toBe(55)
			t.expect(f.d).toBe(Classic.waveDepth(wave))
			t.expect(f.x).toBe(26)
			t.expect(g.sides[2].run.formation.live).toBe(0)
			local ticks = 0
			while g.phase == "flyin" and ticks < 1000 do
				ticks += 1
				TwoPlayer.step(g, nil)
			end
			t.expect(ticks >= 2.5 * Classic.TICK_RATE and ticks <= 3.5 * Classic.TICK_RATE).toBe(true)
			-- then it marches by the solo rules: one tick per living alien
			local m = nil
			for _ = 1, 100 do
				for _, ev in TwoPlayer.step(g, nil) do
					if ev.kind == "March" then
						m = ev
					end
				end
				if m then
					break
				end
			end
			t.expect(m ~= nil).toBe(true)
			t.expect((m :: TwoPlayer.Event).player).toBe(1)
			t.expect((m :: TwoPlayer.Event).interval).toBe(55)
			quiet(g)
		end
	end)

	it("ends the wave once the waiting player leaves and every group is gone", function()
		local g = formed()
		lose(g, 2)
		killAll(g, 1)
		killAll(g, 2)
		t.expect(#kinds(run(g, 50))).toBe(0)
		t.expect(g.phase).toBe("playing")
		TwoPlayer.retire(g, 2)
		t.expect(kinds(run(g, 1))).toEqual({ "WaveClear" })
	end)

	it("ends the match once both players are out, and then nothing changes", function()
		local g = formed()
		t.expect(TwoPlayer.retire(g, 1)).toBe(true)
		t.expect(g.phase).toBe("playing")
		t.expect(TwoPlayer.retire(g, 2)).toBe(true)
		t.expect(g.phase).toBe("over")
		local m = g.mystery.elapsed
		t.expect(#kinds(run(g, 200, { { move = 1, fire = true }, { move = 1, fire = true } }))).toBe(0)
		t.expect(g.mystery.elapsed).toBe(m)
		t.expect(g.sides[1].run.cannon).toBe(C.cannonStart)
	end)
	it("keeps the leaver's score, lives, revives and reason for the boards", function()
		local g = formed()
		lose(g, 2)
		t.expect(TwoPlayer.revive(g, 2)).toBe(true)
		lose(g, 2)
		g.sides[2].run.score = 340
		t.expect(TwoPlayer.retire(g, 2)).toBe(true)
		local r2 = g.sides[2].run
		t.expect(r2.revives).toBe(1)
		t.expect(r2.lives).toBe(0)
		t.expect(r2.reason).toBe("lives")
		t.expect(r2.score).toBe(340)
	end)

	it(
		"leaves the leaver's bunkers on the field as they were, through later waves, still a target",
		function()
			local g = formed()
			local b2 = g.sides[2].run.barriers
			Barriers.erode(b2, 1, 1, 6, -1)
			t.expect(Barriers.count(b2)).toBe(4 * 48 - 3)
			TwoPlayer.retire(g, 2)
			t.expect(Barriers.count(g.sides[2].run.barriers)).toBe(4 * 48 - 3)
			killAll(g, 1)
			t.expect(kinds(run(g, 1))).toEqual({ "WaveClear" })
			t.expect(kinds(run(g, C.waveClearTicks))).toEqual({ "WaveStart" })
			t.expect(Barriers.count(g.sides[2].run.barriers)).toBe(4 * 48 - 3)
			-- player 1's shot at player 2's bunker 2, column 1, from its far side
			g.sides[1].run.shot = { x = C.fieldWidth - 1 - 77, d = TwoPlayer.CONFIG.fieldDepth - 1 - 45 }
			local e = run(g, 1)
			t.expect(kinds(e)).toEqual({ "BarrierHit" })
			t.expect(e[1].player).toBe(2)
			t.expect(e[1].shooter).toBe(1)
			t.expect(Barriers.count(g.sides[2].run.barriers)).toBe(4 * 48 - 6)
		end
	)
end)
