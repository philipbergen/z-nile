--!strict
-- f0028 AC3: the mouse path stays, and touch look and snap call the same View functions.
local place = require("@tests/lib/place")
local t = require("@tests/lib/t")

local game = place.load()

local function find(path: { string }): any
	local node = game
	for _, name in path do
		node = node and node:FindFirstChild(name)
	end
	return node
end

local function source(name: string): string
	local node = find({ "StarterPlayer", "StarterPlayerScripts", "Client", name })
	t.expect(node ~= nil).toBe(true)
	return string.gsub(node.Source, "%-%-[^\n]*", "")
end

return t.spec("f0028 look adapter", function(it)
	it(
		"the mouse delta reaches View.look only when no touch is holding the mouse and this frame has not looked",
		function()
			local src = source("Camera")
			t.expect(string.find(src, "GetMouseDelta()", 1, true) ~= nil).toBe(true)
			t.expect(string.find(src, "function Camera.lookBy(", 1, true) ~= nil).toBe(true)
			t.expect(string.find(src, "function Camera.holdMouse(", 1, true) ~= nil).toBe(true)
			t.expect(string.find(src, "function Camera.snap(", 1, true) ~= nil).toBe(true)
			t.expect(string.find(src, "function Camera.setCursor(", 1, true) ~= nil).toBe(true)
			t.expect(string.find(src, "lookedThisFrame = true", 1, true) ~= nil).toBe(true)
			local guard = string.find(src, "not mouseHeld and not lookedThisFrame", 1, true)
			local apply = string.find(src, "View.look(look, delta", 1, true)
			local cleared = string.find(src, "lookedThisFrame = false", 1, true)
			local early = string.find(src, "snap == nil", 1, true)
			t.expect(guard ~= nil).toBe(true)
			t.expect(apply ~= nil).toBe(true)
			t.expect(cleared ~= nil).toBe(true)
			t.expect(early ~= nil).toBe(true)
			if guard and apply and cleared and early then
				t.expect(guard < apply).toBe(true)
				t.expect(apply < cleared).toBe(true)
				t.expect(cleared < early).toBe(true)
			end
		end
	)

	it("Main passes Camera.snap and then Camera.lookBy into Controls", function()
		local src = source("Main")
		t.expect(string.find(src, "Controls.start(Camera.snap, Camera.lookBy,", 1, true) ~= nil).toBe(true)
		t.expect(string.find(src, "Camera.holdMouse", 1, true) ~= nil).toBe(true)
	end)
end)
