--!strict
-- Flow rank line: rules the acceptance spec does not pin.
local Flow = require("@logic/Flow")
local t = require("@tests/lib/t")

return t.spec("Flow rank extras", function(it)
	it("a rank with a fraction or a huge value is not a line", function()
		t.expect(Flow.rankLine(2.5)).toBe(nil)
		t.expect(Flow.rankLine(math.huge)).toBe(nil)
		t.expect(Flow.rankLine(1)).toBe("ALL-TIME #1")
	end)

	it("no edge returns the same view in either state", function()
		local view: Flow.RankView = { over = 3 }
		local a, aBit = Flow.follow(view, false, false)
		t.expect(a).toBe(view)
		t.expect(aBit).toBe(false)
		local b, bBit = Flow.follow(view, true, true)
		t.expect(b).toBe(view)
		t.expect(bBit).toBe(true)
	end)

	it("a second early packet for the same next run replaces the first", function()
		local view: Flow.RankView = { over = 0 }
		view = Flow.hearRank(view, 1, 7, false)
		view = Flow.hearRank(view, 1, 4, false)
		local opened = Flow.follow(view, true, false)
		t.expect(Flow.shownRank(opened, true)).toBe("ALL-TIME #4")
	end)
end)
