--!strict
-- f0126 AC7 (the ghosts): a restless picker in the classic maze, played seed by seed until the case's moment comes.
-- A ghost that reaches a picking player catches them and wastes the pick ("caught"); the ghosts keep walking while
-- the player stands; and ghosts walk into holes (eaten.spec has a blue ghost met while picking).
local Maze = require("@logic/Maze")
local Movement = require("@logic/Movement")
local Session = require("@logic/Session")
local t = require("@tests/lib/t")

local classic = Maze.layout("classic")
local CONFIG: Session.Config = { movement = Movement.DEFAULT_CONFIG, maxIntentsPerTick = 4, ghosts = true }

local function new(seed: number): Session.Session
	local s = Session.new(classic, seed, CONFIG)
	Session.join(s, "p")
	return s
end

local TURNS = { "Left", "Right", "Back", "Left", "Right" }

-- Plays a seed as a restless picker: asks for a pick every step and, while no pick is under way, turns at random
-- (a seeded generator of the spec's own) every 9 steps; it presses nothing while picking. `watch` sees every step
-- (the frame before it, its events, the frame after) and returns true to stop. Ends at the first death.
local function drive(
	seed: number,
	limit: number,
	watch: (
		before: Session.Frame,
		events: { Session.Event },
		after: Session.Frame,
		s: Session.Session
	) -> boolean
): boolean
	local s = new(seed)
	local r = seed
	local before = Session.frame(s, "p")
	for k = 1, limit do
		if before.pick == nil then
			Session.submit(s, "p", "Pick")
			if k % 9 == 0 then
				r = (r * 1103515245 + 12345) % 2147483648
				Session.submit(s, "p", TURNS[r % 5 + 1])
			end
		end
		local events = Session.step(s)
		local after = Session.frame(s, "p")
		if watch(before, events, after, s) then
			return true
		end
		if after.play.lives < before.play.lives then
			return false
		end
		before = after
	end
	return false
end

local function has(events: { Session.Event }, kind: string): Session.Event?
	for _, e in events do
		if e.kind == kind then
			return e
		end
	end
	return nil
end

return t.spec("f0126 ghosts and picks", function(it)
	it("a ghost that reaches a picking player catches them, and the pick is wasted", function()
		for seed = 1, 600 do
			local found = drive(seed, 2000, function(before, events, after)
				if before.pick and has(events, "Caught") then
					local stopped = has(events, "PickStopped")
					t.expect(stopped ~= nil).toBe(true)
					t.expect((stopped :: Session.Event).reason).toBe("caught")
					t.expect(has(events, "WallPicked")).toBe(nil)
					t.expect(after.pick).toBe(nil)
					t.expect(after.play.lives).toBe(before.play.lives - 1)
					return true
				end
				return false
			end)
			if found then
				return
			end
		end
		error("no seed has a ghost catch a picking player")
	end)

	it("the ghosts walk on while the player picks", function()
		local stands = 0
		for seed = 1, 60 do
			drive(seed, 1500, function(before, _, after)
				if before.pick and after.pick then
					stands += 1
					local moved = false
					for i, g in before.ghosts :: { Session.GhostSnapshot } do
						local now = (after.ghosts :: { Session.GhostSnapshot })[i]
						moved = moved or now.x ~= g.x or now.y ~= g.y
					end
					t.expect(moved).toBe(true)
				end
				return false
			end)
		end
		t.expect(stands >= 100).toBe(true)
	end)

	it("the ghosts walk into the holes", function()
		for seed = 1, 600 do
			local found = drive(seed, 2000, function(_, _, after)
				for _, hole in (after.walls :: Session.Walls).opened do
					for _, g in after.ghosts :: { Session.GhostSnapshot } do
						if math.floor(g.x + 0.5) == hole.x and math.floor(g.y + 0.5) == hole.y then
							return true
						end
					end
				end
				return false
			end)
			if found then
				return
			end
		end
		error("no ghost ever stood in a hole")
	end)
end)
