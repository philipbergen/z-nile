--!strict
-- f0205 AC5: the portal's carousel screen (StarterPlayerScripts.Client.CarouselView), run from its real source on a
-- stub client. It turns the platform's touch controls off and draws one card per game in a ScreenGui inside the safe
-- insets: the title and the wrapped tagline at their regions, a turning 3-D preview of the game's parts through its own
-- camera CAMERA.height up and CAMERA.distance back looking at the centre, the price badge (empty until the server
-- answers, then the words Card.WORDS gives or the sale in the arcade's Prices words, struck through as rich text, its
-- two labels at Card.BADGE) and two slots, Buttons and Boards, for the play buttons and the boards. The cards sit where
-- Carousel's boxes say, again when the screen's size changes. One ContextActionService binding at Carousel.PRIORITY
-- takes the nine keys and the wheel: A, Left and the left shoulder go back, D, Right and the right shoulder forward,
-- on the press; the wheel one card per roll; all sunk, and all passed on while the player types in a text box. A swipe
-- moves the row wherever it starts. Enter, KeypadEnter or ButtonA tell the play listeners the front card's name, for
-- a published card only. It asks the server once, after it listens, and start returns at once.
local Card = require("@logic/Card")
local Carousel = require("@logic/Carousel")
local Games = require("@shared/Games")
local luau = require("@lune/luau")
local place = require("@tests/lib/place")
local t = require("@tests/lib/t")

local built = place.load()
local SOURCE = (built :: any)
	:GetService("StarterPlayer")
	:FindFirstChild("StarterPlayerScripts")
	:FindFirstChild("Client")
	:FindFirstChild("CarouselView").Source

-- the arcade's Prices as this spec hands it over: words no card holds, so the badge must print what Prices says
local PRICES = table.freeze({ struck = "9 X", price = "2 X", sale = "DEAL" })
-- the real Card, but with badge words no card holds, so the view must print the words Card gives it
local WORDS = table.freeze({ free = "GO!", soon = "LATER" })
local CARD = setmetatable({ WORDS = WORDS }, { __index = Card })

type Signal = { Connect: (any, (...any) -> ()) -> any, fire: (...any) -> (), count: () -> number }

local function standin(): any
	local s: any
	s = setmetatable({}, {
		__index = function(): any
			return s
		end,
		__call = function(): any
			return nil
		end,
	})
	return s
end

local function value(kind: string, ...: any): any
	return table.freeze({ kind = kind, args = table.freeze(table.pack(...)) })
end

local function enumProxy(): any
	return setmetatable({}, {
		__index = function(self: any, group: string): any
			local g = setmetatable({}, {
				__index = function(gs: any, item: string): any
					local v = table.freeze({ Name = item, EnumType = group })
					rawset(gs, item, v)
					return v
				end,
			})
			rawset(self, group, g)
			return g
		end,
	})
end

