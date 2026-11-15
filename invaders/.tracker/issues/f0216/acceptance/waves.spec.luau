--!strict
-- f0216 AC6. Invasion: a living alien reaching the base line ends the game at once, whatever the lives
-- left (reason "invasion"). A revive (only at game over) gives 3 lives and restarts that wave from its starting
-- state: a full formation at the wave's starting depth, fresh barriers, no shots, the cannon at its start; the
-- score, the wave and the extra life already given stay, and the revive is counted. Waves: the last alien killed
-- clears the wave (a 120-tick pause), and the next wave's formation starts one row closer, cycling after 8.
local Barriers = require("@logic/Barriers")
local Classic = require("@logic/Classic")
local Formation = require("@logic/Formation")
local t = require("@tests/lib/t")

local CFG = Classic.CONFIG
local F = Formation.CLASSIC

local function run(g: Classic.Game, n: number, input: Classic.Input?): { Classic.Event }
	local all = {}
	for _ = 1, n do
		for _, e in Classic.step(g, input) do
			table.insert(all, e)
		end
	end
	return all
end

local function kinds(events: { Classic.Event }): { string }
	local out = {}
	for _, e in events do
		table.insert(out, e.kind)
	end
	return out
end

-- every alien but (row, col) killed
local function lastOne(g: Classic.Game, row: number, col: number)
	for r = 1, F.rows do
		for c = 1, F.cols do
			if not (r == row and c == col) then
				Formation.kill(g.formation, r, c)
			end
		end
	end
end

-- marches the formation until the game ends; returns the events
local function untilOver(g: Classic.Game): { Classic.Event }
	local all = {}
	for _ = 1, 200000 do
		g.reloadElapsed = -100000
		for _, e in Classic.step(g, nil) do
			table.insert(all, e)
		end
		if g.phase == "gameover" then
			return all
		end
	end
	error("the game never ended")
end

local function invade(g: Classic.Game)
	-- the formation one advance above the line; a short formation so the march is quick
	g.formation.d = CFG.invasionDepth + F.rowStep
	untilOver(g)
end

