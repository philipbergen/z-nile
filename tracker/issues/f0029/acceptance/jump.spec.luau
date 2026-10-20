--!strict
-- f0029 AC5 (c0106): on a touch screen the radar, the power bar and the snap button stay clear of the corner
-- where Roblox draws its touch jump button, in portrait and in landscape. Hud.jumpButtons returns both
-- placements PlayerModule's TouchJump uses (the legacy button first, then the ability-controls button),
-- measured from the bottom-right of the frame the touch GUI fills. Hud.radarBox's fourth argument, true on a
-- touch screen, lifts the radar to one margin above the higher of the two, and never into the top text band.
-- The radar and the HUD live in different frames: DangerHud's ScreenGui fills the device safe area (top bar
-- included), HudView and the touch GUI use the core-UI safe area. Hud.bandTop(core, device) is how far the
-- core area's top sits below the device area's; radarBox's fifth argument takes it, so the jump buttons and the
-- text-band clamp are measured where the HUD draws them.
local Hud = require("@logic/Hud")
local Touch = require("@logic/Touch")
local place = require("@tests/lib/place")
local t = require("@tests/lib/t")

-- Added by this issue. Casts keep the spec type-legal before they exist; a missing function fails at the call.
local jumpButtons = (Hud :: any).jumpButtons
local radarBox = (Hud :: any).radarBox
local bandTop = (Hud :: any).bandTop
local layout = Hud.layout :: any

local SIZE = 120 -- d0105's radar: f0033's 15 tiles at 8 pixels

type Rect = { x: number, y: number, w: number, h: number }

local function overlaps(a: Rect, b: Rect): boolean
	return a.x < b.x + b.w and b.x < a.x + a.w and a.y < b.y + b.h and b.y < a.y + a.h
end

local function boxOf(row: any): any
	return {
		textSize = row.textSize,
		margin = row.margin,
		iconSize = row.iconSize,
		barWidth = row.barWidth,
		barHeight = row.barHeight,
		safeX = row.safeX,
		safeY = row.safeY,
		safeW = row.safeW,
		safeH = row.safeH,
	}
end

