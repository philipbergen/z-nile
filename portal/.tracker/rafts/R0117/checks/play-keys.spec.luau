--!strict
-- R0117 RC2, a raft check that is never promoted (the raft's check.sh runs it by the path `./zn find R0117` gives).
-- SEQUESTERED: never edit during execution. f0205 captures "Enter or A plays", and its own spec stops at the play
-- listeners; f0208's spec starts from a stub CarouselView. This runs the two together: the portal's real client boot
-- (StarterPlayerScripts.Client.Main, with the real CarouselView and PlayButtons, all from the built place) on one stub
-- client. Once the server's card states arrive, Enter, KeypadEnter and the gamepad's A on the front card send
-- Remotes.Play exactly the request a tap on that card's PLAY sends, also after the row moves; each press sends it once;
-- a card coming soon, a card whose state is not known yet and an open test purchase screen send nothing.
local Carousel = require("@logic/Carousel")
local luau = require("@lune/luau")
local place = require("@tests/lib/place")
local t = require("@tests/lib/t")

local built = place.load()
local CLIENT = (built :: any)
	:GetService("StarterPlayer")
	:FindFirstChild("StarterPlayerScripts")
	:FindFirstChild("Client")

local STATES = {
	pickman = { published = true, free = true },
	snake = { published = true, free = false },
	invaders = { published = true, free = true },
	asteroids = { published = false },
}

type Signal = { Connect: (any, (...any) -> ()) -> any, fire: (...any) -> () }

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

local function world(): any
	local w: any = { errors = {}, plays = {}, binds = {}, open = false, clock = 0 }

	local function spawn(fn: (...any) -> (), ...: any)
		local ok, err = coroutine.resume(coroutine.create(fn), ...)
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
			PivotTo = function() end,
			Destroy = function(me: any)
				me.Parent = nil
			end,
		}
		methods.WaitForChild = methods.FindFirstChild
		n = setmetatable({ children = children }, {
			__index = function(_: any, key: string): any
				return methods[key] or props[key]
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

	local localPlayer = node("Player")
	localPlayer.UserId = 1
	local playerGui = node("PlayerGui")
	playerGui.Name = "PlayerGui"
	playerGui.Parent = localPlayer
	w.playerGui = playerGui

	local replicated = node("ReplicatedStorage")
	local remotes = node("Folder")
	remotes.Name = "Remotes"
	remotes.Parent = replicated
	local cards = node("RemoteEvent")
	cards.Name = "Cards"
	cards.OnClientEvent = signal()
	cards.FireServer = function() end
	cards.Parent = remotes
	w.cards = cards
	local play = node("RemoteEvent")
	play.Name = "Play"
	play.OnClientEvent = signal()
	play.FireServer = function(_: any, ...: any)
		local words = {}
		for i = 1, select("#", ...) do
			table.insert(words, tostring((select(i, ...))))
		end
		table.insert(w.plays, table.concat(words, " "))
	end
	play.Parent = remotes

	local services: { [string]: any } = {
		ContextActionService = {
			BindActionAtPriority = function(
				_: any,
				name: string,
				fn: (...any) -> any,
				_touch: boolean,
				priority: number,
				...: any
			)
				w.binds[name] = { fn = fn, priority = priority, inputs = { ... } }
			end,
			BindAction = function(_: any, name: string, fn: (...any) -> any, _touch: boolean, ...: any)
				w.binds[name] = { fn = fn, inputs = { ... } }
			end,
			UnbindAction = function() end,
		},
		Players = { LocalPlayer = localPlayer },
		GuiService = { TouchControlsEnabled = true },
		ReplicatedStorage = replicated,
		RunService = { RenderStepped = signal(), Heartbeat = signal() },
		UserInputService = {
			TouchSwipe = signal(),
			GetFocusedTextBox = function(): any
				return nil
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
			elseif class == "TextButton" then
				made.Activated = signal()
			end
			return made
		end,
	}
	local function plain(...: any): any
		return table.freeze(table.pack(...))
	end
	env.UDim2 = { new = plain, fromScale = plain, fromOffset = plain }
	env.Vector2 = { new = plain }
	env.Vector3 = {
		new = function(x: number?, y: number?, z: number?): any
			return table.freeze({ X = x or 0, Y = y or 0, Z = z or 0 })
		end,
	}
	env.Color3 = { new = plain, fromRGB = plain }
	env.CFrame = { new = plain, lookAt = plain, Angles = plain }
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

	local loaded: { [string]: any } = {}
	local testPurchase = {
		start = function() end,
		isOpen = function(): boolean
			return w.open
		end,
	}
	env.require = function(spec: string): any
		local sibling = string.match(spec, "^%./(%w+)$")
		if sibling then
			if loaded[sibling] == nil then
				local script = CLIENT:FindFirstChild(sibling)
				if script == nil then
					return standin() -- an adapter a later issue adds
				end
				loaded[sibling] = luau.load(script.Source, { debugName = sibling, environment = env })()
			end
			return loaded[sibling]
		end
		if spec == "@game/ReplicatedStorage/Arcade/TestPurchase" then
			return testPurchase
		end
		local logic = string.match(spec, "^@game/ReplicatedStorage/Shared/Logic/(%w+)$")
		if logic then
			return (require :: any)("@logic/" .. logic)
		end
		local shared = string.match(spec, "^@game/ReplicatedStorage/Shared/(%w+)$")
		if shared then
			return (require :: any)("@shared/" .. shared)
		end
		local arcadeLogic = string.match(spec, "^@game/ReplicatedStorage/Arcade/Logic/(%w+)$")
		if arcadeLogic then
			return (require :: any)("@arcade/Logic/" .. arcadeLogic)
		end
		local arcade = string.match(spec, "^@game/ReplicatedStorage/Arcade/(%w+)$")
		if arcade then
			return (require :: any)("@arcade/" .. arcade)
		end
		return standin()
	end

	-- the client's modules load first, on this thread (a require in Lune may yield, which a boot thread must not
	-- wait on); then the client's real boot runs in a thread of its own, as the engine runs a LocalScript
	for _, script in CLIENT:GetChildren() do
		if script.ClassName == "ModuleScript" then
			env.require("./" .. script.Name)
		end
	end
	local main = CLIENT:FindFirstChild("Main")
	t.expect(main ~= nil).toBe(true) -- the client's Main
	spawn(luau.load(main.Source, { debugName = "Main", environment = env }))
	t.expect(table.concat(w.errors, "; ")).toBe("") -- the boot raised nothing

	function w.answer(states: any)
		cards.OnClientEvent.fire(states)
	end
	-- a key through the carousel's one binding, on the press; returns what the handler answered
	function w.press(keyName: string): any
		local b = w.binds[Carousel.ACTION]
		t.expect(b ~= nil).toBe(true) -- the carousel's binding
		local input = {
			UserInputType = enum.UserInputType[if string.sub(keyName, 1, 6) == "Button"
				then "Gamepad1"
				else "Keyboard"],
			KeyCode = enum.KeyCode[keyName],
			Position = env.Vector3.new(0, 0, 0),
		}
		return b.fn(Carousel.ACTION, enum.UserInputState.Begin, input)
	end
	-- a tap on a card's button of a kind ("solo" is PLAY), found from the one Portal screen
	function w.tap(name: string, kind: string)
		local gui = playerGui:FindFirstChild("Portal")
		t.expect(gui ~= nil).toBe(true) -- the Portal screen
		local card = gui:FindFirstChild("Cards"):FindFirstChild(name)
		t.expect(card ~= nil).toBe(true) -- the card
		local button = card:FindFirstChild("Buttons"):FindFirstChild(kind)
		t.expect(button ~= nil).toBe(true) -- the button in the card's Buttons slot
		button.Activated.fire()
	end
	-- what was sent since the last call
	function w.sent(): { string }
		local out = w.plays
		w.plays = {}
		return out
	end
	return w
end

return t.spec("R0117 play keys", function(it)
	it(
		"Enter, KeypadEnter and A on the front card send the request a tap on its PLAY sends, once each",
		function()
			local w = world()
			w.answer(STATES)
			w.tap("pickman", "solo")
			local tapped = w.sent()
			t.expect(tapped).toEqual({ "play pickman solo" })
			for _, key in { "Return", "KeypadEnter", "ButtonA" } do
				t.expect(w.press(key)).toBe(w.Enum.ContextActionResult.Sink)
				t.expect(w.sent()).toEqual(tapped)
			end
			t.expect(#w.errors).toBe(0)
		end
	)

	it("after the row moves, the keys play the card now in front, as its PLAY does", function()
		local w = world()
		w.answer(STATES)
		w.press("D")
		w.tap("snake", "solo")
		local tapped = w.sent()
		t.expect(tapped).toEqual({ "play snake solo" })
		w.press("Return")
		w.press("ButtonA")
		t.expect(w.sent()).toEqual({ tapped[1], tapped[1] })
		w.press("Right")
		w.press("KeypadEnter")
		t.expect(w.sent()).toEqual({ "play invaders solo" })
		t.expect(#w.errors).toBe(0)
	end)

	it("a card coming soon sends nothing, by key or by tap", function()
		local w = world()
		w.answer(STATES)
		w.press("A") -- wraps round from Pickman to Asteroids, which is not published
		for _, key in { "Return", "KeypadEnter", "ButtonA" } do
			w.press(key)
		end
		w.tap("asteroids", "solo")
		t.expect(w.sent()).toEqual({})
		t.expect(#w.errors).toBe(0)
	end)

	it("before the server's states, and while the test purchase screen is open, nothing is sent", function()
		local w = world()
		w.press("Return")
		w.tap("pickman", "solo")
		t.expect(w.sent()).toEqual({})
		w.answer(STATES)
		w.open = true
		w.press("Return")
		w.press("ButtonA")
		w.tap("pickman", "solo")
		t.expect(w.sent()).toEqual({})
		w.open = false
		w.press("Return")
		t.expect(w.sent()).toEqual({ "play pickman solo" })
		t.expect(#w.errors).toBe(0)
	end)
end)
