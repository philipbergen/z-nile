--!strict
local Classic = require("@logic/Classic")
local t = require("@tests/lib/t")

return t.spec("Classic", function(it)
	it("computes wave rock counts up to maxRocks", function()
		local c = Classic.CONFIG
		t.expect(Classic.rockCount(c, 1)).toBe(4)
		t.expect(Classic.rockCount(c, 2)).toBe(6)
		t.expect(Classic.rockCount(c, 3)).toBe(8)
		t.expect(Classic.rockCount(c, 4)).toBe(10)
		t.expect(Classic.rockCount(c, 5)).toBe(11)
		t.expect(Classic.rockCount(c, 10)).toBe(11)
	end)

	it("starts a deterministic wave 1 at centre and freezes on gameover", function()
		local a = Classic.new(42)
		local b = Classic.new(42)
		t.expect(a.phase).toBe("playing")
		t.expect(a.wave).toBe(1)
		t.expect(a.lives).toBe(3)
		t.expect(#a.rocks).toBe(4)
		t.expect(a.ship.x).toBe(Classic.CONFIG.field.width / 2)
		t.expect(a.ship.y).toBe(Classic.CONFIG.field.height / 2)
		t.expect(a.rocks[1].x).toBe(b.rocks[1].x)
		t.expect(a.rocks[1].y).toBe(b.rocks[1].y)

		local evA = Classic.step(a, { fire = true })
		local evB = Classic.step(b, { fire = true })
		t.expect(#evA).toBe(#evB)
		t.expect(evA[1].kind).toBe("Fire")
		t.expect(#a.shots).toBe(1)

		a.phase = "gameover"
		local snapScore = a.score
		local evOver = Classic.step(a, { fire = true, thrust = true })
		t.expect(#evOver).toBe(0)
		t.expect(a.score).toBe(snapScore)
	end)

	it("advances waves after clearing all rocks", function()
		local g = Classic.new(7)
		g.rocks = {}
		local clearEvents = Classic.step(g, nil)
		local sawClear = false
		for _, e in clearEvents do
			if e.kind == "WaveClear" and e.wave == 1 then
				sawClear = true
			end
		end
		t.expect(sawClear).toBe(true)
		t.expect(g.waveTimer).toBe(Classic.CONFIG.waveTicks)

		local sawStart = false
		for _ = 1, Classic.CONFIG.waveTicks do
			local evs = Classic.step(g, nil)
			for _, e in evs do
				if e.kind == "WaveStart" and e.wave == 2 then
					sawStart = true
				end
			end
		end
		t.expect(sawStart).toBe(true)
		t.expect(g.wave).toBe(2)
		t.expect(#g.rocks).toBe(6)
	end)
end)
