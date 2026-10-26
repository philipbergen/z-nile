--!strict
-- f0109: the walls are painted by one rule, View.wallColor (the flash wins, then green while the ghosts are edible,
-- else blue). MazeView's real source runs here on the fake engine (pickman/tests/lib/fakeengine, extended by f0109
-- for Vector3, :SetAttribute, :IsA, the client services and fake.module): every wall part follows blue, green, white,
-- green, blue, and so does every wall dot of the danger radar (DangerHud's real source), whose walls follow the same
-- rule (the user, 2026-10-25). Main hands the lit and edible state to both. The pellets' and shots' colours are read from their views' sources.
local Maze = require("@logic/Maze")
local View = require("@logic/View")
local fake = require("@tests/lib/fakeengine")
local place = require("@tests/lib/place")
local t = require("@tests/lib/t")

local game = place.load()

local function client(name: string): any
	local node = game
	for _, n in { "StarterPlayer", "StarterPlayerScripts", "Client", name } do
		node = node and node:FindFirstChild(n)
	end
	return node
end

-- a script's source without comments, so a mention in a comment proves nothing
local function source(node: any): string
	local src = string.gsub(node.Source, "%-%-[^\n]*", "")
	return src
end

-- the RGB a fake Color3 (fractions, Color3.fromRGB / 255) stands for
local function rgb255(c: any): string
	return `{math.floor(c.R * 255 + 0.5)},{math.floor(c.G * 255 + 0.5)},{math.floor(c.B * 255 + 0.5)}`
end

-- the colour every part named `name` of the model has, or "mixed"
local function colourOf(model: any, name: string): string
	local seen: string? = nil
	local n = 0
	for _, c in model:GetChildren() do
		if c.Name == name then
			n += 1
			local key = rgb255(c.Color)
			if seen ~= nil and seen ~= key then
				return "mixed"
			end
			seen = key
		end
	end
	t.expect(n > 0).toBe(true)
	return seen :: string
end

-- the `local COLOR = Color3.fromRGB(r, g, b)` of a view's source
local function viewColour(name: string): View.Rgb
	local r, g, b =
		string.match(source(client(name)), "local COLOR = Color3%.fromRGB%((%d+),%s*(%d+),%s*(%d+)%)")
	t.expect(r ~= nil).toBe(true)
	return { r = tonumber(r) :: number, g = tonumber(g) :: number, b = tonumber(b) :: number }
end

local function lin(v: number): number
	local c = v / 255
	return if c <= 0.03928 then c / 12.92 else ((c + 0.055) / 1.055) ^ 2.4
end
local function lab(c: View.Rgb): (number, number, number)
	local r, g, b = lin(c.r), lin(c.g), lin(c.b)
	local x = (0.4124 * r + 0.3576 * g + 0.1805 * b) / 0.95047
	local y = 0.2126 * r + 0.7152 * g + 0.0722 * b
	local z = (0.0193 * r + 0.1192 * g + 0.9505 * b) / 1.08883
	local function f(v: number): number
		return if v > 0.008856 then v ^ (1 / 3) else 7.787 * v + 16 / 116
	end
	return 116 * f(y) - 16, 500 * (f(x) - f(y)), 200 * (f(y) - f(z))
end
local function distance(a: View.Rgb, b: View.Rgb): number
	local l1, a1, b1 = lab(a)
	local l2, a2, b2 = lab(b)
	return math.sqrt((l1 - l2) ^ 2 + (a1 - a2) ^ 2 + (b1 - b2) ^ 2)
end

return t.spec("f0109 the walls follow View.wallColor", function(it)
	it(
		"MazeView's real source paints every wall blue, green when edible, white in the flash, green again, then blue",
		function()
			local MazeView = fake.module(client("MazeView").Source, "MazeView")
			local model = MazeView.build(Maze.layout("classic"))
			local function walls(): string
				return colourOf(model, "Wall")
			end
			t.expect(walls()).toBe("33,33,222")
			MazeView.edible(model, true)
			t.expect(walls()).toBe("14,64,14")
			MazeView.flash(model, true)
			t.expect(walls()).toBe("255,255,255")
			MazeView.flash(model, false)
			t.expect(walls()).toBe("14,64,14") -- the flash ends while the ghosts are still edible
			MazeView.edible(model, false)
			t.expect(walls()).toBe("33,33,222")
			-- the door and the floor keep their own colours throughout
			t.expect(colourOf(model, "Door")).toBe("255,184,255")
			t.expect(colourOf(model, "Floor")).toBe("0,0,0")
		end
	)

	it(
		"every wall part MazeView makes takes the model's current colour (a wall built while edible is green)",
		function()
			local src = source(client("MazeView"))
			t.expect((string.find(src, "View.wallColor(false, false)", 1, true))).toBe(nil)
			t.expect(string.find(src, "local function wallColorOf(", 1, true) ~= nil).toBe(true)
			t.expect(string.find(src, '"Wall", wallColorOf(', 1, true) ~= nil).toBe(true)
		end
	)

	it("Main hands the lit and edible state to MazeView and to the danger radar each frame", function()
		local src = source(client("Main"))
		t.expect(
			string.find(src, "MazeView%.edible%(%s*[%w_]+%s*,%s*View%.edible%(%s*[%w_]+%.play%s*%)%s*%)")
				~= nil
		)
			.toBe(true)
		t.expect(string.find(src, "MazeView%.flash%([^)]*%.flash%s*%)") ~= nil).toBe(true)
		t.expect(
			string.find(
				src,
				"DangerHud%.wallState%(%s*[%w_]+%.flash%s*,%s*View%.edible%(%s*[%w_]+%.play%s*%)%s*%)"
			) ~= nil
		).toBe(true)
	end)

	-- design review 002 F1: DangerHud's real source on the fake engine, a real snapshot, one render step per state
	it(
		"the danger radar's real source paints its wall dots by View.wallColor for each state Main hands it",
		function()
			local DangerHud, view = fake.module(client("DangerHud").Source, "DangerHud")
			local Session = require("@logic/Session")
			local classic = Maze.layout("classic")
			local s = Session.new(classic, 1, Session.GAME_CONFIG)
			Session.join(s, "p")
			for _ = 1, 61 do
				Session.step(s)
			end
			local snap = Session.snapshot(s, "p")
			local pose = { x = snap.player.x, y = snap.player.y, yaw = 0 }
			DangerHud.start(function(): any
				return pose
			end)
			DangerHud.push(snap, classic)
			local radar = view.playerGui:FindFirstChild("Danger"):FindFirstChild("Radar")
			local YOU, BLIP = "255,255,0", "255,60,60" -- the player's dot and a hunting ghost's blip
			local function wallDots(): (number, { [string]: boolean })
				local n, seen = 0, {}
				for _, f in radar:GetChildren() do
					if f.Visible ~= false then
						local key = rgb255(f.BackgroundColor3)
						if key ~= YOU and key ~= BLIP then
							n += 1
							seen[key] = true
						end
					end
				end
				return n, seen
			end
			for _, state in
				{ { false, false }, { false, true }, { true, true }, { false, true }, { false, false } }
			do
				DangerHud.wallState(state[1], state[2])
				view.renderStepped:fire(1 / 60)
				local c = View.wallColor(state[1], state[2])
				local want = `{c.r},{c.g},{c.b}`
				local n, seen = wallDots()
				t.expect(n > 0).toBe(true)
				for key in seen do
					t.expect(key).toBe(want)
				end
			end
		end
	)

	it("Inky's colour is far from the pellets' and the shots' as their views draw them", function()
		local inky = View.GHOST_COLORS.inky
		t.expect(distance(inky, viewColour("PelletView")) >= 30).toBe(true)
		t.expect(distance(inky, viewColour("BlastView")) >= 30).toBe(true)
	end)
end)
