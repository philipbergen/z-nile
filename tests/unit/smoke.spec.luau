--!strict
-- Proves the runner and assertion library work end to end.
local t = require("@tests/lib/t")

return t.spec("smoke", function(it)
	it("compares values", function()
		t.expect(1 + 1).toBe(2)
		t.expect({ a = { 1, 2 } }).toEqual({ a = { 1, 2 } })
		t.expect(0.1 + 0.2).toBeNear(0.3)
	end)

	it("detects throws", function()
		t.expect(function()
			error("boom")
		end).toThrow("boom")
	end)
end)
