--!strict
-- f0234 AC4: the wiring and the records. Main hands every frame's run state and tick to the camera
-- (Camera.ready(frame.play, frame.tick)), as it hands the hop; the camera keeps it through View.readyEnd and sends
-- nothing to the server, which decides nothing new. game-design.md records the waiting at the top of a hop beside
-- the spy hop, and architecture.md's Hop row names it. The camera's own behaviour is camera.spec's.
local fs = require("@lune/fs")
local place = require("@tests/lib/place")
local t = require("@tests/lib/t")

local game = place.load()

local function source(name: string): string
	local node: any = game
	for _, part in { "StarterPlayer", "StarterPlayerScripts", "Client", name } do
		node = node and node:FindFirstChild(part)
	end
	assert(node, `no Client.{name} in the game place`)
	local src = string.gsub(node.Source, "%-%-[^\n]*", "")
	return src
end

local function has(src: string, pattern: string): boolean
	return string.find(src, pattern) ~= nil
end

return t.spec("f0234 wiring and records", function(it)
	it("Main hands each frame's run state and tick to Camera.ready", function()
		t.expect(has(source("Main"), "Camera%.ready%(%s*frame%.play%s*,%s*frame%.tick%s*%)")).toBe(true)
	end)

	it("the camera folds it through View.readyEnd, holds the eye by Hop.held, and sends nothing", function()
		local cam = source("Camera")
		t.expect(has(cam, "function Camera%.ready%(")).toBe(true)
		t.expect(has(cam, "View%.readyEnd%(")).toBe(true)
		t.expect(has(cam, "Hop%.held%(")).toBe(true)
		t.expect(has(cam, "FireServer")).toBe(false)
	end)

	it(
		"game-design.md records the wait at the top of a hop, and architecture.md's Hop row names it",
		function()
			local design = fs.readFile(".tracker/game-design.md")
			local line = string.match(design, "\n(%- %*%*Waiting at the top%*%* %(f0234[^\n]*)")
			t.expect(line ~= nil).toBe(true)
			for _, needle in { "READY", "free", "lands", "server" } do
				t.expect(string.find(line :: string, needle, 1, true) ~= nil).toBe(true)
			end
			local arch = fs.readFile(".tracker/architecture.md")
			local row = string.match(arch, "\n| Hop |([^\n]*)")
			t.expect(row ~= nil).toBe(true)
			t.expect(string.find(row :: string, "f0234", 1, true) ~= nil).toBe(true)
		end
	)
end)
