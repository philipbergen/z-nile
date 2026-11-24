--!strict
-- f0217 AC4: each player's own run. Each group marches, advances and fires toward its own player by the solo rules;
-- each player has their own score, lives, extra life and revives; a hit pauses only the player hit, and a run that
-- ends (lives or invasion) ends alone while the other plays on, its group held still and still a target. A wave
-- ends when both groups are gone and nobody waits on a revive, and the next one flies in one row closer. A revive
-- gives that player 3 lives and restarts their part of the wave: their group full at the wave's depth, in place.
local Barriers = require("@logic/Barriers")
local Classic = require("@logic/Classic")
local Formation = require("@logic/Formation")
local TwoPlayer = require("@logic/TwoPlayer")
local t = require("@tests/lib/t")

local C = Classic.CONFIG
local D = TwoPlayer.CONFIG.fieldDepth

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

local function count(events: { TwoPlayer.Event }, kind: string, player: number?): number
	local n = 0
	for _, e in events do
		if e.kind == kind and (player == nil or e.player == player) then
			n += 1
		end
	end
	return n
end

local function find(events: { TwoPlayer.Event }, kind: string, player: number?): TwoPlayer.Event?
	for _, e in events do
		if e.kind == kind and (player == nil or e.player == player) then
			return e
		end
	end
	return nil
end

local function noFire(g: TwoPlayer.Match)
	for _, side in g.sides do
		side.run.reloadElapsed = -1000000
	end
	g.mystery.elapsed = -1000000
end

local function quiet(g: TwoPlayer.Match)
	noFire(g)
	for _, side in g.sides do
		side.run.formation.elapsed = -1000000
	end
end

local function formed(): TwoPlayer.Match
	local g = TwoPlayer.new(1)
	while g.phase == "flyin" do
		TwoPlayer.step(g, nil)
	end
	quiet(g)
	return g
end

local function run(
	g: TwoPlayer.Match,
	n: number,
	inputs: { Classic.Input? }?,
	keep: ((TwoPlayer.Match) -> ())?
): { TwoPlayer.Event }
	local all = {}
	for _ = 1, n do
		if keep then
			keep(g)
		end
		for _, e in TwoPlayer.step(g, inputs) do
			table.insert(all, e)
		end
	end
	return known(all)
end

-- a bomb one tick from player p's cannon
local function drop(g: TwoPlayer.Match, p: number)
	local r = g.sides[p].run
	table.insert(r.bombs, { x = r.cannon, d = C.cannonDepth, slot = 2 })
end

local function killAllBut(g: TwoPlayer.Match, p: number, keepRow: number?, keepCol: number?)
	local f = g.sides[p].run.formation
	for row = 1, f.config.rows do
		for col = 1, f.config.cols do
			if not (row == keepRow and col == keepCol) then
				Formation.kill(f, row, col)
			end
		end
	end
end