-- A sample screen. `inset` is the core-UI safe inset HudView passes to Hud.layout (the touch GUI's frame too).
-- `device` is the device safe inset, DangerHud's frame; nil means the same as `inset`. The radar is computed
-- in DangerHud's frame, with bandTop = inset.top - device.top, and shifted to screen pixels.
type Sample = {
	name: string,
	width: number,
	height: number,
	inset: any,
	device: any?,
	radar: Rect,
	zone: { Rect },
}
local SAMPLES: { Sample } = {
	{
		name = "notched phone, portrait",
		width = 390,
		height = 844,
		inset = { top = 47, bottom = 0, left = 0, right = 0 },
		radar = { x = 261, y = 579, w = SIZE, h = SIZE },
		zone = { { x = 295, y = 754, w = 70, h = 70 }, { x = 254, y = 708, w = 72, h = 72 } },
	},
	{
		name = "notched phone, landscape",
		width = 844,
		height = 390,
		inset = { top = 0, bottom = 0, left = 47, right = 0 },
		radar = { x = 715, y = 125, w = SIZE, h = SIZE },
		zone = { { x = 749, y = 300, w = 70, h = 70 }, { x = 708, y = 254, w = 72, h = 72 } },
	},
	{
		name = "notched phone, landscape, under a 58 px top bar",
		width = 844,
		height = 390,
		inset = { top = 58, bottom = 21, left = 59, right = 59 },
		device = { top = 0, bottom = 21, left = 59, right = 59 },
		radar = { x = 656, y = 104, w = SIZE, h = SIZE },
		zone = { { x = 690, y = 279, w = 70, h = 70 }, { x = 649, y = 233, w = 72, h = 72 } },
	},
	{
		name = "small phone, landscape",
		width = 667,
		height = 375,
		inset = nil,
		radar = { x = 538, y = 110, w = SIZE, h = SIZE },
		zone = { { x = 572, y = 285, w = 70, h = 70 }, { x = 531, y = 239, w = 72, h = 72 } },
	},
	{
		name = "old phone, landscape",
		width = 480,
		height = 320,
		inset = nil,
		radar = { x = 353, y = 57, w = SIZE, h = SIZE },
		zone = { { x = 385, y = 230, w = 70, h = 70 }, { x = 344, y = 184, w = 72, h = 72 } },
	},
	{
		name = "tablet-sized portrait",
		width = 1080,
		height = 1920,
		inset = nil,
		radar = { x = 940, y = 1548, w = SIZE, h = SIZE },
		zone = { { x = 910, y = 1710, w = 120, h = 120 }, { x = 860, y = 1688, w = 120, h = 120 } },
	},
	{
		name = "touch desktop",
		width = 1920,
		height = 1080,
		inset = nil,
		radar = { x = 1780, y = 708, w = SIZE, h = SIZE },
		zone = { { x = 1750, y = 870, w = 120, h = 120 }, { x = 1700, y = 848, w = 120, h = 120 } },
	},
}

local ZERO = { top = 0, bottom = 0, left = 0, right = 0 }

-- DangerHud's frame (x, y, w, h) and the band top it passes
local function frameOf(s: Sample): (number, number, number, number, number)
	local core = s.inset or ZERO
	local d = s.device or core
	return d.left, d.top, s.width - d.left - d.right, s.height - d.top - d.bottom, core.top - d.top
end

local function hitsAny(a: Rect, list: { Rect }): boolean
	for _, b in list do
		if overlaps(a, b) then
			return true
		end
	end
	return false
end

return t.spec("f0029 jump button corner", function(it)
	it("the jump buttons are Roblox's two touch jump placements, small up to a 500 px side", function()
		-- small: legacy 70 px at (W-95, H-90), ability 72 px at (W-136, H-136)
		t.expect(jumpButtons(0, 0, 390, 797)).toEqual({
			{ x = 295, y = 707, w = 70, h = 70 },
			{ x = 254, y = 661, w = 72, h = 72 },
		})
		-- large: legacy 120 px at (W-170, H-210), ability 120 px at (W-220, H-232)
		t.expect(jumpButtons(0, 0, 1920, 1080)).toEqual({
			{ x = 1750, y = 870, w = 120, h = 120 },
			{ x = 1700, y = 848, w = 120, h = 120 },
		})
		-- the frame's origin shifts both
		t.expect(jumpButtons(47, 0, 797, 390)).toEqual({
			{ x = 749, y = 300, w = 70, h = 70 },
			{ x = 708, y = 254, w = 72, h = 72 },
		})
		-- a smaller side of exactly 500 is still small, in either orientation; 501 is large
		t.expect(jumpButtons(0, 0, 800, 500)).toEqual({
			{ x = 705, y = 410, w = 70, h = 70 },
			{ x = 664, y = 364, w = 72, h = 72 },
		})
		t.expect(jumpButtons(0, 0, 500, 800)).toEqual({
			{ x = 405, y = 710, w = 70, h = 70 },
			{ x = 364, y = 664, w = 72, h = 72 },
		})
		t.expect(jumpButtons(0, 0, 800, 501)).toEqual({
			{ x = 630, y = 291, w = 120, h = 120 },
			{ x = 580, y = 269, w = 120, h = 120 },
		})
	end)

	it("bandTop is how far the core-UI area's top sits below the device area's, never negative", function()
		local core = { Min = { X = 0, Y = 0 }, Max = { X = 733, Y = 313 } }
		local device = { Min = { X = 0, Y = -58 }, Max = { X = 733, Y = 334 } }
		t.expect(bandTop(core, device)).toBe(58)
		t.expect(bandTop(core, core)).toBe(0)
		t.expect(bandTop(device, core)).toBe(0)
		local shifted = { Min = { X = -59, Y = -20 }, Max = { X = 792, Y = 334 } }
		t.expect(bandTop({ Min = { X = 0, Y = 16 }, Max = { X = 733, Y = 313 } }, shifted)).toBe(36)
	end)

	it(
		"without the touch argument, or with false, the radar is d0105's box, whatever the band top",
		function()
			for _, v in { { 1280, 720 }, { 1920, 1080 }, { 480, 320 }, { 390, 797 } } do
				local three = radarBox(v[1], v[2], SIZE)
				t.expect(radarBox(v[1], v[2], SIZE, false)).toEqual(three)
				t.expect(radarBox(v[1], v[2], SIZE, nil)).toEqual(three)
				t.expect(radarBox(v[1], v[2], SIZE, false, 58)).toEqual(three)
			end
			t.expect(radarBox(1920, 1080, SIZE, false)).toEqual({ x = 1780, y = 904, w = SIZE, h = SIZE })
		end
	)

	it("on a touch screen the radar sits one margin above the higher jump button, same right edge", function()
		local l = Hud.layout(390, 797)
		local b = radarBox(390, 797, SIZE, true)
		local higher = jumpButtons(0, 0, 390, 797)[2]
		t.expect(b).toEqual({ x = 261, y = 532, w = SIZE, h = SIZE })
		t.expect(b.y + b.h + l.margin).toBe(higher.y)
		t.expect(b.x + b.w).toBe(390 - l.margin)
		-- large frames: the ability button is still the higher one
		local wide = Hud.layout(1920, 1080)
		local w = radarBox(1920, 1080, SIZE, true)
		t.expect(w.y + w.h + wide.margin).toBe(848)
	end)

	it("on a screen too short for that, the radar stops below the top text band", function()
		-- 480 x 200: the higher button starts at y 64, so one margin above it would put the radar at y -63
		local l = Hud.layout(480, 200)
		local b = radarBox(480, 200, SIZE, true)
		t.expect(b).toEqual({ x = 353, y = l.textSize + 2 * l.margin, w = SIZE, h = SIZE })
		t.expect(b.y).toBe(28)
		-- under a 58 px top bar the band starts 58 lower
		t.expect(radarBox(480, 200, SIZE, true, 58)).toEqual({ x = 353, y = 86, w = SIZE, h = SIZE })
		-- a bad band top counts as 0
		t.expect(radarBox(480, 200, SIZE, true, 0 / 0)).toEqual(b)
		t.expect(radarBox(480, 200, SIZE, true, -5)).toEqual(b)
	end)

	it("the jump buttons are measured in the touch GUI's frame below the band top", function()
		-- 900 x 520 under a 58 px top bar: the touch frame is 900 x 462, so the buttons are the small set
		local l = Hud.layout(900, 520)
		local b = radarBox(900, 520, SIZE, true, 58)
		local higher = jumpButtons(0, 58, 900, 462)[2]
		t.expect(higher).toEqual({ x = 764, y = 384, w = 72, h = 72 })
		t.expect(b.y + b.h + l.margin).toBe(higher.y)
		t.expect(b).toEqual({ x = 768, y = 252, w = SIZE, h = SIZE })
	end)

	it(
		"a 320 px tall landscape screen under a 58 px top bar: the radar clears LEVEL, and the clamp wins",
		function()
			local row = layout(480, 320, { top = 58, bottom = 0, left = 0, right = 0 })
			local level = Touch.blocks(boxOf(row)).level
			local radar = radarBox(480, 320, SIZE, true, 58)
			t.expect(radar).toEqual({ x = 353, y = 86, w = SIZE, h = SIZE })
			t.expect(overlaps(radar, level)).toBe(false)
			t.expect(radar.y >= level.y + level.h).toBe(true)
			-- accepted: no room between the text band and the buttons, so it touches the higher one
			local zone = jumpButtons(row.safeX, row.safeY, row.safeW, row.safeH)
			t.expect(overlaps(radar, zone[2])).toBe(true)
			t.expect(overlaps(radar, zone[1])).toBe(false)
		end
	)

	it(
		"portrait and landscape samples: the radar, the power bar and the snap button miss both jump buttons",
		function()
			for _, s in SAMPLES do
				local row = layout(s.width, s.height, s.inset)
				local box = boxOf(row)
				local zone = jumpButtons(row.safeX, row.safeY, row.safeW, row.safeH)
				t.expect(zone).toEqual(s.zone)
				local fx, fy, fw, fh, band = frameOf(s)
				local r = radarBox(fw, fh, SIZE, true, band)
				local radar = { x = fx + r.x, y = fy + r.y, w = r.w, h = r.h }
				t.expect(radar).toEqual(s.radar)
				t.expect(hitsAny(radar, zone)).toBe(false)
				local blocks = Touch.blocks(box)
				t.expect(hitsAny(blocks.power, zone)).toBe(false)
				local button = Touch.snapRect(box)
				t.expect(hitsAny(button, zone)).toBe(false)
				t.expect(overlaps(button, radar)).toBe(false)
				for _, name in { "score", "level", "lives", "power" } do
					t.expect(overlaps(radar, blocks[name])).toBe(false)
				end
				-- inside the screen
				t.expect(radar.x >= 0 and radar.y >= 0).toBe(true)
				t.expect(radar.x + radar.w <= s.width and radar.y + radar.h <= s.height).toBe(true)
			end
		end
	)
	it(
		"DangerHud passes UserInputService.TouchEnabled as the touch argument, still once per render step",
		function()
			local game = place.load()
			local node = game:FindFirstChild("StarterPlayer")
				:FindFirstChild("StarterPlayerScripts")
				:FindFirstChild("Client")
				:FindFirstChild("DangerHud")
			t.expect(node ~= nil and node.ClassName).toBe("ModuleScript")
			local src = string.gsub(node.Source, "%-%-[^\n]*", "")
			local call = "local box = Hud.radarBox(view.X, view.Y, radarSize, UserInputService.TouchEnabled, bandTop())\n"
				.. "\t\tradar.Position = UDim2.fromOffset(box.x, box.y)\n"
			t.expect(string.find(src, call, 1, true) ~= nil).toBe(true)
			t.expect(string.find(src, 'game:GetService("UserInputService")', 1, true) ~= nil).toBe(true)
			-- bandTop() reads the two areas each frame, core first, through the pure helper
			t.expect(string.find(src, "local function bandTop()", 1, true) ~= nil).toBe(true)
			-- and its body is the helper: no constant band with an unused helper call beside it
			t.expect(string.find(src, "local function bandTop%(%)[^\n]*\n%s*return Hud%.bandTop%(") ~= nil)
				.toBe(true)
			local helper = string.match(src, "Hud%.bandTop%b()") or ""
			local core = string.find(helper, "ScreenInsets.CoreUISafeInsets", 1, true)
			local device = string.find(helper, "ScreenInsets.DeviceSafeInsets", 1, true)
			t.expect(core ~= nil and device ~= nil).toBe(true)
			if core and device then
				t.expect(core < device).toBe(true)
			end
			t.expect(select(2, string.gsub(helper, "GetInsetArea%(", "")) == 2).toBe(true)
			local n = 0
			for _ in string.gmatch(src, "Hud%.radarBox%(") do
				n += 1
			end
			t.expect(n).toBe(1)
		end
	)
end)
