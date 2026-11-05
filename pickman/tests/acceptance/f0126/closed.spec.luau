--!strict
-- f0126 AC7 (closed holes): after a new run the holes are walls again for everyone. Played as ghosts.spec plays it
-- (the same restless picker), in a file of its own so the runner runs it beside the others.
local Maze = require("@logic/Maze")
local Movement = require("@logic/Movement")
local Session = require("@logic/Session")
local View = require("@logic/View")
local t = require("@tests/lib/t")

local classic = Maze.layout("classic")
local CONFIG: Session.Config = { movement = Movement.DEFAULT_CONFIG, maxIntentsPerTick = 4, ghosts = true }

local function new(seed: number): Session.Session
	local s = Session.new(classic, seed, CONFIG)
	Session.join(s, "p")
	return s
end

local TURNS = { "Left", "Right", "Back", "Left", "Right" }

return t.spec("f0126 closed holes", function(it)
	it(
		"nobody walks a wall: after a new run with holes closed, no ghost and not the player stands on a wall",
		function()
			-- play until a hole has opened, end the run by three deaths, start a new one, and play on: the closed holes
			-- are walls again for the ghosts too (a fresh maze points them back at the session's maze)
			local checked = 0
			for seed = 1, 40 do
				local s = new(seed)
				local r = seed
				for k = 1, 1500 do
					if Session.frame(s, "p").pick == nil then
						Session.submit(s, "p", "Pick")
						if k % 9 == 0 then
							r = (r * 1103515245 + 12345) % 2147483648
							Session.submit(s, "p", TURNS[r % 5 + 1])
						end
					end
					Session.step(s)
					if #(Session.frame(s, "p").walls :: Session.Walls).opened >= 2 then
						break
					end
				end
				if #(Session.frame(s, "p").walls :: Session.Walls).opened >= 2 then
					while not Session.isOver(s, "p") do
						Session.kill(s, "p")
						Session.step(s)
						Session.step(s)
					end
					local _, ok = Session.playAgain(s, "p")
					t.expect(ok).toBe(true)
					for _ = 1, 600 do
						Session.step(s)
						local f = Session.frame(s, "p")
						local m = View.frameMaze(f)
						t.expect(#(f.walls :: Session.Walls).opened).toBe(0)
						local you = {
							x = math.floor(f.player.x + 0.5) % m.width,
							y = math.floor(f.player.y + 0.5) % m.height,
						}
						t.expect(Maze.kind(m, you) ~= "wall").toBe(true)
						for _, g in f.ghosts :: { Session.GhostSnapshot } do
							local tile =
								{ x = math.floor(g.x + 0.5) % m.width, y = math.floor(g.y + 0.5) % m.height }
							t.expect(Maze.kind(m, tile) ~= "wall").toBe(true)
						end
						checked += 1
					end
				end
			end
			t.expect(checked >= 2000).toBe(true)
		end
	)

	it(
		"after a death the holes stay open to the ghosts: one walks into a hole dug before the death",
		function()
			for seed = 1, 60 do
				local s = new(seed)
				local r = seed
				for k = 1, 1500 do
					if Session.frame(s, "p").pick == nil then
						Session.submit(s, "p", "Pick")
						if k % 9 == 0 then
							r = (r * 1103515245 + 12345) % 2147483648
							Session.submit(s, "p", TURNS[r % 5 + 1])
						end
					end
					Session.step(s)
					if #(Session.frame(s, "p").walls :: Session.Walls).opened >= 2 then
						break
					end
				end
				local holes = (Session.frame(s, "p").walls :: Session.Walls).opened
				if #holes >= 2 then
					Session.kill(s, "p")
					for _ = 1, 1200 do
						Session.step(s)
						local f = Session.frame(s, "p")
						t.expect(#(f.walls :: Session.Walls).opened).toBe(#holes) -- a death keeps them
						for _, hole in holes do
							for _, g in f.ghosts :: { Session.GhostSnapshot } do
								if math.floor(g.x + 0.5) == hole.x and math.floor(g.y + 0.5) == hole.y then
									return
								end
							end
						end
					end
				end
			end
			error("no ghost walked into a hole after a death")
		end
	)
end)