local function world(slow: boolean?): any
	local w: any = { errors = {}, sent = {}, order = {}, binds = {}, clock = 0, played = {}, waiting = {} }

	local function spawn(fn: (...any) -> (), ...: any)
		local co = coroutine.create(fn)
		local ok, err = coroutine.resume(co, ...)
		if not ok then
			table.insert(w.errors, tostring(err))
		end
	end

	local function signal(): Signal
		local fns: { (...any) -> () } = {}
		return {
			Connect = function(_: any, fn: (...any) -> ()): any
				table.insert(fns, fn)
				return { Disconnect = function() end }
			end,
			fire = function(...: any)
				for _, fn in table.clone(fns) do
					spawn(fn, ...)
				end
			end,
			count = function(): number
				return #fns
			end,
		}
	end

	local function node(className: string): any
		local props: any = { ClassName = className, Name = className }
		local children: { any } = {}
		local changed: { [string]: Signal } = {}
		local n: any
		local methods: { [string]: any } = {
			FindFirstChild = function(_: any, name: string): any
				for _, c in children do
					if c.Name == name then
						return c
					end
				end
				return nil
			end,
			GetChildren = function(): { any }
				return table.clone(children)
			end,
			IsA = function(_: any, class: string): boolean
				return className == class
			end,
			GetPropertyChangedSignal = function(_: any, prop: string): Signal
				changed[prop] = changed[prop] or signal()
				return changed[prop]
			end,
			PivotTo = function(_: any, cf: any)
				props.pivot = cf
			end,
			Destroy = function(me: any)
				me.Parent = nil
			end,
			ClearAllChildren = function()
				for _, c in table.clone(children) do
					c.Parent = nil
				end
			end,
			SetAttribute = function(_: any, k: string, v: any)
				props["@" .. k] = v
			end,
			GetAttribute = function(_: any, k: string): any
				return props["@" .. k]
			end,
		}
		methods.WaitForChild = methods.FindFirstChild
		methods.FindFirstChildOfClass = function(_: any, class: string): any
			for _, c in children do
				if c.ClassName == class then
					return c
				end
			end
			return nil
		end
		methods.FindFirstChildWhichIsA = methods.FindFirstChildOfClass
		n = setmetatable({ children = children, changed = changed }, {
			__index = function(_: any, key: string): any
				if methods[key] then
					return methods[key]
				end
				return props[key]
			end,
			__newindex = function(_: any, key: string, v: any)
				if key == "Parent" then
					local old = props.Parent
					if old == v then
						return
					end
					if old then
						local i = table.find(old.children, n)
						if i then
							table.remove(old.children, i)
						end
					end
					props.Parent = v
					if v then
						table.insert(v.children, n)
					end
				else
					props[key] = v
				end
			end,
		})
		return n
	end
	w.node = node

	local localPlayer = node("Player")
	localPlayer.Name = "me"
	localPlayer.UserId = 1
	local playerGui = node("PlayerGui")
	playerGui.Name = "PlayerGui"
	playerGui.Parent = localPlayer
	w.playerGui = playerGui
	local guiService: any = { TouchControlsEnabled = true }
	w.guiService = guiService
	local remote: any = node("RemoteEvent")
	remote.Name = "Cards"
	remote.OnClientEvent = signal()
	remote.FireServer = function(_: any, ...: any)
		table.insert(w.sent, table.pack(...))
		table.insert(w.order, { "ask", remote.OnClientEvent.count() })
	end
	w.remote = remote
	local remotes = node("Folder")
	remotes.Name = "Remotes"
	remote.Parent = remotes
	local replicated: any = {
		WaitForChild = function(_: any, name: string): any
			assert(name == "Remotes", name)
			if slow and not w.released then
				table.insert(w.waiting, coroutine.running())
				coroutine.yield()
			end
			return remotes
		end,
	}
	replicated.FindFirstChild = replicated.WaitForChild
	local swipe, rendered, heartbeat = signal(), signal(), signal()
	w.swipe, w.rendered, w.heartbeat = swipe, rendered, heartbeat
	local services: { [string]: any } = {
		ContextActionService = {
			BindActionAtPriority = function(
				_: any,
				name: string,
				fn: (...any) -> any,
				touch: boolean,
				priority: number,
				...: any
			)
				table.insert(
					w.binds,
					{ name = name, fn = fn, touch = touch, priority = priority, inputs = { ... } }
				)
			end,
			BindAction = function(_: any, name: string, fn: (...any) -> any, touch: boolean, ...: any)
				table.insert(
					w.binds,
					{ name = name, fn = fn, touch = touch, priority = nil, inputs = { ... } }
				)
			end,
			UnbindAction = function() end,
		},
		Players = { LocalPlayer = localPlayer },
		GuiService = guiService,
		ReplicatedStorage = replicated,
		RunService = {
			RenderStepped = rendered,
			Heartbeat = heartbeat,
			IsStudio = function()
				return false
			end,
		},
		UserInputService = {
			TouchSwipe = swipe,
			InputBegan = signal(),
			InputEnded = signal(),
			InputChanged = signal(),
			LastInputTypeChanged = signal(),
			GetLastInputType = function(): any
				return nil
			end,
			GetFocusedTextBox = function(): any
				return w.focused -- a TextBox the player is typing in (the chat box), nil when none
			end,
		},
	}
	local enum = enumProxy()
	w.Enum = enum

	local env: { [string]: any } = {}
	env.game = {
		GetService = function(_: any, name: string): any
			return services[name] or standin()
		end,
	}
	env.Enum = enum
	env.Instance = {
		new = function(class: string): any
			local made = node(class)
			if class == "ScreenGui" then
				made.AbsoluteSize = { X = 1280, Y = 720 }
			end
			return made
		end,
	}
	-- every UDim2 is one normalised value whatever builds it: X and Y, each a Scale and an Offset
	local function udim2(xs: number?, xo: number?, ys: number?, yo: number?): any
		return table.freeze({
			X = table.freeze({ Scale = xs or 0, Offset = xo or 0 }),
			Y = table.freeze({ Scale = ys or 0, Offset = yo or 0 }),
		})
	end
	env.UDim2 = {
		new = function(xs: number?, xo: number?, ys: number?, yo: number?): any
			return udim2(xs, xo, ys, yo)
		end,
		fromScale = function(xs: number?, ys: number?): any
			return udim2(xs, 0, ys, 0)
		end,
		fromOffset = function(xo: number?, yo: number?): any
			return udim2(0, xo, 0, yo)
		end,
	}
	env.UDim = {
		new = function(...: any): any
			return value("udim", ...)
		end,
	}
	env.Vector2 = {
		new = function(...: any): any
			return value("v2", ...)
		end,
	}
	env.Vector3 = {
		new = function(x: number?, y: number?, z: number?): any
			return table.freeze({ kind = "v3", X = x or 0, Y = y or 0, Z = z or 0 })
		end,
	}
	-- a colour is its three channels in 0..1, whatever builds it
	env.Color3 = {
		new = function(r: number?, g: number?, b: number?): any
			return table.freeze({ R = r or 0, G = g or 0, B = b or 0 })
		end,
		fromRGB = function(r: number?, g: number?, b: number?): any
			return table.freeze({ R = (r or 0) / 255, G = (g or 0) / 255, B = (b or 0) / 255 })
		end,
	}
	-- a CFrame keeps where it is and the point it looks at, whatever builds it (lookAt, or new with a target)
	local function frame(eye: any, target: any): any
		return table.freeze({ kind = "frame", Position = eye, target = target })
	end
	env.CFrame = {
		new = function(a: any, b: any, c: any): any
			if type(a) == "table" then
				return frame(a, b)
			end
			return frame(env.Vector3.new(a, b, c), nil)
		end,
		lookAt = function(eye: any, target: any): any
			return frame(eye, target)
		end,
		Angles = function(...: any): any
			return value("angles", ...)
		end,
	}
	env.TweenInfo = {
		new = function(...: any): any
			return value("tween", ...)
		end,
	}
	env.task = {
		spawn = spawn,
		defer = spawn,
		delay = function() end,
		wait = function()
			return 0
		end,
	}
	env.os = {
		clock = function(): number
			return w.clock
		end,
		time = function(): number
			return 1000000
		end,
	}
	env.require = function(spec: string): any
		local logic = string.match(spec, "^@game/ReplicatedStorage/Shared/Logic/(%w+)$")
		if logic == "Card" then
			return CARD
		end
		if logic then
			return (require :: any)("@logic/" .. logic)
		end
		local shared = string.match(spec, "^@game/ReplicatedStorage/Shared/(%w+)$")
		if shared then
			return (require :: any)("@shared/" .. shared)
		end
		if spec == "@game/ReplicatedStorage/Arcade/Prices" then
			return PRICES
		end
		local arcadeLogic = string.match(spec, "^@game/ReplicatedStorage/Arcade/Logic/(%w+)$")
		if arcadeLogic then
			return (require :: any)("@arcade/Logic/" .. arcadeLogic)
		end
		local arcade = string.match(spec, "^@game/ReplicatedStorage/Arcade/(%w+)$")
		if arcade then
			return (require :: any)("@arcade/" .. arcade)
		end
		return standin() -- a sibling adapter a later issue adds
	end
	w.View = luau.load(SOURCE, { debugName = "CarouselView", environment = env })()

	function w.release()
		w.released = true
		for _, co in w.waiting do
			local ok, err = coroutine.resume(co)
			if not ok then
				table.insert(w.errors, tostring(err))
			end
		end
		w.waiting = {}
	end
	function w.gui(): any
		local found = {}
		for _, c in playerGui.children do
			if c.ClassName == "ScreenGui" and c.Name == "Portal" then
				table.insert(found, c)
			end
		end
		t.expect(#found).toBe(1) -- one Portal ScreenGui
		return found[1]
	end
	function w.card(name: string): any
		local cards = w.gui():FindFirstChild("Cards")
		t.expect(cards ~= nil).toBe(true) -- the Cards frame
		local c = cards:FindFirstChild(name)
		t.expect(c ~= nil and c.ClassName).toBe("Frame") -- the card
		return c
	end
	function w.badge(name: string): (any, any)
		local b = w.card(name):FindFirstChild("Badge")
		t.expect(b ~= nil).toBe(true)
		local struck, offer = b:FindFirstChild("Struck"), b:FindFirstChild("Offer")
		t.expect(struck ~= nil and offer ~= nil).toBe(true)
		return struck, offer
	end
	function w.answer(states: any)
		remote.OnClientEvent.fire(states)
	end
	-- a ContextActionService input through the one binding: returns what the handler answered
	function w.press(keyName: string, state: string?): any
		local b = w.binds[1]
		local input = {
			UserInputType = enum.UserInputType[if string.sub(keyName, 1, 6) == "Button"
				then "Gamepad1"
				else "Keyboard"],
			KeyCode = enum.KeyCode[keyName],
			Position = env.Vector3.new(0, 0, 0),
		}
		return b.fn(Carousel.ACTION, enum.UserInputState[state or "Begin"], input)
	end
	function w.wheel(z: number, at: number): any
		w.clock = at
		local b = w.binds[1]
		local input = {
			UserInputType = enum.UserInputType.MouseWheel,
			KeyCode = enum.KeyCode.Unknown,
			Position = env.Vector3.new(0, 0, z),
		}
		return b.fn(Carousel.ACTION, enum.UserInputState.Change, input)
	end
	-- which game's card sits in front, by the boxes Carousel gives for the screen's size
	function w.front(): string?
		local size = w.gui().AbsoluteSize
		local box = Carousel.box(0, size.X, size.Y)
		for _, e in Games.LIST do
			local p = w.card(e.name).Position
			if
				p
				and p.X.Scale == 0
				and p.Y.Scale == 0
				and math.abs(p.X.Offset - box.x) < 1e-6
				and math.abs(p.Y.Offset - box.y) < 1e-6
			then
				return e.name
			end
		end
		return nil
	end
	w.View.onPlay(function(name: string)
		table.insert(w.played, name)
	end)
	return w
end

-- start runs in a boot thread of its own, as Main's would: `booted` says whether it returned before the remote came
local function started(slow: boolean?): any
	local w = world(slow)
	local boot = coroutine.create(function()
		w.View.start()
	end)
	local ok, err = coroutine.resume(boot)
	if not ok then
		table.insert(w.errors, tostring(err))
	end
	w.booted = coroutine.status(boot) == "dead"
	return w
end

-- a frame at a region of its parent: scale positions, `x` from the left, `width` wide
local function region(f: any, r: Card.Region, x: number, width: number)
	t.expect(f.Position ~= nil and f.Size ~= nil).toBe(true)
	t.expect(f.Position.X.Scale).toBeNear(x, 1e-9)
	t.expect(f.Position.Y.Scale).toBeNear(r.top, 1e-9)
	t.expect(f.Size.X.Scale).toBeNear(width, 1e-9)
	t.expect(f.Size.Y.Scale).toBeNear(r.height, 1e-9)
	t.expect(f.Position.X.Offset + f.Position.Y.Offset + f.Size.X.Offset + f.Size.Y.Offset).toBe(0)
end

-- a card placed at a box, in pixels
local function pixels(c: any, box: any)
	t.expect(c.Position.X.Scale + c.Position.Y.Scale + c.Size.X.Scale + c.Size.Y.Scale).toBe(0)
	t.expect(c.Position.X.Offset).toBeNear(box.x, 1e-6)
	t.expect(c.Position.Y.Offset).toBeNear(box.y, 1e-6)
	t.expect(c.Size.X.Offset).toBeNear(box.width, 1e-6)
	t.expect(c.Size.Y.Offset).toBeNear(box.height, 1e-6)
end

local ALL_SALE = {
	pickman = { published = true, free = false },
	snake = { published = true, free = false },
	invaders = { published = true, free = false },
	asteroids = { published = true, free = false },
}

return t.spec("f0205 client", function(it)
	it("draws one Portal screen in the player's gui, inside the safe insets, kept across respawns", function()
		local w = started()
		local gui = w.gui()
		t.expect(gui.ResetOnSpawn).toBe(false)
		t.expect(gui.ScreenInsets).toBe(w.Enum.ScreenInsets.CoreUISafeInsets)
		t.expect(gui.IgnoreGuiInset == true).toBe(false)
		t.expect(#w.errors).toBe(0)
	end)

	it("one card per game, each with its title and tagline", function()
		local w = started()
		local cards = w.gui():FindFirstChild("Cards")
		local frames = 0
		for _, c in cards.children do
			if c.ClassName == "Frame" then
				frames += 1
			end
		end
		t.expect(frames).toBe(#Games.LIST)
		for _, e in Games.LIST do
			local c = w.card(e.name)
			t.expect(c:FindFirstChild("Title").Text).toBe(e.title)
			t.expect(c:FindFirstChild("Tagline").Text).toBe(e.tagline)
		end
	end)

	it("each card's preview is a viewport with its own camera showing the game's parts", function()
		local w = started()
		for _, e in Games.LIST do
			local view = w.card(e.name):FindFirstChild("Preview")
			t.expect(view ~= nil and view.ClassName).toBe("ViewportFrame")
			local cam = view.CurrentCamera
			t.expect(cam ~= nil and cam.ClassName).toBe("Camera")
			t.expect(cam.Parent).toBe(view)
			t.expect(cam.FieldOfView).toBe(Card.CAMERA.fov)
			local scene = view:FindFirstChild("Scene")
			t.expect(scene ~= nil and scene.ClassName).toBe("Model")
			local parts = {}
			for _, c in scene.children do
				if c.ClassName == "Part" then
					table.insert(parts, c)
				end
			end
			t.expect(#parts).toBe(#e.preview)
			for i, p in e.preview do
				local made = parts[i]
				t.expect(made.Shape).toBe(w.Enum.PartType[p.shape])
				t.expect(made.Size.X).toBe(p.size[1])
				t.expect(made.Size.Y).toBe(p.size[2])
				t.expect(made.Size.Z).toBe(p.size[3])
				t.expect(made.Position.X).toBe(p.at[1])
				t.expect(made.Position.Y).toBe(p.at[2])
				t.expect(made.Position.Z).toBe(p.at[3])
				t.expect(made.Color.R * 255).toBeNear(p.color[1], 1e-9)
				t.expect(made.Color.G * 255).toBeNear(p.color[2], 1e-9)
				t.expect(made.Color.B * 255).toBeNear(p.color[3], 1e-9)
				t.expect(made.Anchored).toBe(true)
			end
		end
	end)

	it("each card keeps empty Buttons and Boards slots, and a Badge, at Card's regions", function()
		local w = started()
		for _, e in Games.LIST do
			for _, name in { "Badge", "Buttons", "Boards" } do
				local f = w.card(e.name):FindFirstChild(name)
				t.expect(f ~= nil and f.ClassName).toBe("Frame")
				local r = Card.REGIONS[name]
				region(f, r, Card.INSET, 1 - 2 * Card.INSET)
			end
			t.expect(#w.card(e.name):FindFirstChild("Buttons").children).toBe(0)
			t.expect(#w.card(e.name):FindFirstChild("Boards").children).toBe(0)
		end
	end)

	it("until the server answers, every badge is empty", function()
		local w = started(true)
		for _, e in Games.LIST do
			local struck, offer = w.badge(e.name)
			t.expect(struck.Text).toBe("")
			t.expect(offer.Text).toBe("")
		end
	end)

	it("asks the server once, after it listens for the answer", function()
		local w = started()
		t.expect(#w.sent).toBe(1)
		t.expect(w.order[1][1]).toBe("ask")
		t.expect(w.order[1][2]).toBe(1)
	end)

	it("start returns at once while the server's remote is not there yet, and asks once it is", function()
		local w = started(true)
		t.expect(w.booted).toBe(true)
		t.expect(#w.sent).toBe(0)
		t.expect(w.gui() ~= nil).toBe(true)
		w.release()
		t.expect(#w.sent).toBe(1)
		t.expect(#w.errors).toBe(0)
	end)

	it(
		"the server's answer draws each badge: coming soon, free game ready, or the sale in the Prices words",
		function()
			local w = started()
			w.answer({
				pickman = { published = true, free = false },
				snake = { published = true, free = true },
				invaders = { published = false },
				asteroids = { published = true },
			})
			local struck, offer = w.badge("pickman")
			t.expect(struck.Text).toBe("<s>9 X</s>")
			t.expect(struck.RichText).toBe(true)
			t.expect(offer.Text).toBe("2 X DEAL")
			struck, offer = w.badge("snake")
			t.expect(struck.Text).toBe("")
			t.expect(offer.Text).toBe(WORDS.free)
			struck, offer = w.badge("invaders")
			t.expect(struck.Text).toBe("")
			t.expect(offer.Text).toBe(WORDS.soon)
			struck, offer = w.badge("asteroids")
			t.expect(struck.Text).toBe("")
			t.expect(offer.Text).toBe("")
		end
	)

	it("a later answer replaces the badges, and a malformed one empties only the cards it spoils", function()
		local w = started()
		w.answer(ALL_SALE)
		w.answer({
			pickman = { published = true, free = true },
			snake = { published = "yes" },
			invaders = { published = true, free = false },
			asteroids = { published = true, free = false },
		})
		local _, offer = w.badge("pickman")
		t.expect(offer.Text).toBe(WORDS.free)
		local struck
		struck, offer = w.badge("snake")
		t.expect(struck.Text).toBe("")
		t.expect(offer.Text).toBe("")
		_, offer = w.badge("invaders")
		t.expect(offer.Text).toBe("2 X DEAL")
		w.answer("nonsense")
		_, offer = w.badge("invaders")
		t.expect(offer.Text).toBe("")
		t.expect(#w.errors).toBe(0)
	end)

	it(
		"the cards sit in Carousel's boxes for the screen's size, Pickman in front, the far one hidden",
		function()
			local w = started()
			local size = w.gui().AbsoluteSize
			for i, e in Games.LIST do
				local c = w.card(e.name)
				local box = Carousel.box(Carousel.offset(Carousel.new(#Games.LIST), i), size.X, size.Y)
				pixels(c, box)
				t.expect(c.Visible).toBe(box.shown)
				t.expect(c:FindFirstChild("Dim").BackgroundTransparency).toBeNear(1 - box.dim, 1e-9)
			end
			t.expect(w.front()).toBe("pickman")
			t.expect(w.View.focused()).toBe("pickman")
		end
	)

	it("when the screen's size changes, the cards are placed again for the new size", function()
		local w = started()
		local gui = w.gui()
		gui.AbsoluteSize = { X = 390, Y = 844 }
		local resized = gui.changed.AbsoluteSize -- the view listens for the size to change
		t.expect(resized ~= nil).toBe(true)
		resized.fire()
		local box = Carousel.box(0, 390, 844)
		local c = w.card("pickman")
		pixels(c, box)
		t.expect(w.front()).toBe("pickman")
	end)

	it("one binding below the test purchase screen's priority takes the nine keys and the wheel", function()
		local w = started()
		t.expect(#w.binds).toBe(1)
		local b = w.binds[1]
		t.expect(b.name).toBe(Carousel.ACTION)
		t.expect(b.touch).toBe(false)
		t.expect(b.priority).toBe(Carousel.PRIORITY)
		t.expect(b.priority < 3000).toBe(true)
		local names = {}
		for _, input in b.inputs do
			table.insert(names, `{input.EnumType}.{input.Name}`)
		end
		table.sort(names)
		t.expect(table.concat(names, " ")).toBe(
			"KeyCode.A KeyCode.ButtonA KeyCode.ButtonL1 KeyCode.ButtonR1 KeyCode.D KeyCode.KeypadEnter"
				.. " KeyCode.Left KeyCode.Return KeyCode.Right UserInputType.MouseWheel"
		)
	end)

	it("D moves the row forward on the press; the release adds nothing; the binding sinks the key", function()
		local w = started()
		local answer = w.press("D", "Begin")
		t.expect(answer).toBe(w.Enum.ContextActionResult.Sink)
		t.expect(w.front()).toBe("snake")
		t.expect(w.View.focused()).toBe("snake")
		w.press("D", "End")
		t.expect(w.front()).toBe("snake")
	end)

	it("A goes back, round from the first card to the last", function()
		local w = started()
		w.press("A")
		t.expect(w.front()).toBe("asteroids")
		w.press("A", "End")
		t.expect(w.front()).toBe("asteroids")
	end)

	it("the arrows and the shoulders move the row too", function()
		local w = started()
		w.press("Right")
		w.press("ButtonR1")
		t.expect(w.front()).toBe("invaders")
		w.press("Left")
		t.expect(w.front()).toBe("snake")
		w.press("ButtonL1")
		t.expect(w.front()).toBe("pickman")
	end)

	it("the wheel moves one card per roll: down forward, up back, after a rest of WHEEL_GAP", function()
		local w = started()
		w.wheel(-1, 10)
		t.expect(w.front()).toBe("snake")
		w.wheel(-1, 10.125)
		t.expect(w.front()).toBe("snake")
		w.wheel(1, 10.5)
		t.expect(w.front()).toBe("pickman")
	end)

	it(
		"a swipe to the left brings the next card, to the right the previous one, wherever it starts",
		function()
			local w = started()
			w.swipe.fire(w.Enum.SwipeDirection.Left, 1, false)
			t.expect(w.front()).toBe("snake")
			w.swipe.fire(w.Enum.SwipeDirection.Left, 1, true) -- started over a button: it still moves the row
			t.expect(w.front()).toBe("invaders")
			w.swipe.fire(w.Enum.SwipeDirection.Right, 1, false)
			t.expect(w.front()).toBe("snake")
			w.swipe.fire(w.Enum.SwipeDirection.Up, 1, false)
			t.expect(w.front()).toBe("snake")
		end
	)

	it("Enter plays the front card: the play listeners hear its name once, on the press", function()
		local w = started()
		w.answer(ALL_SALE)
		w.press("Return", "Begin")
		t.expect(table.concat(w.played, " ")).toBe("pickman")
		w.press("Return", "End")
		t.expect(#w.played).toBe(1)
		w.press("D")
		w.press("KeypadEnter")
		w.press("D")
		w.press("ButtonA")
		t.expect(table.concat(w.played, " ")).toBe("pickman snake invaders")
	end)

	it("a card coming soon, or one whose state is not known yet, plays nothing", function()
		local w = started()
		w.press("Return")
		t.expect(#w.played).toBe(0)
		w.answer({
			pickman = { published = false },
			snake = { published = true, free = true },
			invaders = { published = true, free = false },
			asteroids = { published = true, free = false },
		})
		w.press("Return")
		w.press("ButtonA")
		t.expect(#w.played).toBe(0)
		w.press("D")
		w.press("Return")
		t.expect(table.concat(w.played, " ")).toBe("snake")
	end)

	it("a free card plays, and so does one on sale", function()
		local w = started()
		w.answer({
			pickman = { published = true, free = true },
			snake = { published = true, free = false },
			invaders = { published = false },
			asteroids = { published = false },
		})
		w.press("Return")
		w.press("D")
		w.press("Return")
		t.expect(table.concat(w.played, " ")).toBe("pickman snake")
	end)

	it("every listener hears a play, however many there are", function()
		local w = started()
		local other = {}
		w.View.onPlay(function(name: string)
			table.insert(other, name)
		end)
		w.answer(ALL_SALE)
		w.press("Return")
		t.expect(table.concat(w.played, " ")).toBe("pickman")
		t.expect(table.concat(other, " ")).toBe("pickman")
	end)

	it("card() gives each game's card frame, the one its slots are in", function()
		local w = started()
		for _, e in Games.LIST do
			t.expect(w.View.card(e.name)).toBe(w.card(e.name))
		end
		t.expect(w.View.card("nothing")).toBe(nil)
	end)

	it("the shown previews turn by Card.angle of the clock each frame; a hidden one does not", function()
		local w = started()
		w.clock = 3
		w.rendered.fire(1 / 60)
		local front = w.card("pickman"):FindFirstChild("Preview"):FindFirstChild("Scene")
		t.expect(front.pivot ~= nil and front.pivot.kind).toBe("angles")
		t.expect(front.pivot.args[1]).toBe(0)
		t.expect(front.pivot.args[2]).toBeNear(Card.angle(3), 1e-12)
		t.expect(front.pivot.args[3]).toBe(0)
		local far = w.card("invaders"):FindFirstChild("Preview"):FindFirstChild("Scene")
		t.expect(far.pivot).toBe(nil)
		w.clock = 4
		w.rendered.fire(1 / 60)
		t.expect(front.pivot.args[2]).toBeNear(Card.angle(4), 1e-12)
	end)

	it("started twice it draws one screen, binds once and asks once", function()
		local w = started()
		w.View.start()
		t.expect(w.gui() ~= nil).toBe(true)
		t.expect(#w.binds).toBe(1)
		t.expect(#w.sent).toBe(1)
		t.expect(#w.errors).toBe(0)
	end)
	it(
		"the title and tagline sit at their regions, the tagline wrapped; the preview spans its region's width",
		function()
			local w = started()
			local inner = 1 - 2 * Card.INSET
			for _, e in Games.LIST do
				local c = w.card(e.name)
				local title, tagline = c:FindFirstChild("Title"), c:FindFirstChild("Tagline")
				region(title, Card.REGIONS.Title, Card.INSET, inner)
				region(tagline, Card.REGIONS.Tagline, Card.INSET, inner)
				t.expect(tagline.TextWrapped).toBe(true)
				t.expect(title.TextScaled).toBe(true)
				t.expect(tagline.TextScaled).toBe(true)
				region(c:FindFirstChild("Preview"), Card.REGIONS.Preview, 0, 1)
			end
		end
	)

	it("the badge's struck price and offer share its width as Card.BADGE says", function()
		local w = started()
		local full = { top = 0, height = 1 }
		for _, e in Games.LIST do
			local struck, offer = w.badge(e.name)
			region(struck, full, 0, Card.BADGE.struck)
			region(offer, full, Card.BADGE.struck + Card.BADGE.gap, Card.BADGE.offer)
		end
	end)

	it(
		"each preview's camera sits CAMERA.height up and CAMERA.distance back, looking at the scene's centre",
		function()
			local w = started()
			for _, e in Games.LIST do
				local cam = w.card(e.name):FindFirstChild("Preview").CurrentCamera
				t.expect(cam ~= nil).toBe(true)
				local cf = cam.CFrame
				t.expect(cf ~= nil and cf.kind).toBe("frame")
				t.expect(cf.Position.X).toBe(0)
				t.expect(cf.Position.Y).toBe(Card.CAMERA.height)
				t.expect(cf.Position.Z).toBe(Card.CAMERA.distance)
				t.expect(cf.target ~= nil).toBe(true)
				t.expect(cf.target.X).toBe(0)
				t.expect(cf.target.Y).toBe(0)
				t.expect(cf.target.Z).toBe(0)
			end
		end
	)

	it("the platform's touch controls are off: no thumbstick or jump button over the cards", function()
		local w = started()
		t.expect(w.guiService.TouchControlsEnabled).toBe(false)
	end)

	it(
		"while the player types in a text box (the chat), the keys and the wheel move nothing and pass on",
		function()
			local w = started()
			w.answer(ALL_SALE)
			w.focused = w.node("TextBox")
			t.expect(w.press("D")).toBe(w.Enum.ContextActionResult.Pass)
			t.expect(w.press("Return")).toBe(w.Enum.ContextActionResult.Pass)
			t.expect(w.wheel(-1, 10)).toBe(w.Enum.ContextActionResult.Pass)
			t.expect(w.front()).toBe("pickman")
			t.expect(#w.played).toBe(0)
			w.focused = nil
			w.press("D")
			t.expect(w.front()).toBe("snake")
		end
	)

	it("the wheel's input is sunk too, so nothing below the binding zooms on it", function()
		local w = started()
		t.expect(w.wheel(-1, 10)).toBe(w.Enum.ContextActionResult.Sink)
		t.expect(w.wheel(-1, 10.125)).toBe(w.Enum.ContextActionResult.Sink)
	end)
end)
