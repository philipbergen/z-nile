--!strict
-- f0120 AC4: snapshot schema v1: exactly the designed fields, plain data safe to replicate, and a
-- jumpTick that tells the client when not to interpolate.
local Maze = require("@logic/Maze")
local Session = require("@logic/Session")
local serde = require("@lune/serde")
local t = require("@tests/lib/t")

local function keys(v: { [string]: any }): { string }
	local out = {}
	for k in v do
		table.insert(out, k)
	end
	table.sort(out)
	return out
end

return t.spec("f0120 snapshot schema", function(it)
	local classic = Maze.layout("classic")

	it("has exactly the v1 fields", function()
		local s = Session.new(classic, 1)
		Session.join(s, "p")
		local snap = Session.snapshot(s, "p")
		t.expect(Session.SNAPSHOT_VERSION).toBe(1)
		t.expect(keys(snap :: any)).toEqual({ "maze", "player", "tick", "v" })
		t.expect(keys(snap.player :: any)).toEqual({ "heading", "jumpTick", "moving", "x", "y" })
		t.expect(snap.v).toBe(1)
		t.expect(snap.tick).toBe(0)
		t.expect(snap.maze).toBe("classic")
		t.expect(snap.player.jumpTick).toBe(-1)
	end)

	it("round-trips through JSON unchanged", function()
		local s = Session.new(classic, 1)
		Session.join(s, "p")
		for _ = 1, 7 do
			Session.step(s)
		end
		local snap = Session.snapshot(s, "p")
		t.expect(serde.decode("json", serde.encode("json", snap))).toEqual(snap)
	end)

	it("is a fresh table: changing it does not change the session", function()
		local s = Session.new(classic, 1)
		Session.join(s, "p")
		local snap = Session.snapshot(s, "p")
		snap.player.x = 99
		snap.tick = 99
		t.expect(Session.snapshot(s, "p").player.x).toBe(13)
		t.expect(Session.snapshot(s, "p").tick).toBe(0)
	end)

	it("jumpTick is the tick of the latest position discontinuity (a2: tunnel jumps)", function()
		-- Heading west from (2,1) on a 5-wide wrapping row: the position jumps at tick 12.
		local s = Session.new(Maze.parse({ "#####", "  P  ", "#####" }, "loop"), 1)
		Session.join(s, "p")
		local seen: { [number]: number } = {}
		for tk = 1, 40 do
			local events = Session.step(s)
			local snap = Session.snapshot(s, "p")
			seen[tk] = snap.player.jumpTick
			local wrapped = false
			for _, e in events do
				wrapped = wrapped or e.kind == "Wrapped"
			end
			if wrapped then
				t.expect(snap.player.jumpTick).toBe(tk)
			end
		end
		t.expect(seen[11]).toBe(-1)
		t.expect(seen[12]).toBe(12)
		t.expect(seen[20]).toBe(12)
		t.expect(seen[32]).toBe(32)
		t.expect(Session.snapshot(s, "p").maze).toBe("loop")
	end)
end)
