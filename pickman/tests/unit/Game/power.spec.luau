--!strict
-- Game: a power period lengthened by a factor (f0126's long ghost pill).
local Game = require("@logic/Game")
local t = require("@tests/lib/t")

return t.spec("Game power factor", function(it)
	it("a factor multiplies the level's frightened time, and none is the time itself", function()
		local g = Game.new(Game.IMMEDIATE_CONFIG)
		Game.power(g)
		local base = g.frightened
		t.expect(base > 0).toBe(true)
		Game.power(g, 2)
		t.expect(g.frightened).toBe(2 * base)
		Game.power(g, 1)
		t.expect(g.frightened).toBe(base)
	end)
end)
