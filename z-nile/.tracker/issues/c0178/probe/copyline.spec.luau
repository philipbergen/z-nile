--!strict
-- c0178 check-only probe (never promoted): two fixtures whose clone the seam makes fail with EXDEV, so each falls back to a copy;
-- check.sh AC3 reads the run's output for the one line that says so.
local t = require("@tests/lib/t")
local trackerfix = require("@tests/lib/trackerfix")

return t.spec("c0178 probe: a run whose fixtures were copied", function(it)
	it("makes two fixtures by the copy fallback", function()
		trackerfix.SIMULATE = "EXDEV"
		local ok, err = pcall(function()
			trackerfix.new("c0178-copyline-a", {})
			trackerfix.new("c0178-copyline-b", {})
		end)
		trackerfix.SIMULATE = nil
		if not ok then
			error(err, 0)
		end
		t.expect(true).toBe(true)
	end)
end)
