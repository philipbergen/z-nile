--!strict
-- f0101 AC5: the spy hop's adapters. The server decides the hop (airborne.spec); the clients only send it and show
-- it (f0104 binds Space to send Hop.INTENT). Main hands each frame's `hopped` to Camera, and Camera lifts the eye
-- by Hop.rise of it at the tick being shown (View.shownTick of the two latest snapshots, the blend the ghosts are
-- drawn at), so the rise matches the server's airborne window. Camera keeps no jump of its own and sends nothing. The ghosts are drawn GHOST-sized and the walls and doors at the lowered SCALE.wallHeight.
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
	it("Main hands every frame's hopped to the camera", function()
		local main = source("Main")
		t.expect(string.find(main, "Camera%.hopped%(%s*frame%.hopped%s*%)") ~= nil).toBe(true)
	end)

	it("Camera keeps the server's hop and starts none of its own", function()
		local src = source("Camera")
		t.expect(has(src, "function Camera.hopped(")).toBe(true)
		t.expect(has(src, "function Camera.jump(")).toBe(false)
		t.expect(has(src, "View.canJump")).toBe(false)
		t.expect(has(src, "Hop.canStart")).toBe(false)
		t.expect(has(src, "FireServer")).toBe(false)
	end)

	it(
		"the eye is the standing height plus Hop.rise at the tick being shown, in the camera's one CFrame",
		function()
			local src = source("Camera")
			local at =
				string.match(src, "View%.SCALE%.eyeHeight%s*%+%s*Hop%.rise%(%s*hopped%s*,%s*([%w_]+)%s*%)")
			t.expect(at ~= nil).toBe(true)
			-- that tick is View.shownTick of the two snapshots the pose is blended from, at the same View.alpha
			local blend = string.match(
				src,
				"local%s+"
					.. (at :: string)
					.. "%s*=%s*View%.shownTick%(%s*prev%s*,%s*snap%s*,%s*View%.alpha%(%s*os%.clock%(%)%s*%-%s*arrived%s*%)%s*%)"
			)
			t.expect(blend ~= nil).toBe(true)
			local frames = 0
			for _ in string.gmatch(src, "camera%.CFrame%s*=") do
				frames += 1
			end
			t.expect(frames).toBe(1)
		end
	)

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
