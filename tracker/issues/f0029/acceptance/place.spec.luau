--!strict
-- f0029 AC3: HudView applies GuiService insets itself and draws the snap control in the margin.
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

return t.spec("f0029 hud adapter", function(it)
	it(
		"HudView reads the device cutout, lays out in viewport pixels, and does not let the engine inset it again",
		function()
			local src = source("HudView")
			local function has(needle: string): boolean
				return string.find(src, needle, 1, true) ~= nil
			end
			t.expect(has("Hud.layout(")).toBe(true)
			t.expect(has("ViewportSize")).toBe(true)
			t.expect(has("Hud.safeInset(")).toBe(true)
			t.expect(has("PickmanHud")).toBe(true)
			t.expect(
				has("GetInsetArea(Enum.ScreenInsets.CoreUISafeInsets")
					or has("GetInsetArea((Enum :: any).ScreenInsets.CoreUISafeInsets")
			).toBe(true)
			t.expect(
				has("GetInsetArea(Enum.ScreenInsets.None")
					or has("GetInsetArea((Enum :: any).ScreenInsets.None")
			).toBe(true)
			local noneAt = string.find(src, "ScreenInsets = Enum.ScreenInsets.None", 1, true)
				or string.find(src, "ScreenInsets = (Enum :: any).ScreenInsets.None", 1, true)
			local ignoreAt = string.find(src, "IgnoreGuiInset = true", 1, true)
			t.expect(ignoreAt ~= nil).toBe(true)
			t.expect(noneAt ~= nil).toBe(true)
			if ignoreAt and noneAt then
				t.expect(ignoreAt < noneAt).toBe(true)
			end
			t.expect(
				has("SafeAreaCompatibility = Enum.SafeAreaCompatibility.None")
					or has("SafeAreaCompatibility = (Enum :: any).SafeAreaCompatibility.None")
			).toBe(true)
			t.expect((string.find(src, "GetGuiInset", 1, true))).toBe(nil)
		end
	)

	it(
		"HudView lays out the full screen from the None area, with ViewportSize only as the fallback",
		function()
			local src = source("HudView")
			local w, h = string.match(
				src,
				"local%s+([%w_]+)%s*,%s*([%w_]+)%s*=%s*Touch%.screenSize%(%s*[^\n]*ViewportSize"
			)
			t.expect(w ~= nil and h ~= nil).toBe(true)
			if w and h then
				t.expect(string.find(src, "Hud%.layout%(%s*" .. w .. "%s*,%s*" .. h .. "%s*,") ~= nil)
					.toBe(true)
			end
			t.expect((string.find(src, "Hud%.layout%([^\n]*ViewportSize"))).toBe(nil)
			t.expect(string.find(src, "ViewportSize", 1, true) ~= nil).toBe(true)
		end
	)

	it(
		"the PickmanHud step itself reads both inset areas and the screen size; nothing reads them elsewhere",
		function()
			local src = source("HudView")
			local bindAt, bindEnd = string.find(src, 'BindToRenderStep%(%s*"PickmanHud"')
			t.expect(bindAt ~= nil).toBe(true)
			if bindAt == nil or bindEnd == nil then
				return
			end
			local closeAt = string.find(src, "\n%s*end%)", bindEnd)
			t.expect(closeAt ~= nil).toBe(true)
			local body = string.sub(src, bindAt, closeAt or #src)
			t.expect(string.find(body, "GetInsetArea%([^\n]-ScreenInsets%.None") ~= nil).toBe(true)
			t.expect(string.find(body, "GetInsetArea%([^\n]-ScreenInsets%.CoreUISafeInsets") ~= nil)
				.toBe(true)
			t.expect(string.find(body, "Touch.screenSize(", 1, true) ~= nil).toBe(true)
			local outside = string.sub(src, 1, bindAt - 1) .. string.sub(src, (closeAt or #src) + 1)
			t.expect((string.find(outside, "GetInsetArea(", 1, true))).toBe(nil)
		end
	)

	it(
		"the snap control is a non-active frame placed by Touch.snapRect, and the HUD still sends nothing",
		function()
			local src = source("HudView")
			t.expect(string.find(src, "Touch.snapRect(", 1, true) ~= nil).toBe(true)
			t.expect(string.find(src, "function HudView.snapRect(", 1, true) ~= nil).toBe(true)
			t.expect(string.find(src, '.Name = "Snap"', 1, true) ~= nil).toBe(true)
			t.expect(string.find(src, "Active = false", 1, true) ~= nil).toBe(true)
			t.expect((string.find(src, "FireServer", 1, true))).toBe(nil)
			t.expect((string.find(src, "Remotes", 1, true))).toBe(nil)
		end
	)

	it("Main gives Controls the snap rectangle from HudView", function()
		local src = source("Main")
		t.expect(string.find(src, "HudView.snapRect", 1, true) ~= nil).toBe(true)
		t.expect(string.find(src, "Controls.start(", 1, true) ~= nil).toBe(true)
	end)
end)
