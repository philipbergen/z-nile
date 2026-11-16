--!strict
-- f0126 AC7 (eating while picking): a blue ghost met by a picking player is eaten, and the pick goes on to finish.
-- Played as ghosts.spec plays it (the same restless picker), in a file of its own: its seed search is the slow one.
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

return t.spec("f0126 eating while picking", function(it)
	it("a blue ghost met while picking is eaten, and the pick goes on", function()
		for seed = 1, 1000 do
			local wall: Maze.Tile? = nil
			local found = drive(seed, 2000, function(before, events, after)
				if wall then
					if has(events, "PickStopped") then
						error("the pick was wasted after a ghost was eaten")
					end
					local picked = has(events, "WallPicked")
					if picked then
						t.expect(picked.x).toBe((wall :: Maze.Tile).x)
						t.expect(picked.y).toBe((wall :: Maze.Tile).y)
						return true
					end
					return false
				end
				if before.pick and has(events, "GhostEaten") then
					t.expect(has(events, "PickStopped")).toBe(nil)
					t.expect(after.pick ~= nil).toBe(true)
					wall = (before.pick :: Session.Pick).wall
				end
				return false
			end)
			if found then
				return
			end
		end
		error("no seed has a picking player eat a blue ghost")
	end)
end)