return t.spec("f0217 sides", function(it)
	it("marches each group toward its own player by the solo rules", function()
		local g = formed()
		for p = 1, 2 do
			g.sides[p].run.formation.elapsed = 0
		end
		local events = run(g, 2000, nil, noFire)
		for p = 1, 2 do
			local f = g.sides[p].run.formation
			-- 5 x 8 at x = 50 makes 21 steps right before its first advance, one every 40 ticks (one per alien)
			local marches, advanced = 0, false
			for _, e in events do
				if e.player == p and e.kind == "March" and not advanced then
					marches += 1
					t.expect(e.interval).toBe(40)
				elseif e.player == p and e.kind == "Advance" then
					advanced = true
				end
			end
			t.expect(marches).toBe(21)
			t.expect(advanced).toBe(true)
			t.expect(f.d < Classic.waveDepth(1)).toBe(true)
		end
		-- in the field, player 2's group came toward the far end
		local _, _, _, d1 = TwoPlayer.fieldBox(g, 2, Formation.box(g.sides[2].run.formation, 1, 1))
		t.expect(d1 > D - Classic.waveDepth(1)).toBe(true)
	end)

	it("aims each group's shots at its own player, and only that player's hit costs them", function()
		local g = formed()
		g.sides[2].run.reloadElapsed = Classic.reloadTicks(0) - 1
		local e = run(g, 1)
		t.expect(kinds(e)).toEqual({ "AlienFire" })
		t.expect(e[1].player).toBe(2)
		t.expect(e[1].slot).toBe(1)
		-- the cannon at 112 is midway between columns 4 and 5 (centres 104 and 120): the lower one
		t.expect(e[1].col).toBe(4)
		local bomb = g.sides[2].run.bombs[1]
		t.expect(bomb.x).toBe(104)
		t.expect(bomb.d).toBe(Classic.waveDepth(1))
		t.expect(#g.sides[1].run.bombs).toBe(0)
		-- it comes down toward player 2 and costs player 2 a life
		g.sides[2].run.cannon = 104
		local hit = run(g, 200, nil, noFire)
		local h = find(hit, "CannonHit")
		t.expect(h ~= nil).toBe(true)
		t.expect((h :: TwoPlayer.Event).player).toBe(2)
		t.expect(g.sides[2].run.lives).toBe(2)
		t.expect(g.sides[1].run.lives).toBe(3)
	end)

	it("keeps each player's score, lives and extra life their own", function()
		local g = formed()
		g.sides[1].run.score = 1490
		g.sides[1].run.shot = { x = 55, d = 116 } -- player 1's own front-left alien
		local e = run(g, 1)
		t.expect(kinds(e)).toEqual({ "AlienHit", "ExtraLife" })
		t.expect(e[2].player).toBe(1)
		t.expect(e[2].lives).toBe(4)
		t.expect(g.sides[1].run.lives).toBe(4)
		t.expect(g.sides[2].run.lives).toBe(3)
		t.expect(g.sides[2].run.score).toBe(0)
		-- player 2 wins theirs by shooting player 1's group
		g.sides[2].run.score = 1490
		g.sides[2].run.shot = { x = 168 - 16, d = 330 }
		local e2 = run(g, 2)
		t.expect(kinds(e2)).toEqual({ "AlienHit", "ExtraLife" })
		t.expect(e2[1].player).toBe(1)
		t.expect(e2[1].shooter).toBe(2)
		t.expect(e2[2].player).toBe(2)
		t.expect(g.sides[2].run.lives).toBe(4)
		t.expect(g.sides[1].run.lives).toBe(4)
		t.expect(g.sides[1].run.score).toBe(1500)
	end)

	it("pauses only the player who was hit", function()
		local g = formed()
		g.sides[1].run.cannon = 40
		drop(g, 1)
		-- both groups' next steps are due this tick: the hit stops player 1's, not player 2's
		for p = 1, 2 do
			local f = g.sides[p].run.formation
			f.elapsed = Formation.interval(f) - 1
		end
		local e = run(g, 1)
		t.expect(kinds(e)).toEqual({ "CannonHit", "March" })
		t.expect(e[1].player).toBe(1)
		t.expect(e[1].lives).toBe(2)
		t.expect(e[2].player).toBe(2)
		t.expect(TwoPlayer.phaseOf(g, 1)).toBe("dying")
		t.expect(TwoPlayer.phaseOf(g, 2)).toBe("playing")
		local fx = g.sides[1].run.formation.x
		local both = { { move = 1, fire = true }, { move = 1, fire = true } }
		local during = run(g, C.dyingTicks - 1, both, function(m)
			noFire(m)
			m.sides[1].run.formation.elapsed = 1000
			if m.sides[2].run.formation.elapsed < 0 then
				m.sides[2].run.formation.elapsed = 0
			end
		end)
		t.expect(count(during, "March", 1) + count(during, "Advance", 1) + count(during, "PlayerFire", 1))
			.toBe(0)
		t.expect(count(during, "March", 2) > 0).toBe(true)
		t.expect(count(during, "PlayerFire", 2) > 0).toBe(true)
		t.expect(g.sides[1].run.cannon).toBe(40)
		t.expect(g.sides[1].run.formation.x).toBe(fx)
		t.expect(g.sides[2].run.cannon > C.cannonStart).toBe(true)
		local back = run(g, 1, both, quiet)
		local r = find(back, "Respawn")
		t.expect(r ~= nil).toBe(true)
		t.expect((r :: TwoPlayer.Event).player).toBe(1)
		t.expect((r :: TwoPlayer.Event).lives).toBe(2)
		t.expect(g.sides[1].run.cannon).toBe(C.cannonStart)
		t.expect(TwoPlayer.phaseOf(g, 1)).toBe("playing")
	end)

	it("ends one player's run alone, on lives or by invasion, and the other plays on", function()
		local g = formed()
		g.sides[2].run.lives = 1
		drop(g, 2)
		local e = run(g, 1)
		t.expect(kinds(e)).toEqual({ "CannonHit", "GameOver" })
		t.expect(e[2].player).toBe(2)
		t.expect(e[2].reason).toBe("lives")
		t.expect(TwoPlayer.phaseOf(g, 2)).toBe("gameover")
		t.expect(TwoPlayer.phaseOf(g, 1)).toBe("playing")
		-- player 1's group reaches player 1's base line: game over at once, with lives left
		local f = g.sides[1].run.formation
		f.d = C.invasionDepth + Formation.CLASSIC.rowStep
		f.x = Formation.CLASSIC.fieldWidth - Formation.CLASSIC.margin - (7 * 16 + 12)
		f.elapsed = Formation.interval(f) - 1
		local inv = run(g, 1, nil, noFire)
		t.expect(kinds(inv)).toEqual({ "Advance", "GameOver" })
		t.expect(inv[2].player).toBe(1)
		t.expect(inv[2].reason).toBe("invasion")
		t.expect(g.sides[1].run.lives).toBe(3)
	end)

	it("holds a waiting player's group still and lets the other player shoot it", function()
		local g = formed()
		g.sides[2].run.lives = 1
		drop(g, 2)
		run(g, 1)
		local f2 = g.sides[2].run.formation
		local x, d = f2.x, f2.d
		g.sides[1].run.formation.elapsed = 0
		local later = run(g, 300, { { move = 1 }, { move = 1, fire = true } }, function(m)
			noFire(m)
			m.sides[2].run.formation.elapsed = 1000
		end)
		t.expect(count(later, "March", 2) + count(later, "AlienFire", 2) + count(later, "PlayerFire", 2))
			.toBe(0)
		t.expect(count(later, "March", 1) > 0).toBe(true)
		t.expect(f2.x).toBe(x)
		t.expect(f2.d).toBe(d)
		t.expect(g.sides[2].run.cannon).toBe(C.cannonStart)
		-- player 1 shoots into the held group
		quiet(g)
		local fx0 = TwoPlayer.fieldBox(g, 2, Formation.box(f2, 1, 1))
		g.sides[1].run.shot = { x = fx0 + 6, d = D - Classic.waveDepth(1) - 8 - 6 }
		local hit = run(g, 2)
		local h = find(hit, "AlienHit")
		t.expect(h ~= nil).toBe(true)
		t.expect((h :: TwoPlayer.Event).player).toBe(2)
		t.expect((h :: TwoPlayer.Event).shooter).toBe(1)
		t.expect(f2.live).toBe(39)
	end)

	it("ends the wave only when both groups are gone, then the next one flies in one row closer", function()
		local g = formed()
		g.sides[1].run.score = 70
		g.sides[2].run.lives = 2
		Barriers.erode(g.sides[1].run.barriers, 1, 1, 1, 1)
		killAllBut(g, 1, 1, 1)
		g.sides[1].run.shot = { x = 55, d = 116 }
		local e = run(g, 1)
		t.expect(kinds(e)).toEqual({ "AlienHit", "GroupClear" })
		t.expect(e[2].player).toBe(1)
		t.expect(g.phase).toBe("playing")
		t.expect(#kinds(run(g, 30, nil, quiet))).toBe(0)
		t.expect(g.phase).toBe("playing")
		-- player 2's last alien goes too: the wave is over
		killAllBut(g, 2, 1, 1)
		table.insert(g.sides[2].run.bombs, { x = 10, d = 100, slot = 3 })
		g.sides[1].run.shot = { x = 168, d = 330 }
		g.mystery.nextDir = -1
		local last = run(g, 2)
		t.expect(kinds(last)).toEqual({ "AlienHit", "GroupClear", "WaveClear" })
		t.expect(last[3].wave).toBe(1)
		t.expect(g.phase).toBe("waveclear")
		for p = 1, 2 do
			t.expect(g.sides[p].run.shot).toBe(nil)
			t.expect(#g.sides[p].run.bombs).toBe(0)
		end
		t.expect(#kinds(run(g, C.waveClearTicks - 1, { { move = 1, fire = true } }))).toBe(0)
		t.expect(g.phase).toBe("waveclear")
		local start = run(g, 1)
		t.expect(kinds(start)).toEqual({ "WaveStart" })
		t.expect(start[1].wave).toBe(2)
		t.expect(g.wave).toBe(2)
		t.expect(g.phase).toBe("flyin")
		t.expect(#g.flyers).toBe(80)
		t.expect(g.mystery.x).toBe(nil)
		t.expect(g.mystery.elapsed).toBe(0)
		t.expect(g.mystery.nextDir).toBe(1)
		for p = 1, 2 do
			local r = g.sides[p].run
			t.expect(r.wave).toBe(2)
			t.expect(r.formation.live).toBe(40)
			t.expect(r.formation.d).toBe(Classic.waveDepth(2))
			t.expect(Barriers.count(r.barriers)).toBe(4 * 48)
			t.expect(r.cannon).toBe(C.cannonStart)
		end
		t.expect(g.sides[1].run.score).toBe(90)
		t.expect(g.sides[2].run.lives).toBe(2)
	end)

	it("holds the wave's end while a player waits on a revive", function()
		local g = formed()
		g.sides[2].run.lives = 1
		drop(g, 2)
		run(g, 1)
		killAllBut(g, 1)
		killAllBut(g, 2, 1, 1)
		g.sides[1].run.shot = { x = 168, d = 330 }
		local e = run(g, 2)
		t.expect(kinds(e)).toEqual({ "AlienHit", "GroupClear" })
		t.expect(#kinds(run(g, 200, nil, quiet))).toBe(0)
		t.expect(g.phase).toBe("playing")
		t.expect(TwoPlayer.revive(g, 2)).toBe(true)
		t.expect(g.sides[2].run.formation.live).toBe(40)
		run(g, 5, nil, quiet)
		t.expect(g.phase).toBe("playing")
	end)

	it(
		"revives one player alone: 3 lives, and their group back at the wave's start, already in place",
		function()
			local g = formed()
			local r1 = g.sides[1].run
			r1.score = 230
			r1.shotsFired = 12
			killAllBut(g, 1, 3, 3)
			r1.formation.x += 10
			r1.formation.d -= 16
			Barriers.erode(r1.barriers, 2, 4, 1, 1)
			r1.lives = 1
			drop(g, 1)
			run(g, 1)
			t.expect(TwoPlayer.phaseOf(g, 1)).toBe("gameover")
			local r2 = g.sides[2].run
			Formation.kill(r2.formation, 2, 2)
			local x2, d2, live2, cannon2 = r2.formation.x, r2.formation.d, r2.formation.live, r2.cannon
			t.expect(TwoPlayer.revive(g, 2)).toBe(false)
			t.expect(TwoPlayer.revive(g, 1)).toBe(true)
			t.expect(r1.lives).toBe(3)
			t.expect(r1.revives).toBe(1)
			t.expect(r1.reason).toBe(nil)
			t.expect(TwoPlayer.phaseOf(g, 1)).toBe("playing")
			t.expect(r1.score).toBe(230)
			t.expect(r1.shotsFired).toBe(12)
			t.expect(r1.formation.live).toBe(40)
			t.expect(r1.formation.d).toBe(Classic.waveDepth(1))
			t.expect(r1.formation.x).toBe(50)
			t.expect(r1.formation.config.cols).toBe(8)
			for _, w in g.sides[1].waiting do
				t.expect(w).toBe(false)
			end
			t.expect(Barriers.count(r1.barriers)).toBe(4 * 48)
			t.expect(r1.cannon).toBe(C.cannonStart)
			t.expect(r1.shot).toBe(nil)
			t.expect(#r1.bombs).toBe(0)
			-- the other player is untouched
			t.expect(r2.formation.x).toBe(x2)
			t.expect(r2.formation.d).toBe(d2)
			t.expect(r2.formation.live).toBe(live2)
			t.expect(r2.cannon).toBe(cannon2)
			t.expect(r2.revives).toBe(0)
			t.expect(TwoPlayer.revive(g, 1)).toBe(false)
			-- and the revived group marches at once: it does not fly in again
			r1.formation.elapsed = Formation.interval(r1.formation) - 1
			local e = run(g, 1, nil, noFire)
			t.expect(count(e, "March", 1)).toBe(1)
			t.expect(g.phase).toBe("playing")
		end
	)

	it(
		"revives a player during a fly-in with their group in place, and the other's still flying in",
		function()
			local g = TwoPlayer.new(1)
			run(g, 20)
			local r1 = g.sides[1].run
			r1.lives = 1
			drop(g, 1)
			run(g, 1)
			t.expect(TwoPlayer.phaseOf(g, 1)).toBe("gameover")
			t.expect(TwoPlayer.revive(g, 1)).toBe(true)
			t.expect(r1.formation.live).toBe(40)
			for _, w in g.sides[1].waiting do
				t.expect(w).toBe(false)
			end
			local mine, theirs = 0, 0
			for _, fl in g.flyers do
				if fl.player == 1 then
					mine += 1
				else
					theirs += 1
				end
			end
			t.expect(mine).toBe(0)
			t.expect(theirs > 0).toBe(true)
			t.expect(g.phase).toBe("flyin")
			local ticks = 0
			while g.phase == "flyin" and ticks < 400 do
				ticks += 1
				TwoPlayer.step(g, nil)
			end
			t.expect(g.phase).toBe("playing")
			t.expect(g.sides[2].run.formation.live).toBe(40)
		end
	)
	it("ends a dying pause the wave's clear froze with the next wave's start, and says so", function()
		local g = formed()
		g.sides[1].run.cannon = 40
		drop(g, 1)
		run(g, 1)
		t.expect(TwoPlayer.phaseOf(g, 1)).toBe("dying")
		-- player 2 clears the wave on the next tick
		killAllBut(g, 1)
		killAllBut(g, 2, 1, 1)
		g.sides[2].run.shot = { x = 55, d = 116 }
		t.expect(kinds(run(g, 1))).toEqual({ "AlienHit", "GroupClear", "WaveClear" })
		-- through the wave's pause the pause does not count
		local timer = g.sides[1].run.timer
		t.expect(#kinds(run(g, C.waveClearTicks - 1))).toBe(0)
		t.expect(TwoPlayer.phaseOf(g, 1)).toBe("dying")
		t.expect(g.sides[1].run.timer).toBe(timer)
		local e = run(g, 1)
		t.expect(kinds(e)).toEqual({ "WaveStart", "Respawn" })
		t.expect(e[2].player).toBe(1)
		t.expect(e[2].lives).toBe(2)
		t.expect(TwoPlayer.phaseOf(g, 1)).toBe("playing")
		t.expect(g.sides[1].run.cannon).toBe(C.cannonStart)
	end)

	it("revives a player whose partner left mid-wave with the wave's own group of 5 x 8", function()
		local g = formed()
		TwoPlayer.retire(g, 2)
		local r1 = g.sides[1].run
		r1.lives = 1
		drop(g, 1)
		run(g, 1)
		t.expect(TwoPlayer.revive(g, 1)).toBe(true)
		t.expect(r1.formation.config.cols).toBe(8)
		t.expect(r1.formation.live).toBe(40)
	end)
end)
