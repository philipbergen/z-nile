--!strict
-- f0109: the client paints the walls through View.wallColor: MazeView keeps the lit and edible state on its model and
-- repaints, and Main tells it each frame whether the ghosts are edible (View.edible of the frame's play record). The
-- level-clear flash call stays as f0031 pins it.
local place = require("@tests/lib/place")
local t = require("@tests/lib/t")

local game = place.load()

local function client(name: string): any
	local node = game
	for _, n in { "StarterPlayer", "StarterPlayerScripts", "Client", name } do
		node = node and node:FindFirstChild(n)
	end
	return node
end

-- a script's source without comments, so a mention in a comment proves nothing
local function source(node: any): string
	local src = string.gsub(node.Source, "%-%-[^\n]*", "")
	return src
end

return t.spec("f0109 the client paints the walls by View.wallColor", function(it)
	it("MazeView paints the walls with View.wallColor and keeps no wall colours of its own", function()
		local src = source(client("MazeView"))
		t.expect(string.find(src, "View.wallColor(", 1, true) ~= nil).toBe(true)
		t.expect(string.find(src, "function MazeView.edible(", 1, true) ~= nil).toBe(true)
		t.expect(string.find(src, "function MazeView.flash(", 1, true) ~= nil).toBe(true)
		t.expect((string.find(src, "Color3.fromRGB(33, 33, 222)", 1, true))).toBe(nil)
		t.expect((string.find(src, "Color3.fromRGB(255, 255, 255)", 1, true))).toBe(nil)
	end)

	it(
		"walls built or rebuilt while the ghosts are edible come out green: every wall part takes the model's colour",
		function()
			local src = source(client("MazeView"))
			-- no wall part is made in a fixed colour: build (and f0126's rewall) paint through the model's lit/edible state
			t.expect((string.find(src, "View.wallColor(false, false)", 1, true))).toBe(nil)
			t.expect((string.find(src, "View.wallColor(false, true)", 1, true))).toBe(nil)
			t.expect(string.find(src, "local function wallColorOf(", 1, true) ~= nil).toBe(true)
			t.expect(string.find(src, '"Wall", wallColorOf(', 1, true) ~= nil).toBe(true)
		end
	)

	it(
		"Main tells MazeView each frame whether the ghosts are edible, from View.edible of the frame's play",
		function()
			local src = source(client("Main"))
			t.expect(
				string.find(src, "MazeView%.edible%(%s*[%w_]+%s*,%s*View%.edible%(%s*[%w_]+%.play%s*%)%s*%)")
					~= nil
			).toBe(true)
			t.expect(string.find(src, "MazeView%.flash%([^)]*%.flash%s*%)") ~= nil).toBe(true)
		end
	)
end)
