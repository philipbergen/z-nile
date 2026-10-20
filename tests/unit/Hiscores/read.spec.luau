--!strict
-- Hiscores board read: rules the acceptance spec does not pin.
local Hiscores = require("@logic/Hiscores")
local t = require("@tests/lib/t")

return t.spec("Hiscores read extras", function(it)
	it("the failure wait doubles from the gap and never passes the ttl", function()
		t.expect(Hiscores.failureWait(1, 15, 0)).toBe(1)
		t.expect(Hiscores.failureWait(1, 15, 3)).toBe(8)
		t.expect(Hiscores.failureWait(2, 7, 2)).toBe(7)
	end)

	it("a fetch is called once for a stale cache and its rows are cached", function()
		local calls = 0
		local rows: { Hiscores.Row } = { { rank = 1, name = "A", userId = "1", score = 3, level = 1 } }
		local cache, got = Hiscores.lookup(nil, 100, 15, 1, false, function()
			calls += 1
			return rows
		end, nil)
		t.expect(calls).toBe(1)
		t.expect(got).toBe(rows)
		t.expect((cache :: Hiscores.CacheEntry).at).toBe(100)
		local again = Hiscores.lookup(cache, 101, 15, 1, false, function()
			calls += 1
			return nil
		end, nil)
		t.expect(calls).toBe(1)
		t.expect(again).toBe(cache)
	end)

	it("no fetch function keeps everything as it was", function()
		local failure: Hiscores.Failure = { at = 0, count = 1 }
		local cache, rows, kept = Hiscores.lookup(nil, 50, 15, 1, false, nil, failure)
		t.expect(cache).toBe(nil)
		t.expect(rows).toBe(nil)
		t.expect(kept).toBe(failure)
	end)
end)
