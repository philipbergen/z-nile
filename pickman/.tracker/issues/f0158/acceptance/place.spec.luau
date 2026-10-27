--!strict
-- f0158 AC3: DangerHud draws the danger ring and decides nothing. Its real source runs on the fake engine
-- (pickman/tests/lib/fakeengine's fake.module, from f0109, which f0158 depends on) with a real snapshot. After a
-- render step the drawn Ring screen is the core-UI safe area below Roblox's top bar (G8: ScreenInsets
-- CoreUISafeInsets, never IgnoreGuiInset, review 003 F2), under the radar and the HUD (DisplayOrder below 0). It
-- holds Awareness.SECTORS x Awareness.RING.dots frames, the same frames after a second step, each round and anchored
-- at its box's top-left (review 002 F3), at the box Awareness.ring gives for the indicators Awareness computes; a lit
-- dot in View.DANGER_COLOR at transparency 1 - (lit.min + (lit.max - lit.min) x closeness), an unlit one white at
-- 1 - RING.idle, so a near dangerous ghost's sector is more opaque than a far one's (review 001 F2). When the Ring
-- screen's area differs from the screen's, the dots follow the Ring screen's area (review 002 F1). The edge glows'
-- boxes are gone and the adapter does no geometry (source reads).
-- Casts keep the spec type-legal on main before f0158 (Awareness.ring, RING, View.DANGER_COLOR) and f0109 (fake.module)
-- exist; a missing member fails at the call.
local Awareness: any = require("@logic/Awareness")
local Maze = require("@logic/Maze")
local Session = require("@logic/Session")
local View: any = require("@logic/View")
local fake: any = require("@tests/lib/fakeengine")
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
	return (string.gsub(client(name).Source, "%-%-[^\n]*", ""))
end

local function has(src: string, needle: string): boolean
	return string.find(src, needle, 1, true) ~= nil
end

local W, H = 1280, 720
local EPS = 1e-6

local function near(a: number, b: number): boolean
	return math.abs(a - b) < EPS
end

-- an open tile `lo`..`hi` steps from the player along the maze, in another sector than `notSector`
local function ghostAt(m: Maze.Maze, pose: any, lo: number, hi: number, notSector: number?): (number, number)
	local from = { x = math.floor(pose.x + 0.5), y = math.floor(pose.y + 0.5) }
	for y = 0, m.height - 1 do
		for x = 0, m.width - 1 do
			if Maze.kind(m, { x = x, y = y }) ~= "wall" then
				local d = Awareness.pathDistance(m, from, { x = x, y = y }, hi)
				if d and d >= lo and Awareness.sector(Awareness.bearing(pose, x, y)) ~= notSector then
					return x, y
				end
			end
		end
	end
	error(`no open tile {lo}..{hi} away`, 0)
end

