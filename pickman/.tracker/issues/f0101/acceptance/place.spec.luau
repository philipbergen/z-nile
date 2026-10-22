--!strict
-- f0101 AC4: the spy hop is the camera's alone. Camera starts a jump only when View.canJump says so and lifts the
-- eye by View.jumpRise every frame; the rail, the tiles and the server are untouched (no jump crosses the wire).
-- The ghosts are drawn GHOST-sized and the walls and doors at the lowered SCALE.wallHeight.
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

local function source(name: string): string
	local src = string.gsub(client(name).Source, "%-%-[^\n]*", "")
	return src
end

local function has(src: string, needle: string): boolean
	return string.find(src, needle, 1, true) ~= nil
end

return t.spec("f0101 spy hop adapters", function(it)
	it("Camera has a jump that asks View.canJump and keeps when it started", function()
		local src = source("Camera")
		t.expect(has(src, "function Camera.jump(")).toBe(true)
		t.expect(has(src, "View.canJump(")).toBe(true)
	end)

	it("the eye is the standing height plus View.jumpRise, in the camera's one CFrame", function()
		local src = source("Camera")
		t.expect(string.find(src, "View%.SCALE%.eyeHeight%s*%+%s*View%.jumpRise%(") ~= nil).toBe(true)
		local frames = 0
		for _ in string.gmatch(src, "camera%.CFrame%s*=") do
			frames += 1
		end
		t.expect(frames).toBe(1)
	end)

	it("the jump sends nothing to the server", function()
		for _, name in { "Camera", "Controls" } do
			local src = source(name)
			t.expect(has(src, '"Jump")')).toBe(false) -- never a FireServer("Jump")
		end
		t.expect(has(source("Camera"), "FireServer")).toBe(false)
	end)

	it("GhostView sizes a ghost's body from View.GHOST", function()
		local src = source("GhostView")
		t.expect(has(src, "View.GHOST.height")).toBe(true)
		t.expect(has(src, "View.GHOST.width")).toBe(true)
		t.expect(has(src, "Vector3.new(6, 7, 6)")).toBe(false)
	end)

	it("MazeView raises walls and doors to View.SCALE's wall height", function()
		local src = source("MazeView")
		local uses = 0
		for _ in string.gmatch(src, "s%.wallHeight") do
			uses += 1
		end
		t.expect(uses >= 4).toBe(true)
		t.expect(string.find(src, "local s%s*=%s*View%.SCALE") ~= nil).toBe(true)
	end)
end)
