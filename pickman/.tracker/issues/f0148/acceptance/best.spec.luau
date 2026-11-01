--!strict
-- f0148 AC1: the rules of the best level, engine-free (Logic/Best). A player's record holds the best level reached
-- (the user, 2026-11-01: "Highest reached") and the start they chose in the lobby; a run may start on any level from 1
-- to the best; the game place claims the choice once, and anything not allowed starts on level 1. The lobby's picker
-- shows once there is a choice, starts on the best (the user: "Your best"), and steps within 1..best.
local Best = require("@logic/Best")
local t = require("@tests/lib/t")

return t.spec("f0148 the best level", function(it)
	it("the store and the attribute have one name each, shared by the lobby and the game place", function()
		t.expect(Best.STORE).toBe("PickmanBest")
		t.expect(Best.ATTRIBUTE).toBe("PickmanBest")
	end)

	it("a stored value reads back as a record of whole levels, and anything else as a fresh one", function()
		t.expect(Best.decode(nil)).toEqual({ best = 1 })
		t.expect(Best.decode("3")).toEqual({ best = 1 })
		t.expect(Best.decode({ best = 4 })).toEqual({ best = 4 })
		t.expect(Best.decode({ best = 4, next = 2 })).toEqual({ best = 4, next = 2 })
		for _, bad in { 0, -1, 2.5, 0 / 0, math.huge } do
			t.expect(Best.decode({ best = bad })).toEqual({ best = 1 })
			t.expect(Best.decode({ best = 3, next = bad })).toEqual({ best = 3 })
		end
	end)

	it("a run may start on a whole level from 1 to the best, and on nothing else", function()
		for level = 1, 4 do
			t.expect(Best.valid(level, 4)).toBe(level)
		end
		for _, bad in { 0, 5, 2.5, -1, 0 / 0, math.huge, "2", true } :: { any } do
			t.expect(Best.valid(bad, 4)).toBe(nil)
		end
	end)

	it("reaching a level raises the best, never lowers it, and keeps the choice", function()
		t.expect(Best.reached({ best = 3 }, 5)).toEqual({ best = 5 })
		t.expect(Best.reached({ best = 5, next = 2 }, 3)).toEqual({ best = 5, next = 2 })
		t.expect(Best.reached({ best = 1 }, 2).best).toBe(2) -- clearing level 1 reaches 2: a choice exists
	end)

	it("the lobby's choice is kept when allowed, else the best is chosen", function()
		t.expect(Best.choose({ best = 4 }, 2)).toEqual({ best = 4, next = 2 })
		t.expect(Best.choose({ best = 4 }, 4)).toEqual({ best = 4, next = 4 })
		t.expect(Best.choose({ best = 4 }, 9)).toEqual({ best = 4, next = 4 })
		t.expect(Best.choose({ best = 4 }, nil)).toEqual({ best = 4, next = 4 })
		t.expect(Best.choose({ best = 1 }, nil)).toEqual({ best = 1, next = 1 })
	end)

	it(
		"the game place claims the choice once: an allowed one, else level 1; the choice is cleared",
		function()
			local start, kept = Best.claim({ best = 4, next = 3 })
			t.expect(start).toBe(3)
			t.expect(kept).toEqual({ best = 4 })
			local again = Best.claim(kept)
			t.expect(again).toBe(1) -- claimed already: a second arrival without a new choice starts on 1
			t.expect((Best.claim({ best = 2, next = 5 }))).toBe(1) -- over the best (a stale or forged record)
			t.expect((Best.claim({ best = 1 }))).toBe(1)
		end
	)

	it(
		"the picker shows once there is a choice, starts on the best, and its arrows say which way is open",
		function()
			t.expect(Best.picker(1, nil)).toEqual({ shown = false, level = 1, down = false, up = false })
			t.expect(Best.picker(4, nil)).toEqual({ shown = true, level = 4, down = true, up = false })
			t.expect(Best.picker(4, 1)).toEqual({ shown = true, level = 1, down = false, up = true })
			t.expect(Best.picker(4, 2)).toEqual({ shown = true, level = 2, down = true, up = true })
			t.expect(Best.picker(4, 7).level).toBe(4) -- a choice over the best (a lower best read later) is the best
			t.expect(Best.picker(0 / 0, nil)).toEqual({ shown = false, level = 1, down = false, up = false })
		end
	)

	it("the arrows step one level within 1..best, starting from the best", function()
		t.expect(Best.step(4, nil, -1)).toBe(3)
		t.expect(Best.step(4, 3, -1)).toBe(2)
		t.expect(Best.step(4, 1, -1)).toBe(1)
		t.expect(Best.step(4, 4, 1)).toBe(4)
		t.expect(Best.step(4, 2, 1)).toBe(3)
		t.expect(Best.step(4, 2, 0)).toBe(2)
	end)

	it("on a keyboard Left steps lower and Right higher; no other key steps", function()
		t.expect(Best.keyStep("Left")).toBe(-1)
		t.expect(Best.keyStep("Right")).toBe(1)
		for _, other in { "A", "D", "Up", "Space", "Return", 5 :: any, nil :: any } do
			t.expect(Best.keyStep(other)).toBe(nil)
		end
	end)
end)
