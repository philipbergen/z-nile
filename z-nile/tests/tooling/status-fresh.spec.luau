--!strict
-- R0025 review 004 F1: a claim stamp must be new on origin/main. status.fresh redraws until `taken` rejects no value,
-- and gives up (nil) after its bound instead of looping forever.
local status = require("@scripts/tracker/status")
local t = require("@tests/lib/t")

local function drawer(values: { string }): (() -> string, () -> number)
	local i = 0
	return function(): string
		i += 1
		return values[i] or "active-x-x-x"
	end, function(): number
		return i
	end
end

return t.spec("status.fresh", function(it)
	it("returns the first draw that is not taken", function()
		local draw, calls = drawer({ "active-a-a-a", "active-b-b-b", "active-c-c-c" })
		local taken = { ["active-a-a-a"] = true, ["active-b-b-b"] = true }
		t.expect(status.fresh(draw, function(v)
			return taken[v] == true
		end)).toBe("active-c-c-c")
		t.expect(calls()).toBe(3)
	end)

	it("takes the first draw when nothing is taken", function()
		local draw, calls = drawer({ "active-a-a-a" })
		t.expect(status.fresh(draw, function()
			return false
		end)).toBe("active-a-a-a")
		t.expect(calls()).toBe(1)
	end)

	it("gives up after its bound", function()
		local draw, calls = drawer({})
		t.expect(status.fresh(draw, function()
			return true
		end, 7)).toBe(nil)
		t.expect(calls()).toBe(7)
	end)

	it("the real stamp keeps its shape", function()
		local n = 0
		local v = status.stamp("active", function(max: number): number
			n += 1
			return ((n - 1) % max) + 1
		end)
		t.expect(string.match(v, "^active%-%a+%-%a+%-%a+$") ~= nil).toBe(true)
	end)
end)
