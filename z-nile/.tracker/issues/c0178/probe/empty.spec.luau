--!strict
-- c0178 check-only probe: the same run without fixtures, the baseline that AC2 subtracts.
local t = require("@tests/lib/t")

return t.spec("c0178 probe: no fixtures", function(it)
	it("makes nothing", function()
		t.expect(true).toBe(true)
	end)
end)
