--!strict
-- Hiscores: rules the acceptance specs do not pin.
local Hiscores = require("@logic/Hiscores")
local t = require("@tests/lib/t")

local FRI = 1792108800

return t.spec("Hiscores extras", function(it)
	it("the week key never moves forward within a UTC week and rolls on Monday", function()
		local monday = 1791763200
		for day = 0, 6 do
			t.expect(Hiscores.weekKey(monday + day * 86400 + 86399)).toBe("2026-10-12")
		end
		t.expect(Hiscores.weekKey(monday + 7 * 86400)).toBe("2026-10-19")
		t.expect(Hiscores.weekKey(monday - 1)).toBe("2026-10-05")
	end)

	it("a name is cut by characters, not bytes, and a non-string is the placeholder", function()
		local long = string.rep("é", 25)
		local chars = utf8.len(Hiscores.cleanName(long))
		t.expect(chars).toBe(20)
		t.expect(Hiscores.cleanName(42)).toBe("Player")
		t.expect(Hiscores.cleanName("")).toBe("Player")
	end)

	it("rankOf finds a user id and nothing else", function()
		local rows: any = {
			{ rank = 1, name = "A", userId = "1", score = 9, level = 1 },
			{ rank = 2, name = "B", userId = "15", score = 8, level = 1 },
		}
		t.expect(Hiscores.rankOf(rows, "15")).toBe(2)
		t.expect(Hiscores.rankOf(rows, "5")).toBe(nil)
	end)

	it("a submit that qualifies on one board only writes that board", function()
		local store = Hiscores.fake()
		Hiscores.submit(store, { userId = "7", score = 50, level = 2, name = "Ada" }, FRI)
		-- the next day: the all-time row stands, the day board is new
		local wrote =
			Hiscores.submit(store, { userId = "7", score = 40, level = 9, name = "Ada" }, FRI + 86400)
		t.expect(wrote.all).toBe(false)
		t.expect(wrote.day).toBe(true)
		t.expect(wrote.week).toBe(false)
	end)

	it("a zero budget is never spent and a positive one is reduced", function()
		local ok, left = Hiscores.spend(3, 0)
		t.expect(ok).toBe(false)
		t.expect(left).toBe(3)
		local spent, rest = Hiscores.spend(3, 3)
		t.expect(spent).toBe(true)
		t.expect(rest).toBe(0)
	end)
end)
