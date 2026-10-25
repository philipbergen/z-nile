--!strict
-- f0310: the client draws the ghosts between two snapshots the way it draws the player: a blend by the
-- elapsed real time, no blending across a jump (a tunnel wrap, a reset), the look and heading from the
-- latest snapshot.
local Session = require("@logic/Session")
local View = require("@logic/View")
local t = require("@tests/lib/t")

local function ghost(name: string, x: number, y: number, jump: number?, look: string?): Session.GhostSnapshot
	return {
		name = name :: any,
		x = x,
		y = y,
		heading = "E",
		look = (look or "normal") :: any,
		flash = false,
		jumpTick = jump or -1,
	}
end

local function snap(tick: number, ghosts: { Session.GhostSnapshot }?): Session.Snapshot
	return {
		v = 1,
		tick = tick,
		maze = "classic",
		player = { x = 1, y = 1, heading = "E", moving = true, jumpTick = -1 },
		ghosts = ghosts,
	}
end

return t.spec("f0310 View.interpolateGhosts", function(it)
	it("blends each ghost between the two snapshots by alpha", function()
		local prev = snap(10, { ghost("blinky", 4, 5), ghost("pinky", 10, 10) })
		local latest = snap(11, { ghost("blinky", 5, 5), ghost("pinky", 10, 12) })
		local halfway = View.interpolateGhosts(prev, latest, 0.5)
		t.expect(#halfway).toBe(2)
		t.expect(halfway[1].x).toBe(4.5)
		t.expect(halfway[1].y).toBe(5)
		t.expect(halfway[2].x).toBe(10)
		t.expect(halfway[2].y).toBe(11)
		t.expect(View.interpolateGhosts(prev, latest, 0)[1].x).toBe(4)
		t.expect(View.interpolateGhosts(prev, latest, 1)[1].x).toBe(5)
	end)

	it("clamps alpha to 0..1 and treats a missing alpha as arrived", function()
		local prev = snap(10, { ghost("blinky", 4, 5) })
		local latest = snap(11, { ghost("blinky", 5, 5) })
		t.expect(View.interpolateGhosts(prev, latest, -3)[1].x).toBe(4)
		t.expect(View.interpolateGhosts(prev, latest, 7)[1].x).toBe(5)
		t.expect(View.interpolateGhosts(prev, latest, 0 / 0)[1].x).toBe(5)
	end)

	it(
		"does not blend across a jump: a ghost that wrapped through a tunnel or was reset is shown where it is",
		function()
			local prev = snap(10, { ghost("blinky", 0.5, 14), ghost("pinky", 10, 10) })
			local latest = snap(11, { ghost("blinky", 26.5, 14, 11), ghost("pinky", 10, 11) })
			local mid = View.interpolateGhosts(prev, latest, 0.5)
			t.expect(mid[1].x).toBe(26.5) -- jumped: no sliding across the maze
			t.expect(mid[2].y).toBe(10.5) -- the other one still blends
			-- a jump that is older than the previous snapshot no longer matters
			local settled = snap(11, { ghost("blinky", 26, 14, 9) })
			t.expect(View.interpolateGhosts(snap(10, { ghost("blinky", 27, 14) }), settled, 0.5)[1].x)
				.toBe(26.5)
		end
	)

	it("with no previous snapshot, or one that is not older, shows the latest as it is", function()
		local latest = snap(11, { ghost("blinky", 5, 5) })
		t.expect(View.interpolateGhosts(nil, latest, 0.5)[1].x).toBe(5)
		t.expect(View.interpolateGhosts(snap(11, { ghost("blinky", 1, 1) }), latest, 0.5)[1].x).toBe(5)
		t.expect(View.interpolateGhosts(snap(12, { ghost("blinky", 1, 1) }), latest, 0.5)[1].x).toBe(5)
	end)

	it("takes the look, the flash and the heading from the latest snapshot", function()
		local prev = snap(10, { ghost("blinky", 4, 5, nil, "frightened") })
		local latestGhost = ghost("blinky", 5, 5, nil, "blinking")
		latestGhost.flash = true
		latestGhost.heading = "S"
		local out = View.interpolateGhosts(prev, snap(11, { latestGhost }), 0.5)
		t.expect(out[1].look).toBe("blinking")
		t.expect(out[1].flash).toBe(true)
		t.expect(out[1].heading).toBe("S")
	end)

	it("a snapshot without ghosts gives none, and a changed ghost list is not blended by position", function()
		t.expect(View.interpolateGhosts(snap(10), snap(11), 0.5)).toEqual({})
		local prev = snap(10, { ghost("pinky", 4, 5) })
		local latest = snap(11, { ghost("blinky", 5, 5) })
		t.expect(View.interpolateGhosts(prev, latest, 0.5)[1].x).toBe(5)
	end)
end)
