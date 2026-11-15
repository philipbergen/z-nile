--!strict
-- f0197 AC1: each title has its own stores, named from its prefix, and pickman's prefix "" keeps today's names, so
-- its boards keep their rows. The new names are reached through `:: any` so this spec type-checks before they exist.
local Hiscores = require("@logic/Hiscores")
local t = require("@tests/lib/t")

local H = Hiscores :: any
local FRI = 1792108800

return t.spec("f0197 a title's stores", function(it)
	it('AC1: the prefix "" names pickman\'s stores as they are today', function()
		local names = H.names("")
		t.expect(names.ordered).toBe("Hiscores")
		t.expect(names.companion).toBe("HiscoreEntries")
		t.expect(names.top).toBe("HiscoreTop")
		t.expect(Hiscores.TOP_SCOPE).toBe("all")
		t.expect(Hiscores.TOP_KEY).toBe("runs")
	end)

	it("AC1: another prefix names three stores of its own, none of them pickman's", function()
		local snake = H.names("Snake")
		t.expect(snake.ordered).toBe("SnakeHiscores")
		t.expect(snake.companion).toBe("SnakeHiscoreEntries")
		t.expect(snake.top).toBe("SnakeHiscoreTop")
		local seen: { [string]: boolean } = {}
		for _, prefix in { "", "Snake", "Invaders", "Asteroids", "Snake2" } do
			local names = H.names(prefix)
			for _, field in { "ordered", "companion", "top" } do
				t.expect(seen[names[field]]).toBe(nil)
				seen[names[field]] = true
			end
		end
	end)

	it(
		'AC1: a prefix is "" or a capital, then letters and digits, at most PREFIX_MAX; anything else errors',
		function()
			t.expect(H.PREFIX_MAX).toBe(20)
			local long = "A" .. string.rep("b", 19)
			t.expect(H.names(long).top).toBe(long .. "HiscoreTop")
			-- the longest name fits the engine's 50 characters
			t.expect(#H.names(long).companion <= 50).toBe(true)
			for _, bad in { "snake", "Sn ake", "Snake_", "S-1", long .. "c", "9Lives", 7, true } :: { any } do
				local ok = pcall(H.names, bad)
				t.expect(ok).toBe(false)
			end
		end
	)

	it("AC1: the names are frozen, so no caller can point a title at another's stores", function()
		local names = H.names("Snake")
		t.expect(table.isfrozen(names)).toBe(true)
	end)

	it("AC1: a board's store target is the title's store, scoped by period, or its global name", function()
		local snake = H.names("Snake")
		local ordered, scope = H.storeTarget(snake, "ordered", Hiscores.board("day", FRI), true)
		t.expect(ordered).toBe("SnakeHiscores")
		t.expect(scope).toBe("day:2026-10-16")
		local companion, allScope = H.storeTarget(snake, "companion", Hiscores.board("all", FRI), true)
		t.expect(companion).toBe("SnakeHiscoreEntries")
		t.expect(allScope).toBe("all")
		local global, globalScope = H.storeTarget(snake, "companion", Hiscores.board("week", FRI), false)
		t.expect(global).toBe("SnakeHiscoreEntries_week_2026_10_12")
		t.expect(globalScope).toBe("global")
		local pickman = H.storeTarget(H.names(""), "ordered", Hiscores.board("all", FRI), true)
		t.expect(pickman).toBe("Hiscores")
	end)
end)
