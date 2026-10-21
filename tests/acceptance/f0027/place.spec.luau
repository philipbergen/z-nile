--!strict
-- f0027 AC3: Controls feeds touches through the fold and still sends key intents the old way.
local fs = require("@lune/fs")
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

return t.spec("f0027 touch adapter", function(it)
	it("the Touch feature requires View and is not an engine module", function()
		local src = fs.readFile("src/shared/Logic/Touch/init.luau")
		t.expect(string.find(src, "./View", 1, true) ~= nil).toBe(true)
	end)

	it("Controls tracks UserInputService touches and does not turn the default thumbstick on", function()
		local src = source("Controls")
		t.expect(string.find(src, "Touch.track(", 1, true) ~= nil).toBe(true)
		t.expect(string.find(src, "UserInputType.Touch", 1, true) ~= nil).toBe(true)
		t.expect(string.find(src, "TouchControlsEnabled = false", 1, true) ~= nil).toBe(true)
		t.expect(string.find(src, "onTouch(", 1, true) ~= nil).toBe(true)
		t.expect((string.find(src, "Gamepad", 1, true))).toBe(nil)
		t.expect((string.find(src, "gameProcessed", 1, true))).toBe(nil)
	end)

	it(
		"Controls reads the None area per event: its screen width and converted point are what Touch.track gets",
		function()
			local src = source("Controls")
			local area = "GuiService:GetInsetArea%([^\n]-ScreenInsets%.None"
			-- the conversion reads the area inline, so it cannot be cached at start
			local a, b =
				string.match(src, "local%s+([%w_]+)%s*,%s*([%w_]+)%s*=%s*Touch%.toScreen%(%s*" .. area)
			t.expect(a ~= nil and b ~= nil).toBe(true)
			-- so does the width
			local w = string.match(src, "local%s+([%w_]+)%s*=%s*Touch%.screenSize%(%s*" .. area)
			t.expect(w ~= nil).toBe(true)
			-- one Touch.track(, after the conversion, fed those names
			local n = 0
			for _ in string.gmatch(src, "Touch%.track%(") do
				n += 1
			end
			t.expect(n).toBe(1)
			local convertAt = string.find(src, "Touch.toScreen(", 1, true)
			local trackAt = string.find(src, "Touch.track(", 1, true)
			t.expect(convertAt ~= nil and trackAt ~= nil and convertAt < trackAt).toBe(true)
			local call = string.match(src, "Touch%.track%b()") or ""
			if a and b and w then
				t.expect(string.find(call, "x%s*=%s*" .. a .. "%f[^%w_]") ~= nil).toBe(true)
				t.expect(string.find(call, "y%s*=%s*" .. b .. "%f[^%w_]") ~= nil).toBe(true)
				t.expect(string.find(call, "width%s*=%s*" .. w .. "%f[^%w_]") ~= nil).toBe(true)
			end
			t.expect((string.find(call, "ViewportSize", 1, true))).toBe(nil)
			t.expect((string.find(call, "Position", 1, true))).toBe(nil)
			-- both reads are evaluated per event: they sit in the same function as the one Touch.track( call
			-- (no helper between, nothing hoisted to start), and toScreen reads the event's own Position
			local fnAt: number? = nil
			local from = 1
			while trackAt do
				local at = string.find(src, "%f[%w_]function%f[^%w_]", from)
				if at == nil or at > trackAt then
					break
				end
				fnAt = at
				from = at + 1
			end
			local convertLocal = string.find(src, "local%s+[%w_]+%s*,%s*[%w_]+%s*=%s*Touch%.toScreen%(")
			local widthLocal = string.find(src, "local%s+[%w_]+%s*=%s*Touch%.screenSize%(")
			t.expect(fnAt ~= nil and convertLocal ~= nil and widthLocal ~= nil).toBe(true)
			if fnAt and convertLocal and widthLocal and trackAt then
				t.expect(convertLocal > fnAt and convertLocal < trackAt).toBe(true)
				t.expect(widthLocal > fnAt and widthLocal < trackAt).toBe(true)
			end
			t.expect(
				string.find(
					src,
					"Touch%.toScreen%(%s*GuiService:GetInsetArea%b()%s*,%s*[%w_]+%.Position%.X%s*,%s*[%w_]+%.Position%.Y"
				) ~= nil
			).toBe(true)
		end
	)

	it(
		"the keyboard path is unchanged: the action map, the high-priority bind, and the Intent remote",
		function()
			local src = source("Controls")
			t.expect(string.find(src, "View.action(", 1, true) ~= nil).toBe(true)
			t.expect(string.find(src, "BindActionAtPriority", 1, true) ~= nil).toBe(true)
			t.expect(string.find(src, ":FireServer(", 1, true) ~= nil).toBe(true)
			t.expect(string.find(src, "View.KEYS", 1, true) ~= nil).toBe(true)
		end
	)
end)
