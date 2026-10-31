--!strict
-- c0159 AC1 and AC2: three promoted specs that pin DangerHud's edge glows are narrowed, not deleted, so that f0158's
-- danger ring (decided with the user, 2026-10-26: "Replace edge glows"; its screen is the core-UI safe area, G8) can
-- land with main green. The five cases narrowed:
--   tests/acceptance/d0105/adapter.spec.luau :: "it still draws the radar Awareness computes" (no edgePoint needle)
--   tests/acceptance/f0033/adapters.spec.luau :: "it draws what Awareness computes: the radar and the indicators"
--   tests/acceptance/f0102/place.spec.luau :: "it draws the danger directions Awareness computes: the edge glows, or f0158's ring"
--   tests/acceptance/f0102/place.spec.luau :: "the danger directions have their own screen, under the radar, the Flow overlay and the HUD"
--   tests/acceptance/f0102/place.spec.luau :: "DangerHud colours nothing by position"
-- c0106's narrow-adapter.spec fingerprints d0105's adapter.spec as text, so its two fingerprint values move with
-- the narrowing (c0159 overrides it too). Each changed file is pinned whole (lesson zz-test/narrowing-pins-the-whole-file), by the SHA-256 of its exact
-- text with only item ids masked and line endings made LF (c0150's model). Then every case of the three files runs
-- in this process against today's DangerHud and against RING, a DangerHud drawing f0158's ring as f0158's Design
-- describes it: both must pass, and so must each CORRECT variant of RING (other spellings f0158 may use; design review
-- 001 F1/F3). Each REGRESSION of RING must still fail the case named for it. The three
-- specs read DangerHud's source from place.load()'s DataModel, which is built once per process and shared, so this
-- spec swaps that ModuleScript's Source and puts it back after each run. It reads the files as text, so any later
-- change to one of them must update its digest here (only `--full` runs a text read; the requires keep this spec
-- selected for DangerHud and Awareness changes).
local d0105 = require("@tests/acceptance/d0105/adapter.spec")
local f0033 = require("@tests/acceptance/f0033/adapters.spec")
local f0102 = require("@tests/acceptance/f0102/place.spec")
local fs = require("@lune/fs")
local place = require("@tests/lib/place")
local serde = require("@lune/serde")
local t = require("@tests/lib/t")

-- today's ids, as full tests/acceptance/<id> paths, which a compaction rewrites with the folders; each item folder's
-- id is taken from them (renamed.id is for ids written before a compaction)
local FILES = {
	{ dir = "tests/acceptance/d0105", file = "adapter.spec.luau", spec = d0105 },
	{ dir = "tests/acceptance/f0033", file = "adapters.spec.luau", spec = f0033 },
	{ dir = "tests/acceptance/f0102", file = "place.spec.luau", spec = f0102 },
}

-- every file c0159 changes, each pinned whole: the three above, and c0106's spec, whose fingerprint of d0105's
-- adapter.spec moves with the narrowing (it reads that file as text; it never reads DangerHud)
local PINNED = {
	{ dir = "tests/acceptance/d0105", file = "adapter.spec.luau" },
	{ dir = "tests/acceptance/f0033", file = "adapters.spec.luau" },
	{ dir = "tests/acceptance/f0102", file = "place.spec.luau" },
	{ dir = "tests/acceptance/c0106", file = "narrow-adapter.spec.luau" },
}

local SHA: { [string]: string } = {
	["adapter.spec.luau"] = "1edeac3fea7d9110dc1c2df1f505962911acbfad5cbac381763156f70a15ddfb",
	["adapters.spec.luau"] = "e924857f23e329df401fff4be20a53fb9fb640fa55c90423b53dfbc0ae7755ba",
	["narrow-adapter.spec.luau"] = "1564e4533699751d2117b08c9306a6dbeb35b8ab4c7865a233dabb2463ae43ba",
	["place.spec.luau"] = "51d4688d3a5b9765366106b31e7de8f2276b426111deec46dbcb0c3b35992d9a",
}

-- the file's text with item ids masked and CRLF made LF; nothing else changes
local function exact(path: string): string
	local text = string.gsub(fs.readFile(path), "\r\n", "\n")
	text = string.gsub(text, "%f[%w_][fdcR]%d+%f[^%w_]", "ID")
	return text
end

-- A DangerHud that draws f0158's ring instead of the edge glows: today's radar unchanged; the glows' screen becomes
-- the ring's (Ring, the core-UI safe area, DisplayOrder -1), and each render step draws Awareness.ring's dots in
-- View.DANGER_COLOR (lit) or white (unlit). Its requires are spelled through REQ so that no require text appears
-- in this file.
local REQ = "requ" .. "ire"
local RING = string.gsub(
	[==[
--!strict
-- Client adapter: the danger aids. A radar in the bottom-right corner (Hud.radarBox), and the danger ring
-- (f0158): one circle of dots around the middle of the core-UI safe area, a sector lit for each direction a
-- dangerous ghost is in. All the geometry is Awareness (and the colours View); this only draws it.
local GuiService = game:GetService("GuiService") :: any
local Players = game:GetService("Players")
local RunService = game:GetService("RunService")
local UserInputService = game:GetService("UserInputService")

local Awareness = REQ("@game/ReplicatedStorage/Shared/Logic/Awareness")
local Hud = REQ("@game/ReplicatedStorage/Shared/Logic/Hud")
local Maze = REQ("@game/ReplicatedStorage/Shared/Logic/Maze")
local Session = REQ("@game/ReplicatedStorage/Shared/Logic/Session")
local View = REQ("@game/ReplicatedStorage/Shared/Logic/View")

local CELL = 8
local LOOK_COLORS: { [string]: Color3 } = {
	normal = Color3.fromRGB(255, 60, 60),
	frightened = Color3.fromRGB(80, 80, 255),
	blinking = Color3.fromRGB(230, 230, 255),
	eyes = Color3.fromRGB(200, 200, 200),
}

local DangerHud = {}

local latest: Session.Snapshot? = nil
local maze: Maze.Maze? = nil

function DangerHud.push(snap: Session.Snapshot, m: Maze.Maze)
	if latest == nil or snap.tick > latest.tick then
		latest = snap
		maze = m
	end
end

function DangerHud.start(getPose: () -> Awareness.Pose?)
	local gui = Instance.new("ScreenGui")
	gui.Name = "Danger"
	gui.ResetOnSpawn = false
	gui.IgnoreGuiInset = true
	gui.Parent = (Players.LocalPlayer :: Player):WaitForChild("PlayerGui")
	local ring = Instance.new("ScreenGui")
	ring.Name = "Ring"
	ring.ResetOnSpawn = false
	ring.ScreenInsets = Enum.ScreenInsets.CoreUISafeInsets
	ring.DisplayOrder = -1
	ring.Parent = gui.Parent

	local radarSize = (Awareness.RADAR_RADIUS * 2 + 1) * CELL
	local radar = Instance.new("Frame")
	radar.Name = "Radar"
	radar.Size = UDim2.fromOffset(radarSize, radarSize)
	radar.BackgroundColor3 = Color3.new(0, 0, 0)
	radar.BackgroundTransparency = 0.35
	radar.ClipsDescendants = true
	radar.Parent = gui
	local function dot(parent: Instance, color: Color3, size: number): Frame
		local f = Instance.new("Frame")
		f.AnchorPoint = Vector2.new(0.5, 0.5)
		f.Size = UDim2.fromOffset(size, size)
		f.BackgroundColor3 = color
		f.BorderSizePixel = 0
		f.Parent = parent
		return f
	end
	local you = dot(radar, Color3.fromRGB(255, 255, 0), CELL)
	you.Position = UDim2.fromOffset(radarSize / 2, radarSize / 2)
	local walls: { Frame } = {}
	local blips: { Frame } = {}
	local frames: { Frame } = {}
	local function bandTop(): number
		return Hud.bandTop(
			GuiService:GetInsetArea(Enum.ScreenInsets.CoreUISafeInsets),
			GuiService:GetInsetArea(Enum.ScreenInsets.DeviceSafeInsets)
		)
	end
	RunService.RenderStepped:Connect(function()
		local view = gui.AbsoluteSize
		local box = Hud.radarBox(view.X, view.Y, radarSize, UserInputService.TouchEnabled, bandTop())
		radar.Position = UDim2.fromOffset(box.x, box.y)
		local snap, m, pose = latest, maze, getPose()
		if snap == nil or m == nil or pose == nil or snap.ghosts == nil then
			return
		end
		local ghosts: { Awareness.Ghost } = {}
		for _, g in snap.ghosts do
			local entry: Awareness.Ghost = { x = g.x, y = g.y, look = g.look, name = g.name, flash = g.flash }
			table.insert(ghosts, entry)
		end
		local r = Awareness.radar(m, pose, ghosts)
		for i, w in r.walls do
			local f: Frame = walls[i] or dot(radar, Color3.fromRGB(33, 33, 222), CELL)
			walls[i] = f
			f.Visible = true
			f.Position = UDim2.fromOffset(radarSize / 2 + w.x * CELL, radarSize / 2 + w.y * CELL)
		end
		for i = #r.walls + 1, #walls do
			walls[i].Visible = false
		end
		for i = 1, #ghosts do
			local f: Frame = blips[i] or dot(radar, Color3.new(1, 1, 1), CELL)
			blips[i] = f
			f.Visible = false
		end
		for i, b in r.blips do
			local f: Frame = blips[i]
			f.Visible = true
			f.BackgroundColor3 = LOOK_COLORS[b.look] or LOOK_COLORS.normal
			f.Position = UDim2.fromOffset(radarSize / 2 + b.x * CELL, radarSize / 2 + b.y * CELL)
		end

		local area = ring.AbsoluteSize
		local list = Awareness.indicators(m, pose, ghosts, {
			verticalFieldOfView = math.rad(workspace.CurrentCamera.FieldOfView),
			aspect = area.X / math.max(area.Y, 1),
			inView = true,
		})
		local warn = View.DANGER_COLOR
		local spec = Awareness.RING
		for i, d in Awareness.ring(list, area.X, area.Y) do
			local f = frames[i]
			if f == nil then
				f = Instance.new("Frame")
				f.BorderSizePixel = 0
				local corner = Instance.new("UICorner")
				corner.CornerRadius = UDim.new(0.5, 0)
				corner.Parent = f
				f.Parent = ring
				frames[i] = f
			end
			f.Position = UDim2.fromOffset(d.x, d.y)
			f.Size = UDim2.fromOffset(d.w, d.h)
			if d.lit then
				f.BackgroundColor3 = Color3.fromRGB(warn.r, warn.g, warn.b)
				f.BackgroundTransparency = 1 - (spec.lit.min + (spec.lit.max - spec.lit.min) * d.closeness)
			else
				f.BackgroundColor3 = Color3.new(1, 1, 1)
				f.BackgroundTransparency = 1 - spec.idle
			end
		end
	end)
end

return DangerHud
]==],
	"REQ%(",
	REQ .. "("
)

type Regression = { name: string, from: string, to: string, fails: { string } }

local SCREEN = "the danger directions have their own screen, under the radar, the Flow overlay and the HUD"

-- each a plausible wrong ring DangerHud, and the narrowed case that must still catch it
local REGRESSIONS: { Regression } = {
	{
		name = "the radar is no longer asked",
		from = "local r = Awareness.radar(m, pose, ghosts)",
		to = "local r = { walls = {}, blips = {} }",
		fails = {
			"it still draws the radar Awareness computes",
			"it draws what Awareness computes: the radar and the indicators",
		},
	},
	{
		name = "the ring is not drawn from Awareness",
		from = "Awareness.ring(list, area.X, area.Y)",
		to = "{}",
		fails = { "it draws the danger directions Awareness computes: the edge glows, or f0158's ring" },
	},
	{
		name = "the ring is drawn over the HUD",
		from = "ring.DisplayOrder = -1",
		to = "ring.DisplayOrder = 2",
		fails = { SCREEN },
	},
	{
		name = "the ring's screen keeps the default order, level with the radar and the Flow overlay",
		from = "\n\tring.DisplayOrder = -1",
		to = "",
		fails = { SCREEN },
	},
	{
		name = "the ghosts are read by position",
		from = "for _, g in snap.ghosts do",
		to = "for k = 1, #snap.ghosts do\n\t\t\tlocal g = snap.ghosts[k]",
		fails = { "DangerHud colours nothing by position" },
	},
}

-- correct ring DangerHuds spelled otherwise: every case of the three specs must pass on each
local CORRECT: { { name: string, from: string, to: string } } = {
	{
		name = "the insets set through a local",
		from = "ring.ScreenInsets = Enum.ScreenInsets.CoreUISafeInsets",
		to = "local insets = Enum.ScreenInsets.CoreUISafeInsets\n\tring.ScreenInsets = insets",
	},
	{
		name = "another order below 0",
		from = "ring.DisplayOrder = -1",
		to = "ring.DisplayOrder = -5",
	},
	{
		name = "the ghost entries without the names and flashes the ring does not use",
		from = "{ x = g.x, y = g.y, look = g.look, name = g.name, flash = g.flash }",
		to = "{ x = g.x, y = g.y, look = g.look }",
	},
	{
		name = "the dots kept in a local before drawing",
		from = "for i, d in Awareness.ring(list, area.X, area.Y) do",
		to = "local dots = Awareness.ring(list, area.X, area.Y)\n\t\tfor i, d in dots do",
	},
}

-- RING with the one occurrence of from replaced by to (the anchor must occur exactly once)
local function edited(from: string, to: string): string
	local at, stop = string.find(RING, from, 1, true)
	t.expect(at ~= nil and string.find(RING, from, (stop :: number) + 1, true) == nil).toBe(true)
	return string.sub(RING, 1, (at :: number) - 1) .. to .. string.sub(RING, (stop :: number) + 1)
end

local game = place.load() -- the same DataModel the three specs read (place.load builds once per process)

local function dangerHud(): any
	local node: any = game
	for _, part in { "StarterPlayer", "StarterPlayerScripts", "Client", "DangerHud" } do
		node = node and node:FindFirstChild(part)
	end
	t.expect(node ~= nil and node.ClassName).toBe("ModuleScript")
	return node
end

-- runs every case of the three specs with DangerHud's source set to src, puts the real source back, and returns
-- the names of the cases that failed; a failure that is not one of t's assertions is an error here
local function failing(src: string): { [string]: boolean }
	local node = dangerHud()
	local real = node.Source
	node.Source = src
	local failed: { [string]: boolean } = {}
	local ok, err = pcall(function()
		for _, f in FILES do
			for _, c in f.spec.cases do
				local passed, why = pcall(c.fn :: () -> any)
				if not passed then
					-- t raises at its caller's line ("<file>:<line>: expected …"); Luau's own errors never start so
					if not string.find(tostring(why), "^[^\n]-:%d+: expected ") then
						error(`{c.name}: not an assertion failure: {why}`, 0)
					end
					failed[c.name] = true
				end
			end
		end
	end)
	node.Source = real
	if not ok then
		error(err, 0)
	end
	return failed
end

local function names(set: { [string]: boolean }): string
	local list = {}
	for k in set do
		table.insert(list, k)
	end
	table.sort(list)
	return table.concat(list, "; ")
end

return t.spec("c0159 the edge-glow pins, narrowed", function(it)
	it("the four specs are still there, and their items' check.sh files still run them", function()
		for _, f in PINNED do
			t.expect(fs.isFile(f.dir .. "/" .. f.file)).toBe(true)
			local id = string.match(f.dir, "[^/]+$")
			assert(id, "no id in " .. f.dir)
			-- a check line (one starting `check "`, not a comment) runs the file
			local runs = false
			for line in string.gmatch(fs.readFile(".tracker/issues/done/" .. id .. "/check.sh"), "[^\n]+") do
				if string.sub(line, 1, 7) == 'check "' and string.find(line, `"$A/{f.file}"`, 1, true) then
					runs = true
				end
			end
			t.expect(runs).toBe(true)
		end
	end)

	it("each changed file is exactly the narrowed one", function()
		for _, f in PINNED do
			t.expect(serde.hash("sha256", exact(f.dir .. "/" .. f.file))).toBe(SHA[f.file])
		end
	end)

	it("every case of the three specs passes on today's DangerHud", function()
		t.expect(names(failing(dangerHud().Source))).toBe("")
	end)

	it(
		"every case of the three specs passes on a DangerHud that draws f0158's ring instead of the glows",
		function()
			t.expect(names(failing(RING))).toBe("")
		end
	)

	it("every case of the three specs passes on each correct variant of the ring DangerHud", function()
		for _, c in CORRECT do
			local failed = names(failing(edited(c.from, c.to)))
			if failed ~= "" then
				error(`{c.name}: failed {failed}`, 0)
			end
		end
	end)

	it("each regression of the ring DangerHud still fails the case that pins it", function()
		local cases: { [string]: boolean } = {}
		for _, f in FILES do
			for _, c in f.spec.cases do
				cases[c.name] = true
			end
		end
		for _, r in REGRESSIONS do
			for _, name in r.fails do
				if not cases[name] then
					error(`{r.name}: no case named "{name}"`, 0)
				end
			end
			local failed = failing(edited(r.from, r.to))
			for _, name in r.fails do
				if not failed[name] then
					error(`{r.name}: "{name}" still passed (failed: {names(failed)})`, 0)
				end
			end
		end
	end)
end)