return t.spec("f0158 ring adapter", function(it)
	it(
		"its real source draws Awareness.ring's dots: boxes, the warning colour, the opacities, frames reused",
		function()
			local DangerHud, view = fake.module(client("DangerHud").Source, "DangerHud", { X = W, Y = H })
			local classic = Maze.layout("classic")
			local session = Session.new(classic, 1, Session.GAME_CONFIG)
			Session.join(session, "p")
			for _ = 1, 61 do
				Session.step(session)
			end
			local snap: any = Session.snapshot(session, "p")
			local pose = { x = snap.player.x, y = snap.player.y, yaw = 0 }
			local nx, ny = ghostAt(classic, pose, 2, 3, nil)
			local nearSector = Awareness.sector(Awareness.bearing(pose, nx, ny))
			local fx, fy = ghostAt(classic, pose, 9, 11, nearSector)
			local farSector = Awareness.sector(Awareness.bearing(pose, fx, fy))
			local ghosts: { any } = {
				{ x = nx, y = ny, look = "normal", name = "blinky", flash = false },
				{ x = fx, y = fy, look = "normal", name = "inky", flash = false },
			}
			snap.ghosts = ghosts
			DangerHud.start(function(): any
				return pose
			end)
			DangerHud.push(snap, classic)
			view.renderStepped:fire(1 / 60)
			local ring = view.playerGui:FindFirstChild("Ring")
			t.expect(ring ~= nil).toBe(true)
			-- review 003 F2: the drawn Ring screen is the core-UI area (G8), never IgnoreGuiInset (which in Roblox resets
			-- ScreenInsets to the device area), and below the radar's screen (Danger, the default 0)
			t.expect(tostring(ring.ScreenInsets)).toBe("ScreenInsets.CoreUISafeInsets")
			t.expect(ring.IgnoreGuiInset == nil or ring.IgnoreGuiInset == false).toBe(true)
			t.expect(ring.DisplayOrder ~= nil and ring.DisplayOrder < 0).toBe(true)
			local danger = view.playerGui:FindFirstChild("Danger")
			t.expect(danger.DisplayOrder == nil or danger.DisplayOrder == 0).toBe(true)
			local want = Awareness.ring(Awareness.indicators(classic, pose, ghosts, { inView = true }), W, H)
			local count = Awareness.SECTORS * Awareness.RING.dots
			t.expect(#want).toBe(count)
			local frames = ring:GetChildren()
			t.expect(#frames).toBe(count)
			local lit = 0
			local opacity: { [number]: number } = {}
			for i, f in frames do
				local d = want[i]
				t.expect(f.Visible).toBe(true)
				-- round, and anchored at its box's top-left (review 002 F3): a centre anchor would draw the ring half a dot off
				t.expect(f.AnchorPoint == nil or (f.AnchorPoint.X == 0 and f.AnchorPoint.Y == 0)).toBe(true)
				local corners = 0
				for _, c in f:GetChildren() do
					if c.ClassName == "UICorner" then
						corners += 1
						t.expect(c.CornerRadius.Scale).toBe(0.5)
					end
				end
				t.expect(corners).toBe(1)
				t.expect(near(f.Position.X.Offset, d.x) and near(f.Position.Y.Offset, d.y)).toBe(true)
				t.expect(near(f.Size.X.Offset, d.w) and near(f.Size.Y.Offset, d.h)).toBe(true)
				local c = f.BackgroundColor3
				if d.lit then
					lit += 1
					local r = View.DANGER_COLOR
					t.expect(near(c.R, r.r / 255) and near(c.G, r.g / 255) and near(c.B, r.b / 255))
						.toBe(true)
					local a = Awareness.RING.lit.min
						+ (Awareness.RING.lit.max - Awareness.RING.lit.min) * d.closeness
					t.expect(near(f.BackgroundTransparency, 1 - a)).toBe(true)
					opacity[d.sector] = 1 - f.BackgroundTransparency
				else
					t.expect(c.R == 1 and c.G == 1 and c.B == 1).toBe(true)
					t.expect(near(f.BackgroundTransparency, 1 - Awareness.RING.idle)).toBe(true)
				end
			end
			t.expect(lit).toBe(2 * Awareness.RING.dots)
			t.expect(opacity[nearSector] > opacity[farSector]).toBe(true)
			-- a second step keeps the same frames
			view.renderStepped:fire(1 / 60)
			local again = ring:GetChildren()
			t.expect(#again).toBe(count)
			for i, f in frames do
				t.expect(again[i] == f).toBe(true)
			end
			-- review 002 F1: the ring is sized and centred by its own screen's area (G8), not the radar's or the camera's.
			-- The fake gives every screen the screen's size, so the Ring screen gets a core-UI-sized area (f0029's
			-- 58 / 21 / 59 / 59 inset) while the Danger screen keeps W x H.
			local cw, ch = W - 118, H - 79
			ring.AbsoluteSize = { X = cw, Y = ch }
			t.expect(view.playerGui:FindFirstChild("Danger").AbsoluteSize.X).toBe(W)
			view.renderStepped:fire(1 / 60)
			local inner =
				Awareness.ring(Awareness.indicators(classic, pose, ghosts, { inView = true }), cw, ch)
			for i, f in ring:GetChildren() do
				local d = inner[i]
				t.expect(near(f.Position.X.Offset, d.x) and near(f.Position.Y.Offset, d.y)).toBe(true)
				t.expect(near(f.Size.X.Offset, d.w) and near(f.Size.Y.Offset, d.h)).toBe(true)
			end
		end
	)

	it("it asks Awareness.ring and paints from View.DANGER_COLOR, never a ghost's colour", function()
		local src = source("DangerHud")
		t.expect(has(src, "Awareness.ring(")).toBe(true)
		t.expect(has(src, "View.DANGER_COLOR")).toBe(true)
		t.expect(has(src, "View.ghostColor(")).toBe(false)
	end)

	it(
		"the ring has its own screen, the core-UI safe area below the top bar (the HUD's frame), under the HUD",
		function()
			-- G8, decided with the user 2026-10-26: "Centre below top bar"
			local src = source("DangerHud")
			t.expect(string.find(src, "%.ScreenInsets%s*=%s*Enum%.ScreenInsets%.CoreUISafeInsets") ~= nil)
				.toBe(true)
			local orders = {}
			for n in string.gmatch(src, "DisplayOrder%s*=%s*(%-?%d+)") do
				table.insert(orders, tonumber(n) :: number)
			end
			t.expect(#orders).toBe(1)
			-- below 0 (review 002 F4): the radar (Danger, the default 0), the Flow overlay and the HUD (1) draw over the
			-- ring, which G9's accepted overlaps rely on
			t.expect(orders[1] < 0).toBe(true)
			local flow = string.match(source("FlowView"), "DisplayOrder%s*=%s*(%-?%d+)")
			t.expect(flow == nil or (tonumber(flow) :: number) > orders[1]).toBe(true)
			t.expect(has(source("HudView"), "DisplayOrder = 1")).toBe(true)
		end
	)

	it("the edge glows are gone and the adapter does no geometry", function()
		local src = source("DangerHud")
		for _, word in
			{ "Awareness.glowBox(", "Awareness.edgePoint(", "math.sin", "math.cos", "math.atan", "math.sqrt" }
		do
			t.expect(has(src, word)).toBe(false)
		end
	end)
end)
