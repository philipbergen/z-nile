--!strict
-- R0012 review 001: how the touch adapters call the Touch fold and act on what it returns. The fold's own
-- behaviour is pinned by the f0027-f0029 acceptance specs; these pin the adapter text around it.
local place = require("@tests/lib/place")
local t = require("@tests/lib/t")

local game = place.load()

local function source(name: string): string
	local node = game:FindFirstChild("StarterPlayer")
	for _, child in { "StarterPlayerScripts", "Client", name } do
		node = node and node:FindFirstChild(child)
	end
	t.expect(node ~= nil).toBe(true)
	return (string.gsub((node :: any).Source, "%-%-[^\n]*", ""))
end

local function count(src: string, needle: string): number
	local n, at = 0, 1
	while true do
		local s, e = string.find(src, needle, at, true)
		if s == nil then
			return n
		end
		n += 1
		at = (e :: number) + 1
	end
end

-- The text of `function <name>(` up to the first line that is exactly `end` at that indent.
local function body(src: string, name: string): string
	local s = string.find(src, "function " .. name .. "(", 1, true)
	t.expect(s ~= nil).toBe(true)
	local e = string.find(src, "\nend", s :: number, true)
	t.expect(e ~= nil).toBe(true)
	return string.sub(src, s :: number, e :: number)
end

return t.spec("touch adapters", function(it)
	it("Controls passes the called snap rectangle into its one Touch.track", function()
		local src = source("Controls")
		t.expect(count(src, "Touch.track(")).toBe(1)
		t.expect(string.find(src, "local rect = if snapRect then snapRect() else nil", 1, true) ~= nil)
			.toBe(true)
		local call = string.find(src, "Touch.track(", 1, true) :: number
		local close = string.find(src, "\n\t\t)", call, true)
		t.expect(close ~= nil).toBe(true)
		local args = string.sub(src, call, close :: number)
		t.expect(string.find(args, "{ width = sw, snap = rect }", 1, true) ~= nil).toBe(true)
	end)

	it("Controls fires a turn's intent, looks by dx then dy, and snaps on the snap effect", function()
		local src = source("Controls")
		t.expect(
			string.find(src, 'effect.kind == "turn" then\n\t\t\t\tintent:FireServer(effect.intent)', 1, true)
				~= nil
		).toBe(true)
		t.expect(string.find(src, "onLook(effect.dx, effect.dy)", 1, true) ~= nil).toBe(true)
		t.expect(string.find(src, 'effect.kind == "snap" then\n\t\t\t\tonSnap()', 1, true) ~= nil).toBe(true)
	end)

	it(
		"Controls reports held only on a change, counting every physical touch, and resets on focus loss",
		function()
			local src = source("Controls")
			t.expect(count(src, "onTouch(")).toBe(1)
			local change = string.find(
				src,
				"if down ~= held then\n\t\t\theld = down\n\t\t\tif onTouch then\n\t\t\t\tonTouch(held)",
				1,
				true
			)
			t.expect(change ~= nil).toBe(true)
			t.expect(string.find(src, "local down = next(ids) ~= nil", 1, true) ~= nil).toBe(true)
			t.expect(string.find(src, "next(fingers.fingers)", 1, true) == nil).toBe(true)
			local focus = string.find(src, "WindowFocusReleased:Connect(function()", 1, true)
			t.expect(focus ~= nil).toBe(true)
			local reset =
				string.sub(src, focus :: number, string.find(src, "end)", focus :: number, true) :: number)
			t.expect(string.find(reset, "fingers = Touch.empty()", 1, true) ~= nil).toBe(true)
			t.expect(string.find(reset, "ids = {}", 1, true) ~= nil).toBe(true)
			t.expect(string.find(reset, "hold()", 1, true) ~= nil).toBe(true)
		end
	)

	it(
		"Camera.holdMouse also skips the mouse delta of the frame in which a finger went down or up",
		function()
			local hold = body(source("Camera"), "Camera.holdMouse")
			t.expect(string.find(hold, "mouseHeld = held", 1, true) ~= nil).toBe(true)
			t.expect(string.find(hold, "lookedThisFrame = true", 1, true) ~= nil).toBe(true)
		end
	)

	it("HudView shows the snap frame only on a touch screen", function()
		local src = source("HudView")
		t.expect(string.find(src, "s.Visible = UserInputService.TouchEnabled", 1, true) ~= nil).toBe(true)
	end)
end)