return t.spec("f0216 waves", function(it)
	it("ends the game at once when the formation reaches the base line, with lives left", function()
		local g = Classic.new(1)
		t.expect(g.lives).toBe(3)
		g.formation.d = CFG.invasionDepth + F.rowStep
		local e = untilOver(g)
		local k = kinds(e)
		t.expect(k[#k - 1]).toBe("Advance")
		t.expect(k[#k]).toBe("GameOver")
		t.expect(e[#e].reason).toBe("invasion")
		t.expect(g.reason).toBe("invasion")
		t.expect(g.lives).toBe(3)
		t.expect(g.formation.d).toBe(CFG.invasionDepth)
		t.expect(CFG.invasionDepth).toBe(CFG.cannonDepth)
	end)

	it(
		"judges the living front row: with the front rows dead the formation comes closer before it invades",
		function()
			local g = Classic.new(1)
			for col = 1, F.cols do
				Formation.kill(g.formation, 1, col)
				Formation.kill(g.formation, 2, col)
			end
			g.formation.d = CFG.invasionDepth + F.rowStep -- row 3 is 2 row spacings further back
			untilOver(g)
			local _, _, near = Formation.extent(g.formation)
			t.expect(near).toBe(CFG.invasionDepth)
			t.expect(g.formation.d).toBe(CFG.invasionDepth - 2 * F.rowSpacing)
		end
	)

	it("does not invade one advance short of the line", function()
		local g = Classic.new(1)
		g.formation.d = CFG.invasionDepth + 2 * F.rowStep
		local advances = 0
		for _ = 1, 200000 do
			g.reloadElapsed = -100000
			for _, e in Classic.step(g, nil) do
				if e.kind == "Advance" then
					advances += 1
				end
			end
			if advances == 1 then
				break
			end
		end
		t.expect(g.phase).toBe("playing")
		t.expect(g.formation.d).toBe(CFG.invasionDepth + F.rowStep)
	end)

	it(
		"revives only at game over: 3 lives and the wave restarted from its start; score and wave stay",
		function()
			local g = Classic.new(1)
			t.expect(Classic.revive(g)).toBe(false)
			t.expect(g.revives).toBe(0)
			g.wave = 3
			g.score = 2220
			g.extraLifeGiven = true
			g.shotsFired = 40
			Barriers.erode(g.barriers, 1, 4, 1, 1)
			invade(g)
			t.expect(g.phase).toBe("gameover")
			-- every field the wave's start resets, set away from its start value
			g.cannon = 40
			g.reloadElapsed = 30
			g.nextSlot = 3
			g.mystery.x = 100
			g.mystery.elapsed = 700
			g.mystery.nextDir = -1
			g.shot = { x = 40, d = 50 }
			table.insert(g.bombs, { x = 80, d = 60, slot = 2 })
			t.expect(Classic.revive(g)).toBe(true)
			t.expect(g.phase).toBe("playing")
			t.expect(g.reason).toBe(nil)
			t.expect(g.lives).toBe(CFG.reviveLives)
			t.expect(CFG.reviveLives).toBe(3)
			t.expect(g.revives).toBe(1)
			t.expect(g.wave).toBe(3)
			t.expect(g.score).toBe(2220)
			t.expect(g.extraLifeGiven).toBe(true)
			t.expect(g.shotsFired).toBe(40)
			t.expect(g.formation.live).toBe(55)
			t.expect(g.formation.d).toBe(Classic.waveDepth(3))
			t.expect(g.formation.dir).toBe(1)
			t.expect(g.formation.x).toBe(Formation.new(F, 0).x)
			t.expect(Barriers.count(g.barriers)).toBe(4 * 48)
			t.expect(g.shot).toBe(nil)
			t.expect(#g.bombs).toBe(0)
			t.expect(g.cannon).toBe(CFG.cannonStart)
			t.expect(g.reloadElapsed).toBe(0)
			t.expect(g.nextSlot).toBe(1)
			t.expect(g.mystery.x).toBe(nil)
			t.expect(g.mystery.elapsed).toBe(0)
			t.expect(g.mystery.nextDir).toBe(1)
			t.expect(g.timer).toBe(0)
			t.expect(Classic.revive(g)).toBe(false) -- not at game over any more
			t.expect(g.revives).toBe(1)
			-- and it plays: the cannon fires
			run(g, 1, { fire = true })
			t.expect(g.shot ~= nil).toBe(true)
		end
	)

	it("revives a game lost on lives the same way, and counts each revive", function()
		local g = Classic.new(1)
		g.reloadElapsed = -100000
		g.lives = 1
		Formation.kill(g.formation, 1, 1)
		table.insert(g.bombs, { x = g.cannon, d = CFG.cannonDepth, slot = 2 })
		run(g, 1)
		t.expect(g.reason).toBe("lives")
		t.expect(Classic.revive(g)).toBe(true)
		t.expect(g.lives).toBe(3)
		t.expect(g.formation.live).toBe(55)
		invade(g)
		t.expect(Classic.revive(g)).toBe(true)
		t.expect(g.revives).toBe(2)
	end)

	it(
		"clears the wave with its last alien, pauses 120 ticks, then starts the next one row closer",
		function()
			local g = Classic.new(1)
			g.reloadElapsed = -100000
			g.formation.elapsed = -100000
			lastOne(g, 1, 6)
			g.cannon = 112
			table.insert(g.bombs, { x = 150, d = 100, slot = 2 })
			Barriers.erode(g.barriers, 2, 1, 1, 1)
			run(g, 1, { fire = true })
			local n = 0
			local e: { Classic.Event }
			repeat
				n += 1
				e = run(g, 1)
			until table.find(kinds(e), "WaveClear") or n > 100
			t.expect(table.find(kinds(e), "WaveClear") ~= nil).toBe(true)
			t.expect(g.phase).toBe("waveclear")
			t.expect(#g.bombs).toBe(0)
			t.expect(g.shot).toBe(nil)
			t.expect(g.wave).toBe(1)
			t.expect(CFG.waveClearTicks).toBe(120) -- 2 s at 60 ticks a second
			-- every field the wave's start resets, set away from its start value (the pause leaves them alone)
			g.cannon = 40
			g.reloadElapsed = 30
			g.nextSlot = 3
			g.mystery.x = 100
			g.mystery.elapsed = 700
			g.mystery.nextDir = -1
			local during = run(g, CFG.waveClearTicks - 1, { move = 1, fire = true })
			t.expect(#during).toBe(0)
			t.expect(g.phase).toBe("waveclear")
			t.expect(g.shotsFired).toBe(1)
			local start = run(g, 1)
			t.expect(kinds(start)).toEqual({ "WaveStart" })
			t.expect(start[1].wave).toBe(2)
			t.expect(g.wave).toBe(2)
			t.expect(g.phase).toBe("playing")
			t.expect(g.formation.live).toBe(55)
			t.expect(g.formation.d).toBe(CFG.firstDepth - F.rowStep)
			t.expect(Barriers.count(g.barriers)).toBe(4 * 48)
			t.expect(g.lives).toBe(3)
			t.expect(g.cannon).toBe(CFG.cannonStart)
			t.expect(g.reloadElapsed).toBe(0)
			t.expect(g.nextSlot).toBe(1)
			t.expect(g.mystery.x).toBe(nil)
			t.expect(g.mystery.elapsed).toBe(0)
			t.expect(g.mystery.nextDir).toBe(1)
			t.expect(g.timer).toBe(0)
		end
	)

	it("lets the clear win over a cannon hit in the same tick", function()
		local g = Classic.new(1)
		g.reloadElapsed = -100000
		g.formation.elapsed = -100000
		lastOne(g, 1, 6)
		local _, d0 = Formation.box(g.formation, 1, 6)
		local x0, _, x1 = Formation.box(g.formation, 1, 6)
		-- the cannon's shot reaches the last alien this tick, and a bomb reaches the cannon this tick
		g.shot = { x = (x0 + x1) // 2, d = d0 - CFG.shotSpeed }
		table.insert(g.bombs, { x = g.cannon, d = CFG.cannonDepth, slot = 2 })
		local e = run(g, 1)
		t.expect(kinds(e)).toEqual({ "AlienHit", "WaveClear" })
		t.expect(g.lives).toBe(3)
		t.expect(g.phase).toBe("waveclear")
		t.expect(#g.bombs).toBe(0)
		local later = run(g, CFG.waveClearTicks)
		t.expect(kinds(later)).toEqual({ "WaveStart" })
		t.expect(g.wave).toBe(2)
		t.expect(g.formation.live).toBe(55)
	end)

	it("starts each wave one row closer, back to the first depth after 8", function()
		t.expect(CFG.firstDepth).toBe(120)
		local depths = {}
		for wave = 1, 17 do
			table.insert(depths, Classic.waveDepth(wave))
		end
		t.expect(depths)
			.toEqual({ 120, 112, 104, 96, 88, 80, 72, 64, 120, 112, 104, 96, 88, 80, 72, 64, 120 })
		-- in the game, clearing wave 8 brings wave 9 at wave 1's depth
		local g = Classic.new(1)
		g.wave = 8
		g.reloadElapsed = -100000
		g.formation.elapsed = -100000
		lastOne(g, 1, 6)
		g.cannon = 112
		run(g, 1, { fire = true })
		run(g, 40 + CFG.waveClearTicks)
		t.expect(g.wave).toBe(9)
		t.expect(g.formation.d).toBe(Classic.waveDepth(1))
	end)

	it("starts every wave more than one advance above the base line", function()
		for wave = 1, 8 do
			t.expect(Classic.waveDepth(wave) > CFG.invasionDepth + F.rowStep).toBe(true)
		end
	end)
end)
