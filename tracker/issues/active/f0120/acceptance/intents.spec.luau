--!strict
-- f0120 AC2: the server trusts nothing from a client. Only known intents from joined players are
-- queued, at most maxIntentsPerTick per player per tick, and queued intents apply in order.
local Maze = require("@logic/Maze")
local Session = require("@logic/Session")
local t = require("@tests/lib/t")

local classic = Maze.layout("classic")

local function fresh(): Session.Session
	local s = Session.new(classic, 1)
	Session.join(s, "p")
	return s
end

return t.spec("f0120 intent validation", function(it)
	it("accepts the four intents", function()
		for _, i in { "Left", "Right", "Back", "Forward" } do
			local ok, why = Session.submit(fresh(), "p", i)
			t.expect(ok).toBe(true)
			t.expect(why).toBe(nil)
		end
	end)

	it("rejects anything else as an invalid intent", function()
		local bad: { any } = { "left", "Jump", "", 1, true, { "Left" }, { intent = "Left" } }
		for _, v in bad do
			local ok, why = Session.submit(fresh(), "p", v)
			t.expect(ok).toBe(false)
			t.expect(why).toBe("invalid intent")
		end
		local ok, why = Session.submit(fresh(), "p", nil)
		t.expect(ok).toBe(false)
		t.expect(why).toBe("invalid intent")
	end)

	it("rejects intents for a player who has not joined", function()
		local ok, why = Session.submit(fresh(), "stranger", "Left")
		t.expect(ok).toBe(false)
		t.expect(why).toBe("unknown player")
	end)

	it("rate-limits each player per tick and resets after the step", function()
		local s = Session.new(
			classic,
			1,
			{ movement = { speed = 30, turnBufferTicks = 24 }, maxIntentsPerTick = 3 }
		)
		Session.join(s, "p")
		Session.join(s, "q")
		for _ = 1, 3 do
			t.expect((Session.submit(s, "p", "Forward"))).toBe(true)
		end
		local ok, why = Session.submit(s, "p", "Forward")
		t.expect(ok).toBe(false)
		t.expect(why).toBe("rate limited")
		t.expect((Session.submit(s, "q", "Forward"))).toBe(true)
		Session.step(s)
		t.expect((Session.submit(s, "p", "Forward"))).toBe(true)
	end)

	it("the default limit is 4 per player per tick", function()
		local s = fresh()
		for _ = 1, 4 do
			t.expect((Session.submit(s, "p", "Forward"))).toBe(true)
		end
		t.expect((Session.submit(s, "p", "Forward"))).toBe(false)
	end)

	it("rejected intents have no effect", function()
		local s = fresh()
		Session.submit(s, "p", "back")
		Session.submit(s, "p", 42)
		Session.step(s)
		t.expect(Session.snapshot(s, "p").player.heading).toBe("W")
		t.expect(Session.snapshot(s, "p").player.x).toBe(12.75)
	end)

	it("queued intents apply in the next step, in submission order", function()
		-- From the classic spawn heading west, Right (north) is taken at (12, 23) at tick 4.
		local a = fresh()
		Session.submit(a, "p", "Right")
		Session.submit(a, "p", "Forward")
		local b = fresh()
		Session.submit(b, "p", "Forward")
		Session.submit(b, "p", "Right")
		for _ = 1, 5 do
			Session.step(a)
			Session.step(b)
		end
		t.expect(Session.snapshot(a, "p").player.heading).toBe("W")
		t.expect(Session.snapshot(b, "p").player.heading).toBe("N")
		t.expect(Session.snapshot(b, "p").player.y).toBe(22.75)
	end)

	it("Back twice in one tick cancels out", function()
		local s = fresh()
		Session.submit(s, "p", "Back")
		Session.submit(s, "p", "Back")
		Session.step(s)
		t.expect(Session.snapshot(s, "p").player.heading).toBe("W")
		t.expect(Session.snapshot(s, "p").player.x).toBe(12.75)
	end)
end)
