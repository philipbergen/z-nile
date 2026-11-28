--!strict
local TwoPlayer = require("@logic/TwoPlayer")
local t = require("@tests/lib/t")

return t.spec("TwoPlayer", function(it)
	it("starts wave 1 with 1.5x rocks and two pilots at opposite homes deterministically", function()
		local a = TwoPlayer.new(42)
		local b = TwoPlayer.new(42)
		t.expect(a.phase).toBe("playing")
		t.expect(a.wave).toBe(1)
		t.expect(#a.pilots).toBe(2)
		t.expect(#a.rocks).toBe(6)
		t.expect(a.pilots[1].ship.x ~= a.pilots[2].ship.x).toBe(true)
		t.expect(a.rocks[1].x).toBe(b.rocks[1].x)
		t.expect(a.rocks[1].y).toBe(b.rocks[1].y)

		local evA = TwoPlayer.step(a, { { fire = true }, { thrust = true } })
		local evB = TwoPlayer.step(b, { { fire = true }, { thrust = true } })
		t.expect(#evA).toBe(#evB)
		t.expect(#a.pilots[1].shots).toBe(1)
	end)

	it("handles leave and revive cleanly", function()
		local m = TwoPlayer.new(7)
		t.expect(TwoPlayer.leave(m, 2)).toBe(true)
		t.expect(m.pilots[2].left).toBe(true)
		t.expect(m.phase).toBe("playing")
		-- leaving again is a no-op
		t.expect(TwoPlayer.leave(m, 2)).toBe(false)
		-- revive refused while pilot 1 is still alive
		t.expect(TwoPlayer.revive(m, 1)).toBe(false)
	end)
end)
