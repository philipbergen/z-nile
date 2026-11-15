--!strict
-- f0203 AC5: every game's controls, as its game design lists them, are built from the cores on every input
-- (keyboard, gamepad and touch: pickman's rule, f0146), and the cores hold no key map (each game keeps its own).
-- The tables quote pickman/.tracker/game-design.md (Platforms, Gamepad), snake's, invaders' and asteroids' game designs.
local Look = require("@logic/Look")
local Pad = require("@logic/Pad")
local Touch = require("@logic/Touch")
local fs = require("@lune/fs")
local t = require("@tests/lib/t")

type Game = {
	name: string,
	buttons: { string }, -- the touch buttons the design names
	left: Touch.Use,
	right: Touch.Use,
	steer: "turns" | "held", -- the stick sends one turn a push, or is held to move or rotate
	axes: Pad.Axes,
	lookStick: boolean, -- the right stick looks
	arrowsLook: boolean, -- the arrow keys look and spring back
}

local GAMES: { Game } = {
	-- pickman: swipe-to-turn on the left half, look on the right, SNAP, FIRE, JUMP and PICK buttons; the left stick
	-- and the D-pad turn (one intent a push), the right stick looks; the arrows look (f0104)
	{
		name = "pickman",
		buttons = { "snap", "fire", "hop", "pick" },
		left = "swipe",
		right = "look",
		steer = "turns",
		axes = "both",
		lookStick = true,
		arrowsLook = true,
	},
	-- snake: "A/D turn, arrow keys look, Space boosts. Gamepad: stick or D-pad turns, RT boosts. Touch: LEFT and RIGHT
	-- buttons on the bottom corners and a BOOST button"
	{
		name = "snake",
		buttons = { "left", "right", "boost" },
		left = "none",
		right = "none",
		steer = "turns",
		axes = "horizontal",
		lookStick = false,
		arrowsLook = true,
	},
	-- invaders: "A/D (or the arrows) move, Space fires. Gamepad: stick or D-pad moves, A or RT fires. Touch: LEFT and
	-- RIGHT buttons on the left, a FIRE disc on the right"
	{
		name = "invaders",
		buttons = { "left", "right", "fire" },
		left = "none",
		right = "none",
		steer = "held",
		axes = "horizontal",
		lookStick = false,
		arrowsLook = false,
	},
	-- asteroids: "A/D rotate, W thrusts, Space fires, Shift jumps to hyperspace, and the arrow keys look round the
	-- cockpit. Gamepad: left stick rotates, RT thrusts, A fires, B hyperspace, right stick looks. Touch: ROTATE LEFT
	-- and RIGHT on the left, THRUST, FIRE and HYPER on the right"
	{
		name = "asteroids",
		buttons = { "rotateLeft", "rotateRight", "thrust", "fire", "hyper" },
		left = "none",
		right = "look",
		steer = "held",
		axes = "horizontal",
		lookStick = true,
		arrowsLook = true,
	},
}

-- the buttons in a row along the bottom of an 800 x 600 screen, 60 px squares, 10 px apart
local function context(g: Game): Touch.Context
	local buttons: { Touch.Button } = {}
	for i, name in g.buttons do
		table.insert(buttons, { name = name, rect = { x = 10 + (i - 1) * 70, y = 530, w = 60, h = 60 } })
	end
	return { width = 800, buttons = buttons, left = g.left, right = g.right }
end

return t.spec("f0203 games", function(it)
	for _, g in GAMES do
		it(
			`{g.name}: every touch button is held from its press to its release, alongside the others`,
			function()
				local ctx = context(g)
				local s = Touch.empty()
				local pressed: { string } = {}
				for i, b in ctx.buttons do
					local fx
					s, fx =
						Touch.track(s, { id = i, phase = "begin", x = b.rect.x + 5, y = b.rect.y + 5 }, ctx)
					t.expect(#fx).toBe(1)
					t.expect(fx[1]).toEqual({ kind = "press", name = b.name })
					table.insert(pressed, b.name)
				end
				for i, b in ctx.buttons do
					local fx
					s, fx = Touch.track(s, { id = i, phase = "end", x = b.rect.x + 5, y = b.rect.y + 5 }, ctx)
					t.expect(fx).toEqual({ { kind = "release", name = b.name } })
				end
				t.expect(#pressed).toBe(#g.buttons)
			end
		)

		it(`{g.name}: the screen halves do what its design uses them for`, function()
			local ctx = context(g)
			for _, side in { { x = 100, use = g.left }, { x = 600, use = g.right } } do
				local s, fx =
					Touch.track(Touch.empty(), { id = 1, phase = "begin", x = side.x, y = 100 }, ctx)
				local f1, f2
				s, f1 = Touch.track(s, { id = 1, phase = "move", x = side.x + 60, y = 100 }, ctx)
				s, f2 = Touch.track(s, { id = 1, phase = "end", x = side.x + 60, y = 100 }, ctx)
				local all = table.clone(fx)
				for _, f in f1 do
					table.insert(all, f)
				end
				for _, f in f2 do
					table.insert(all, f)
				end
				if side.use == "swipe" then
					t.expect(all).toEqual({ { kind = "swipe", dir = "right" } })
				elseif side.use == "look" then
					t.expect(all).toEqual({ { kind = "look", dx = 60, dy = 0 } })
				else
					t.expect(all).toEqual({})
				end
			end
		end)

		it(
			`{g.name}: the stick {g.steer == "turns" and "turns once a push" or "is held"} on its axes`,
			function()
				local tuning = Pad.tune({ axes = g.axes })
				local s, dir = Pad.steer(Pad.steerStart(), -1, 0, tuning)
				t.expect(dir).toBe("left")
				s, dir = Pad.steer(s, -0.9, 0.1, tuning)
				t.expect(dir).toBe(nil)
				t.expect(s.held).toBe("left")
				s, dir = Pad.steer(s, 1, 0, tuning)
				t.expect(dir).toBe("right")
				t.expect(s.held).toBe("right")
				local _, up = Pad.steer(Pad.steerStart(), 0, 1, tuning)
				t.expect(up).toBe(if g.axes == "both" then "up" else nil)
			end
		)

		if g.lookStick then
			it(`{g.name}: the look stick turns the first-person look`, function()
				local l = Look.turn(Look.snap(), Pad.look(1, 0.5, 0.1))
				t.expect(l.yaw < 0).toBe(true)
				t.expect(l.pitch > 0).toBe(true)
			end)
		end

		if g.arrowsLook then
			it(`{g.name}: the arrow keys look round and spring back`, function()
				local a = Look.press(Look.arrows(), "left", true)
				local s = Look.spring(Look.rest(), Look.snap(), a, 1)
				t.expect(s.look.yaw).toBeNear(math.pi / 2, 1e-9)
				s = Look.spring(s, s.look, Look.press(a, "left", false), 1)
				t.expect(s.look.yaw).toBeNear(0, 1e-9)
			end)
		end
	end

	it("the cores hold no key map: no key or button names, and no action tables", function()
		local bad = {}
		for _, feature in { "Rng", "Pad", "Touch", "Look" } do
			local src = fs.readFile(`src/shared/Logic/{feature}/init.luau`)
			for _, word in
				{
					"KeyCode",
					"ButtonA",
					"ButtonB",
					"ButtonX",
					"ButtonY",
					"ButtonR2",
					"ButtonL2",
					"ButtonR3",
					"DPad",
					"Thumbstick",
				}
			do
				if string.find(src, word, 1, true) then
					table.insert(bad, `{feature}: {word}`)
				end
			end
		end
		t.expect(table.concat(bad, ", ")).toBe("")
		local pad = Pad :: any
		local look = Look :: any
		t.expect(pad.BUTTONS == nil and pad.action == nil and look.KEYS == nil and look.action == nil)
			.toBe(true)
	end)
end)
