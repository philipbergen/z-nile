--!strict
-- f0126 AC6: the adapters. F sends Picks.INTENT on the one Intent remote; Main hands the camera each frame's hop
-- length, rebuilds the walls (holes open, marked walls gold) when View.wallsKey changes, gives the radar the frame's
-- maze and the HUD the pick and the boon; the shot's beam ends in the frame's maze; the walls flash with the marked
-- ones; nothing new sends anything to the server but Controls.
local place = require("@tests/lib/place")
local t = require("@tests/lib/t")

local game = place.load()

local function client(name: string): any
	local node: any = game
	for _, part in { "StarterPlayer", "StarterPlayerScripts", "Client", name } do
		node = node and node:FindFirstChild(part)
	end
	t.expect(node ~= nil).toBe(true)
	return node
end

-- the source with its comments stripped
local function source(name: string): string
	local src = string.gsub(client(name).Source, "%-%-[^\n]*", "")
	return src
end

local function has(src: string, needle: string): boolean
	return string.find(src, needle, 1, true) ~= nil
end

local function matches(src: string, pattern: string): boolean
	return string.find(src, pattern) ~= nil
end

return t.spec("f0126 adapters", function(it)
	it(
		"F sends View.PICK_INTENT (Picks.INTENT) on the Intent remote, and no wire string of its own",
		function()
			local src = source("Controls")
			t.expect(
				matches(src, 'action%s*==%s*"Pick"%s*then%s*intent:FireServer%(%s*View%.PICK_INTENT%s*%)')
			)
				.toBe(true)
			t.expect(has(src, '"Pick")')).toBe(false)
			local remotes = 0
			for _ in string.gmatch(src, ':WaitForChild%("Intent"%)') do
				remotes += 1
			end
			t.expect(remotes).toBe(1)
		end
	)

	it(
		"Controls adds no require for the pick: its wire string comes through View (stub loaders stay valid)",
		function()
			-- specs that load Controls with a table of its modules (tests/place/touch-adapters, f0110's) keep working
			local src = source("Controls")
			t.expect(has(src, "Shared/Logic/Picks")).toBe(false)
			t.expect(has(src, "Picks.INTENT")).toBe(false)
		end
	)

	it("the camera lifts the eye by the hop at its own length, given by Main from each frame", function()
		local cam = source("Camera")
		t.expect(has(cam, "function Camera.hopTicks(")).toBe(true)
		t.expect(
			matches(
				cam,
				"View%.SCALE%.eyeHeight%s*%+%s*Hop%.rise%(%s*hopped%s*,%s*[%w_]+%s*,%s*hopTicks%s*%)"
			)
		)
			.toBe(true)
		t.expect(has(cam, "FireServer")).toBe(false)
		local main = source("Main")
		t.expect(matches(main, "Camera%.hopTicks%(%s*frame%.hopTicks%s*%)")).toBe(true)
		t.expect(matches(main, "Camera%.hopped%(%s*frame%.hopped%s*%)")).toBe(true)
	end)

	it("Main rebuilds the walls from the frame's maze and marks when View.wallsKey changes", function()
		local main = source("Main")
		t.expect(matches(main, "View%.wallsKey%(%s*frame%s*%)")).toBe(true)
		t.expect(matches(main, "MazeView%.rewall%(%s*[%w_]+%s*,%s*View%.frameMaze%(%s*frame%s*%)%s*,"))
			.toBe(true)
		t.expect(has(main, "frame.walls.marked")).toBe(true)
	end)

	it("the radar and the beam see the frame's maze, holes open", function()
		local main = source("Main")
		t.expect(matches(main, "DangerHud%.push%(%s*snap%s*,%s*View%.frameMaze%(%s*frame%s*%)%s*%)"))
			.toBe(true)
		t.expect(has(main, "DangerHud.push(snap, Maze.layout")).toBe(false)
		local blast = source("BlastView")
		t.expect(matches(blast, "View%.frameMaze%(%s*frame%s*%)")).toBe(true)
		t.expect(has(blast, "Maze.layout(frame.maze)")).toBe(false)
	end)

	it(
		"MazeView builds the marked walls as walls of their own (their colours and flash: views.spec)",
		function()
			local src = source("MazeView")
			t.expect(has(src, "function MazeView.rewall(")).toBe(true)
			t.expect(matches(src, "View%.walls%(%s*[%w_]+%s*,%s*[%w_]+%s*,%s*[%w_%.]+%s*%)")).toBe(true)
			t.expect(has(src, '"MarkedWall"')).toBe(true)
			t.expect(has(src, ".marked")).toBe(true)
		end
	)

	it(
		"the HUD shows the pick and the boon with Hud.pickProgress and Hud.boonBanner, from Main's frame",
		function()
			local hud = source("HudView")
			t.expect(has(hud, "function HudView.pick(")).toBe(true)
			t.expect(has(hud, "Hud.pickProgress(")).toBe(true)
			t.expect(has(hud, "Hud.boonBanner(")).toBe(true)
			t.expect(has(hud, "Hud.pickBox(")).toBe(true) -- placed by the pure layout, in screen pixels
			t.expect(has(hud, "Hud.boonBox(")).toBe(true)
			t.expect(has(hud, "FireServer")).toBe(false)
			local main = source("Main")
			t.expect(matches(main, "HudView%.pick%(%s*frame%.pick%s*,%s*frame%.boon%s*,%s*frame%.tick%s*%)"))
				.toBe(true)
		end
	)

	it(
		"Session never moves the player or aims a shot in the session's shared maze, only in the member's",
		function()
			local node: any = game
			for _, part in { "ReplicatedStorage", "Shared", "Logic", "Session" } do
				node = node and node:FindFirstChild(part)
			end
			t.expect(node ~= nil).toBe(true)
			local src = string.gsub(node.Source, "%-%-[^\n]*", "")
			-- `s.maze` is the session's own, documented field: each member plays in its copy with the holes open
			for _, call in
				{ "Movement%.step", "Movement%.occupied", "Blaster%.target", "Blaster%.ray", "Ghosts%.step" }
			do
				t.expect(matches(src, call .. "%(%s*s%.maze")).toBe(false)
			end
		end
	)
end)
