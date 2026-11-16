--!strict
-- f0208 AC5: the play buttons' client (StarterPlayerScripts.Client.PlayButtons), run from its real source on a stub
-- client with a stub CarouselView (its cards' Buttons slots, its play listeners, its front card). Each card's slot
-- gets its buttons once the server's card states arrive: PLAY on every card, ARENA on Snake, 2 PLAYERS on Invaders and
-- Asteroids, none on a card coming soon, each with its price ("FREE", or 5 R$ struck through and 1 R$) as rich text,
-- never gamepad-selectable; a tap, the carousel's PLAY (onPlay), 2 or X for the second button, Backspace or B to
-- cancel and I or Y to invite only ask the server, on the press, and nothing while the test purchase screen is open.
-- The server's status draws the player's own play on its card; a waiting count says another player waits; the
-- server's "invite" opens Roblox's invite prompt with the inviter's id as launch data.
local Card = require("@logic/Card")
local Games = require("@shared/Games")
local Play = require("@logic/Play")
local Prices = require("@arcade/Prices")
local luau = require("@lune/luau")
local place = require("@tests/lib/place")
local t = require("@tests/lib/t")

local built = place.load()
local SOURCE = (built :: any)
	:GetService("StarterPlayer")
	:FindFirstChild("StarterPlayerScripts")
	:FindFirstChild("Client")
	:FindFirstChild("PlayButtons").Source

local SALE = `{Card.strike(Prices.struck)} {Prices.price}`
local STATES = {
	pickman = { published = true, free = true },
	snake = { published = true, free = false },
	invaders = { published = true, free = true },
	asteroids = { published = false },
}

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

local function world(held: boolean?): any
	local w: any = {
		errors = {},
		plays = {},
		asks = 0,
		binds = {},
		listeners = {},
		front = "pickman",
		open = false,
		canInvite = true,
		prompts = {},
		inviteChecks = 0,
		waiters = {},
		log = {},
	}
	local function spawn(fn: (...any) -> (), ...: any)
		local co = coroutine.create(fn)
		local ok, err = coroutine.resume(co, ...)
		if not ok then
			table.insert(w.errors, tostring(err))
		end
	end
	local function signal(): any
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
	-- a stub Instance: a Parent assignment makes it its parent's child, found by Name
	local function inst(class: string): any
		local data: any = { ClassName = class, Name = class }
		local kids: { any } = {}
		if class == "TextButton" then
			data.Activated = signal()
		end
		local o: any = {}
		function data.FindFirstChild(_: any, name: string): any
			for _, k in kids do
				if k.Name == name then
					return k
				end
			end
			return nil
		end
		function data.GetChildren(): { any }
			return table.clone(kids)
		end
		data._kids = kids
		setmetatable(o, {
			__index = data,
			__newindex = function(_: any, key: string, value: any)
				if key == "Parent" then
					local old = data.Parent
					if old ~= nil then
						local i = table.find(old._kids, o)
						if i then
							table.remove(old._kids, i)
						end
					end
					if value ~= nil then
						table.insert(value._kids, o)
					end
				end
				data[key] = value
			end,
		})
		return o
	end
	w.inst = inst

	local frames: { [string]: any } = {}
	for _, entry in Games.LIST do
		local card = inst("Frame")
		card.Name = entry.name
		local slot = inst("Frame")
		slot.Name = "Buttons"
		slot.Parent = card
		frames[entry.name] = card
	end
	w.frames = frames
	local carousel: any = {
		card = function(name: string): any
			return frames[name]
		end,
		onPlay = function(fn: (string) -> ())
			table.insert(w.listeners, fn)
		end,
		focused = function(): string
			return w.front
		end,
	}

	local playRemote: any = { Name = "Play", OnClientEvent = signal() }
	playRemote.FireServer = function(_: any, ...: any)
		table.insert(w.plays, table.pack(...))
	end
	local cardsRemote: any = { Name = "Cards", OnClientEvent = signal() }
	cardsRemote.FireServer = function(_: any, ...: any)
		w.asks += 1
		w.askArgs = select("#", ...)
		table.insert(
			w.log,
			`ask after {playRemote.OnClientEvent.count()} {cardsRemote.OnClientEvent.count()}`
		)
	end
	w.playRemote, w.cardsRemote = playRemote, cardsRemote
	local remotes: any = {
		WaitForChild = function(_: any, name: string): any
			return if name == "Play" then playRemote elseif name == "Cards" then cardsRemote else nil
		end,
	}
	w.held = held == true
	local me: any = { Name = "me", UserId = 42 }
	local services: { [string]: any } = {
		ContextActionService = {
			BindActionAtPriority = function(
				_: any,
				name: string,
				fn: any,
				touch: any,
				priority: number,
				...: any
			)
				local keys = {}
				for _, k in { ... } do
					table.insert(keys, k.Name)
				end
				table.sort(keys)
				table.insert(
					w.binds,
					{ name = name, fn = fn, touch = touch, priority = priority, keys = keys }
				)
			end,
		},
		Players = { LocalPlayer = me },
		ReplicatedStorage = {
			WaitForChild = function(_: any, name: string): any
				assert(name == "Remotes", name)
				if w.held then
					table.insert(w.waiters, coroutine.running())
					coroutine.yield()
				end
				return remotes
			end,
		},
		UserInputService = {
			GetFocusedTextBox = function(): any
				return w.typing
			end,
		},
		SocialService = {
			CanSendGameInviteAsync = function(_: any, player: any): boolean
				w.inviteChecks += 1
				t.expect(player).toBe(me)
				if w.canInvite == "throw" then
					error("web call failed")
				end
				return w.canInvite
			end,
			PromptGameInvite = function(_: any, player: any, options: any)
				table.insert(w.prompts, { player = player, options = options })
			end,
		},
	}
	w.me = me
	local testPurchase: any = {
		isOpen = function(): boolean
			return w.open
		end,
		start = function() end,
	}

	local keyCodes = setmetatable({}, {
		__index = function(_: any, name: string): any
			return { Name = name }
		end,
	})
	local env: { [string]: any } = {}
	env.game = {
		GetService = function(_: any, name: string): any
			return services[name] or standin()
		end,
	}
	env.Instance = { new = inst }
	env.UDim2 = {
		fromScale = function(x: number, y: number): any
			return { X = x, Y = y }
		end,
	}
	env.Color3 = {
		new = function(): any
			return {}
		end,
		fromRGB = function(): any
			return {}
		end,
	}
	env.Enum = {
		KeyCode = keyCodes,
		UserInputState = { Begin = "Begin", End = "End", Change = "Change" },
		ContextActionResult = { Sink = "Sink", Pass = "Pass" },
		Font = standin(),
	}
	env.task = {
		spawn = spawn,
		defer = spawn,
		delay = function() end,
		wait = function()
			return 0
		end,
	}
	env.require = function(spec: string): any
		local logic = string.match(spec, "^@game/ReplicatedStorage/Shared/Logic/(%w+)$")
		if logic then
			return (require :: any)("@logic/" .. logic)
		end
		local shared = string.match(spec, "^@game/ReplicatedStorage/Shared/(%w+)$")
		if shared then
			return (require :: any)("@shared/" .. shared)
		end
		if spec == "@game/ReplicatedStorage/Arcade/TestPurchase" then
			return testPurchase
		end
		local arcadeLogic = string.match(spec, "^@game/ReplicatedStorage/Arcade/Logic/(%w+)$")
		if arcadeLogic then
			return (require :: any)("@arcade/Logic/" .. arcadeLogic)
		end
		local arcade = string.match(spec, "^@game/ReplicatedStorage/Arcade/(%w+)$")
		if arcade then
			return (require :: any)("@arcade/" .. arcade)
		end
		if spec == "./CarouselView" then
			return carousel
		end
		return standin() -- a sibling adapter a later issue adds
	end
	local PlayButtons = luau.load(SOURCE, { debugName = "PlayButtons", environment = env })()
	w.PlayButtons = PlayButtons
	local returned = false
	spawn(function()
		PlayButtons.start()
		returned = true
	end)
	w.returned = returned

	function w.release()
		w.held = false
		for _, co in w.waiters do
			local ok, err = coroutine.resume(co)
			if not ok then
				table.insert(w.errors, tostring(err))
			end
		end
		w.waiters = {}
	end
	function w.cards(raw: any)
		cardsRemote.OnClientEvent.fire(raw)
	end
	function w.say(...: any)
		playRemote.OnClientEvent.fire(...)
	end
	function w.slot(name: string): any
		return frames[name]:FindFirstChild("Buttons")
	end
	function w.button(name: string, kind: string): any
		local b = w.slot(name):FindFirstChild(kind)
		assert(b ~= nil, `no {kind} button on {name}`)
		return b
	end
	function w.shown(name: string): { string }
		local out = {}
		for _, kind in { "solo", "arena", "pair", "cancel", "invite" } do
			if w.button(name, kind).Visible then
				table.insert(out, kind)
			end
		end
		return out
	end
	function w.note(name: string): string?
		local n = w.slot(name):FindFirstChild("Note")
		assert(n ~= nil, `no note on {name}`)
		return if n.Visible then n.Text else nil
	end
	function w.tap(name: string, kind: string)
		w.button(name, kind).Activated.fire()
	end
	function w.play(name: string)
		for _, fn in w.listeners do
			spawn(fn, name)
		end
	end
	function w.key(name: string, state: string?): string?
		local bind = w.binds[1]
		assert(bind ~= nil, "no binding")
		local out
		spawn(function()
			out = bind.fn(bind.name, state or "Begin", { KeyCode = { Name = name } })
		end)
		return out
	end
	function w.sent(): { string }
		local out = {}
		for _, m in w.plays do
			local parts = {}
			for i = 1, m.n do
				table.insert(parts, tostring(m[i]))
			end
			table.insert(out, table.concat(parts, " "))
		end
		return out
	end
	return w
end

local function clean(w: any)
	t.expect(table.concat(w.errors, "\n")).toBe("")
end

return t.spec("f0208 client", function(it)
	it(
		"each card's slot gets PLAY, ARENA on Snake, 2 PLAYERS on Invaders and Asteroids; a card coming soon none",
		function()
			local w = world()
			w.cards(STATES)
			t.expect(w.shown("pickman")).toEqual({ "solo" })
			t.expect(w.shown("snake")).toEqual({ "solo", "arena" })
			t.expect(w.shown("invaders")).toEqual({ "solo", "pair" })
			t.expect(w.shown("asteroids")).toEqual({})
			local both = table.clone(STATES) :: any
			both.asteroids = { published = true, free = false }
			w.cards(both)
			t.expect(w.shown("asteroids")).toEqual({ "solo", "pair" })
			clean(w)
		end
	)

	it("each button says its name over its price, as rich text, and is never gamepad-selectable", function()
		local w = world()
		w.cards(STATES)
		t.expect(w.button("pickman", "solo").Text).toBe("PLAY\nFREE")
		t.expect(w.button("snake", "solo").Text).toBe(`PLAY\n{SALE}`)
		t.expect(w.button("snake", "arena").Text).toBe(`ARENA\n{SALE}`)
		t.expect(w.button("invaders", "pair").Text).toBe("2 PLAYERS\nFREE")
		for _, kind in { "solo", "arena", "pair", "cancel", "invite" } do
			t.expect(w.button("snake", kind).RichText).toBe(true)
			t.expect(w.button("snake", kind).Selectable).toBe(false)
		end
		clean(w)
	end)

	it("the buttons and the note sit where Play.slots and Play.noteBox put them", function()
		local w = world()
		w.cards(STATES)
		local function placed(kind: string, slot: any)
			local b = w.button("snake", kind)
			t.expect(b.Position.X).toBeNear(slot.x, 1e-9)
			t.expect(b.Position.Y).toBeNear(slot.y, 1e-9)
			t.expect(b.Size.X).toBeNear(slot.width, 1e-9)
			t.expect(b.Size.Y).toBeNear(slot.height, 1e-9)
		end
		local full = Play.slots(2, false)
		placed("solo", full[1])
		placed("arena", full[2])
		w.say("status", { phase = "failed", name = "snake", mode = "arena" })
		local under = Play.slots(2, true)
		placed("solo", under[1])
		placed("arena", under[2])
		local note = w.slot("snake"):FindFirstChild("Note")
		local box = Play.noteBox(2)
		t.expect(note.Position.Y).toBeNear(box.y, 1e-9)
		t.expect(note.Size.Y).toBeNear(box.height, 1e-9)
		t.expect(note.Size.X).toBeNear(box.width, 1e-9)
		w.say("status", { phase = "checking", name = "snake", mode = "arena" })
		t.expect(note.Size.Y).toBeNear(Play.noteBox(0).height, 1e-9)
		clean(w)
	end)

	it(
		"a note wraps; a button's text does not, its name over its price; under a note, the name alone",
		function()
			local w = world()
			w.cards(STATES)
			t.expect(w.slot("snake"):FindFirstChild("Note").TextWrapped).toBe(true)
			t.expect(w.slot("snake"):FindFirstChild("Note").TextScaled).toBe(true)
			t.expect(w.button("snake", "solo").TextWrapped).toBe(false)
			t.expect(w.button("snake", "solo").TextScaled).toBe(true)
			w.say("status", { phase = "failed", name = "snake", mode = "arena" })
			t.expect(w.button("snake", "solo").Text).toBe("PLAY")
			t.expect(w.button("snake", "arena").Text).toBe("ARENA")
			clean(w)
		end
	)

	it("a tap asks the server to play that card's title in that button's mode", function()
		local w = world()
		w.cards(STATES)
		w.tap("pickman", "solo")
		w.tap("snake", "arena")
		w.tap("invaders", "pair")
		t.expect(w.sent()).toEqual({ "play pickman solo", "play snake arena", "play invaders pair" })
		clean(w)
	end)

	it("before the server's states nothing plays: taps and the carousel's PLAY send nothing", function()
		local w = world()
		w.tap("pickman", "solo")
		w.play("pickman")
		t.expect(#w.plays).toBe(0)
		clean(w)
	end)

	it("a hidden button, or a card coming soon, sends nothing", function()
		local w = world()
		w.cards(STATES)
		w.tap("pickman", "cancel")
		w.tap("pickman", "arena")
		w.tap("asteroids", "solo")
		w.play("asteroids")
		t.expect(#w.plays).toBe(0)
		clean(w)
	end)

	it(
		"the carousel's PLAY (Enter, KeypadEnter, ButtonA) asks to play the card in PLAY's mode, once",
		function()
			local w = world()
			w.cards(STATES)
			t.expect(#w.listeners).toBe(1)
			w.play("invaders")
			t.expect(w.sent()).toEqual({ "play invaders solo" })
			clean(w)
		end
	)

	it(
		"one binding, PortalPlay between the default controls and the test screen, of exactly its seven keys",
		function()
			local w = world()
			t.expect(#w.binds).toBe(1)
			t.expect(w.binds[1].name).toBe("PortalPlay")
			t.expect(w.binds[1].priority).toBe(Play.PRIORITY)
			t.expect(w.binds[1].priority > 2000).toBe(true)
			t.expect(w.binds[1].priority < 3000).toBe(true)
			t.expect(w.binds[1].touch).toBe(false)
			t.expect(w.binds[1].keys)
				.toEqual({ "Backspace", "ButtonB", "ButtonX", "ButtonY", "I", "KeypadTwo", "Two" })
			clean(w)
		end
	)

	it("2, keypad 2 and X press the front card's second button on the press, and sink it", function()
		local w = world()
		w.cards(STATES)
		w.front = "snake"
		t.expect(w.key("Two")).toBe("Sink")
		t.expect(w.key("Two", "End")).toBe("Pass")
		w.front = "invaders"
		t.expect(w.key("ButtonX")).toBe("Sink")
		t.expect(w.key("KeypadTwo")).toBe("Sink")
		t.expect(w.sent()).toEqual({ "play snake arena", "play invaders pair", "play invaders pair" })
		clean(w)
	end)

	it("a card with one button, or none, passes the second-button keys on and sends nothing", function()
		local w = world()
		w.cards(STATES)
		w.front = "pickman"
		t.expect(w.key("Two")).toBe("Pass")
		w.front = "asteroids"
		t.expect(w.key("ButtonX")).toBe("Pass")
		t.expect(w.key("Backspace")).toBe("Pass")
		t.expect(#w.plays).toBe(0)
		clean(w)
	end)

	it("while the test purchase screen is open nothing is sent: taps, PLAY and keys", function()
		local w = world()
		w.cards(STATES)
		w.open = true
		w.front = "snake"
		w.tap("snake", "solo")
		w.play("snake")
		t.expect(w.key("Two")).toBe("Pass")
		t.expect(#w.plays).toBe(0)
		w.open = false
		w.tap("snake", "solo")
		t.expect(#w.plays).toBe(1)
		clean(w)
	end)

	it(
		"a 2 PLAYERS wait: the card says WAITING with CANCEL and INVITE, which ask the server, by tap or key",
		function()
			local w = world()
			w.cards(STATES)
			w.say("status", { phase = "waiting", name = "invaders", mode = "pair" })
			t.expect(w.note("invaders")).toBe("WAITING FOR A SECOND PLAYER")
			t.expect(w.shown("invaders")).toEqual({ "cancel", "invite" })
			t.expect(w.shown("pickman")).toEqual({ "solo" })
			w.tap("invaders", "invite")
			w.tap("invaders", "cancel")
			w.front = "pickman"
			t.expect(w.key("I")).toBe("Sink")
			t.expect(w.key("ButtonY")).toBe("Sink")
			t.expect(w.key("Backspace")).toBe("Sink")
			t.expect(w.key("ButtonB")).toBe("Sink")
			t.expect(w.sent()).toEqual({ "invite", "cancel", "invite", "invite", "cancel", "cancel" })
			clean(w)
		end
	)

	it("while the player types in a text box (the chat) the keys pass on and send nothing", function()
		local w = world()
		w.cards(STATES)
		w.front = "snake"
		w.typing = {}
		t.expect(w.key("Two")).toBe("Pass")
		w.say("status", { phase = "waiting", name = "invaders", mode = "pair" })
		t.expect(w.key("I")).toBe("Pass")
		t.expect(w.key("Backspace")).toBe("Pass")
		t.expect(#w.plays).toBe(0)
		w.typing = nil
		t.expect(w.key("Backspace")).toBe("Sink")
		clean(w)
	end)

	it("with no wait, Backspace, B, I and Y pass on and send nothing", function()
		local w = world()
		w.cards(STATES)
		for _, key in { "Backspace", "ButtonB", "I", "ButtonY" } do
			t.expect(w.key(key)).toBe("Pass")
		end
		t.expect(#w.plays).toBe(0)
		clean(w)
	end)

	it("the player's play is drawn on its card: checking, buying and starting show the note alone", function()
		local w = world()
		w.cards(STATES)
		for phase, note in
			{ checking = "CHECKING...", buying = "COMPLETE THE PURCHASE", going = "STARTING..." }
		do
			w.say("status", { phase = phase, name = "snake", mode = "arena" })
			t.expect(w.note("snake")).toBe(note)
			t.expect(w.shown("snake")).toEqual({})
		end
		w.say("status", { phase = "failed", name = "snake", mode = "arena" })
		t.expect(w.note("snake")).toBe("COULD NOT START. TRY AGAIN.")
		t.expect(w.shown("snake")).toEqual({ "solo", "arena" })
		w.say("status", { phase = "idle" })
		t.expect(w.note("snake")).toBe(nil)
		t.expect(w.shown("snake")).toEqual({ "solo", "arena" })
		clean(w)
	end)

	it("a status that makes no sense draws the cards as if idle", function()
		local w = world()
		w.cards(STATES)
		w.say("status", { phase = "waiting", name = "invaders", mode = "pair" })
		w.say("status", { phase = "waiting", name = "pickman", mode = "pair" })
		t.expect(w.shown("invaders")).toEqual({ "solo", "pair" })
		t.expect(w.note("invaders")).toBe(nil)
		clean(w)
	end)

	it(
		"another player waiting shows on that 2 PLAYERS card; a count that makes no sense is dropped",
		function()
			local w = world()
			w.cards(STATES)
			w.say("waiting", { invaders = 1, asteroids = 0 })
			t.expect(w.note("invaders")).toBe("A PLAYER IS WAITING")
			t.expect(w.shown("invaders")).toEqual({ "solo", "pair" })
			w.say("waiting", { invaders = -1 })
			t.expect(w.note("invaders")).toBe(nil)
			w.say("waiting", "lots")
			w.say("waiting", { invaders = "1" })
			t.expect(w.note("invaders")).toBe(nil)
			clean(w)
		end
	)

	it("the server's invite opens Roblox's invite prompt with the player's id as launch data", function()
		local w = world()
		w.say("invite")
		t.expect(w.inviteChecks).toBe(1)
		t.expect(#w.prompts).toBe(1)
		t.expect(w.prompts[1].player).toBe(w.me)
		t.expect(w.prompts[1].options.ClassName).toBe("ExperienceInviteOptions")
		t.expect(w.prompts[1].options.LaunchData).toBe("42")
		clean(w)
	end)

	it("no prompt when the player cannot invite, or the check fails", function()
		local w = world()
		w.canInvite = false
		w.say("invite")
		w.canInvite = "throw"
		w.say("invite")
		t.expect(#w.prompts).toBe(0)
		clean(w)
	end)

	it("asks the cards' states once, after it listens on both remotes", function()
		local w = world()
		t.expect(w.asks).toBe(1)
		t.expect(w.log).toEqual({ "ask after 1 1" })
		t.expect(w.askArgs).toBe(0)
		clean(w)
	end)

	it("start returns at once while the remotes are not there, and works once they are", function()
		local w = world(true)
		t.expect(w.returned).toBe(true)
		t.expect(w.asks).toBe(0)
		w.release()
		t.expect(w.asks).toBe(1)
		w.cards(STATES)
		w.tap("pickman", "solo")
		t.expect(w.sent()).toEqual({ "play pickman solo" })
		clean(w)
	end)

	it("started twice it builds, binds, listens and asks once", function()
		local w = world()
		w.PlayButtons.start()
		t.expect(#w.binds).toBe(1)
		t.expect(#w.listeners).toBe(1)
		t.expect(w.asks).toBe(1)
		t.expect(#w.slot("pickman"):GetChildren()).toBe(6)
		clean(w)
	end)
end)
