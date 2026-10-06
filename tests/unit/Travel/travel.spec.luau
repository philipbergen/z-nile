--!strict
-- Travel: rules the acceptance spec does not pin.
local Travel = require("@logic/Travel")
local t = require("@tests/lib/t")

return t.spec("Travel extras", function(it)
	it("digits beyond the largest place id are not a destination, even where tonumber rounds them", function()
		-- 2^53 + 1 reads back as 2^53, one past MAX_PLACE_ID
		t.expect(Travel.destination("9007199254740993")).toBe(nil)
		t.expect(Travel.destination("9007199254740992")).toBe(nil)
		t.expect(Travel.destination("9007199254740991")).toBe(Travel.MAX_PLACE_ID)
	end)

	it("a timed-out request cools down from the moment the timeout is seen", function()
		-- the server looks once a second, so this is at most a second later than the deadline
		local tr = Travel.new()
		Travel.request(tr, "a", 0) -- the cap is at 60
		t.expect(Travel.status(tr, "a", 100)).toBe("cooling")
		t.expect(Travel.status(tr, "a", 102.9)).toBe("cooling")
		t.expect(Travel.status(tr, "a", 103)).toBe("idle")
	end)
end)
