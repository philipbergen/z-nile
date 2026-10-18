--!strict
-- d0105 AC3: DangerHud places the radar from Hud.radarBox of the current screen on every render step,
-- before a snapshot is required. It keeps the default anchor and does not turn a CoreGui off.
local place = require("@tests/lib/place")
local t = require("@tests/lib/t")

local game = place.load()

local function source(): string
	local node = game:FindFirstChild("StarterPlayer")
		:FindFirstChild("StarterPlayerScripts")
		:FindFirstChild("Client")
		:FindFirstChild("DangerHud")
	t.expect(node ~= nil and node.ClassName).toBe("ModuleScript")
	return string.gsub(node.Source, "%-%-[^\n]*", "")
end

return t.spec("d0105 danger hud corner", function(it)
	it(
		"places the radar from the current screen size on every render step, before the snapshot guard",
		function()
			local src = source()
			local block = "RenderStepped:Connect(function()\n"
				.. "\t\tlocal view = gui.AbsoluteSize\n"
				.. "\t\tlocal box = Hud.radarBox(view.X, view.Y, radarSize)\n"
				.. "\t\tradar.Position = UDim2.fromOffset(box.x, box.y)\n"
			t.expect(string.find(src, block, 1, true) ~= nil).toBe(true)
			local function count(needle: string): number
				local n, i = 0, 1
				while true do
					local at = string.find(src, needle, i, true)
					if at == nil then
						break
					end
					n += 1
					i = at + #needle
				end
				return n
			end
			t.expect(count("radar.Position")).toBe(1)
			t.expect(count("local view =")).toBe(1)
		end
	)

	it("the old top-right corner is gone", function()
		local src = source()
		t.expect((string.find(src, "UDim2.new(1, -16, 0, 16)", 1, true))).toBe(nil)
		t.expect((string.find(src, "Vector2.new(1, 0)", 1, true))).toBe(nil)
		t.expect((string.find(src, "radar.AnchorPoint", 1, true))).toBe(nil)
	end)

	it("the chat stays on: no core-gui or text-chat switch", function()
		local src = source()
		for _, word in
			{
				"SetCore",
				"SetCoreGuiEnabled",
				"CoreGuiType",
				"PlayerList",
				"ChatWindowConfiguration",
				"BubbleChatConfiguration",
				"TextChatService",
			}
		do
			t.expect((string.find(src, word, 1, true))).toBe(nil)
		end
	end)

	it("it still draws the radar Awareness computes", function()
		local src = source()
		t.expect(string.find(src, "Awareness.radar(", 1, true) ~= nil).toBe(true)
		t.expect(string.find(src, "Awareness.indicators(", 1, true) ~= nil).toBe(true)
		t.expect(string.find(src, "Awareness.edgePoint(", 1, true) ~= nil).toBe(true)
	end)
end)
