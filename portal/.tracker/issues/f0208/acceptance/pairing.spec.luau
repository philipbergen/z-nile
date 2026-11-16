--!strict
-- f0208 AC2: the 2 PLAYERS waiting lines of one portal server (Logic/Pairing) and the shared arenas (Logic/Arena).
-- A player waits in one line at most; the second player to join a title's line is paired with the first waiting
-- there, and both leave it; lines are per title. An ARENA player joins the arena on record while it has had fewer
-- than CAP players sent and opened less than OPEN_SECONDS ago, else opens a new one; a record that makes no sense is
-- no arena. Nothing mutates its input.
local Arena = require("@logic/Arena")
local Pairing = require("@logic/Pairing")
local t = require("@tests/lib/t")

local function snapshot(q: any): string
	local names = {}
	for name, line in q.lines do
		table.insert(names, `{name}={table.concat(line, ",")}`)
	end
	table.sort(names)
	return table.concat(names, ";")
end

return t.spec("f0208 Pairing and Arena", function(it)
	it("the first player to join a line waits there", function()
		local q, pair = Pairing.join(Pairing.new(), "invaders", "1")
		t.expect(pair).toBe(nil)
		t.expect(Pairing.count(q, "invaders")).toBe(1)
		t.expect(Pairing.line(q, "1")).toBe("invaders")
		t.expect(Pairing.count(q, "asteroids")).toBe(0)
	end)

	it("the second player is paired with the first, in that order, and both leave the line", function()
		local q = Pairing.join(Pairing.new(), "invaders", "1")
		local after, pair = Pairing.join(q, "invaders", "2")
		t.expect(pair).toEqual({ "1", "2" })
		t.expect(Pairing.count(after, "invaders")).toBe(0)
		t.expect(Pairing.line(after, "1")).toBe(nil)
		t.expect(Pairing.line(after, "2")).toBe(nil)
	end)

	it("a third player after a pair waits for the next one", function()
		local q = Pairing.join(Pairing.new(), "invaders", "1")
		q = Pairing.join(q, "invaders", "2")
		local after, pair = Pairing.join(q, "invaders", "3")
		t.expect(pair).toBe(nil)
		t.expect(Pairing.line(after, "3")).toBe("invaders")
	end)

	it("lines are per title: a player waiting on Asteroids is not paired with one on Invaders", function()
		local q = Pairing.join(Pairing.new(), "invaders", "1")
		local after, pair = Pairing.join(q, "asteroids", "2")
		t.expect(pair).toBe(nil)
		t.expect(Pairing.count(after, "invaders")).toBe(1)
		t.expect(Pairing.count(after, "asteroids")).toBe(1)
	end)

	it("a player waits in one line at most: joining another leaves the first", function()
		local q = Pairing.join(Pairing.new(), "invaders", "1")
		q = Pairing.join(q, "asteroids", "1")
		t.expect(Pairing.count(q, "invaders")).toBe(0)
		t.expect(Pairing.line(q, "1")).toBe("asteroids")
		local _, pair = Pairing.join(q, "invaders", "2")
		t.expect(pair).toBe(nil)
	end)

	it("a player is never paired with themself", function()
		local q = Pairing.join(Pairing.new(), "invaders", "1")
		local after, pair = Pairing.join(q, "invaders", "1")
		t.expect(pair).toBe(nil)
		t.expect(Pairing.count(after, "invaders")).toBe(1)
	end)

	it("leaving takes a player out of their line; leaving with none changes nothing", function()
		local q = Pairing.join(Pairing.new(), "invaders", "1")
		q = Pairing.join(q, "asteroids", "2")
		local after = Pairing.leave(q, "1")
		t.expect(Pairing.count(after, "invaders")).toBe(0)
		t.expect(Pairing.count(after, "asteroids")).toBe(1)
		t.expect(snapshot(Pairing.leave(after, "9"))).toBe(snapshot(after))
		local _, pair = Pairing.join(after, "invaders", "3")
		t.expect(pair).toBe(nil)
	end)

	it("nothing mutates the queue it is given", function()
		local q = Pairing.join(Pairing.new(), "invaders", "1")
		local before = snapshot(q)
		Pairing.join(q, "invaders", "2")
		Pairing.join(q, "asteroids", "1")
		Pairing.leave(q, "1")
		t.expect(snapshot(q)).toBe(before)
	end)

	it("the arenas: 24 players each, open for 600 s, in the PortalArenas map", function()
		t.expect(Arena.CAP).toBe(24)
		t.expect(Arena.OPEN_SECONDS).toBe(600)
		t.expect(Arena.MAP).toBe("PortalArenas")
	end)

	it("with no arena on record the player opens one with the fresh id", function()
		t.expect(Arena.join(nil, "fresh", 1000)).toEqual({ id = "fresh", count = 1, opened = 1000 })
		t.expect(Arena.open(nil, 1000)).toBe(nil)
	end)

	it("an open arena takes the player: one more sent, the same id and opening", function()
		local r = { id = "a1", count = 5, opened = 900 }
		t.expect(Arena.join(r, "fresh", 1000)).toEqual({ id = "a1", count = 6, opened = 900 })
		t.expect(Arena.open(r, 1000)).toEqual(r)
	end)

	it("an arena takes players until CAP were sent", function()
		t.expect(Arena.join({ id = "a1", count = 23, opened = 900 }, "fresh", 1000))
			.toEqual({ id = "a1", count = 24, opened = 900 })
		t.expect(Arena.join({ id = "a1", count = 24, opened = 900 }, "fresh", 1000))
			.toEqual({ id = "fresh", count = 1, opened = 1000 })
	end)

	it("an arena takes players for OPEN_SECONDS after it opened, not a second more", function()
		t.expect(Arena.join({ id = "a1", count = 1, opened = 1000 }, "fresh", 1599).id).toBe("a1")
		t.expect(Arena.join({ id = "a1", count = 1, opened = 1000 }, "fresh", 1600))
			.toEqual({ id = "fresh", count = 1, opened = 1600 })
	end)

	it(
		"an arena opened up to SKEW_SECONDS after now (another server's clock ahead) counts as open; further is not",
		function()
			t.expect(Arena.SKEW_SECONDS).toBe(30)
			t.expect(Arena.join({ id = "a1", count = 1, opened = 1001 }, "fresh", 1000).id).toBe("a1")
			t.expect(Arena.join({ id = "a1", count = 1, opened = 1030 }, "fresh", 1000).id).toBe("a1")
			t.expect(Arena.join({ id = "a1", count = 1, opened = 1031 }, "fresh", 1000).id).toBe("fresh")
		end
	)

	it("a stored record that makes no sense is no arena", function()
		for _, bad in
			{
				{ id = "", count = 1, opened = 900 },
				{ id = 7, count = 1, opened = 900 },
				{ id = "a1", count = "1", opened = 900 },
				{ id = "a1", count = -1, opened = 900 },
				{ id = "a1", count = 1.5, opened = 900 },
				{ id = "a1", count = 0 / 0, opened = 900 },
				{ id = "a1", count = 1, opened = 900.5 },
				{ id = "a1", count = 1 },
				"a1",
				5,
			} :: { any }
		do
			t.expect(Arena.open(bad, 1000)).toBe(nil)
			t.expect(Arena.join(bad, "fresh", 1000).id).toBe("fresh")
		end
	end)

	it("nothing mutates the record it is given", function()
		local r = { id = "a1", count = 5, opened = 900 }
		Arena.join(r, "fresh", 1000)
		t.expect(r).toEqual({ id = "a1", count = 5, opened = 900 })
	end)
end)
