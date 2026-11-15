--!strict
-- f0203 AC5: every game's controls, feature by feature and input by input, as its game design names them, are built
-- from the cores (pickman's rule, f0146: every feature on keyboard, gamepad and touch), and the cores hold no key map.
-- Each cell is quoted from the game's design, or is `undecided` where the design names no input for that feature:
-- that cell is the named issue's to decide (it owns the game's controls), and here the cores only show they can serve
-- it, without choosing it for the game.
local Look = require("@logic/Look")
local Pad = require("@logic/Pad")
local Touch = require("@logic/Touch")
local fs = require("@lune/fs")
local t = require("@tests/lib/t")

type Cell = {
	kind: "key" | "arrows" | "button" | "stick" | "lookStick" | "touchButton" | "half" | "undecided",
	text: string?, -- a key or a pad button, as the design names it (each game's own map: no core holds it)
	axes: Pad.Axes?, -- a stick's axes
	mode: ("turns" | "held")?, -- a stick: one turn a push, or held to move or rotate
	name: string?, -- a touch button's name
	side: Touch.Side?, -- the half a touch button sits on, as the design places it
	use: Touch.Use?, -- a half's use
	issue: string?, -- an undecided cell's owner
	via: ("lookStick" | "lookHalf")?, -- the core path that would serve an undecided cell
}
type Feature = { name: string, keyboard: Cell, gamepad: Cell, touch: { Cell } }
type Game = { name: string, features: { Feature } }

local function key(text: string): Cell
	return { kind = "key", text = text }
end
local function button(text: string): Cell
	return { kind = "button", text = text }
end
local function stick(axes: Pad.Axes, mode: "turns" | "held"): Cell
	return { kind = "stick", axes = axes, mode = mode }
end
local function tb(name: string, side: Touch.Side): Cell
	return { kind = "touchButton", name = name, side = side }
end
local function half(side: Touch.Side, use: Touch.Use): Cell
	return { kind = "half", side = side, use = use }
end
local function undecided(issue: string, via: "lookStick" | "lookHalf"): Cell
	return { kind = "undecided", issue = issue, via = via }
end
local ARROWS: Cell = { kind = "arrows" }
local LOOK_STICK: Cell = { kind = "lookStick" }

local GAMES: { Game } = {
	{
		-- pickman/.tracker/game-design.md: Desktop keys (W A S D, Space, E, F, the arrows look and spring back: f0104),
		-- Gamepad (f0146: the left stick and the D-pad turn, one intent a push; the right stick looks; R3 recentres;
		-- the bottom face button jumps; R2 fires; Y picks), touch (swipe-to-turn on the left half, look on the right,
		-- SNAP, FIRE, JUMP and PICK buttons: R0012, f0110, f0126)
		name = "pickman",
		features = {
			{
				name = "turn",
				keyboard = key("W A S D"),
				gamepad = stick("both", "turns"),
				touch = { half("left", "swipe") },
			},
			{
				name = "jump",
				keyboard = key("Space"),
				gamepad = button("ButtonA"),
				touch = { tb("hop", "right") },
			},
			{
				name = "fire",
				keyboard = key("E"),
				gamepad = button("ButtonR2"),
				touch = { tb("fire", "right") },
			},
			{
				name = "pick",
				keyboard = key("F"),
				gamepad = button("ButtonY"),
				touch = { tb("pick", "right") },
			},
			{ name = "look", keyboard = ARROWS, gamepad = LOOK_STICK, touch = { half("right", "look") } },
			-- the keyboard's look springs back to the heading by itself (f0104), so the arrows are its recentre
			{
				name = "snap",
				keyboard = ARROWS,
				gamepad = button("ButtonR3"),
				touch = { tb("snap", "right") },
			},
		},
	},
	{
		-- snake/.tracker/game-design.md: "Keys follow Pickman's habits: A/D turn, arrow keys look, Space boosts.
		-- Gamepad: stick or D-pad turns, RT boosts. Touch: LEFT and RIGHT buttons on the bottom corners (44 pt
		-- minimum) and a BOOST button." The look has no gamepad or touch input there: f0213's to decide.
		name = "snake",
		features = {
			{
				name = "turn",
				keyboard = key("A/D"),
				gamepad = stick("horizontal", "turns"),
				touch = { tb("left", "left"), tb("right", "right") },
			},
			{
				name = "boost",
				keyboard = key("Space"),
				gamepad = button("ButtonR2"),
				touch = { tb("boost", "right") },
			},
			{
				name = "look",
				keyboard = ARROWS,
				gamepad = undecided("f0213", "lookStick"),
				touch = { undecided("f0213", "lookHalf") },
			},
		},
	},
	{
		-- invaders/.tracker/game-design.md: "Keys: A/D (or the arrows) move, Space fires. Gamepad: stick or D-pad
		-- moves, A or RT fires. Touch: LEFT and RIGHT buttons on the left, a FIRE disc on the right."
		name = "invaders",
		features = {
			{
				name = "move",
				keyboard = key("A/D or the arrows"),
				gamepad = stick("horizontal", "held"),
				touch = { tb("left", "left"), tb("right", "left") },
			},
			{
				name = "fire",
				keyboard = key("Space"),
				gamepad = button("ButtonA or ButtonR2"),
				touch = { tb("fire", "right") },
			},
		},
	},
	{
		-- asteroids/.tracker/game-design.md: "Keys: A/D rotate, W thrusts, Space fires, Shift jumps to hyperspace, and
		-- the arrow keys look round the cockpit. Gamepad: left stick rotates, RT thrusts, A fires, B hyperspace, right
		-- stick looks. Touch: ROTATE LEFT and RIGHT on the left, THRUST, FIRE and HYPER on the right." The look has no
		-- touch input there: f0222's to decide.
		name = "asteroids",
		features = {
			{
				name = "rotate",
				keyboard = key("A/D"),
				gamepad = stick("horizontal", "held"),
				touch = { tb("rotateLeft", "left"), tb("rotateRight", "left") },
			},
			{
				name = "thrust",
				keyboard = key("W"),
				gamepad = button("ButtonR2"),
				touch = { tb("thrust", "right") },
			},
			{
				name = "fire",
				keyboard = key("Space"),
				gamepad = button("ButtonA"),
				touch = { tb("fire", "right") },
			},
			{
				name = "hyper",
				keyboard = key("Shift"),
				gamepad = button("ButtonB"),
				touch = { tb("hyper", "right") },
			},
			{
				name = "look",
				keyboard = ARROWS,
				gamepad = LOOK_STICK,
				touch = { undecided("f0222", "lookHalf") },
			},
		},
	},
}

-- the game's touch screen: 800 x 600, each half's buttons in a row along its bottom (60 px squares, 10 px apart),
-- and each half used as its design says (nothing when no cell names it)
local function context(g: Game): Touch.Context
	local buttons: { Touch.Button } = {}
	local count: { [string]: number } = { left = 0, right = 0 }
	local uses: { [string]: Touch.Use } = { left = "none", right = "none" }
	for _, f in g.features do
		for _, c in f.touch do
			if c.kind == "touchButton" then
				local side = c.side :: Touch.Side
				local x0 = if side == "left" then 10 else 410
				table.insert(buttons, {
					name = c.name :: string,
					rect = { x = x0 + count[side] * 70, y = 530, w = 60, h = 60 },
				})
				count[side] += 1
			elseif c.kind == "half" then
				uses[c.side :: Touch.Side] = c.use :: Touch.Use
			end
		end
	end
	return { width = 800, buttons = buttons, left = uses.left, right = uses.right }
end

local function rectOf(ctx: Touch.Context, name: string): Touch.Rect
	for _, b in ctx.buttons do
		if b.name == name then
			return b.rect
		end
	end
	error(`no button {name}`)
end

-- a finger on the half's middle, moved 60 px right and lifted: every effect, in order
local function stroke(ctx: Touch.Context, side: Touch.Side): { Touch.Effect }
	local x = if side == "left" then 100 else 600
	local all: { Touch.Effect } = {}
	local s = Touch.empty()
	for _, e in
		{
			{ id = 1, phase = "begin", x = x, y = 100 },
			{ id = 1, phase = "move", x = x + 60, y = 100 },
			{ id = 1, phase = "end", x = x + 60, y = 100 },
		} :: { Touch.Event }
	do
		local fx
		s, fx = Touch.track(s, e, ctx)
		for _, f in fx do
			table.insert(all, f)
		end
	end
	return all
end

local function lookStickTurns(): boolean
	local l = Look.turn(Look.snap(), Pad.look(1, 0.5, 0.1))
	return l.yaw < 0 and l.pitch > 0
end

return t.spec("f0203 games", function(it)
	it("every feature of every game has a keyboard, a gamepad and a touch cell", function()
		local bad = {}
		for _, g in GAMES do
			for _, f in g.features do
				if f.keyboard == nil or f.gamepad == nil or #f.touch == 0 then
					table.insert(bad, `{g.name}.{f.name}`)
				end
			end
		end
		t.expect(table.concat(bad, ", ")).toBe("")
	end)

	it(
		"the cells the designs leave open are exactly snake's look on gamepad and touch and asteroids' on touch",
		function()
			local open = {}
			for _, g in GAMES do
				for _, f in g.features do
					local cells: { { input: string, cell: Cell } } =
						{ { input = "gamepad", cell = f.gamepad } }
					for _, c in f.touch do
						table.insert(cells, { input = "touch", cell = c })
					end
					for _, ic in cells do
						if ic.cell.kind == "undecided" then
							table.insert(open, `{g.name}.{f.name}.{ic.input}={ic.cell.issue}`)
						end
					end
				end
			end
			table.sort(open)
			t.expect(open)
				.toEqual({ "asteroids.look.touch=f0222", "snake.look.gamepad=f0213", "snake.look.touch=f0213" })
		end
	)

	for _, g in GAMES do
		local ctx = context(g)
		for _, f in g.features do
			local label = `{g.name}.{f.name}`

			if f.keyboard.kind == "arrows" then
				it(`{label}: the arrow keys look round and spring back (Look)`, function()
					local a = Look.press(Look.arrows(), "left", true)
					local s = Look.spring(Look.rest(), Look.snap(), a, 1)
					t.expect(s.look.yaw).toBeNear(math.pi / 2, 1e-9)
					s = Look.spring(s, s.look, Look.press(a, "left", false), 1)
					t.expect(s.look.yaw).toBeNear(0, 1e-9)
					t.expect(s.spring).toBe(false)
				end)
			end

			local pad = f.gamepad
			if pad.kind == "stick" then
				it(`{label}: the stick {pad.mode} on {pad.axes} axes (Pad.steer)`, function()
					local tuning = Pad.tune({ axes = pad.axes })
					local s = Pad.steerStart()
					local sent: { Pad.Dir } = {}
					for _ = 1, 10 do
						local dir
						s, dir = Pad.steer(s, -0.9, 0.1, tuning)
						if dir then
							table.insert(sent, dir)
						end
						if pad.mode == "held" then
							t.expect(s.held).toBe("left") -- held for as long as the tilt is
						end
					end
					t.expect(sent).toEqual({ "left" }) -- one turn a push
					s = Pad.steer(s, 0, 0, tuning)
					t.expect(s.held).toBe(nil)
					local _, up = Pad.steer(Pad.steerStart(), 0, 1, tuning)
					t.expect(up).toBe(if pad.axes == "both" then "up" else nil)
				end)
			elseif pad.kind == "lookStick" or (pad.kind == "undecided" and pad.via == "lookStick") then
				it(`{label}: the look stick turns the first-person look (Pad.look, Look.turn)`, function()
					t.expect(lookStickTurns()).toBe(true)
				end)
			end

			for _, c in f.touch do
				if c.kind == "touchButton" then
					local name = c.name :: string
					it(
						`{label}: the {name} button sits on the {c.side} half and is held from press to release`,
						function()
							local r = rectOf(ctx, name)
							local _, side = Touch.zone(ctx, r.x + 5, r.y + 5)
							t.expect(side).toBe(c.side)
							local s, fx = Touch.track(
								Touch.empty(),
								{ id = 3, phase = "begin", x = r.x + 5, y = r.y + 5 },
								ctx
							)
							t.expect(fx).toEqual({ { kind = "press", name = name } })
							s, fx = Touch.track(s, { id = 3, phase = "move", x = r.x + 9, y = r.y + 9 }, ctx)
							t.expect(fx).toEqual({})
							s, fx = Touch.track(s, { id = 3, phase = "end", x = r.x + 9, y = r.y + 9 }, ctx)
							t.expect(fx).toEqual({ { kind = "release", name = name } })
						end
					)
				elseif c.kind == "half" then
					it(`{label}: the {c.side} half is used for {c.use}`, function()
						local fx = stroke(ctx, c.side :: Touch.Side)
						if c.use == "swipe" then
							t.expect(fx).toEqual({ { kind = "swipe", dir = "right" } })
						else
							t.expect(fx).toEqual({ { kind = "look", dx = 60, dy = 0 } })
						end
					end)
				elseif c.kind == "undecided" then
					it(`{label}: open ({c.issue}): a look half could serve it (Touch, Look.mouse)`, function()
						local open: Touch.Context =
							{ width = 800, buttons = ctx.buttons, left = "none", right = "look" }
						local fx = stroke(open, "right")
						t.expect(fx).toEqual({ { kind = "look", dx = 60, dy = 0 } })
						local l = Look.mouse(Look.snap(), 60, 0)
						t.expect(l.yaw < 0).toBe(true)
					end)
				end
			end
		end

		it(`{g.name}: a half no cell names takes no finger`, function()
			local sides: { Touch.Side } = { "left", "right" }
			for _, side in sides do
				local use = if side == "left" then ctx.left else ctx.right
				if use == "none" then
					t.expect(stroke(ctx, side :: Touch.Side)).toEqual({})
				end
			end
		end)
	end

	it(
		"the cores hold no key map or layout: no key or button names, no action tables, no HUD rectangles",
		function()
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
			local pad, look, touch = Pad :: any, Look :: any, Touch :: any
			local present = {}
			for _, f in
				{
					{ pad, "Pad", "BUTTONS" },
					{ pad, "Pad", "action" },
					{ pad, "Pad", "CONTINUE" },
					{ look, "Look", "KEYS" },
					{ look, "Look", "action" },
				}
			do
				if f[1][f[3]] ~= nil then
					table.insert(present, `{f[2]}.{f[3]}`)
				end
			end
			for _, name in { "buttons", "snapRect", "hopRect", "fireRect", "pickRect", "blocks" } do
				if touch[name] ~= nil then
					table.insert(present, `Touch.{name}`)
				end
			end
			t.expect(table.concat(present, ", ")).toBe("")
		end
	)
end)
