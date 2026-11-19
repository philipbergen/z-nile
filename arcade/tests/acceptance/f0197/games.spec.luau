--!strict
-- f0197 AC3: HiscoreGames lists every title's prefix (so each has stores of its own, and pickman's "" keeps today's)
-- and what its progress figure, the rows' `level`, counts. The module is absent until the raft builds it, so it is
-- required at run time and this spec type-checks before it exists.
local Hiscores = require("@logic/Hiscores")
local fs = require("@lune/fs")
local t = require("@tests/lib/t")

local H = Hiscores :: any
local FRI = 1792108800
local GAMES = "src/shared/HiscoreGames.luau"

local function games(): any
	t.expect(fs.isFile(GAMES)).toBe(true)
	return (require :: any)("@shared/HiscoreGames")
end

return t.spec("f0197 every title's boards", function(it)
	it('AC3: HiscoreGames gives every title a prefix of its own, and pickman\'s is ""', function()
		local g = games()
		local titles: { string } = {}
		for title in g do
			table.insert(titles, title)
		end
		table.sort(titles)
		t.expect(titles).toEqual({ "asteroids", "invaders", "pickman", "snake" })
		t.expect(g.pickman.prefix).toBe("")
		t.expect(g.snake.prefix).toBe("Snake")
		t.expect(g.invaders.prefix).toBe("Invaders")
		t.expect(g.asteroids.prefix).toBe("Asteroids")
		local seen: { [string]: boolean } = {}
		for _, title in titles do
			local prefix = g[title].prefix
			t.expect(seen[prefix]).toBe(nil)
			seen[prefix] = true
			t.expect((pcall(H.names, prefix))).toBe(true)
		end
		t.expect(table.isfrozen(g)).toBe(true)
		t.expect(table.isfrozen(g.snake)).toBe(true)
	end)

	it(
		"AC3: each title's progress figure is named: Pickman's level, Snake's map, Invaders' and Asteroids' wave",
		function()
			local g = games()
			t.expect(g.pickman.progress).toBe("Level")
			t.expect(g.snake.progress).toBe("Map")
			t.expect(g.invaders.progress).toBe("Wave")
			t.expect(g.asteroids.progress).toBe("Wave")
		end
	)

	it("AC3: the progress figure is stored with the row as its level, whatever the title", function()
		local store = Hiscores.fake()
		Hiscores.submit(store, { userId = "7", name = "Ada", score = 90, level = 6, revives = 1 } :: any, FRI)
		local row = Hiscores.top(store, "all", FRI)[1]
		t.expect(row.level).toBe(6)
		t.expect((store.get(Hiscores.board("all", FRI), "7") :: any).level).toBe(6)
	end)
end)
