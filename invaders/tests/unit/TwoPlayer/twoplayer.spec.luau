--!strict
local TwoPlayer = require("@logic/TwoPlayer")
local t = require("@tests/lib/t")

return t.spec("TwoPlayer", function(it)
	it("maps player 1 and player 2 coordinates and boxes at all four corners", function()
		local m = TwoPlayer.new(42)
		local w = m.config.pair.fieldWidth
		local depth = m.config.fieldDepth

		local corners = {
			{ 0, 0 },
			{ w - 1, 0 },
			{ 0, depth - 1 },
			{ w - 1, depth - 1 },
		}
		for _, pt in corners do
			local x, d = pt[1], pt[2]
			local x1, d1 = TwoPlayer.toField(m, 1, x, d)
			t.expect({ x1, d1 }).toEqual({ x, d })

			local x2, d2 = TwoPlayer.toField(m, 2, x, d)
			t.expect({ x2, d2 }).toEqual({ w - 1 - x, depth - 1 - d })

			local rx, rd = TwoPlayer.toField(m, 2, x2, d2)
			t.expect({ rx, rd }).toEqual({ x, d })

			local b1x0, b1d0, b1x1, b1d1 = TwoPlayer.fieldBox(m, 1, x, d, x + 1, d + 1)
			t.expect({ b1x0, b1d0, b1x1, b1d1 }).toEqual({ x, d, x + 1, d + 1 })

			local b2x0, b2d0, b2x1, b2d1 = TwoPlayer.fieldBox(m, 2, x, d, x + 1, d + 1)
			t.expect({ b2x0, b2d0, b2x1, b2d1 }).toEqual({ w - (x + 1), depth - (d + 1), w - x, depth - d })
		end
	end)

	it("tracks flyerBox before, at, and after its midline turn and on arrival", function()
		local m = TwoPlayer.new(99)
		local fl = m.flyers[1]
		local fly = m.config.flyIn
		local w = m.config.pair.fieldWidth

		-- Start of flight (tick 0): at east entry on the midline lane
		m.flyTick = fl.start
		local sx0, sd0, _, _, sArrived = TwoPlayer.flyerBox(m, fl)
		t.expect(sx0).toBe(w)
		t.expect(sd0).toBe(fly.lane)
		t.expect(sArrived).toBe(false)

		-- Before turn: moving west along the midline lane
		m.flyTick = fl.start + 1
		local bx0, bd0, _, _, bArrived = TwoPlayer.flyerBox(m, fl)
		t.expect(bx0).toBe(w - fly.speed)
		t.expect(bd0).toBe(fly.lane)
		t.expect(bArrived).toBe(false)

		-- Advance to arrival to read target coordinates
		m.flyTick = fl.start + 1000
		local tx0, td0, _, _, tArrived = TwoPlayer.flyerBox(m, fl)
		t.expect(tArrived).toBe(true)

		-- After turn: x is fixed at tx0 and d is moving from fly.lane toward td0
		local across = w - tx0
		local turnTick = fl.start + math.ceil(across / fly.speed) + 1
		m.flyTick = turnTick
		local ax0, ad0, _, _, aArrived = TwoPlayer.flyerBox(m, fl)
		t.expect(ax0).toBe(tx0)
		t.expect(ad0 ~= fly.lane).toBe(true)
		t.expect(aArrived).toBe(false)
	end)

	it("reports phaseOf for playing, dying, gameover, and out, and rejects unknown players in revive/retire", function()
		local m = TwoPlayer.new(99)
		t.expect(TwoPlayer.phaseOf(m, 1)).toBe("playing")
		m.sides[1].run.phase = "dying"
		t.expect(TwoPlayer.phaseOf(m, 1)).toBe("dying")
		m.sides[1].run.phase = "gameover"
		t.expect(TwoPlayer.phaseOf(m, 1)).toBe("gameover")

		t.expect(TwoPlayer.revive(m, 0)).toBe(false)
		t.expect(TwoPlayer.revive(m, 3)).toBe(false)
		t.expect(TwoPlayer.retire(m, 0)).toBe(false)
		t.expect(TwoPlayer.retire(m, 3)).toBe(false)

		t.expect(TwoPlayer.retire(m, 1)).toBe(true)
		t.expect(TwoPlayer.phaseOf(m, 1)).toBe("out")
	end)

	it("starts wave 1 in flyin with two 5x8 groups and transitions to playing deterministically", function()
		local a = TwoPlayer.new(99)
		local b = TwoPlayer.new(99)
		t.expect(a.phase).toBe("flyin")
		t.expect(a.wave).toBe(1)
		t.expect(#a.sides).toBe(2)
		t.expect(a.sides[1].run.config.formation.cols).toBe(8)
		t.expect(a.sides[2].run.config.formation.cols).toBe(8)
		t.expect(#a.flyers).toBe(80)

		for _ = 1, 500 do
			TwoPlayer.step(a, {})
			TwoPlayer.step(b, {})
			if a.phase == "playing" then
				break
			end
		end
		t.expect(a.phase).toBe("playing")
		t.expect(b.phase).toBe("playing")
		t.expect(#a.flyers).toBe(0)
	end)
end)
